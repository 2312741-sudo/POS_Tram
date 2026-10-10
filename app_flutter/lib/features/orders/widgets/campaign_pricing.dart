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
    int? nowMs,
  }) {
    return calculatePrice(
      input: PricingInput(
        branchId: branchId,
        guestCount: guestCount,
        serverNowMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
        lines: lines(cart, products),
      ),
      activeCampaigns: [campaign],
      counters: const {},
      customerCounters: const {},
    );
  }

  /// Lý do chưa áp dụng (nếu có) của chương trình trong [quote]
  static String? reason(PriceQuoteModel quote, CampaignModel campaign) =>
      quote.reasons.where((r) => r.campaignId == campaign.campaignId).map((r) => r.reasonMessage).firstOrNull;

  /// Bản ghi giảm giá lưu vào bill.discounts (giữ promoId/promoCode cho tương thích + trường mới cho báo cáo)
  static BillDiscountModel discount(
    CampaignModel campaign,
    int amount, {
    String? voucherCode,
    String? staffNote,
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
  }) {
    final out = <BillDiscountModel>[];
    final dropped = <String>[];
    for (final d in applied) {
      final c = d.campaignId == null ? null : campaignsById[d.campaignId];
      if (c == null) {
        out.add(d);
        continue;
      }
      final q = quote(c, cart: cart, products: products, branchId: branchId, guestCount: guestCount);
      final amt = q.totalPromotionDiscount;
      if (amt > 0) {
        out.add(d.copyWith(amount: amt));
      } else {
        dropped.add(d.description);
      }
    }
    return (discounts: out, dropped: dropped);
  }
}
