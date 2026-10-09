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

/// Pricing Engine - Pure function
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
  List<LineBenefit> lineBenefits = [];

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

  // Evaluate campaigns
  for (var campaign in activeCampaigns) {
    if (!campaign.isEligibleAt(input.serverNowMs)) {
      nonAppliedReasons.add(QuoteReason(campaignId: campaign.campaignId, reasonCode: 'OUTSIDE_SCHEDULE', reasonMessage: 'Ngoài thời gian áp dụng'));
      continue;
    }
    if (!campaign.isEligibleForBranch(input.branchId)) {
      nonAppliedReasons.add(QuoteReason(campaignId: campaign.campaignId, reasonCode: 'BRANCH_NOT_SUPPORTED', reasonMessage: 'Không áp dụng tại chi nhánh này'));
      continue;
    }

    if (campaign.campaignType == 'BILLDISCOUNT' || campaign.campaignType == 'BILL_DISCOUNT') {
      if (campaign.tiers.isNotEmpty && campaign.tiers.first.conditionBasis == 'GUESTCOUNT') {
        if (input.guestCount == null || input.guestCount! < campaign.tiers.first.threshold) {
          nonAppliedReasons.add(QuoteReason(campaignId: campaign.campaignId, reasonCode: 'GUEST_COUNT_REQUIRED', reasonMessage: 'Chưa đủ số lượng khách'));
          continue;
        }
      }
      eligibleBillDiscounts.add(campaign);
    } else if (campaign.campaignType == 'BUYXGETY' || campaign.campaignType == 'BUY_X_GET_Y') {
      for (var condition in campaign.buyConditions) {
        var buyItemIds = condition.buyItemIds;
        var buyQty = condition.requiredBuyQty;
        var rewardQty = condition.rewardQty;
        var multiplierOn = condition.multiplyByBundle;

        int totalBuyUnits = input.lines
            .where((l) => buyItemIds.contains(l.itemId) && !l.isGift)
            .fold(0, (sum, l) => sum + l.quantity);

        if (totalBuyUnits < buyQty) {
          nonAppliedReasons.add(QuoteReason(campaignId: campaign.campaignId, reasonCode: 'INSUFFICIENT_BUY_ITEMS', reasonMessage: 'Chưa đủ số lượng mua'));
          continue;
        }

        int bundles = totalBuyUnits ~/ buyQty;
        if (!multiplierOn) {
          bundles = 1;
        }
        int rewardsEarned = bundles * rewardQty;

        bool hasXYCollision = false;
        for (var rid in condition.rewardItemIds) {
          if (buyItemIds.contains(rid)) hasXYCollision = true;
        }

        if (hasXYCollision) {
          if (totalBuyUnits < (buyQty + rewardQty)) {
            nonAppliedReasons.add(QuoteReason(campaignId: campaign.campaignId, reasonCode: 'INSUFFICIENT_BUY_ITEMS', reasonMessage: 'Chưa đủ số lượng mua'));
            continue;
          } else {
            bundles = totalBuyUnits ~/ (buyQty + rewardQty);
            if (!multiplierOn) bundles = 1;
            rewardsEarned = bundles * rewardQty;
          }
        }

        if (rewardsEarned > 0 && !appliedCampaigns.contains(campaign.campaignId)) {
          appliedCampaigns.add(campaign.campaignId);
        }
      }
    } else if (campaign.campaignType == 'ITEMPRICERULE' || campaign.campaignType == 'ITEM_PRICE_RULE') {
      var itemIds = campaign.includedItemIds;
      var groupIds = campaign.includedGroupIds;
      if (campaign.tiers.isNotEmpty) {
        var tier = campaign.tiers.first;
        var fixedPrice = (tier.benefitMode == 'FIXEDPRICE') ? tier.value : null;

        bool applied = false;
        for (var line in input.lines) {
          bool isMatch = (itemIds.isEmpty && groupIds.isEmpty) ||
              itemIds.contains(line.itemId) ||
              (line.groupId != null && groupIds.contains(line.groupId));
          if (!line.isGift && isMatch) {
            if (fixedPrice != null && line.unitPrice > fixedPrice) {
              int discount = (line.unitPrice - fixedPrice) * line.quantity;
              lineDiscounts[line.lineId] = (lineDiscounts[line.lineId] ?? 0) + discount;
              lineFinalPrices[line.lineId] = (lineFinalPrices[line.lineId] ?? 0) - discount;
              totalDiscount += discount;
              applied = true;
            }
          }
        }
        if (applied && !appliedCampaigns.contains(campaign.campaignId)) {
          appliedCampaigns.add(campaign.campaignId);
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
      var tier = campaign.tiers.first;
      var maxDiscount = tier.maxDiscountMoney;
      var percent = (tier.benefitMode == 'PERCENT') ? tier.value : null; 
      var fixed = (tier.benefitMode == 'FIXED') ? tier.value : null;

      int baseMoney = grossMoney;
      if (campaign.includedItemIds.isNotEmpty || campaign.includedGroupIds.isNotEmpty) {
        baseMoney = input.lines
            .where((l) =>
                !l.isGift &&
                (campaign.includedItemIds.contains(l.itemId) ||
                    (l.groupId != null && campaign.includedGroupIds.contains(l.groupId))))
            .fold(0, (sum, l) => sum + l.unitPrice * l.quantity);
      }

      if (tier.threshold > 0 && baseMoney < tier.threshold) {
        continue;
      }

      int d = 0;
      if (percent != null) {
        d = (baseMoney * percent) ~/ 10000;
        if (maxDiscount > 0 && d > maxDiscount) {
          d = maxDiscount;
        }
      } else if (fixed != null) {
        d = fixed;
      }
      
      d = min(d, baseMoney); 

      calculatedBillDiscounts.add({
        'campaign': campaign,
        'discount': d,
      });
    }

    if (calculatedBillDiscounts.isNotEmpty) {
      var bestDiscount = calculatedBillDiscounts.reduce((a, b) => (a['discount'] as int) >= (b['discount'] as int) ? a : b);
      var campaign = bestDiscount['campaign'] as CampaignModel;
      int discountToApply = bestDiscount['discount'] as int;

      if (discountToApply > 0) {
        totalDiscount += discountToApply;
        appliedCampaigns.add(campaign.campaignId);

        int eligibleMoney = input.lines.where((l) => !l.isGift).fold(0, (sum, l) => sum + l.unitPrice * l.quantity);
        int allocatedSum = 0;
        List<Map<String, dynamic>> remainders = [];
        Map<String, int> allocations = {};

        for (var line in input.lines) {
          if (!line.isGift) {
            int lineMoney = line.unitPrice * line.quantity;
            double weight = lineMoney / eligibleMoney;
            int allocated = (discountToApply * weight).floor();
            double remainder = (discountToApply * weight) - allocated;
            
            allocations[line.lineId] = allocated;
            allocatedSum += allocated;

            remainders.add({
              'lineId': line.lineId,
              'remainder': remainder,
            });
          }
        }

        int diff = discountToApply - allocatedSum;
        remainders.sort((a, b) {
          int r = (b['remainder'] as double).compareTo(a['remainder'] as double);
          if (r != 0) return r;
          return (b['lineId'] as String).compareTo(a['lineId'] as String);
        });

        for (int i = 0; i < diff; i++) {
          String id = remainders[i]['lineId'];
          allocations[id] = (allocations[id] ?? 0) + 1;
        }

        for (var line in input.lines) {
          if (!line.isGift) {
            String id = line.lineId;
            int alloc = allocations[id] ?? 0;
            lineDiscounts[id] = (lineDiscounts[id] ?? 0) + alloc;
            lineFinalPrices[id] = (lineFinalPrices[id] ?? 0) - alloc;
          }
        }

        billBenefits.add(BillBenefit(
          campaignId: campaign.campaignId,
          tierId: campaign.tiers.first.tierId,
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
    billBenefits: billBenefits,
    appliedCampaignIds: appliedCampaigns,
    reasons: nonAppliedReasons,
    state: 'VALID',
    createdAt: input.serverNowMs,
  );
}
