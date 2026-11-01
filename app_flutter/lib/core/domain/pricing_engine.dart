import '../../data/models/campaign_models.dart';
import 'dart:math';
import '../../data/models/order_item_model.dart';

/// Đầu vào cho Pricing Engine
class PricingInput {
  final String branchId;
  final String? customerId;
  /// Ngày sinh khách đã gắn vào đơn (yyyy-MM-dd hoặc dd/MM/yyyy); rỗng/null = chưa có khách / chưa có ngày sinh
  final String? customerBirthday;
  final int? guestCount;
  final int serverNowMs;
  final List<PricingLineItem> lines;
  final String? enteredCode;
  final int manualDiscountMoney;
  final int pricingPolicyVersion;
  /// Bỏ qua kiểm tra khung giờ (dùng khi tính lại đơn ĐÃ ÁP DỤNG khuyến mãi để treo đơn qua giờ không bị mất)
  final bool ignoreSchedule;
  /// Tặng/giảm món theo giá trị đơn: CHỈ giảm trên dòng món tặng riêng (rewardCampaignId), không lấy món khách đã gọi
  final bool dedicatedRewardOnly;
  /// Tiền đã giảm trên từng dòng (lineId) bởi các chương trình áp dụng TRƯỚC (cộng dồn KM): chương trình này chỉ
  /// giảm trên phần còn lại — vd ly chanh đã tặng 0đ thì giảm 20% hóa đơn không tính lại trên ly đó.
  final Map<String, int> priorLineDiscounts;

  PricingInput({
    required this.branchId,
    this.customerId,
    this.customerBirthday,
    this.guestCount,
    required this.serverNowMs,
    required this.lines,
    this.enteredCode,
    this.manualDiscountMoney = 0,
    this.pricingPolicyVersion = 1,
    this.ignoreSchedule = false,
    this.dedicatedRewardOnly = false,
    this.priorLineDiscounts = const {},
  });
}

class PricingLineItem {
  final String lineId;
  final String itemId;
  final String? itemName;
  final String? itemCode;
  final String? dbKey;
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

  /// Lúc gọi món (ms). KM có khung giờ chỉ tính dòng gọi TRONG khung giờ; null = món mới (tính theo lúc bấm).
  final int? orderedAtMs;

  /// Dòng MÓN TẶNG thêm riêng cho chương trình này (không tính vào mốc giá trị đơn; được ưu tiên nhận ưu đãi)
  final String? rewardCampaignId;

  /// Tiền topping của MỘT phần (đã gồm trong unitPrice) và số topping — để tặng kèm đúng số topping cho món tặng
  final int toppingUnitPrice;
  final int toppingCount;

  PricingLineItem({
    required this.lineId,
    required this.itemId,
    this.itemName,
    this.itemCode,
    this.dbKey,
    this.itemVariantId,
    this.groupId,
    required this.quantity,
    required this.unitPrice,
    this.isGift = false,
    this.discountedQuantity = 0,
    this.discountPercent = 0,
    this.discountUnitAmount = 0,
    this.orderedAtMs,
    this.rewardCampaignId,
    this.toppingUnitPrice = 0,
    this.toppingCount = 0,
  });

  /// Dựng từ dòng món của giỏ hàng (giữ cấu hình giảm giá theo phần)
  factory PricingLineItem.fromOrderItem(
    OrderItemModel item, {
    required String lineId,
    String? groupId,
    String? itemCode,
    String? dbKey,
  }) =>
      PricingLineItem(
        lineId: lineId,
        itemId: item.productId.toString(),
        itemName: item.name,
        itemCode: itemCode,
        dbKey: dbKey,
        groupId: groupId,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        discountedQuantity: item.discountedQuantity,
        discountPercent: item.discountPercent,
        discountUnitAmount: item.discountUnitAmount,
        orderedAtMs: item.orderedAt,
        rewardCampaignId: item.rewardCampaignId.isEmpty ? null : item.rewardCampaignId,
        toppingUnitPrice: item.toppingPrice,
        toppingCount: item.selectedToppings.where((t) => t.trim().isNotEmpty).length,
      );

  /// Bản sao bỏ giờ gọi món (để so sánh: nếu không xét giờ gọi thì chương trình có được áp dụng không)
  PricingLineItem withoutOrderTime() => PricingLineItem(
        lineId: lineId,
        itemId: itemId,
        itemName: itemName,
        itemCode: itemCode,
        dbKey: dbKey,
        itemVariantId: itemVariantId,
        groupId: groupId,
        quantity: quantity,
        unitPrice: unitPrice,
        isGift: isGift,
        discountedQuantity: discountedQuantity,
        discountPercent: discountPercent,
        discountUnitAmount: discountUnitAmount,
        rewardCampaignId: rewardCampaignId,
        toppingUnitPrice: toppingUnitPrice,
        toppingCount: toppingCount,
      );

  /// Dòng này gọi trong thời gian áp dụng của [c]? (món chưa có giờ gọi = món mới → luôn được tính)
  bool orderedWithin(CampaignModel c) => orderedAtMs == null || orderedAtMs! <= 0 || c.isEligibleAt(orderedAtMs!);

  /// Chuẩn hóa bỏ dấu tiếng Việt để đối sánh linh hoạt (không phụ thuộc gõ dấu khác nhau)
  static String stripAccents(String str) {
    var result = str;
    const from =
        'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to =
        'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }

  /// Khóa so khớp NHÓM món: bỏ dấu, không phân biệt hoa/thường, gộp khoảng trắng
  /// (tên nhóm gõ khác dấu/khoảng trắng giữa web và app vẫn khớp).
  static String normGroup(String s) =>
      stripAccents(s.replaceAll(RegExp(r'[\u0300-\u036f]'), '').trim().toLowerCase()).replaceAll(RegExp(r'\s+'), ' ');

  /// Kiểm tra xem dòng món này có khớp với định danh [target] hay không.
  /// [target] có thể là: numeric productId, tên món, mã SKU món, hoặc database key RTDB.
  bool matchesTarget(String target) {
    final t = target.trim().toLowerCase();
    if (t.isEmpty) return false;
    if (itemId.toLowerCase() == t) return true;
    if (itemName != null && itemName!.trim().toLowerCase() == t) return true;
    if (itemCode != null && itemCode!.trim().toLowerCase() == t) return true;
    if (dbKey != null && dbKey!.trim().toLowerCase() == t) return true;
    final tAscii = stripAccents(t);
    if (itemName != null && stripAccents(itemName!.trim().toLowerCase()) == tAscii) return true;
    return false;
  }

  /// Kiểm tra xem dòng món này có khớp với bất kỳ định danh nào trong [targets] hay không.
  bool matchesAnyTarget(Iterable<String> targets) {
    return targets.any((t) => matchesTarget(t));
  }

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

/// Hôm nay (giờ Việt Nam, UTC+7) có phải sinh nhật không. Chấp nhận yyyy-MM-dd, dd/MM/yyyy, dd-MM-yyyy.
bool isBirthdayToday(String? birthday, int nowMs) {
  final s = (birthday ?? '').trim();
  if (s.isEmpty) return false;
  int? month, day;
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  final vn = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(s);
  if (iso != null) {
    month = int.parse(iso.group(2)!);
    day = int.parse(iso.group(3)!);
  } else if (vn != null) {
    day = int.parse(vn.group(1)!);
    month = int.parse(vn.group(2)!);
  }
  if (month == null || day == null) return false;
  final now = DateTime.fromMillisecondsSinceEpoch(nowMs, isUtc: true).add(const Duration(hours: 7));
  return now.month == month && now.day == day;
}

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
  // Cộng dồn KM: trừ phần các chương trình trước đã giảm (mốc giá trị đơn vẫn xét trên giá sau giảm thủ công)
  input.priorLineDiscounts.forEach((id, d) {
    if (d > 0 && lineFinalPrices.containsKey(id)) lineFinalPrices[id] = max(0, lineFinalPrices[id]! - d);
  });
  // Số phần của dòng đã được dùng làm món thưởng (tránh giảm 2 lần)
  final rewardedUnits = <String, int>{};

  void addReason(CampaignModel c, String code, String msg) {
    nonAppliedReasons.add(QuoteReason(campaignId: c.campaignId, reasonCode: code, reasonMessage: msg));
  }

  void markApplied(String campaignId) {
    if (!appliedCampaigns.contains(campaignId)) appliedCampaigns.add(campaignId);
  }

  bool matchGroup(String? itemGroup, Set<String> targetGroups) {
    if (itemGroup == null || targetGroups.isEmpty) return false;
    final itemNorm = PricingLineItem.normGroup(itemGroup);
    return targetGroups.any((g) => PricingLineItem.normGroup(g) == itemNorm);
  }

  bool inScope(CampaignModel c, PricingLineItem l) {
    if (l.isGift) return false;
    if (!l.orderedWithin(c)) return false;
    if (l.matchesAnyTarget(c.excludedItemIds)) return false;
    if (c.includedItemIds.isEmpty && c.includedGroupIds.isEmpty) return true;
    return l.matchesAnyTarget(c.includedItemIds) || matchGroup(l.groupId, c.includedGroupIds.toSet());
  }

  /// Giảm [units] phần của dòng [line] theo cách tính lợi ích; tôn trọng giảm giá đã có trên dòng
  /// (không vượt quá giá trị còn lại tương ứng với số phần). Trả về số tiền đã giảm.
  int rewardUnitsOnLine(PricingLineItem line, int units, String mode, int value, String campaignId, String tierId, {int? freeToppings}) {
    final avail = line.quantity - (rewardedUnits[line.lineId] ?? 0);
    if (units <= 0 || avail <= 0) return 0;
    final k = min(units, avail);
    final remaining = max(0, lineFinalPrices[line.lineId] ?? 0);
    // Dòng món tặng có topping: ưu đãi tính trên phần món (giá + size), cộng thêm tối đa [freeToppings] topping
    // được tặng kèm (theo giá trung bình một topping của dòng); topping vượt số tặng vẫn tính tiền.
    final perUnit = freeToppings == null
        ? _unitBenefit(mode, value, line.unitPrice)
        : (() {
            final topUnit = line.toppingCount > 0 ? max(0, min(line.toppingUnitPrice, line.unitPrice)) : 0;
            // Đủ số topping được tặng → tặng hết (chính xác); vượt số tặng → chia theo giá trung bình một topping
            final freeTop = line.toppingCount == 0
                ? 0
                : (freeToppings >= line.toppingCount ? topUnit : topUnit * freeToppings ~/ line.toppingCount);
            return min(line.unitPrice, _unitBenefit(mode, value, line.unitPrice - topUnit) + freeTop);
          })();
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
    int? Function(PricingLineItem)? freeToppingsOf,
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
      total += rewardUnitsOnLine(l, take, mode, value, campaignId, tierId, freeToppings: freeToppingsOf?.call(l));
      left -= take;
      if (both) bothLeft -= take;
    }
    return total;
  }

  // Evaluate campaigns
  for (var campaign in activeCampaigns) {
    if (!input.ignoreSchedule && !campaign.isEligibleAt(input.serverNowMs)) {
      addReason(campaign, 'OUTSIDE_SCHEDULE', 'Ngoài thời gian áp dụng');
      continue;
    }
    if (!campaign.isEligibleForBranch(input.branchId)) {
      addReason(campaign, 'BRANCH_NOT_SUPPORTED', 'Không áp dụng tại chi nhánh này');
      continue;
    }
    if (campaign.birthdayOnly && !isBirthdayToday(input.customerBirthday, input.serverNowMs)) {
      final has = (input.customerBirthday ?? '').trim().isNotEmpty;
      addReason(campaign, has ? 'NOT_BIRTHDAY' : 'BIRTHDAY_CUSTOMER_REQUIRED',
          has ? 'Hôm nay không phải sinh nhật của khách' : 'Gắn khách hàng có ngày sinh để áp dụng (chỉ đúng ngày sinh nhật)');
      continue;
    }
    // Chỉ món gọi TRONG khung giờ của chương trình mới được tính (món gọi ngoài giờ không đủ điều kiện)
    final lines = input.lines.where((l) => l.orderedWithin(campaign)).toList();
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
        final buyGroups = condition.buyGroupIds.toSet();
        final rewardGroups = condition.rewardGroupIds.toSet();
        bool isBuy(PricingLineItem l) => l.matchesAnyTarget(buyIds) || matchGroup(l.groupId, buyGroups);
        bool isReward(PricingLineItem l) => l.matchesAnyTarget(rewardIds) || matchGroup(l.groupId, rewardGroups);
        final buyQty = condition.requiredBuyQty;
        final rewardQty = condition.rewardQty;
        if ((buyIds.isEmpty && buyGroups.isEmpty) || (rewardIds.isEmpty && rewardGroups.isEmpty) || buyQty <= 0 || rewardQty <= 0) {
          addReason(campaign, 'INVALID_CONFIG', 'Điều kiện Mua X tặng/giảm Y chưa cấu hình đủ');
          continue;
        }

        int avail(PricingLineItem l) => l.quantity - (rewardedUnits[l.lineId] ?? 0);
        int xo = 0, yo = 0, bo = 0; // chỉ X, chỉ Y, vừa X vừa Y
        for (final l in lines) {
          if (l.isGift || l.matchesAnyTarget(campaign.excludedItemIds)) continue;
          final isX = isBuy(l);
          final isY = isReward(l);
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

        final candidates = lines
            .where((l) => !l.isGift && isReward(l) && !l.matchesAnyTarget(campaign.excludedItemIds))
            .toList();
        campaignDiscount += distributeReward(
          candidates: candidates,
          units: bestReward,
          mode: condition.benefitMode,
          value: condition.value,
          campaignId: campaign.campaignId,
          tierId: condition.conditionId,
          isBoth: isBuy,
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
      // Dòng món tặng của chính chương trình không tính vào mốc giá trị đơn
      bool isOwnReward(PricingLineItem l) => l.rewardCampaignId != null && l.rewardCampaignId == campaign.campaignId;
      int base = 0;
      for (final l in lines) {
        if (inScope(campaign, l) && !isOwnReward(l)) base += afterManual[l.lineId] ?? 0;
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
      final rewardGroups = tier.rewardGroupIds.toSet();
      if (rewardIds.isEmpty && rewardGroups.isEmpty) {
        addReason(campaign, 'INVALID_CONFIG', 'Chưa chọn món được tặng/giảm');
        continue;
      }
      final units = tier.maxRewardQty > 0 ? tier.maxRewardQty : 1;
      final matching = lines
          .where((l) =>
              !l.isGift &&
              (l.matchesAnyTarget(rewardIds) || matchGroup(l.groupId, rewardGroups)) &&
              !l.matchesAnyTarget(campaign.excludedItemIds))
          .toList();
      // Ưu tiên dòng món tặng riêng; không có thì (trừ khi dedicatedRewardOnly) giảm trên món đã có như trước
      final dedicated = matching.where(isOwnReward).toList();
      // Chỉ hình thức TẶNG (miễn phí) mới cần ly tặng riêng; giảm tiền / giảm % thì giảm thẳng trên món khách đã gọi
      // (vd 'giảm 16K cho 1 ly xoài')
      final giftOnly = input.dedicatedRewardOnly && normalizeBenefitMode(tier.benefitMode) == 'FREE';
      final candidates = dedicated.isNotEmpty ? dedicated : (giftOnly ? <PricingLineItem>[] : matching);
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
        // Món tặng (dòng tặng riêng hoặc món có sẵn trong đơn) chỉ miễn phí giá món + size; topping / phụ thu
        // (vd 'Tăng giá Grab') chỉ tặng đúng số topping cấu hình (0 = tính tiền)
        freeToppingsOf: (_) => tier.freeToppingCount,
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
        // Đồng giá (FIXEDPRICE) hoặc đồng giảm: % / số tiền / tặng — tính theo từng phần của dòng
        // maxRewardQty > 0: chỉ áp cho tối đa N phần trong đơn (0 = mọi phần)
        // Safeguard cho mã KM Trà Xoài (KM/G-003): luôn chỉ giảm tối đa 1 phần kể cả khi DB bị cấu hình 0 hoặc rỗng
        final isMangoTeaSpecial = campaign.campaignId == 'CAM_1792678747107_dn5u' || campaign.programCode == 'KM/G-003';
        final defaultMax = isMangoTeaSpecial ? 1 : 1 << 30;
        int unitsLeft = tier.maxRewardQty > 0 ? tier.maxRewardQty : defaultMax;
        bool applied = false;
        for (var line in lines) {
          if (unitsLeft <= 0) break;
          if (!inScope(campaign, line)) continue;
          final perUnit = _unitBenefit(tier.benefitMode, tier.value, line.unitPrice);
          if (perUnit <= 0) continue;
          final remaining = max(0, lineFinalPrices[line.lineId] ?? 0);
          final take = min(line.quantity, unitsLeft);
          int discount = min(perUnit * take, remaining);
          if (discount <= 0) continue;
          unitsLeft -= take;
          lineDiscounts[line.lineId] = (lineDiscounts[line.lineId] ?? 0) + discount;
          lineFinalPrices[line.lineId] = remaining - discount;
          totalDiscount += discount;
          applied = true;
        }
        if (applied) {
          markApplied(campaign.campaignId);
        } else if (!lines.any((l) => inScope(campaign, l))) {
          addReason(campaign, 'ITEM_NOT_IN_BILL', 'Thêm món thuộc chương trình vào đơn để áp dụng');
        }
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
