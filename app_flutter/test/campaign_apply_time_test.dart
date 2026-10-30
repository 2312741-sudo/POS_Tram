import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

/// Khung giờ khuyến mãi: lúc bấm phải trong giờ VÀ chỉ món GỌI trong khung giờ mới được tính.
void main() {
  // Giờ Việt Nam (UTC+7) → timestamp
  int vn(int h, [int m = 0]) => DateTime.utc(2026, 10, 22, h - 7, m).millisecondsSinceEpoch;

  // "Combo bánh và nước giảm 10K" — khung 18:00–20:00, như dữ liệu web ghi vào RTDB
  final combo = CampaignModel.fromMap({
    'campaignId': 'CAM_HD1', 'programCode': 'KM/HD0001', 'name': 'Combo bánh và nước giảm 10K',
    'campaignType': 'BUYXGETY', 'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false,
    'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
    'schedule': {'timezone': 'Asia/Ho_Chi_Minh', 'timeSlots': [{'startTime': '18:00', 'endTime': '20:00'}]},
    'buyConditions': [{
      'conditionId': 'C1', 'buyItemIds': [], 'buyGroupIds': ['TRÀ TRÁI CÂY'], 'requiredBuyQty': 1,
      'rewardItemIds': ['77'], 'rewardGroupIds': [], 'rewardQty': 1, 'benefitMode': 'FIXED', 'value': 10000, 'multiplyByBundle': true,
    }],
  });
  final products = [
    ProductModel(id: 5, name: 'Trà Olong - Chanh tươi', code: 'DR1', price: 45000, unit: 'Ly', category: 'TRÀ TRÁI CÂY'),
    ProductModel(id: 77, name: 'Bánh lăn choco', code: 'CK1', price: 30000, unit: 'Cái', category: 'BÁNH'),
  ];
  // Nước gọi lúc [drinkAt], bánh gọi lúc [cakeAt] (null = món mới chưa có giờ gọi)
  List<OrderItemModel> cart({int? drinkAt, int? cakeAt}) => [
        OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1, orderedAt: drinkAt),
        OrderItemModel(productId: 77, name: 'Bánh lăn choco', price: 30000, quantity: 1, orderedAt: cakeAt),
      ];
  int apply(int nowMs, List<OrderItemModel> items, {bool isApplied = false}) => CartCampaignPricing.quoteForApply(
        combo, cart: items, products: products, branchId: 'TRAM01', isApplied: isApplied, nowMs: nowMs,
      ).totalPromotionDiscount;

  test('nước + bánh gọi trong khung giờ, bấm KM trong giờ → được giảm', () {
    expect(apply(vn(18, 30), cart(drinkAt: vn(18, 10), cakeAt: vn(18, 25))), 10000);
    expect(apply(vn(18, 30), cart()), 10000); // món mới chưa gửi
    expect(CartCampaignPricing.outsideScheduleMessage(combo, cart: cart(drinkAt: vn(18, 10)), products: products), isNull);
  });

  test('nước gọi 17:50 (ngoài giờ), bấm KM 18:30 → bánh KHÔNG được giảm + có thông báo', () {
    final items = cart(drinkAt: vn(17, 50), cakeAt: vn(18, 30));
    expect(apply(vn(18, 30), items), 0);
    expect(CartCampaignPricing.getComboInfo(combo, cart: items, products: products)!.buyUnits, 0);
    final msg = CartCampaignPricing.outsideScheduleMessage(combo, cart: items, products: products);
    expect(msg, contains('Trà Olong - Chanh tươi (gọi lúc 17:50)'));
    expect(msg, contains('18:00–20:00'));
  });

  test('2 nước: 1 gọi ngoài giờ, 1 trong giờ → chỉ được 1 combo', () {
    final items = [
      OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1, orderedAt: vn(17, 40)),
      OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1, orderedAt: vn(18, 5)),
      OrderItemModel(productId: 77, name: 'Bánh lăn choco', price: 30000, quantity: 2, orderedAt: vn(18, 6)),
    ];
    expect(apply(vn(18, 10), items), 10000);
  });

  test('bấm KM ngoài khung giờ (17:50) → không áp dụng', () {
    expect(apply(vn(17, 50), cart()), 0);
    expect(combo.isEligibleAt(vn(17, 50)), isFalse);
  });

  test('đã áp dụng lúc 19:50 (món gọi trong giờ), treo đơn tới 20:30 → vẫn giữ giảm', () {
    final items = cart(drinkAt: vn(19, 40), cakeAt: vn(19, 45));
    expect(apply(vn(20, 30), items, isApplied: true), 10000);
    final r = CartCampaignPricing.recalculate(
      [CartCampaignPricing.discount(combo, 10000)], {'CAM_HD1': combo},
      cart: items, products: products, branchId: 'TRAM01', orderTimestampMs: vn(20, 30), isExistingOrder: true,
    );
    expect(r.discounts.map((d) => d.amount), [10000]);
  });

  test('tự báo: nước gọi ngoài giờ + thêm bánh trong giờ → báo không áp dụng; đủ điều kiện thì không báo', () {
    String? block(List<OrderItemModel> items) => CartCampaignPricing.lateOrderBlock(
          combo, cart: items, products: products, branchId: 'TRAM01', nowMs: vn(18, 30));
    expect(block(cart(drinkAt: vn(17, 50), cakeAt: vn(18, 30))), contains('gọi lúc 17:50'));
    expect(block(cart(drinkAt: vn(18, 10), cakeAt: vn(18, 30))), isNull);
    // Chỉ có nước gọi ngoài giờ, chưa có bánh → chưa lẽ ra được giảm → không báo
    expect(block([cart(drinkAt: vn(17, 50)).first]), isNull);
    final partial = block([
      OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1, orderedAt: vn(17, 40)),
      OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1, orderedAt: vn(18, 5)),
      OrderItemModel(productId: 77, name: 'Bánh lăn choco', price: 30000, quantity: 2, orderedAt: vn(18, 6)),
    ]);
    expect(partial, contains('chỉ được giảm 10.000đ thay vì 20.000đ'));
  });
}
