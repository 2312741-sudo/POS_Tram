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
    final prodByNumId = {for (final p in products) p.id: p};
    final prodByName = {for (final p in products) p.name.trim().toLowerCase(): p};
    return [
      for (int i = 0; i < cart.length; i++)
        (() {
          final item = cart[i];
          final p = prodByNumId[item.productId] ?? prodByName[item.name.trim().toLowerCase()];
          return PricingLineItem.fromOrderItem(
            item,
            lineId: 'L$i',
            groupId: p?.category ?? cat[item.productId],
            itemCode: p?.code,
            dbKey: p?.dbKey,
          );
        })(),
    ];
  }

  /// Tính toán chi tiết số tiền giảm giá do khuyến mãi áp dụng trên từng dòng món trong giỏ hàng.
  /// Trả về map: lineIndex -> danh sách các ưu đãi khuyến mãi áp dụng trên dòng đó.
  static Map<int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>>
      computeLinePromotionDiscounts({
    required List<OrderItemModel> cart,
    required List<BillDiscountModel> appliedDiscounts,
    required Map<String, CampaignModel> campaignsById,
    required List<ProductModel> products,
    required String branchId,
    String? customerBirthday,
    int? guestCount,
    int? orderTimestampMs,
    bool isExistingOrder = true,
  }) {
    final result = <int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>>{};
    if (cart.isEmpty || appliedDiscounts.isEmpty) return result;

    for (final d in appliedDiscounts) {
      final c = d.campaignId != null ? campaignsById[d.campaignId] : null;
      if (c == null) continue;

      final q = quote(
        c,
        cart: cart,
        products: products,
        branchId: branchId,
        guestCount: guestCount,
        customerBirthday: customerBirthday,
        nowMs: orderTimestampMs,
        ignoreSchedule: isExistingOrder,
      );

      final seenLines = <String>{};
      for (final rb in q.rewardBenefits) {
        if (rb.discountMoney <= 0) continue;
        final idxStr = rb.lineId.replaceAll(RegExp(r'[^0-9]'), '');
        final lineIdx = int.tryParse(idxStr);
        if (lineIdx != null && lineIdx >= 0 && lineIdx < cart.length) {
          seenLines.add(rb.lineId);
          result.putIfAbsent(lineIdx, () => []).add((
            campaignName: c.name,
            discountAmount: rb.discountMoney,
            quantity: rb.quantity > 0 ? rb.quantity : cart[lineIdx].quantity,
            isGift: rb.isGift,
          ));
        }
      }

      for (final lb in q.lineBenefits) {
        if (seenLines.contains(lb.lineId) || lb.discountMoney <= 0) continue;
        final idxStr = lb.lineId.replaceAll(RegExp(r'[^0-9]'), '');
        final lineIdx = int.tryParse(idxStr);
        if (lineIdx != null && lineIdx >= 0 && lineIdx < cart.length) {
          result.putIfAbsent(lineIdx, () => []).add((
            campaignName: c.name,
            discountAmount: lb.discountMoney,
            quantity: cart[lineIdx].quantity,
            isGift: lb.isGift,
          ));
        }
      }
    }

    return result;
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
    bool ignoreSchedule = false,
  }) {
    return calculatePrice(
      input: PricingInput(
        branchId: branchId,
        customerBirthday: customerBirthday,
        guestCount: guestCount,
        serverNowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
        lines: lines(cart, products),
        ignoreSchedule: ignoreSchedule,
      ),
      activeCampaigns: [campaign],
      counters: const {},
      customerCounters: const {},
    );
  }

  /// Báo giá khi nhân viên bấm áp dụng / xem chương trình trên giỏ.
  /// Lúc bấm ([nowMs], mặc định giờ hiện tại) phải trong khung giờ, và chỉ các món GỌI trong khung giờ được tính
  /// (nước gọi trước giờ combo thì bánh không được giảm — xem outsideScheduleMessage). Chương trình ĐÃ áp dụng
  /// ([isApplied]) bỏ qua giờ bấm để đơn treo qua hết giờ vẫn giữ giảm (khớp web: recalculateDiscounts).
  static PriceQuoteModel quoteForApply(
    CampaignModel campaign, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
    required String branchId,
    required bool isApplied,
    int? guestCount,
    String? customerBirthday,
    int? nowMs,
  }) =>
      quote(
        campaign,
        cart: cart,
        products: products,
        branchId: branchId,
        guestCount: guestCount,
        customerBirthday: customerBirthday,
        nowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
        ignoreSchedule: isApplied,
      );

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
      if (l.matchesAnyTarget(ids)) return true;
      if (l.groupId == null || groups.isEmpty) return false;
      final gNorm = PricingLineItem.normGroup(l.groupId!);
      return groups.any((g) => PricingLineItem.normGroup(g) == gNorm);
    }

    List<ProductModel> pick(Set<String> ids, Set<String> groups) => products
        .where((p) =>
            !p.isTopping &&
            p.isAvailable &&
            !c.excludedItemIds.any((ex) => p.matchesTarget(ex)) &&
            (ids.any((id) => p.matchesTarget(id)) || groups.any((g) => PricingLineItem.normGroup(g) == PricingLineItem.normGroup(p.category))))
        .toList();

    final type = c.campaignType.toUpperCase().replaceAll('_', '');
    if (type == 'BUYXGETY') {
      for (final cond in c.buyConditions) {
        final buyIds = cond.buyItemIds.toSet(), buyGroups = cond.buyGroupIds.toSet();
        final rewardIds = cond.rewardItemIds.toSet(), rewardGroups = cond.rewardGroupIds.toSet();
        if (cond.requiredBuyQty <= 0 || cond.rewardQty <= 0) continue;
        final x = lns.where((l) => !l.isGift && l.orderedWithin(c) && matches(l, buyIds, buyGroups)).fold<int>(0, (s, l) => s + l.quantity);
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
        if (l.isGift || !l.orderedWithin(c) || l.matchesAnyTarget(c.excludedItemIds)) continue;
        final inScope = inScopeAll || l.matchesAnyTarget(c.includedItemIds) || (l.groupId != null && c.includedGroupIds.contains(l.groupId));
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

  /// Món liên quan tới chương trình nhưng GỌI NGOÀI khung giờ áp dụng → không được tính KM.
  /// Trả câu thông báo cho nhân viên (null = không có món nào như vậy).
  static String? outsideScheduleMessage(
    CampaignModel c, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
  }) {
    final lns = lines(cart, products);
    bool group(PricingLineItem l, Iterable<String> groups) =>
        l.groupId != null && groups.any((g) => PricingLineItem.normGroup(g) == PricingLineItem.normGroup(l.groupId!));
    bool related(PricingLineItem l) {
      if (l.isGift || l.matchesAnyTarget(c.excludedItemIds)) return false;
      final type = c.campaignType.toUpperCase().replaceAll('_', '');
      if (type == 'BUYXGETY') {
        return c.buyConditions.any((cond) =>
            l.matchesAnyTarget(cond.buyItemIds) || group(l, cond.buyGroupIds) ||
            l.matchesAnyTarget(cond.rewardItemIds) || group(l, cond.rewardGroupIds));
      }
      if (c.includedItemIds.isEmpty && c.includedGroupIds.isEmpty) return true;
      return l.matchesAnyTarget(c.includedItemIds) || group(l, c.includedGroupIds);
    }

    String hm(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 7));
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    final out = lns.where((l) => related(l) && !l.orderedWithin(c)).toList();
    if (out.isEmpty) return null;
    final names = out.map((l) => '${l.itemName ?? l.itemId} (gọi lúc ${hm(l.orderedAtMs!)})').join(', ');
    return '$names gọi ngoài thời gian khuyến mãi (${c.schedule.summary()}) nên không được áp dụng. '
        'Chỉ món gọi trong khung giờ mới được tính.';
  }

  /// Giỏ hàng LẼ RA được giảm (nhiều hơn) nhưng bị chặn vì có món gọi ngoài khung giờ?
  /// Trả câu thông báo (null = không bị ảnh hưởng). Dùng để tự báo nhân viên, không cần bấm vào chương trình.
  static String? lateOrderBlock(
    CampaignModel c, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
    required String branchId,
    int? guestCount,
    String? customerBirthday,
    int? nowMs,
  }) {
    final msg = outsideScheduleMessage(c, cart: cart, products: products);
    if (msg == null) return null;
    PriceQuoteModel run(List<PricingLineItem> lns) => calculatePrice(
          input: PricingInput(
            branchId: branchId,
            customerBirthday: customerBirthday,
            guestCount: guestCount,
            serverNowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
            lines: lns,
          ),
          activeCampaigns: [c],
          counters: const {},
          customerCounters: const {},
        );
    final lns = lines(cart, products);
    final real = run(lns).totalPromotionDiscount;
    final ignoringTime = run([for (final l in lns) l.withoutOrderTime()]).totalPromotionDiscount;
    if (ignoringTime <= real) return null;
    String vnd(int v) => '${v.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}đ';
    return real > 0 ? '$msg Đơn chỉ được giảm ${vnd(real)} thay vì ${vnd(ignoringTime)}.' : msg;
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
      if (l.matchesAnyTarget(ids)) return true;
      if (l.groupId == null || groups.isEmpty) return false;
      final gNorm = PricingLineItem.normGroup(l.groupId!);
      return groups.any((g) => PricingLineItem.normGroup(g) == gNorm);
    }

    List<ProductModel> pick(Set<String> ids, Set<String> groups) => products
        .where((p) =>
            !p.isTopping &&
            p.isAvailable &&
            !c.excludedItemIds.any((ex) => p.matchesTarget(ex)) &&
            (ids.any((id) => p.matchesTarget(id)) || groups.any((g) => PricingLineItem.normGroup(g) == PricingLineItem.normGroup(p.category))))
        .toList();

    if (type == 'BUYXGETY') {
      for (final cond in c.buyConditions) {
        final buyIds = cond.buyItemIds.toSet(), buyGroups = cond.buyGroupIds.toSet();
        final rewardIds = cond.rewardItemIds.toSet(), rewardGroups = cond.rewardGroupIds.toSet();
        if (cond.requiredBuyQty <= 0 || cond.rewardQty <= 0) continue;

        // Số lượng nước trong giỏ hàng (chỉ nước gọi trong khung giờ chương trình)
        final buyUnits = lns
            .where((l) => !l.isGift && l.orderedWithin(c) && matches(l, buyIds, buyGroups))
            .fold<int>(0, (s, l) => s + l.quantity);

        // Số lượng bánh hiện có trong giỏ hàng
        final rewardUnitsInCart = lns
            .where((l) => !l.isGift && l.orderedWithin(c) && matches(l, rewardIds, rewardGroups))
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

  /// Gợi ý chẩn đoán khi combo báo "chưa có nước": nhóm/món chương trình cần mua và nhóm của các món đang trong đơn
  static String comboMissHint(
    CampaignModel c, {
    required List<OrderItemModel> cart,
    required List<ProductModel> products,
  }) {
    if (c.buyConditions.isEmpty) return '';
    final cond = c.buyConditions.first;
    final need = <String>[
      if (cond.buyGroupIds.isNotEmpty) 'nhóm ${cond.buyGroupIds.join(" / ")}',
      if (cond.buyItemIds.isNotEmpty) '${cond.buyItemIds.length} món chỉ định',
    ];
    if (need.isEmpty) return '';
    final have = lines(cart, products).map((l) => '${l.itemName ?? l.itemId} [${l.groupId ?? "?"}]').toList();
    return '\n   Cần: ${need.join(" + ")}${have.isEmpty ? "" : "\n   Đơn có: ${have.join(", ")}"}';
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
    int? orderTimestampMs,
    bool isExistingOrder = true,
  }) {
    final out = <BillDiscountModel>[];
    final dropped = <String>[];
    for (final d in applied) {
      final c = d.campaignId == null ? null : campaignsById[d.campaignId];
      if (c == null) {
        out.add(d);
        continue;
      }
      // Với đơn đã áp dụng CTKM (khi treo đơn qua giờ combo):
      // Bỏ qua giới hạn khung giờ (ignoreSchedule: true), chỉ tính toán dựa trên món thực tế trong giỏ.
      final q = quote(
        c,
        cart: cart,
        products: products,
        branchId: branchId,
        guestCount: guestCount,
        customerBirthday: customerBirthday,
        nowMs: orderTimestampMs,
        ignoreSchedule: isExistingOrder,
      );
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

  /// Kiểm tra xem CTKM [incoming] có thể áp dụng vào đơn hiện tại (đang có [currentDiscounts]) hay không
  static ({
    bool canStack,
    bool requiresClearingExisting,
    CampaignModel? conflictingExclusiveCampaign,
    int? maxAllowedCampaigns,
    String? reason,
  }) checkStacking({
    required List<BillDiscountModel> currentDiscounts,
    required CampaignModel incoming,
    required Map<String, CampaignModel> campaignsById,
    bool allowStackPromotions = true,
  }) {
    final otherDiscounts = currentDiscounts.where((d) => d.campaignId != incoming.campaignId).toList();
    if (otherDiscounts.isEmpty) {
      return (
        canStack: true,
        requiresClearingExisting: false,
        conflictingExclusiveCampaign: null,
        maxAllowedCampaigns: incoming.effectiveMaxCampaignsPerOrder,
        reason: null,
      );
    }

    if (!allowStackPromotions) {
      return (
        canStack: false,
        requiresClearingExisting: true,
        conflictingExclusiveCampaign: null,
        maxAllowedCampaigns: 1,
        reason: 'Cửa hàng đang cài đặt không cho phép cộng dồn khuyến mãi.',
      );
    }

    if (!incoming.isStackable || incoming.effectiveMaxCampaignsPerOrder == 1) {
      return (
        canStack: false,
        requiresClearingExisting: true,
        conflictingExclusiveCampaign: null,
        maxAllowedCampaigns: 1,
        reason: 'Chương trình "${incoming.name}" áp dụng độc quyền (không cho phép cộng dồn với CTKM khác).',
      );
    }

    // Kiểm tra xem trong các ưu đãi đã có, có CTKM độc quyền nào không
    for (final d in otherDiscounts) {
      if (d.campaignId != null) {
        final existingC = campaignsById[d.campaignId];
        if (existingC != null && (!existingC.isStackable || existingC.effectiveMaxCampaignsPerOrder == 1)) {
          return (
            canStack: false,
            requiresClearingExisting: false,
            conflictingExclusiveCampaign: existingC,
            maxAllowedCampaigns: 1,
            reason: 'Đơn đang áp dụng "${existingC.name}" (chương trình độc quyền, không cho phép cộng dồn).',
          );
        }
      }
    }

    // Kiểm tra giới hạn số lượng tối đa trên đơn
    final limits = <int>[
      incoming.effectiveMaxCampaignsPerOrder,
      for (final d in otherDiscounts)
        if (d.campaignId != null && campaignsById.containsKey(d.campaignId))
          campaignsById[d.campaignId]!.effectiveMaxCampaignsPerOrder,
    ].where((n) => n > 0 && n < 999).toList();

    if (limits.isNotEmpty) {
      final maxAllowed = limits.reduce((a, b) => a < b ? a : b);
      if (otherDiscounts.length >= maxAllowed) {
        return (
          canStack: false,
          requiresClearingExisting: false,
          conflictingExclusiveCampaign: null,
          maxAllowedCampaigns: maxAllowed,
          reason: 'Đơn đã đạt giới hạn tối đa $maxAllowed chương trình khuyến mãi theo cài đặt.',
        );
      }
      return (
        canStack: true,
        requiresClearingExisting: false,
        conflictingExclusiveCampaign: null,
        maxAllowedCampaigns: maxAllowed,
        reason: null,
      );
    }

    return (
      canStack: true,
      requiresClearingExisting: false,
      conflictingExclusiveCampaign: null,
      maxAllowedCampaigns: null,
      reason: null,
    );
  }

  /// Thực hiện cộng dồn hoặc thay thế khi thêm một khuyến mãi mới vào giỏ
  static ({List<BillDiscountModel> discounts, List<String> removed}) addWithStacking({
    required List<BillDiscountModel> currentDiscounts,
    required BillDiscountModel incomingDiscount,
    CampaignModel? incomingCampaign,
    required Map<String, CampaignModel> campaignsById,
    bool allowStackPromotions = true,
  }) {
    final without = currentDiscounts.where((d) =>
        (incomingDiscount.campaignId != null && d.campaignId != incomingDiscount.campaignId) ||
        (incomingDiscount.promoId != null && d.promoId != incomingDiscount.promoId) ||
        (incomingDiscount.voucherCode != null && d.voucherCode != incomingDiscount.voucherCode)).toList();

    bool isStackable(CampaignModel? c) => c == null || (c.isStackable && c.effectiveMaxCampaignsPerOrder > 1);

    List<BillDiscountModel> keep;
    if (!allowStackPromotions || (incomingCampaign != null && !isStackable(incomingCampaign))) {
      keep = [];
    } else {
      keep = without.where((d) {
        final c = d.campaignId == null ? null : campaignsById[d.campaignId];
        return isStackable(c);
      }).toList();

      final limits = <int>[
        if (incomingCampaign != null && incomingCampaign.effectiveMaxCampaignsPerOrder < 999)
          incomingCampaign.effectiveMaxCampaignsPerOrder,
        for (final d in keep)
          if (d.campaignId != null && campaignsById.containsKey(d.campaignId))
            if (campaignsById[d.campaignId]!.effectiveMaxCampaignsPerOrder < 999)
              campaignsById[d.campaignId]!.effectiveMaxCampaignsPerOrder,
      ];

      if (limits.isNotEmpty) {
        final maxAllowed = limits.reduce((a, b) => a < b ? a : b);
        final maxKeep = (maxAllowed - 1).clamp(0, 999);
        if (keep.length > maxKeep) {
          keep = keep.sublist(keep.length - maxKeep);
        }
      }
    }

    final removed = without.where((d) => !keep.contains(d)).map((d) => d.description).toList();
    return (discounts: [...keep, incomingDiscount], removed: removed);
  }
}
