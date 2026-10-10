import '../../data/models/campaign_models.dart';
import 'dart:math';
import '../../data/models/order_item_model.dart';

/// Đầu vào cho Pricing Engine
class PricingInput {
  final String branchId;
  final String? customerId;
  final int? guestCount;
  final int serverNowMs;
  final List<PricingLineItem> lines;
  final String? enteredCode;
  final int manualDiscountMoney;
  final int pricingPolicyVersion;

  PricingInput({
    required this.branchId,
    this.customerId,
    this.guestCount,
    required this.serverNowMs,
    required this.lines,
    this.enteredCode,
    this.manualDiscountMoney = 0,
    this.pricingPolicyVersion = 1,
  });
}

class PricingLineItem {
  final String lineId;
  final String itemId;
  final String? itemVariantId;
  final String? groupId;
  final int quantity;
  final int unitPrice;
  final bool isGift;

  /// Giảm giá thủ công theo dòng, áp cho [discountedQuantity] phần trong dòng:
  /// [discountPercent] %/phần hoặc [discountUnitAmount] đ/phần.
  final int discountedQuantity;
  final int discountPercent;
  final int discountUnitAmount;

  PricingLineItem({
    required this.lineId,
    required this.itemId,
    this.itemVariantId,
    this.groupId,
    required this.quantity,
    required this.unitPrice,
    this.isGift = false,
    this.discountedQuantity = 0,
    this.discountPercent = 0,
    this.discountUnitAmount = 0,
  });

  /// Dựng từ dòng món của giỏ hàng (giữ cấu hình giảm giá theo phần)
  factory PricingLineItem.fromOrderItem(OrderItemModel item, {required String lineId, String? groupId}) => PricingLineItem(
        lineId: lineId,
        itemId: item.productId.toString(),
        groupId: groupId,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discountedQuantity: item.discountedQuantity,
        discountPercent: item.discountPercent,
        discountUnitAmount: item.discountUnitAmount,
      );

  /// Tổng giảm thủ công của dòng = giảm mỗi phần × số phần được giảm (chặn theo tiền dòng)
  int get manualLineDiscount => isGift
      ? 0
      : OrderItemModel.computeLineDiscount(
          unitPrice: unitPrice,
          quantity: quantity,
          discountedQuantity: discountedQuantity,
          percent: discountPercent,
          unitAmount: discountUnitAmount,
        );
}

// ==================== HELPERS ====================

bool _isType(String type, String compact) => type.toUpperCase().replaceAll('_', '') == compact;

/// Chuẩn hóa cách tính lợi ích: FREE (tặng 100%), PERCENT (basis points), FIXED (đ/phần), FIXEDPRICE (đồng giá)
String normalizeBenefitMode(String mode) {
  final u = mode.toUpperCase().replaceAll('_', '');
  switch (u) {
    case 'FREEITEM':
    case 'FREE':
    case 'GIFT':
      return 'FREE';
    case 'PERCENT':
    case 'DISCOUNTPERCENT':
      return 'PERCENT';
    case 'FIXED':
    case 'AMOUNT':
    case 'DISCOUNTAMOUNT':
      return 'FIXED';
    case 'FIXEDPRICE':
      return 'FIXEDPRICE';
    default:
      return u;
  }
}

/// Số tiền giảm cho 1 phần món theo cách tính lợi ích
int _unitBenefit(String mode, int value, int unitPrice) {
  if (unitPrice <= 0) return 0;
  switch (normalizeBenefitMode(mode)) {
    case 'FREE':
      return unitPrice;
    case 'PERCENT':
      return unitPrice * value.clamp(0, 10000) ~/ 10000;
    case 'FIXED':
      return min(max(0, value), unitPrice);
    case 'FIXEDPRICE':
      return max(0, unitPrice - value);
    default:
      return 0;
  }
}

/// Pricing Engine - Pure function
///
/// Thứ tự áp dụng: giảm thủ công theo dòng → KM theo món (đồng giá, Mua X tặng/giảm Y,
/// giảm/tặng món theo giá trị hóa đơn) → giảm giá hóa đơn (tính trên giá trị còn lại).
/// Món thưởng chỉ được giảm trên các dòng ĐÃ CÓ trong hóa đơn (engine không tự thêm dòng tặng),
/// ưu tiên phần rẻ nhất trước.
PriceQuoteModel calculatePrice({
  required PricingInput input,
  required List<CampaignModel> activeCampaigns,
  required Map<String, CampaignCountersModel> counters,
  required Map<String, CustomerCampaignCounterModel> customerCounters,
  // voucherByCode is mocked for now
  Map<String, dynamic>? voucherByCode,
}) {
  int grossMoney = 0;
  for (var line in input.lines) {
    if (!line.isGift) {
      grossMoney += line.unitPrice * line.quantity;
    }
  }

  List<QuoteReason> nonAppliedReasons = [];
  List<String> appliedCampaigns = [];
  int totalDiscount = 0;

  List<CampaignModel> eligibleBillDiscounts = [];
  List<LineBenefit> rewardBenefits = [];

  Map<String, int> lineFinalPrices = {};
  Map<String, int> lineDiscounts = {};
  int manualLineDiscountTotal = 0;
  for (var line in input.lines) {
    if (!line.isGift) {
      // Giảm giá thủ công theo số phần được chọn của dòng
      final manual = line.manualLineDiscount;
      manualLineDiscountTotal += manual;
      lineFinalPrices[line.lineId] = line.unitPrice * line.quantity - manual;
      lineDiscounts[line.lineId] = manual;
    }
  }
  // Giá trị dòng sau giảm thủ công (dùng làm cơ sở ngưỡng giá trị đơn)
  final afterManual = Map<String, int>.from(lineFinalPrices);
  // Số phần của dòng đã được dùng làm món thưởng (tránh giảm 2 lần)
  final rewardedUnits = <String, int>{};

  void addReason(CampaignModel c, String code, String msg) {
    nonAppliedReasons.add(QuoteReason(campaignId: c.campaignId, reasonCode: code, reasonMessage: msg));
  }

  void markApplied(String campaignId) {
    if (!appliedCampaigns.contains(campaignId)) appliedCampaigns.add(campaignId);
  }

  bool inScope(CampaignModel c, PricingLineItem l) {
    if (l.isGift) return false;
    if (c.excludedItemIds.contains(l.itemId)) return false;
    if (c.includedItemIds.isEmpty && c.includedGroupIds.isEmpty) return true;
    return c.includedItemIds.contains(l.itemId) || (l.groupId != null && c.includedGroupIds.contains(l.groupId));
  }

  /// Giảm [units] phần của dòng [line] theo cách tính lợi ích; tôn trọng giảm giá đã có trên dòng
  /// (không vượt quá giá trị còn lại tương ứng với số phần). Trả về số tiền đã giảm.
  int rewardUnitsOnLine(PricingLineItem line, int units, String mode, int value, String campaignId, String tierId) {
    final avail = line.quantity - (rewardedUnits[line.lineId] ?? 0);
    if (units <= 0 || avail <= 0) return 0;
    final k = min(units, avail);
    final remaining = max(0, lineFinalPrices[line.lineId] ?? 0);
    final perUnit = _unitBenefit(mode, value, line.unitPrice);
    final amount = min(perUnit * k, remaining * k ~/ avail);
    rewardedUnits[line.lineId] = (rewardedUnits[line.lineId] ?? 0) + k;
    if (amount <= 0) return 0;
    lineDiscounts[line.lineId] = (lineDiscounts[line.lineId] ?? 0) + amount;
    lineFinalPrices[line.lineId] = remaining - amount;
    rewardBenefits.add(LineBenefit(
      lineId: line.lineId,
      campaignId: campaignId,
      tierId: tierId,
      discountMoney: amount,
      originalPrice: line.unitPrice * k,
      effectivePrice: line.unitPrice * k - amount,
      isGift: normalizeBenefitMode(mode) == 'FREE',
      giftSourceCampaignId: campaignId,
      quantity: k,
    ));
    return amount;
  }

  /// Phân bổ [units] phần thưởng lên các dòng ứng viên, phần rẻ nhất trước.
  /// [maxFromBoth] giới hạn số phần lấy từ các dòng vừa là X vừa là Y (null = không giới hạn).
  int distributeReward({
    required List<PricingLineItem> candidates,
    required int units,
    required String mode,
    required int value,
    required String campaignId,
    required String tierId,
    bool Function(PricingLineItem)? isBoth,
    int? maxFromBoth,
  }) {
    final sorted = List<PricingLineItem>.from(candidates)
      ..sort((a, b) {
        final c = a.unitPrice.compareTo(b.unitPrice);
        return c != 0 ? c : a.lineId.compareTo(b.lineId);
      });
    int left = units;
    int bothLeft = maxFromBoth ?? 1 << 30;
    int total = 0;
    for (final l in sorted) {
      if (left <= 0) break;
      final avail = l.quantity - (rewardedUnits[l.lineId] ?? 0);
      if (avail <= 0) continue;
      final both = isBoth?.call(l) ?? false;
      var take = min(avail, left);
      if (both) take = min(take, bothLeft);
      if (take <= 0) continue;
      total += rewardUnitsOnLine(l, take, mode, value, campaignId, tierId);
      left -= take;
      if (both) bothLeft -= take;
    }
    return total;
  }

  // Evaluate campaigns
  for (var campaign in activeCampaigns) {
    if (!campaign.isEligibleAt(input.serverNowMs)) {
      addReason(campaign, 'OUTSIDE_SCHEDULE', 'Ngoài thời gian áp dụng');
      continue;
    }
    if (!campaign.isEligibleForBranch(input.branchId)) {
      addReason(campaign, 'BRANCH_NOT_SUPPORTED', 'Không áp dụng tại chi nhánh này');
      continue;
    }
    final type = campaign.campaignType;

    if (_isType(type, 'BILLDISCOUNT')) {
      if (campaign.tiers.isNotEmpty && campaign.tiers.first.conditionBasis == 'GUESTCOUNT') {
        if (input.guestCount == null || input.guestCount! < campaign.tiers.first.threshold) {
          addReason(campaign, 'GUEST_COUNT_REQUIRED', 'Chưa đủ số lượng khách');
          continue;
        }
      }
      eligibleBillDiscounts.add(campaign);
    } else if (_isType(type, 'BUYXGETY')) {
      int campaignDiscount = 0;
      bool earnedAny = false;
      for (var condition in campaign.buyConditions) {
        final buyIds = condition.buyItemIds.toSet();
        final rewardIds = condition.rewardItemIds.toSet();
        final buyQty = condition.requiredBuyQty;
        final rewardQty = condition.rewardQty;
        if (buyIds.isEmpty || rewardIds.isEmpty || buyQty <= 0 || rewardQty <= 0) {
          addReason(campaign, 'INVALID_CONFIG', 'Điều kiện Mua X tặng/giảm Y chưa cấu hình đủ');
          continue;
        }

        int avail(PricingLineItem l) => l.quantity - (rewardedUnits[l.lineId] ?? 0);
        int xo = 0, yo = 0, bo = 0; // chỉ X, chỉ Y, vừa X vừa Y
        for (final l in input.lines) {
          if (l.isGift || campaign.excludedItemIds.contains(l.itemId)) continue;
          final isX = buyIds.contains(l.itemId);
          final isY = rewardIds.contains(l.itemId);
          final a = max(0, avail(l));
          if (isX && isY) {
            bo += a;
          } else if (isX) {
            xo += a;
          } else if (isY) {
            yo += a;
          }
        }

        // Chọn số bộ b (nhân theo số món X nếu bật) cho số phần thưởng lớn nhất,
        // đảm bảo các phần X dùng để "mua" không trùng với phần Y được thưởng.
        final maxB = condition.multiplyByBundle ? (xo + bo) ~/ buyQty : min(1, (xo + bo) ~/ buyQty);
        int bestB = 0, bestReward = 0, bestBothAllowed = 0;
        for (int b = 1; b <= maxB; b++) {
          final needFromBoth = max(0, b * buyQty - xo);
          if (needFromBoth > bo) break;
          final bothForY = bo - needFromBoth;
          final reward = min(b * rewardQty, yo + bothForY);
          if (bestB == 0 || reward > bestReward) {
            bestB = b;
            bestReward = reward;
            bestBothAllowed = bothForY;
          }
        }
        if (bestB == 0) {
          addReason(campaign, 'INSUFFICIENT_BUY_ITEMS', 'Chưa đủ số lượng mua (cần $buyQty món X)');
          continue;
        }
        earnedAny = true;
        if (bestReward <= 0) {
          addReason(campaign, 'REWARD_ITEM_NOT_IN_BILL', 'Đủ điều kiện: thêm ${bestB * rewardQty} món Y vào đơn để được hưởng ưu đãi');
          continue;
        }

        final candidates = input.lines
            .where((l) => !l.isGift && rewardIds.contains(l.itemId) && !campaign.excludedItemIds.contains(l.itemId))
            .toList();
        campaignDiscount += distributeReward(
          candidates: candidates,
          units: bestReward,
          mode: condition.benefitMode,
          value: condition.value,
          campaignId: campaign.campaignId,
          tierId: condition.conditionId,
          isBoth: (l) => buyIds.contains(l.itemId),
          maxFromBoth: bestBothAllowed,
        );
      }
      if (campaignDiscount > 0) {
        totalDiscount += campaignDiscount;
        markApplied(campaign.campaignId);
      } else if (earnedAny && !nonAppliedReasons.any((r) => r.campaignId == campaign.campaignId)) {
        addReason(campaign, 'NO_BENEFIT', 'Ưu đãi món Y bằng 0đ');
      }
    } else if (_isType(type, 'ORDERVALUEITEMBENEFIT')) {
      int base = 0;
      for (final l in input.lines) {
        if (inScope(campaign, l)) base += afterManual[l.lineId] ?? 0;
      }
      final tiers = List<CampaignTier>.from(campaign.tiers)..sort((a, b) => b.threshold.compareTo(a.threshold));
      final tier = tiers.where((t) => base >= t.threshold).firstOrNull;
      if (tier == null) {
        final minTh = tiers.isEmpty ? 0 : tiers.last.threshold;
        addReason(campaign, tiers.isEmpty ? 'INVALID_CONFIG' : 'ORDER_VALUE_NOT_REACHED',
            tiers.isEmpty ? 'Chương trình chưa cấu hình mức ưu đãi' : 'Đơn hàng chưa đạt $minTh đ');
        continue;
      }
      final rewardIds = tier.rewardItemIds.toSet();
      if (rewardIds.isEmpty) {
        addReason(campaign, 'INVALID_CONFIG', 'Chưa chọn món được tặng/giảm');
        continue;
      }
      final units = tier.maxRewardQty > 0 ? tier.maxRewardQty : 1;
      final candidates = input.lines
          .where((l) => !l.isGift && rewardIds.contains(l.itemId) && !campaign.excludedItemIds.contains(l.itemId))
          .toList();
      if (candidates.isEmpty) {
        addReason(campaign, 'REWARD_ITEM_NOT_IN_BILL', 'Đơn đủ điều kiện: thêm món được tặng/giảm vào đơn để áp dụng');
        continue;
      }
      final d = distributeReward(
        candidates: candidates,
        units: units,
        mode: tier.benefitMode,
        value: tier.value,
        campaignId: campaign.campaignId,
        tierId: tier.tierId,
      );
      if (d > 0) {
        totalDiscount += d;
        markApplied(campaign.campaignId);
      } else {
        addReason(campaign, 'NO_BENEFIT', 'Ưu đãi món bằng 0đ');
      }
    } else if (_isType(type, 'ITEMPRICERULE')) {
      if (campaign.tiers.isNotEmpty) {
        var tier = campaign.tiers.first;
        var fixedPrice = (tier.benefitMode == 'FIXEDPRICE') ? tier.value : null;

        bool applied = false;
        for (var line in input.lines) {
          if (inScope(campaign, line)) {
            if (fixedPrice != null && line.unitPrice > fixedPrice) {
              final remaining = max(0, lineFinalPrices[line.lineId] ?? 0);
              int discount = min((line.unitPrice - fixedPrice) * line.quantity, remaining);
              if (discount <= 0) continue;
              lineDiscounts[line.lineId] = (lineDiscounts[line.lineId] ?? 0) + discount;
              lineFinalPrices[line.lineId] = remaining - discount;
              totalDiscount += discount;
              applied = true;
            }
          }
        }
        if (applied) markApplied(campaign.campaignId);
      }
    }
  }

  List<BillBenefit> billBenefits = [];
  if (eligibleBillDiscounts.isNotEmpty) {
    eligibleBillDiscounts.sort((a, b) {
      if (a.priority != b.priority) return b.priority.compareTo(a.priority);
      return b.createdAt.compareTo(a.createdAt);
    });

    List<Map<String, dynamic>> calculatedBillDiscounts = [];
    for (var campaign in eligibleBillDiscounts) {
      if (campaign.tiers.isEmpty) continue;
      // Không chọn món = áp dụng cho toàn bộ hóa đơn. Cơ sở = giá trị còn lại sau các giảm theo món.
      final eligibleLines = input.lines.where((l) => inScope(campaign, l)).toList();
      int baseMoney = eligibleLines.fold(0, (s, l) => s + max(0, lineFinalPrices[l.lineId] ?? 0));

      // Bậc cao nhất đạt ngưỡng "Đơn hàng từ"
      final tiers = List<CampaignTier>.from(campaign.tiers)..sort((a, b) => b.threshold.compareTo(a.threshold));
      final tier = campaign.tiers.first.conditionBasis == 'GUESTCOUNT'
          ? campaign.tiers.first
          : tiers.where((t) => t.threshold <= 0 || baseMoney >= t.threshold).firstOrNull;
      if (tier == null) {
        nonAppliedReasons.add(QuoteReason(
          campaignId: campaign.campaignId,
          reasonCode: 'ORDER_VALUE_NOT_REACHED',
          reasonMessage: 'Đơn hàng chưa đạt ${tiers.last.threshold} đ',
        ));
        continue;
      }
      final maxDiscount = tier.maxDiscountMoney;
      final mode = normalizeBenefitMode(tier.benefitMode);

      int d = 0;
      if (mode == 'PERCENT') {
        d = (baseMoney * tier.value) ~/ 10000;
      } else if (mode == 'FIXED') {
        d = tier.value;
      }
      // "Giảm tối đa" áp cho cả 2 kiểu
      if (maxDiscount > 0 && d > maxDiscount) d = maxDiscount;
      d = max(0, min(d, baseMoney));

      calculatedBillDiscounts.add({
        'campaign': campaign,
        'tier': tier,
        'discount': d,
        'lines': eligibleLines,
      });
    }

    if (calculatedBillDiscounts.isNotEmpty) {
      var bestDiscount = calculatedBillDiscounts.reduce((a, b) => (a['discount'] as int) >= (b['discount'] as int) ? a : b);
      var campaign = bestDiscount['campaign'] as CampaignModel;
      var tier = bestDiscount['tier'] as CampaignTier;
      final eligibleLines = bestDiscount['lines'] as List<PricingLineItem>;
      int discountToApply = bestDiscount['discount'] as int;

      if (discountToApply > 0) {
        totalDiscount += discountToApply;
        markApplied(campaign.campaignId);

        int eligibleMoney = eligibleLines.fold(0, (sum, l) => sum + max(0, lineFinalPrices[l.lineId] ?? 0));
        int allocatedSum = 0;
        List<Map<String, dynamic>> remainders = [];
        Map<String, int> allocations = {};

        for (var line in eligibleLines) {
          int lineMoney = max(0, lineFinalPrices[line.lineId] ?? 0);
          double weight = eligibleMoney > 0 ? lineMoney / eligibleMoney : 0;
          int allocated = (discountToApply * weight).floor();
          double remainder = (discountToApply * weight) - allocated;

          allocations[line.lineId] = allocated;
          allocatedSum += allocated;

          remainders.add({
            'lineId': line.lineId,
            'remainder': remainder,
          });
        }

        int diff = discountToApply - allocatedSum;
        remainders.sort((a, b) {
          int r = (b['remainder'] as double).compareTo(a['remainder'] as double);
          if (r != 0) return r;
          return (b['lineId'] as String).compareTo(a['lineId'] as String);
        });

        for (int i = 0; i < diff && remainders.isNotEmpty; i++) {
          String id = remainders[i % remainders.length]['lineId'];
          allocations[id] = (allocations[id] ?? 0) + 1;
        }

        for (var line in eligibleLines) {
          String id = line.lineId;
          int alloc = allocations[id] ?? 0;
          lineDiscounts[id] = (lineDiscounts[id] ?? 0) + alloc;
          lineFinalPrices[id] = (lineFinalPrices[id] ?? 0) - alloc;
        }

        billBenefits.add(BillBenefit(
          campaignId: campaign.campaignId,
          tierId: tier.tierId,
          discountMoney: discountToApply,
          lineAllocations: allocations,
        ));
      }
    }
  }

  final manualDiscount = input.manualDiscountMoney + manualLineDiscountTotal;
  int finalDiscount = totalDiscount + manualDiscount;
  int netMoney = grossMoney - finalDiscount;
  if (netMoney < 0) netMoney = 0;

  // Tổng hợp theo dòng (mỗi dòng 1 phần tử, thứ tự như đầu vào), sau đó là chi tiết món thưởng theo KM
  final List<LineBenefit> lineBenefits = [];
  for (var line in input.lines) {
    if (!line.isGift) {
      lineBenefits.add(LineBenefit(
        lineId: line.lineId,
        campaignId: '',
        tierId: '',
        discountMoney: lineDiscounts[line.lineId] ?? 0,
        originalPrice: line.unitPrice * line.quantity,
        effectivePrice: lineFinalPrices[line.lineId] ?? 0,
        isGift: false,
      ));
    }
  }

  return PriceQuoteModel(
    quoteId: 'Q-${DateTime.now().millisecondsSinceEpoch}',
    orderId: '',
    orderVersion: 1,
    inputHash: '',
    expiresAt: input.serverNowMs + 3600000,
    pricingPolicyVersion: input.pricingPolicyVersion,
    grossMoney: grossMoney,
    eligibleBaseMoney: grossMoney,
    totalPromotionDiscount: totalDiscount,
    manualDiscount: manualDiscount,
    totalDiscountMoney: finalDiscount,
    netMoney: netMoney,
    lineBenefits: lineBenefits,
    rewardBenefits: rewardBenefits,
    billBenefits: billBenefits,
    appliedCampaignIds: appliedCampaigns,
    reasons: nonAppliedReasons,
    state: 'VALID',
    createdAt: input.serverNowMs,
  );
}
