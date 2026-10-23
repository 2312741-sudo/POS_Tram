// lib/features/orders/widgets/campaign_pricing.dart
// Cầu nối giỏ hàng ↔ Pricing Engine cho Chương trình khuyến mãi (CampaignModel).
import '../../../core/domain/pricing_engine.dart';
import '../../../data/models/campaign_models.dart';
import '../../../data/models/order_item_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/promotion_model.dart';

class CartCampaignPricing {
  CartCampaignPricing._();

  /// Dựng dòng tính giá từ giỏ hàng (lineId = vị trí dòng, groupId = tên nhóm món)
  static List<PricingLineItem> lines(List<OrderItemModel> cart, List<ProductModel> products) {
    final cat = {for (final p in products) p.id: p.category};
    return [
      for (int i = 0; i < cart.length; i++)
        PricingLineItem.fromOrderItem(cart[i], lineId: 'L$i', groupId: cat[cart[i].productId]),
    ];
  }

  /// Tính riêng 1 chương trình trên giỏ hàng hiện tại
  static PriceQuoteModel quote(
    CampaignModel campaign, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
    required String branchId,
    int? guestCount,
    String? customerBirthday,
    int? nowMs,
  }) {
    return calculatePrice(
      input: PricingInput(
        branchId: branchId,
        customerBirthday: customerBirthday,
        guestCount: guestCount,
        serverNowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
        lines: lines(cart, products),
      ),
      activeCampaigns: [campaign],
      counters: const {},
      customerCounters: const {},
    );
  }

  /// Chương trình "tặng/giảm món theo giá trị đơn" hoặc "Mua X tặng/giảm Y" đủ điều kiện nhưng món thưởng chưa có trong đơn?
  /// Cho phép bấm để tự thêm món thưởng vào đơn.
  static bool needsRewardItems(PriceQuoteModel quote, CampaignModel campaign) {
    final type = campaign.campaignType.toUpperCase().replaceAll('_', '');
    return (type == 'ORDERVALUEITEMBENEFIT' || type == 'BUYXGETY') &&
        quote.reasons.any((r) => r.campaignId == campaign.campaignId && r.reasonCode == 'REWARD_ITEM_NOT_IN_BILL');
  }

  /// Kế hoạch tự thêm món thưởng: số phần cần thêm + các món có thể chọn (theo món và theo nhóm món).
  /// Trả null nếu chưa đủ điều kiện hoặc không có món thưởng nào trong thực đơn.
  static ({int units, List<ProductModel> candidates})? rewardPlan(
    CampaignModel c, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
  }) {
    final lns = lines(cart, products);
    bool matches(PricingLineItem l, Set<String> ids, Set<String> groups) {
      if (ids.contains(l.itemId)) return true;
      if (l.groupId == null || groups.isEmpty) return false;
      final gNorm = l.groupId!.trim().toLowerCase();
      return groups.any((g) => g.trim().toLowerCase() == gNorm);
    }

    List<ProductModel> pick(Set<String> ids, Set<String> groups) => products
        .where((p) =>
            !p.isTopping &&
            p.isAvailable &&
            !c.excludedItemIds.contains(p.id.toString()) &&
            (ids.contains(p.id.toString()) || groups.any((g) => g.trim().toLowerCase() == p.category.trim().toLowerCase())))
        .toList();

    final type = c.campaignType.toUpperCase().replaceAll('_', '');
    if (type == 'BUYXGETY') {
      for (final cond in c.buyConditions) {
        final buyIds = cond.buyItemIds.toSet(), buyGroups = cond.buyGroupIds.toSet();
        final rewardIds = cond.rewardItemIds.toSet(), rewardGroups = cond.rewardGroupIds.toSet();
        if (cond.requiredBuyQty <= 0 || cond.rewardQty <= 0) continue;
        final x = lns.where((l) => !l.isGift && matches(l, buyIds, buyGroups)).fold<int>(0, (s, l) => s + l.quantity);
        final bundles = cond.multiplyByBundle ? x ~/ cond.requiredBuyQty : (x >= cond.requiredBuyQty ? 1 : 0);
        if (bundles <= 0) continue;
        final cands = pick(rewardIds, rewardGroups);
        if (cands.isNotEmpty) return (units: bundles * cond.rewardQty, candidates: cands);
      }
      return null;
    }
    if (type == 'ORDERVALUEITEMBENEFIT') {
      final inScopeAll = c.includedItemIds.isEmpty && c.includedGroupIds.isEmpty;
      int base = 0;
      for (final l in lns) {
        if (l.isGift || c.excludedItemIds.contains(l.itemId)) continue;
        final inScope = inScopeAll || c.includedItemIds.contains(l.itemId) || (l.groupId != null && c.includedGroupIds.contains(l.groupId));
        if (inScope) base += l.unitPrice * l.quantity - l.manualLineDiscount;
      }
      final tiers = List<CampaignTier>.from(c.tiers)..sort((a, b) => b.threshold.compareTo(a.threshold));
      final tier = tiers.where((t) => base >= t.threshold).firstOrNull;
      if (tier == null) return null;
      final cands = pick(tier.rewardItemIds.toSet(), tier.rewardGroupIds.toSet());
      if (cands.isEmpty) return null;
      return (units: tier.maxRewardQty > 0 ? tier.maxRewardQty : 1, candidates: cands);
    }
    return null;
  }

  /// Lý do chưa áp dụng (nếu có) của chương trình trong [quote]
  static String? reason(PriceQuoteModel quote, CampaignModel campaign) =>
      quote.reasons.where((r) => r.campaignId == campaign.campaignId).map((r) => r.reasonMessage).firstOrNull;

  /// Lấy thông tin chi tiết về combo Mua X tặng/giảm Y:
  /// - [buyUnits]: Tổng số lượng món mua (nước) trong giỏ hàng
  /// - [rewardUnitsInCart]: Số lượng món giảm giá (bánh) hiện có trong giỏ hàng
  /// - [maxRewardAllowed]: Số lượng món giảm giá tối đa được phép theo số món nước
  /// - [remainingRewardUnits]: Số lượng món giảm giá còn được phép chọn thêm
  /// - [candidates]: Danh sách các món thuộc nhóm hoặc món được giảm giá
  /// - [benefitMode]: Cách tính giảm (FIXED, PERCENT, FREE, FIXED_PRICE)
  /// - [discountPerUnit]: Số tiền giảm ước tính mỗi phần
  static ({
    int buyUnits,
    int rewardUnitsInCart,
    int maxRewardAllowed,
    int remainingRewardUnits,
    int requiredBuyQty,
    int rewardQty,
    List<ProductModel> candidates,
    int discountPerUnit,
    String benefitMode,
  })? getComboInfo(
    CampaignModel c, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
  }) {
    final type = c.campaignType.toUpperCase().replaceAll('_', '');
    final lns = lines(cart, products);

    bool matches(PricingLineItem l, Set<String> ids, Set<String> groups) {
      if (ids.contains(l.itemId)) return true;
      if (l.groupId == null || groups.isEmpty) return false;
      final gNorm = l.groupId!.trim().toLowerCase();
      return groups.any((g) => g.trim().toLowerCase() == gNorm);
    }

    List<ProductModel> pick(Set<String> ids, Set<String> groups) => products
        .where((p) =>
            !p.isTopping &&
            p.isAvailable &&
            !c.excludedItemIds.contains(p.id.toString()) &&
            (ids.contains(p.id.toString()) || groups.any((g) => g.trim().toLowerCase() == p.category.trim().toLowerCase())))
        .toList();

    if (type == 'BUYXGETY') {
      for (final cond in c.buyConditions) {
        final buyIds = cond.buyItemIds.toSet(), buyGroups = cond.buyGroupIds.toSet();
        final rewardIds = cond.rewardItemIds.toSet(), rewardGroups = cond.rewardGroupIds.toSet();
        if (cond.requiredBuyQty <= 0 || cond.rewardQty <= 0) continue;

        // Số lượng nước trong giỏ hàng
        final buyUnits = lns
            .where((l) => !l.isGift && matches(l, buyIds, buyGroups))
            .fold<int>(0, (s, l) => s + l.quantity);

        // Số lượng bánh hiện có trong giỏ hàng
        final rewardUnitsInCart = lns
            .where((l) => !l.isGift && matches(l, rewardIds, rewardGroups))
            .fold<int>(0, (s, l) => s + l.quantity);

        final bundles = cond.multiplyByBundle ? buyUnits ~/ cond.requiredBuyQty : (buyUnits >= cond.requiredBuyQty ? 1 : 0);
        final maxRewardAllowed = bundles * cond.rewardQty;
        final remainingRewardUnits = (maxRewardAllowed - rewardUnitsInCart).clamp(0, 9999);

        final candidates = pick(rewardIds, rewardGroups);
        int discountPerUnit = 0;
        final mode = cond.benefitMode.toUpperCase().replaceAll('_', '');
        if (mode == 'FIXED' || mode == 'DISCOUNTAMOUNT') {
          discountPerUnit = cond.value;
        } else if (mode == 'FREE' || mode == 'FREEITEM') {
          discountPerUnit = candidates.isNotEmpty ? candidates.first.price : 0;
        }

        return (
          buyUnits: buyUnits,
          rewardUnitsInCart: rewardUnitsInCart,
          maxRewardAllowed: maxRewardAllowed,
          remainingRewardUnits: remainingRewardUnits,
          requiredBuyQty: cond.requiredBuyQty,
          rewardQty: cond.rewardQty,
          candidates: candidates,
          discountPerUnit: discountPerUnit,
          benefitMode: cond.benefitMode,
        );
      }
    }
    return null;
  }

  /// Bản ghi giảm giá lưu vào bill.discounts (giữ promoId/promoCode cho tương thích + trường mới cho báo cáo)
  static BillDiscountModel discount(
    CampaignModel campaign,
    int amount, {
    String? voucherCode,
    String? staffNote,
    int? comboCount,
  }) {
    final code = (voucherCode != null && voucherCode.trim().isNotEmpty) ? voucherCode.trim().toUpperCase() : null;
    return BillDiscountModel(
      promoId: campaign.campaignId,
      promoCode: code,
      description: code != null ? '${campaign.name} (mã $code)' : campaign.name,
      amount: amount,
      staffNote: staffNote,
      campaignId: campaign.campaignId,
      campaignName: campaign.name,
      programCode: campaign.programCode,
      campaignType: campaign.campaignType,
      voucherCode: code,
      comboCount: comboCount,
    );
  }

  /// Tính lại các giảm giá theo chương trình khi giỏ hàng thay đổi.
  /// Trả về danh sách mới + tên các chương trình bị gỡ (không còn đủ điều kiện).
  static ({List<BillDiscountModel> discounts, List<String> dropped}) recalculate(
    List<BillDiscountModel> applied,
    Map<String, CampaignModel> campaignsById, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
    required String branchId,
    int? guestCount,
    String? customerBirthday,
  }) {
    final out = <BillDiscountModel>[];
    final dropped = <String>[];
    for (final d in applied) {
      final c = d.campaignId == null ? null : campaignsById[d.campaignId];
      if (c == null) {
        out.add(d);
        continue;
      }
      final q = quote(c, cart: cart, products: products, branchId: branchId, guestCount: guestCount, customerBirthday: customerBirthday);
      final amt = q.totalPromotionDiscount;
      if (amt > 0) {
        final comboCnt = q.rewardBenefits
            .where((b) => b.campaignId == c.campaignId)
            .fold<int>(0, (s, b) => s + b.quantity);
        out.add(d.copyWith(amount: amt, comboCount: comboCnt > 0 ? comboCnt : d.comboCount));
      } else {
        dropped.add(d.description);
      }
    }
    return (discounts: out, dropped: dropped);
  }
}
