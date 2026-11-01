import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

/// "Tặng 1 trà chanh cho đơn từ 100K": đơn đã có trà chanh khách gọi → KHÔNG trừ ly đó, mà thêm 1 dòng chanh tặng riêng.
void main() {
  final camp = CampaignModel.fromMap({
    'campaignId': 'CAM_CHANH', 'programCode': 'KM/CHANH', 'name': 'Tặng 1 chanh đơn 100K',
    'campaignType': 'ORDER_VALUE_ITEM_BENEFIT', 'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false,
    'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
    'tiers': [
      {'tierId': 'T1', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 100000, 'benefitMode': 'FREEITEM', 'value': 0, 'maxRewardQty': 1, 'rewardItemIds': ['8'], 'sortOrder': 1},
    ],
  });
  final products = [
    ProductModel(id: 5, name: 'Trà Olong - Xoài', code: 'DR3', price: 45000, unit: 'Ly', category: 'TRÀ'),
    ProductModel(id: 8, name: 'Trà Olong - Chanh tươi', code: 'DR2', price: 30000, unit: 'Ly', category: 'TRÀ'),
  ];
  OrderItemModel xoai(int q) => OrderItemModel(productId: 5, name: 'Trà Olong - Xoài', price: 45000, quantity: q);
  OrderItemModel chanh({String reward = ''}) =>
      OrderItemModel(productId: 8, name: 'Trà Olong - Chanh tươi', price: 30000, quantity: 1, rewardCampaignId: reward);
  int apply(List<OrderItemModel> cart, {bool isApplied = false}) => CartCampaignPricing.quoteForApply(
        camp, cart: cart, products: products, branchId: 'TRAM01', isApplied: isApplied, nowMs: 1000,
      ).totalPromotionDiscount;

  test('đơn 120K đã có 1 trà chanh khách gọi → không trừ ly đó; báo cần thêm món tặng', () {
    final cart = [xoai(2), chanh()];
    expect(apply(cart), 0);
    final q = CartCampaignPricing.quoteForApply(camp, cart: cart, products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000);
    expect(CartCampaignPricing.needsRewardItems(q, camp), isTrue);
  });

  test('thêm dòng chanh TẶNG riêng → giảm đúng 1 ly đó; ly khách gọi vẫn tính tiền', () {
    final cart = [xoai(2), chanh(), chanh(reward: 'CAM_CHANH')];
    final q = CartCampaignPricing.quoteForApply(camp, cart: cart, products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000);
    expect(q.totalPromotionDiscount, 30000);
    expect(q.rewardBenefits.map((b) => b.lineId), ['L2']); // dòng tặng, không phải L1 (ly khách gọi)
  });

  test('dòng món tặng không tính vào mốc 100K', () {
    // 90K món thật + 30K dòng tặng = 120K nhưng chỉ 90K tính mốc → chưa đạt
    expect(apply([xoai(2), chanh(reward: 'CAM_CHANH')]), 0);
  });

  test('đơn cũ đã áp dụng theo cách cũ (không có dòng tặng riêng) → tính lại vẫn giữ giảm trên món có sẵn', () {
    expect(apply([xoai(2), chanh()], isApplied: true), 30000);
  });

  test('rewardCampaignId lưu / đọc lại được trên dòng món', () {
    final m = chanh(reward: 'CAM_CHANH').toMap();
    expect(m['rewardCampaignId'], 'CAM_CHANH');
    expect(OrderItemModel.fromMap(m).rewardCampaignId, 'CAM_CHANH');
    expect(chanh().toMap().containsKey('rewardCampaignId'), isFalse);
  });
}
