import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

/// Khung giờ khuyến mãi xét theo LÚC BẤM ÁP DỤNG, không theo giờ mở bàn / giờ gọi món.
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
  final cart = [
    OrderItemModel(productId: 5, name: 'Trà Olong - Chanh tươi', price: 45000, quantity: 1),
    OrderItemModel(productId: 77, name: 'Bánh lăn choco', price: 30000, quantity: 1),
  ];
  int apply(int nowMs, {bool isApplied = false}) => CartCampaignPricing.quoteForApply(
        combo, cart: cart, products: products, branchId: 'TRAM01', isApplied: isApplied, nowMs: nowMs,
      ).totalPromotionDiscount;

  test('nước gọi 17:50 (bàn mở ngoài giờ), bấm KM 18:30 trong giờ → được giảm', () {
    expect(apply(vn(18, 30)), 10000);
  });
  test('bấm KM ngoài khung giờ (17:50) → không áp dụng', () {
    expect(apply(vn(17, 50)), 0);
    expect(combo.isEligibleAt(vn(17, 50)), isFalse);
  });
  test('đã áp dụng lúc 19:50, treo đơn tới 20:30 → vẫn giữ giảm', () {
    expect(apply(vn(20, 30), isApplied: true), 10000);
    final r = CartCampaignPricing.recalculate(
      [CartCampaignPricing.discount(combo, 10000)], {'CAM_HD1': combo},
      cart: cart, products: products, branchId: 'TRAM01', orderTimestampMs: vn(20, 30), isExistingOrder: true,
    );
    expect(r.discounts.map((d) => d.amount), [10000]);
  });
}
