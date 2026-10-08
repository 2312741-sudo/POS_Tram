import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/core/utils/format_utils.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/inventory_models.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';

RecipeVersionModel _recipe(String id, String output, List<RecipeIngredient> ings,
    {String? variant, String status = 'ACTIVE', int version = 1, String? branch}) {
  return RecipeVersionModel(
    recipeId: id,
    outputItemId: output,
    outputVariant: variant,
    outputQuantityBase: 1,
    outputUnitId: 'ly',
    ingredients: ings,
    branchScope: branch,
    effectiveFrom: 0,
    status: status,
    version: version,
  );
}

RecipeIngredient _ing(String itemId, int qty) =>
    RecipeIngredient(itemId: itemId, itemName: itemId, unitId: 'g', quantityBase: qty, wasteRateBps: 0);

void main() {
  group('BillCodeGenerator', () {
    final at = DateTime(2026, 10, 9, 14, 5, 7);

    test('mã tuần tự HD-yyMMdd-NNNN, đệm 4 chữ số và mở rộng khi > 9999', () {
      expect(BillCodeGenerator.dayKey(at), '261009');
      expect(BillCodeGenerator.sequential(1, at: at), 'HD-261009-0001');
      expect(BillCodeGenerator.sequential(42, at: at), 'HD-261009-0042');
      expect(BillCodeGenerator.sequential(12345, at: at), 'HD-261009-12345');
      expect(BillCodeGenerator.isSequential('HD-261009-0001'), isTrue);
      expect(BillCodeGenerator.isSequential('HD-261009-12345'), isTrue);
    });

    test('mã dự phòng có hậu tố ngẫu nhiên và không trùng định dạng tuần tự', () {
      final code = BillCodeGenerator.fallback(at: at, random: Random(1));
      expect(code, matches(RegExp(r'^HD-261009-140507-[A-Z0-9]{4}$')));
      expect(BillCodeGenerator.isSequential(code), isFalse);
      final codes = List.generate(200, (_) => BillCodeGenerator.fallback(at: at)).toSet();
      expect(codes.length, greaterThan(190), reason: 'hậu tố ngẫu nhiên giảm va chạm cùng giây');
    });

    test('FormatUtils.billCode/orderCode dùng mã tạm có hậu tố', () {
      expect(FormatUtils.billCode(), startsWith('HD-'));
      expect(FormatUtils.orderCode(), startsWith('OD-'));
      expect(BillCodeGenerator.isSequential(FormatUtils.billCode()), isFalse);
    });
  });

  group('OrderLineMerger', () {
    OrderItemModel item({
      int pid = 1,
      int qty = 1,
      String size = '',
      List<String> toppings = const [],
      String sugar = '',
      String ice = '',
      String note = '',
      bool sent = false,
      int discount = 0,
    }) =>
        OrderItemModel(
          productId: pid,
          name: 'Trà sữa',
          price: 30000,
          quantity: qty,
          selectedSize: size,
          sizeExtraPrice: size == 'L' ? 5000 : 0,
          selectedToppings: toppings,
          toppingPrice: toppings.length * 5000,
          selectedSugar: sugar,
          selectedIce: ice,
          note: note,
          isSentKitchen: sent,
          discountAmount: discount,
        );

    test('cộng dồn dòng cấu hình giống hệt (topping khác thứ tự vẫn là 1 dòng)', () {
      final target = [item(qty: 2, toppings: ['A', 'B'])];
      final source = [item(qty: 3, toppings: ['B', 'A'])];
      final merged = OrderLineMerger.merge(target, source);
      expect(merged.length, 1);
      expect(merged.first.quantity, 5);
      expect(target.first.quantity, 2, reason: 'không thay đổi danh sách đầu vào');
    });

    test('không gộp khi khác size / topping / đường / đá / ghi chú / trạng thái bếp', () {
      final target = [item()];
      final source = [
        item(size: 'L'),
        item(toppings: ['Trân châu']),
        item(sugar: '50%'),
        item(ice: 'Ít đá'),
        item(note: 'Mang về'),
        item(sent: true),
        item(pid: 2),
      ];
      final merged = OrderLineMerger.merge(target, source);
      expect(merged.length, 8);
      expect(merged.where((e) => e.selectedSize == 'L').single.sizeExtraPrice, 5000);
      expect(merged.where((e) => e.note == 'Mang về').single.quantity, 1);
    });

    test('cộng dồn giảm giá dòng khi gộp', () {
      final merged = OrderLineMerger.merge([item(discount: 1000)], [item(discount: 2000)]);
      expect(merged.single.discountAmount, 3000);
      expect(merged.single.quantity, 2);
    });
  });

  group('PromotionUsageMath', () {
    test('tăng bộ đếm chương trình và chặn khi vượt maxUses', () {
      final first = PromotionUsageMath.applyCampaignUsage(null,
          campaignId: 'C1', spentDelta: 10000, useDelta: 1, maxUses: 2);
      expect(first!['committedUseCount'], 1);
      expect(first['spentMoney'], 10000);
      final second = PromotionUsageMath.applyCampaignUsage(first,
          campaignId: 'C1', spentDelta: 10000, useDelta: 1, maxUses: 2);
      expect(second!['committedUseCount'], 2);
      expect(
          PromotionUsageMath.applyCampaignUsage(second, campaignId: 'C1', spentDelta: 1, useDelta: 1, maxUses: 2),
          isNull);
    });

    test('chặn khi vượt ngân sách; hoàn tác (delta âm) không bị chặn và không âm', () {
      final cur = {'spentMoney': 90000, 'committedUseCount': 9};
      expect(
          PromotionUsageMath.applyCampaignUsage(cur,
              campaignId: 'C1', spentDelta: 20000, useDelta: 1, budgetMoney: 100000),
          isNull);
      final rolled = PromotionUsageMath.applyCampaignUsage({'spentMoney': 5000, 'committedUseCount': 0},
          campaignId: 'C1', spentDelta: -10000, useDelta: -1, maxUses: 1, budgetMoney: 1);
      expect(rolled!['spentMoney'], 0);
      expect(rolled['committedUseCount'], 0);
    });

    test('giới hạn lượt / khách', () {
      final a = PromotionUsageMath.applyCustomerUsage(null,
          campaignId: 'C1', customerId: 'K1', delta: 1, maxUsesPerCustomer: 1);
      expect(a!['usedCount'], 1);
      expect(
          PromotionUsageMath.applyCustomerUsage(a,
              campaignId: 'C1', customerId: 'K1', delta: 1, maxUsesPerCustomer: 1),
          isNull);
    });

    test('khuyến mãi cũ: maxUsage = 0 là không giới hạn', () {
      expect(PromotionUsageMath.applyLegacyUsage(5, maxUsage: 0), 6);
      expect(PromotionUsageMath.applyLegacyUsage(4, maxUsage: 5), 5);
      expect(PromotionUsageMath.applyLegacyUsage(5, maxUsage: 5), isNull);
      expect(PromotionUsageMath.applyLegacyUsage(0, delta: -1, maxUsage: 5), 0);
    });
  });

  group('StockConsumptionPlanner', () {
    final recipes = [
      _recipe('R1', 'ITM_TS', [_ing('ITM_TRA', 10), _ing('ITM_SUA', 30)]),
      _recipe('R1L', 'ITM_TS', [_ing('ITM_TRA', 15), _ing('ITM_SUA', 45)], variant: 'L'),
      _recipe('R_OLD', 'ITM_TS', [_ing('ITM_TRA', 999)], status: 'ARCHIVED', version: 9),
      _recipe('RT', 'ITM_TC', [_ing('ITM_BOT', 20)]),
    ];

    test('trừ theo công thức đúng size + topping, đọc được cả OrderItemModel và Map', () {
      final lines = [
        StockSaleLine.from(OrderItemModel(
            productId: 7, name: 'Trà sữa', price: 30000, quantity: 2, selectedSize: 'L', selectedToppings: ['Trân Châu'])),
        StockSaleLine.from({'product_id': 7, 'quantity': 1}),
        StockSaleLine.from({'productId': 99, 'quantity': 1}),
      ].whereType<StockSaleLine>().toList();
      expect(lines.length, 3);

      final plan = StockConsumptionPlanner.plan(
        lines: lines,
        recipes: recipes,
        catalogIdByLegacyProductId: {7: 'ITM_TS'},
        catalogIdByName: {'trân châu': 'ITM_TC'},
      );
      // 2 ly size L (15/45) + 1 ly thường (10/30)
      expect(plan.qtyByItem['ITM_TRA'], 2 * 15 + 10);
      expect(plan.qtyByItem['ITM_SUA'], 2 * 45 + 30);
      // topping x2 ly
      expect(plan.qtyByItem['ITM_BOT'], 40);
      expect(plan.unmapped, contains('product:99'));
    });

    test('áp dụng tiêu hao lên số dư: trừ tồn và giá trị theo giá vốn bình quân', () {
      final next = StockConsumptionPlanner.applyConsumption(
        {'onHandQty': 100, 'inventoryValue': 50000, 'averageCostScaled': 50000, 'version': 3},
        balanceId: 'S_ITM',
        branchId: 'S',
        itemId: 'ITM',
        consumeQty: 10,
        now: 1,
      );
      expect(next['onHandQty'], 90);
      expect(next['inventoryValue'], 50000 - 5000);
      expect(next['version'], 4);
      final fresh = StockConsumptionPlanner.applyConsumption(null,
          balanceId: 'S_ITM', branchId: 'S', itemId: 'ITM', consumeQty: 3, now: 1);
      expect(fresh['onHandQty'], -3);
      expect(fresh['branchId'], 'S');
    });
  });

  group('BillRecordBuilder', () {
    test('giữ đầy đủ BillModel.toMap (discounts, VAT, khách...) + trường web đọc', () {
      final bill = BillModel(
        id: 'BILL_1',
        billCode: 'HD-261009-0001',
        orderCode: 'OD-261009-120000-ABCD',
        tableName: 'A1',
        zone: 'Khu A',
        createdAt: 1000,
        closedAt: 2000,
        status: 'PAID',
        staffUsername: 'thungan',
        staffFullName: 'Thu Ngân',
        items: [OrderItemModel(productId: 1, name: 'Cà phê', price: 20000, quantity: 2)],
        subTotal: 40000,
        discounts: [BillDiscountModel(promoId: 'CAM_1', promoCode: 'GIAM10', description: 'Giảm 10k', amount: 10000)],
        totalDiscount: 10000,
        vatRate: 8,
        vatAmount: 2400,
        finalAmount: 32400,
        customerId: 'KH1',
      );
      final rec = BillRecordBuilder.build(bill, storeCode: 'CN02', storeName: 'Trạm Chi nhánh 2', guestCount: 3);
      expect(rec['discounts'], isA<List>());
      expect((rec['discounts'] as List).single['promoCode'], 'GIAM10');
      expect(rec['vatAmount'], 2400);
      expect(rec['customerId'], 'KH1');
      expect(rec['storeName'], 'Trạm Chi nhánh 2');
      expect(rec['storeCode'], 'CN02');
      expect(rec['totalAmount'], 32400);
      expect(rec['discountAmount'], 10000);
      expect(rec['timestamp'], 2000);
      expect(rec['guestCount'], 3);
      expect(jsonDecode(rec['itemsJson'] as String), isA<List>());
      // Đọc lại vẫn ra đúng hóa đơn
      final back = BillModel.fromMap(rec, 'BILL_1');
      expect(back.discounts.single.amount, 10000);
      expect(back.finalAmount, 32400);
    });
  });
}
