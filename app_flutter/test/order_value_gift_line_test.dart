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

  group('tặng kèm topping', () {
    CampaignModel withTops(int n, {String mode = 'FREEITEM'}) => CampaignModel.fromMap({
          'campaignId': 'CAM_CHANH', 'programCode': 'KM/CHANH', 'name': 'Tặng 1 chanh kèm topping',
          'campaignType': 'ORDER_VALUE_ITEM_BENEFIT', 'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false,
          'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
          'tiers': [
            {'tierId': 'T1', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 100000, 'benefitMode': mode, 'value': 0,
             'maxRewardQty': 1, 'rewardToppingQty': n, 'rewardItemIds': ['8'], 'sortOrder': 1},
          ],
        });
    OrderItemModel giftWith(List<String> tops, int toppingPrice) => OrderItemModel(
          productId: 8, name: 'Trà Olong - Chanh tươi', price: 30000, quantity: 1,
          selectedToppings: tops, toppingPrice: toppingPrice, rewardCampaignId: 'CAM_CHANH');
    int q(CampaignModel c, OrderItemModel gift) => CartCampaignPricing.quoteForApply(
          c, cart: [xoai(3), gift], products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000,
        ).totalPromotionDiscount;

    test('tặng 1 chanh kèm 1 topping: ly + 1 topping miễn phí hết', () {
      expect(q(withTops(1), giftWith(['Trân châu'], 5000)), 35000);
    });
    test('chọn 2 topping mà chỉ tặng 1 → topping thứ 2 tính tiền', () {
      expect(q(withTops(1), giftWith(['Trân châu', 'Thạch'], 10000)), 35000);
    });
    test('không cấu hình tặng topping (0) → topping thêm trên ly tặng tính tiền', () {
      expect(q(withTops(0), giftWith(['Trân châu'], 5000)), 30000);
    });
    test('mô tả chương trình ghi "kèm 1 topping"', () {
      expect(withTops(1).tiers.first.rewardToppingQty, 1);
      expect(withTops(1).tiers.first.toMap()['rewardToppingQty'], 1);
    });
  });
}
