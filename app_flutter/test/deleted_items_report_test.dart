import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/deleted_items.dart';
import 'package:tram_flutter/core/reports/bill_report_rows.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/app_models.dart';

OrderItemModel _item({int productId = 1, String name = 'Trà đào', int price = 30000, int qty = 2, bool sent = false}) =>
    OrderItemModel(productId: productId, name: name, price: price, quantity: qty, isSentKitchen: sent);

DeletedItemEntry _entry({int qty = 1, int amount = 30000}) => DeletedItemEntry(
      name: 'Trà đào',
      productId: 1,
      quantity: qty,
      unitPrice: 30000,
      amount: amount,
      reason: DeleteItemReasons.wrongEntry,
      staffUsername: 'nv1',
      staffFullName: 'Nhân viên 1',
      timestamp: 1000,
      sentToKitchen: false,
    );

BillModel _bill(String id, String status, {List<DeletedItemEntry> deleted = const [], List<Map<String, dynamic>> discounts = const [], int finalAmount = 100000}) =>
    BillModel.fromMap({
      'billCode': 'HD-$id',
      'tableName': 'B1',
      'zone': 'Tầng 1',
      'createdAt': 1000,
      'closedAt': 2000,
      'status': status,
      'items': [],
      'subTotal': finalAmount,
      'finalAmount': finalAmount,
      'discounts': discounts,
      'deletedItems': deleted.map((e) => e.toMap()).toList(),
    }, id);

void main() {
  group('Lý do xóa món', () {
    test('lý do hợp lệ, "Khác" bắt buộc nội dung', () {
      expect(DeleteItemReasons.resolve('Nhập sai'), 'Nhập sai');
      expect(DeleteItemReasons.resolve('Khác'), isNull);
      expect(DeleteItemReasons.resolve('Khác', otherText: '  '), isNull);
      expect(DeleteItemReasons.resolve('Khác', otherText: 'Đổ ly'), 'Khác: Đổ ly');
      expect(DeleteItemReasons.resolve('bất kỳ'), isNull);
      expect(DeleteItemReasons.resolve(null), isNull);
    });
  });

  group('Phần đã lưu & tạo entry', () {
    test('chỉ tính phần số lượng đã lưu; phần vừa thêm xóa trước', () {
      final persisted = [_item(qty: 2)];
      final line = _item(qty: 3); // +1 chưa lưu
      expect(DeletedItemsLogic.persistedPortion(persisted: persisted, cart: [line], line: line, removeQty: 1), 0);
      expect(DeletedItemsLogic.persistedPortion(persisted: persisted, cart: [line], line: line, removeQty: 2), 1);
      expect(DeletedItemsLogic.persistedPortion(persisted: persisted, cart: [line], line: line, removeQty: 3), 2);
    });

    test('dòng chưa từng lưu → 0, cấu hình khác → không khớp', () {
      final line = _item(qty: 2);
      expect(DeletedItemsLogic.persistedPortion(persisted: [], cart: [line], line: line, removeQty: 2), 0);
      final other = _item(productId: 2, qty: 2);
      expect(DeletedItemsLogic.persistedPortion(persisted: [other], cart: [line], line: line, removeQty: 2), 0);
    });

    test('dòng đã gửi bếp vẫn khớp dòng đã lưu chưa gửi bếp', () {
      final saved = _item(qty: 2);
      final line = _item(qty: 2, sent: true);
      expect(DeletedItemsLogic.persistedPortion(persisted: [saved], cart: [line], line: line, removeQty: 1), 1);
    });

    test('giá trị xóa trừ phần giảm giá dòng tương ứng', () {
      final line = _item(qty: 2).withLineDiscount(percent: 10, discountedQuantity: 2);
      expect(line.itemTotal, 54000);
      expect(DeletedItemsLogic.removedAmount(line, 1), 27000);
      expect(DeletedItemsLogic.removedAmount(line, 2), 54000);
      // Giảm chỉ 1 phần: bớt 1 phần → phần được giảm vẫn giữ (chặn trong số lượng mới)
      final partial = _item(qty: 2).withLineDiscount(percent: 10, discountedQuantity: 1);
      expect(partial.itemTotal, 57000);
      expect(DeletedItemsLogic.removedAmount(partial, 1), 30000);
    });

    test('buildEntry: đúng trường hợp đồng, chia tỷ lệ khi lẫn phần chưa lưu', () {
      final line = _item(qty: 3, sent: true);
      final e = DeletedItemsLogic.buildEntry(
        line: line,
        removeQty: 3,
        savedQty: 2,
        reason: 'Khách hủy món',
        staffUsername: 'nv1',
        staffFullName: 'Nhân viên 1',
        timestamp: 123,
      );
      expect(e.quantity, 2);
      expect(e.unitPrice, 30000);
      expect(e.amount, 60000);
      expect(e.sentToKitchen, isTrue);
      expect(e.toMap().keys.toSet(), {
        'name', 'productId', 'quantity', 'unitPrice', 'amount', 'reason',
        'staffUsername', 'staffFullName', 'timestamp', 'sentToKitchen',
      });
    });

    test('audit details & trường cấu trúc', () {
      final e = _entry(qty: 2, amount: 54000);
      expect(DeletedItemsLogic.auditDetails(e, 'B1'), 'Xóa 2 x Trà đào (54.000đ) bàn B1 — Lý do: Nhập sai');
      final f = DeletedItemsLogic.auditFields(e, tableName: 'B1', orderCode: 'OD-1');
      expect(f, {'productName': 'Trà đào', 'quantity': 2, 'amount': 54000, 'reason': 'Nhập sai', 'tableName': 'B1', 'orderCode': 'OD-1'});
    });

    test('AuditLogModel ghi phẳng trường cấu trúc và đọc lại', () {
      final log = AuditLogModel(
        timestamp: 1,
        username: 'nv1',
        userFullName: 'NV',
        userRole: 'STAFF',
        action: 'DELETE_ITEM',
        targetType: 'ORDER_ITEM',
        targetId: 'OD-1',
        details: 'x',
        extra: {'reason': 'Nhập sai', 'quantity': 1},
      );
      final m = log.toMap();
      expect(m['reason'], 'Nhập sai');
      expect(AuditLogModel.fromMap(m).extra?['quantity'], 1);
    });
  });

  group('Bàn & hóa đơn mang deletedItems', () {
    test('TableModel: deletedItemsJson lưu/đọc, dọn bàn xóa sạch', () {
      final t = TableModel(name: 'B1', zone: 'Tầng 1', inUse: true);
      t.addDeletedItem(_entry());
      t.addDeletedItem(_entry(qty: 2, amount: 60000));
      final back = TableModel.fromMap(t.toMap(), t.firebaseKey);
      expect(back.deletedItems.length, 2);
      expect(back.deletedItems[1].amount, 60000);
      back.clearTable();
      expect(back.deletedItems, isEmpty);
      expect(back.toMap().containsKey('deletedItemsJson'), isFalse);
    });

    test('BillModel.toMap ghi deletedItems, deletedItemsCount, deletedItemsAmount', () {
      final b = _bill('1', 'PAID', deleted: [_entry(), _entry(qty: 2, amount: 50000)]);
      final m = b.toMap();
      expect((m['deletedItems'] as List).length, 2);
      expect(m['deletedItemsCount'], 3);
      expect(m['deletedItemsAmount'], 80000);
      expect(BillModel.fromMap(m, '1').deletedItemsAmount, 80000);
    });

    test('giảm giá đơn = tổng giảm − giảm giá món', () {
      final b = BillModel(
        id: 'x',
        billCode: 'HD',
        tableName: 'B1',
        zone: '',
        createdAt: 0,
        staffUsername: '',
        staffFullName: '',
        items: [_item(qty: 2).withLineDiscount(percent: 10, discountedQuantity: 2)],
        subTotal: 60000,
        totalDiscount: 16000,
        finalAmount: 44000,
      );
      expect(b.itemDiscountTotal, 6000);
      expect(b.orderLevelDiscount, 10000);
      final row = BillReportRows.summaryRow(b);
      expect(row[BillReportRows.summaryHeaders.indexOf('Giảm giá món')], 6000);
      expect(row[BillReportRows.summaryHeaders.indexOf('Giảm giá đơn')], 10000);
      expect(BillReportRows.statusLabel('PAID'), 'Hoàn thành');
      expect(BillReportRows.statusLabel('CANCELLED'), 'Đã hủy');
    });
  });

  group('Báo cáo', () {
    test('tổng món xóa gồm HĐ PAID và CANCELLED, bỏ trạng thái khác', () {
      final bills = [
        _bill('1', 'PAID', deleted: [_entry()]),
        _bill('2', 'CANCELLED', deleted: [_entry(qty: 2, amount: 60000)]),
        _bill('3', 'REFUNDED', deleted: [_entry(qty: 5, amount: 1)]),
      ];
      final s = ReportCalculator.calculateDeletedItems(bills);
      expect(s.count, 3);
      expect(s.amount, 90000);
      final z = ReportCalculator.generateEndOfDayZReport(bills: bills, shifts: const [], dateStr: '2026-10-10');
      expect(z.tab1TongHop.deletedItemsCount, 3);
      expect(z.tab1TongHop.deletedItemsAmount, 90000);
      expect(z.tab1TongHop.cancelledBillsCount, 1);
    });

    test('báo cáo theo CTKM: gom theo campaignId, fallback promoId', () {
      final bills = [
        _bill('1', 'PAID', finalAmount: 80000, discounts: [
          {'campaignId': 'C1', 'campaignName': 'Giờ vàng', 'programCode': 'GV', 'campaignType': 'BILL_PERCENT', 'voucherCode': 'V-001', 'description': 'x', 'amount': 10000},
        ]),
        _bill('2', 'PAID', finalAmount: 50000, discounts: [
          {'campaignId': 'C1', 'campaignName': 'Giờ vàng', 'description': 'x', 'amount': 5000},
          {'campaignId': 'C1', 'campaignName': 'Giờ vàng', 'voucherCode': 'V-002', 'description': 'x', 'amount': 2000},
        ]),
        _bill('3', 'PAID', finalAmount: 70000, discounts: [
          {'promoId': 'PROMO_TRIAN', 'promoCode': 'TRIAN10K', 'description': 'Tri ân', 'amount': 10000},
        ]),
        _bill('4', 'CANCELLED', discounts: [
          {'campaignId': 'C1', 'description': 'x', 'amount': 99999},
        ]),
      ];
      final r = ReportCalculator.calculateCampaignReport(bills);
      expect(r.length, 2);
      final c1 = r.firstWhere((c) => c.key == 'C1');
      expect(c1.name, 'Giờ vàng');
      expect(c1.code, 'GV');
      expect(c1.type, 'BILL_PERCENT');
      expect(c1.billCount, 2);
      expect(c1.discountAmount, 17000);
      expect(c1.revenue, 130000);
      expect(c1.voucherCodesUsed, 2);
      expect(c1.bills.length, 3);
      expect(c1.bills.map((b) => b.voucherCode).where((v) => v.isNotEmpty).toSet(), {'V-001', 'V-002'});
      final legacy = r.firstWhere((c) => c.key == 'PROMO_TRIAN');
      expect(legacy.code, 'TRIAN10K');
      expect(legacy.name, 'Tri ân khách hàng giảm 10k');
      expect(legacy.billCount, 1);
      expect(legacy.revenue, 70000);
    });
  });
}
