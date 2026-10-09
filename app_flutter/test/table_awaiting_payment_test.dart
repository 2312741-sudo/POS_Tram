// Trạng thái bàn "Chờ thanh toán" (đã in phiếu tạm tính): suy ra trạng thái + các quy tắc xóa cờ.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/table_model.dart';
import 'package:tram_flutter/features/tables/widgets/table_card.dart';

String _json(List<OrderItemModel> items) => jsonEncode(items.map((e) => e.toMap()).toList());

OrderItemModel _item({int qty = 1, String note = '', bool sent = false}) =>
    OrderItemModel(productId: 1, name: 'Cà phê sữa', price: 25000, quantity: qty, note: note, isSentKitchen: sent);

TableModel _servingTable() => TableModel(
      name: 'B1',
      zone: 'Khu A',
      inUse: true,
      currentOrderJson: _json([_item(qty: 2)]),
      openedAt: 1000,
    );

void main() {
  group('Suy ra trạng thái bàn', () {
    test('trống / có khách / chờ thanh toán / đặt trước', () {
      expect(TableStatusStyle.statusOf(TableModel(name: 'B0', zone: 'Khu A')), TableVisualStatus.empty);
      final t = _servingTable();
      expect(TableStatusStyle.statusOf(t), TableVisualStatus.inUse);
      t.markPrePrinted(by: 'thungan', at: 123);
      expect(t.isAwaitingPayment, isTrue);
      expect(TableStatusStyle.statusOf(t), TableVisualStatus.awaitingPayment);
      expect(TableStatusStyle.of(TableVisualStatus.awaitingPayment).label, 'Chờ thanh toán');
      expect(TableStatusStyle.statusOf(TableModel(name: 'B2', zone: 'Khu A', isReserved: true)), TableVisualStatus.reserved);
    });

    test('bàn không có khách thì không "chờ thanh toán" dù còn cờ', () {
      final t = TableModel(name: 'B3', zone: 'Khu A', prePrintedAt: 5);
      expect(t.isAwaitingPayment, isFalse);
      expect(TableStatusStyle.statusOf(t), TableVisualStatus.empty);
    });
  });

  group('Serialize theo hợp đồng prePrintedAt / prePrintedBy', () {
    test('round-trip và bỏ field khi chưa in', () {
      final t = _servingTable();
      expect(t.toMap().containsKey('prePrintedAt'), isFalse);
      expect(t.toMap().containsKey('prePrintedBy'), isFalse);
      t.markPrePrinted(by: 'nv01', at: 1700000000000);
      final back = TableModel.fromMap(t.toMap(), t.firebaseKey);
      expect(back.prePrintedAt, 1700000000000);
      expect(back.prePrintedBy, 'nv01');
      expect(back.isAwaitingPayment, isTrue);
    });

    test('đọc được prePrintedAt dạng chuỗi (dữ liệu web cũ)', () {
      final t = TableModel.fromMap({'name': 'B1', 'zone': 'Khu A', 'inUse': true, 'prePrintedAt': '42'});
      expect(t.prePrintedAt, 42);
    });
  });

  group('Quy tắc xóa cờ tạm tính', () {
    test('thêm / sửa món → quay về "có khách"', () {
      final t = _servingTable()..markPrePrinted(by: 'nv', at: 1);
      t.currentOrderJson = _json([_item(qty: 3)]);
      expect(t.prePrintedAt, isNull);
      expect(t.prePrintedBy, isNull);
      expect(TableStatusStyle.statusOf(t), TableVisualStatus.inUse);

      t.markPrePrinted(at: 2);
      t.currentOrderJson = _json([_item(qty: 3, note: 'ít đá')]);
      expect(t.prePrintedAt, isNull);
    });

    test('ghi lại cùng nội dung / chỉ đổi cờ gửi bếp → giữ trạng thái', () {
      final t = _servingTable()..markPrePrinted(at: 9);
      t.currentOrderJson = _json([_item(qty: 2)]);
      t.currentOrderJson = _json([_item(qty: 2, sent: true)]);
      expect(t.prePrintedAt, 9);
    });

    test('dọn bàn (thanh toán / hủy) xóa cờ', () {
      final t = _servingTable()..markPrePrinted(by: 'nv', at: 1);
      t.clearTable();
      expect(t.prePrintedAt, isNull);
      expect(t.prePrintedBy, isNull);
      expect(t.toMap().containsKey('prePrintedAt'), isFalse);
    });
  });
}
