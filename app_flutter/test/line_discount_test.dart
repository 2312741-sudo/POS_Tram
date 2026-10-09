// Giảm giá theo món áp cho số phần được chọn trong dòng (discountedQuantity).
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

OrderItemModel _item({int qty = 5, int price = 30000, int topping = 0, int size = 0}) => OrderItemModel(
      productId: 1,
      name: 'Trà sữa',
      price: price,
      quantity: qty,
      toppingPrice: topping,
      sizeExtraPrice: size,
    );

String _fmt(int v) => '${v}đ';

void main() {
  group('Tính giảm giá theo phần', () {
    test('PERCENT chỉ giảm 2/5 phần, đơn giá gồm size + topping', () {
      // unitPrice = 30000 + 5000 + 5000 = 40000 → 10% × 2 = 8000
      final it = _item(topping: 5000, size: 5000).withLineDiscount(percent: 10, discountedQuantity: 2);
      expect(it.lineDiscountTotal, 8000);
      expect(it.discountAmount, 8000);
      expect(it.discountedQuantity, 2);
      expect(it.itemTotal, 200000 - 8000);
      expect(it.discountDescription(_fmt), 'Giảm 10% × 2/5 món');
    });

    test('AMOUNT đ/phần × số phần, chặn theo đơn giá & tiền dòng', () {
      final it = _item().withLineDiscount(unitAmount: 5000, discountedQuantity: 3);
      expect(it.lineDiscountTotal, 15000);
      expect(it.discountDescription(_fmt), 'Giảm 5000đ × 3/5 món');
      final capped = _item(qty: 2).withLineDiscount(unitAmount: 99999, discountedQuantity: 5);
      expect(capped.discountedQuantity, 2);
      expect(capped.lineDiscountTotal, 60000);
      expect(capped.itemTotal, 0);
    });

    test('Mặc định tất cả phần = giảm cả dòng', () {
      final it = _item(qty: 3).withLineDiscount(percent: 15, discountedQuantity: 3);
      expect(it.lineDiscountTotal, (90000 * 15 / 100).round());
      expect(it.discountDescription(_fmt), 'Giảm 15% × 3 món');
    });

    test('Bỏ giảm giá', () {
      final it = _item().withLineDiscount(percent: 10, discountedQuantity: 2).withoutLineDiscount();
      expect(it.hasDiscount, isFalse);
      expect(it.discountedQuantity, 0);
      expect(it.discountMode, 'NONE');
    });
  });

  group('Đổi số lượng dòng', () {
    test('giảm số lượng chặn discountedQuantity và tính lại tổng giảm', () {
      final it = _item().withLineDiscount(percent: 50, discountedQuantity: 4); // 4 × 15000
      expect(it.lineDiscountTotal, 60000);
      final smaller = it.copyWith(quantity: 2);
      expect(smaller.discountedQuantity, 2);
      expect(smaller.lineDiscountTotal, 30000);
      // tăng lại: phần mới KHÔNG tự được giảm
      final bigger = smaller.copyWith(quantity: 6);
      expect(bigger.discountedQuantity, 2);
      expect(bigger.lineDiscountTotal, 30000);
    });

    test('đổi topping tính lại giảm theo % trên đơn giá mới', () {
      final it = _item().withLineDiscount(percent: 10, discountedQuantity: 1);
      expect(it.lineDiscountTotal, 3000);
      expect(it.copyWith(toppingPrice: 10000).lineDiscountTotal, 4000);
    });

    test('đổi trường không liên quan không tính lại', () {
      final it = OrderItemModel.fromMap({'productId': 1, 'name': 'A', 'price': 33333, 'quantity': 3, 'discountAmount': 9999, 'discountPercent': 10});
      expect(it.copyWith(isSentKitchen: true).lineDiscountTotal, 9999);
    });

    test('tách hóa đơn chia số phần được giảm, tổng giảm không đổi', () {
      final it = _item().withLineDiscount(unitAmount: 5000, discountedQuantity: 2);
      final (a, b) = it.splitQuantity(3);
      expect(a!.quantity, 3);
      expect(a.discountedQuantity, 2);
      expect(a.lineDiscountTotal, 10000);
      expect(b!.quantity, 2);
      expect(b.discountedQuantity, 0);
      expect(b.lineDiscountTotal, 0);
      expect(a.itemTotal + b.itemTotal, it.itemTotal);
    });
  });

  group('Tương thích dữ liệu cũ (discountAmount = giảm CẢ DÒNG)', () {
    test('dòng cũ giảm số tiền: giữ nguyên tổng đã thu, coi là FIXED', () {
      final it = OrderItemModel.fromMap({'productId': 1, 'name': 'A', 'price': 30000, 'quantity': 3, 'discountAmount': 10000});
      expect(it.discountMode, 'FIXED');
      expect(it.discountedQuantity, 3);
      expect(it.lineDiscountTotal, 10000);
      expect(it.itemTotal, 80000);
      expect(it.discountDescription(_fmt), 'Giảm 10000đ');
      final m = it.toMap();
      expect(m['discountAmount'], 10000);
      expect(m['lineDiscountTotal'], 10000);
      expect(m['discountedQuantity'], 3);
      // Đọc lại bản ghi mới → không đổi
      expect(OrderItemModel.fromMap(m).itemTotal, 80000);
    });

    test('dòng cũ giảm %: discountAmount đã lưu là nguồn sự thật, không tính lại khi đọc', () {
      final it = OrderItemModel.fromMap({'productId': 1, 'name': 'A', 'price': 33333, 'quantity': 3, 'discountAmount': 10000, 'discountPercent': 10});
      expect(it.discountedQuantity, 3);
      expect(it.lineDiscountTotal, 10000);
    });

    test('lineDiscountTotal được ưu tiên hơn discountAmount', () {
      final it = OrderItemModel.fromMap({
        'productId': 1, 'name': 'A', 'price': 30000, 'quantity': 5,
        'discountAmount': 1, 'lineDiscountTotal': 6000, 'discountedQuantity': 2, 'discountPercent': 10,
      });
      expect(it.lineDiscountTotal, 6000);
      expect(it.discountedQuantity, 2);
    });

    test('tổng hóa đơn đã lưu không đổi khi đọc lại', () {
      final bill = BillModel.fromMap({
        'id': 'B1', 'billCode': 'HD-1', 'tableName': 'Bàn 1', 'createdAt': 1, 'status': 'PAID',
        'subTotal': 90000, 'totalDiscount': 10000, 'finalAmount': 80000,
        'items': [
          {'productId': 1, 'name': 'A', 'price': 30000, 'quantity': 3, 'discountAmount': 10000},
        ],
      }, 'B1');
      expect(bill.finalAmount, 80000);
      expect(bill.items.single.itemTotal, 80000);
    });
  });

  group('Gộp dòng', () {
    test('cấu hình giảm khác nhau là các dòng khác nhau', () {
      final plain = _item(qty: 2);
      final pct = _item(qty: 2).withLineDiscount(percent: 10, discountedQuantity: 1);
      final pct20 = _item(qty: 2).withLineDiscount(percent: 20, discountedQuantity: 1);
      final amt = _item(qty: 2).withLineDiscount(unitAmount: 3000, discountedQuantity: 1);
      final merged = OrderLineMerger.merge([plain], [pct, pct20, amt]);
      expect(merged.length, 4);
    });

    test('cùng cấu hình: cộng số lượng, số phần được giảm và tổng giảm', () {
      final a = _item(qty: 3).withLineDiscount(percent: 10, discountedQuantity: 1);
      final b = _item(qty: 2).withLineDiscount(percent: 10, discountedQuantity: 2);
      final merged = OrderLineMerger.merge([a], [b]);
      expect(merged.single.quantity, 5);
      expect(merged.single.discountedQuantity, 3);
      expect(merged.single.lineDiscountTotal, a.lineDiscountTotal + b.lineDiscountTotal);
    });
  });

  group('Pricing engine & báo cáo', () {
    test('PricingLineItem áp giảm thủ công theo phần', () {
      final it = _item().withLineDiscount(percent: 10, discountedQuantity: 2);
      final quote = calculatePrice(
        input: PricingInput(
          branchId: 'B',
          serverNowMs: 0,
          lines: [PricingLineItem.fromOrderItem(it, lineId: 'L1')],
        ),
        activeCampaigns: const [],
        counters: const {},
        customerCounters: const {},
      );
      expect(quote.grossMoney, 150000);
      expect(quote.manualDiscount, 6000);
      expect(quote.totalDiscountMoney, 6000);
      expect(quote.netMoney, 144000);
      expect(quote.lineBenefits.single.effectivePrice, 144000);
    });

    test('báo cáo dùng tổng giảm cả dòng (không nhân số lượng)', () {
      final legacy = OrderItemModel.fromMap({'productId': 2, 'name': 'B', 'price': 30000, 'quantity': 3, 'discountAmount': 10000});
      final partial = _item().withLineDiscount(percent: 10, discountedQuantity: 2); // 6000
      final bill = BillModel(
        id: 'B1', billCode: 'HD-1', tableName: 'Bàn 1', zone: 'A', createdAt: 1, status: 'PAID',
        staffUsername: 'tn', staffFullName: 'Thu ngân', subTotal: 0, finalAmount: 0,
        items: [legacy, partial],
      )..recalculateTotals();
      expect(bill.totalDiscount, 16000);
      final ov = ReportCalculator.calculateOverviewReport([bill]);
      expect(ov.itemDiscounts, 16000);
      final promo = ReportCalculator.calculatePromotionsReport([bill]);
      expect(promo.itemDiscounts.discountAmount, 16000);
      expect(promo.itemDiscounts.details.firstWhere((d) => d.productId == 1).quantity, 2);
    });
  });
}
