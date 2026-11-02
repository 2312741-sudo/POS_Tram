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

  test('đã áp dụng nhưng không còn ly tặng riêng (vd nhân viên xóa) → tính lại gỡ chương trình, KHÔNG trừ ly khách gọi', () {
    final r = CartCampaignPricing.recalculate(
      [CartCampaignPricing.discount(camp, 30000)], {'CAM_CHANH': camp},
      cart: [xoai(2), chanh()], products: products, branchId: 'TRAM01', orderTimestampMs: 1000,
    );
    expect(r.discounts, isEmpty);
    expect(r.dropped, hasLength(1));
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

  group('cộng dồn: giảm hóa đơn KHÔNG tính lại trên ly đã tặng', () {
    final bill20 = CampaignModel.fromMap({
      'campaignId': 'CAM_20', 'programCode': 'KM/20', 'name': 'Giảm 20% hóa đơn',
      'campaignType': 'BILL_DISCOUNT', 'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false,
      'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
      'tiers': [
        {'tierId': 'B1', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 0, 'benefitMode': 'PERCENT', 'value': 2000, 'maxDiscountMoney': 0, 'maxRewardQty': 0, 'rewardItemIds': [], 'sortOrder': 1},
      ],
    });
    final p22 = [
      products[0],
      ProductModel(id: 8, name: 'Trà Olong - Chanh tươi', code: 'DR2', price: 22000, unit: 'Ly', category: 'TRÀ'),
    ];
    final cart = [
      OrderItemModel(productId: 5, name: 'Trà Olong - Xoài', price: 45000, quantity: 3),
      OrderItemModel(productId: 8, name: 'Trà Olong - Chanh tươi', price: 22000, quantity: 1, rewardCampaignId: 'CAM_CHANH'),
    ];
    final byId = {'CAM_CHANH': camp, 'CAM_20': bill20};

    test('tặng chanh 22K (0đ) + giảm 20% hóa đơn → 20% chỉ tính trên 135K còn lại (27.000đ), không 31.400đ', () {
      final st = CartCampaignPricing.quoteStacked([bill20, camp], cart: cart, products: p22, branchId: 'TRAM01', nowMs: 1000);
      expect(st['CAM_CHANH']!.totalPromotionDiscount, 22000);
      expect(st['CAM_20']!.totalPromotionDiscount, 27000);
    });

    test('tính lại khi giỏ đổi (recalculate) cũng cộng dồn đúng, bất kể thứ tự áp dụng', () {
      final r = CartCampaignPricing.recalculate(
        [CartCampaignPricing.discount(bill20, 1), CartCampaignPricing.discount(camp, 1)], byId,
        cart: cart, products: p22, branchId: 'TRAM01', orderTimestampMs: 1000,
      );
      expect({for (final d in r.discounts) d.campaignId: d.amount}, {'CAM_20': 27000, 'CAM_CHANH': 22000});
    });
  });

  test('topping luôn kèm món tặng (Tăng giá Grab 2K): dòng tặng 20K + 2K = 22K giảm đủ về 0đ', () {
    final c = CampaignModel.fromMap({
      'campaignId': 'CAM_CHANH', 'programCode': 'KM/CHANH', 'name': 'Grab - Tặng 1 trà chanh',
      'campaignType': 'ORDER_VALUE_ITEM_BENEFIT', 'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false,
      'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
      'tiers': [
        {'tierId': 'T1', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 100000, 'benefitMode': 'FREEITEM', 'value': 0,
         'maxRewardQty': 1, 'rewardToppingIds': ['-grab2k'], 'rewardItemIds': ['8'], 'sortOrder': 1},
      ],
    });
    expect(c.tiers.first.freeToppingCount, 1);
    final cart = [
      xoai(3),
      OrderItemModel(productId: 8, name: 'Trà Olong - Chanh tươi', price: 20000, quantity: 1,
          selectedToppings: ['Thạch dừa', 'Tăng giá Grab 2K'], toppingPrice: 7000),
      OrderItemModel(productId: 8, name: 'Trà Olong - Chanh tươi', price: 20000, quantity: 1,
          selectedToppings: ['Tăng giá Grab 2K'], toppingPrice: 2000, rewardCampaignId: 'CAM_CHANH'),
    ];
    final q = CartCampaignPricing.quoteForApply(c, cart: cart, products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000);
    expect(q.totalPromotionDiscount, 22000);
    expect(q.rewardBenefits.map((b) => b.lineId), ['L2']);
  });

  test('giảm 16K cho 1 ly xoài (giảm tiền, không phải tặng) → giảm thẳng 1 ly khách gọi', () {
    final c = CampaignModel.fromMap({
      'campaignId': 'X1', 'programCode': 'KM/X1', 'name': 'Giảm 16K 1 ly xoài', 'campaignType': 'ORDER_VALUE_ITEM_BENEFIT',
      'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false, 'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
      'tiers': [
        {'tierId': 'T', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 0, 'benefitMode': 'FIXED', 'value': 16000,
         'maxRewardQty': 1, 'rewardItemIds': ['5'], 'sortOrder': 1},
      ],
    });
    final q = CartCampaignPricing.quoteForApply(c, cart: [xoai(3)], products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000);
    expect(q.totalPromotionDiscount, 16000);
    expect(q.rewardBenefits.map((b) => b.quantity), [1]);
    final st = CartCampaignPricing.quoteStacked([c], cart: [xoai(3)], products: products, branchId: 'TRAM01', nowMs: 1000);
    expect(st['X1']!.totalPromotionDiscount, 16000);
  });

  group('đồng giá / giảm theo món chỉ tính trên giá món + size (topping, phụ thu Grab vẫn tính tiền)', () {
    CampaignModel rule(String mode, int value) => CampaignModel.fromMap({
          'campaignId': 'XOAI', 'programCode': 'KM/XOAI', 'name': 'Xoài', 'campaignType': 'ITEM_PRICE_RULE',
          'active': true, 'branchIds': ['TRAM01'], 'hasCodes': false, 'stackingMode': 'ENABLED', 'priority': 0, 'createdAt': 1,
          'includedItemIds': ['5'],
          'tiers': [
            {'tierId': 'T', 'conditionBasis': 'TOTALAMOUNT', 'threshold': 0, 'benefitMode': mode, 'value': value, 'maxRewardQty': 1, 'rewardItemIds': [], 'sortOrder': 1},
          ],
        });
    // Trà xoài 30K + thạch dừa 5K + Tăng giá Grab 2K = 37K
    final cup = OrderItemModel(productId: 5, name: 'Trà Olong - Xoài', price: 30000, quantity: 1,
        selectedToppings: ['Thạch dừa', 'Tăng giá Grab 2K'], toppingPrice: 7000);
    int disc(CampaignModel c) => CartCampaignPricing.quoteForApply(c, cart: [cup], products: products, branchId: 'TRAM01', isApplied: false, nowMs: 1000).totalPromotionDiscount;

    test('giảm 16K mỗi ly → 37K còn 21K', () => expect(disc(rule('FIXED', 16000)), 16000));
    test('đồng giá 16K → 16K + 7K topping = 23K (không ép cả ly về 16K)', () => expect(disc(rule('FIXEDPRICE', 16000)), 14000));
    test('giảm 50% → giảm 15K (trên 30K giá ly)', () => expect(disc(rule('PERCENT', 5000)), 15000));
  });
}
