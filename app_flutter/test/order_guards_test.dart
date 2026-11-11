import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_guards.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';

OrderItemModel _it(String name, int qty, {bool sent = false, int discount = 0, String key = ''}) => OrderItemModel(
      productId: 1,
      name: name,
      price: 20000,
      quantity: qty,
      isSentKitchen: sent,
      discountUnitAmount: discount,
      discountedQuantity: discount > 0 ? qty : 0,
      lineKey: key.isEmpty ? null : key,
    );

String _json(List<OrderItemModel> items) => jsonEncode(items.map((e) => e.toMap()).toList());

ServerTableRead _server(List<OrderItemModel> items, {bool inUse = true, String? closed}) =>
    ServerTableRead.fromNode({'inUse': inUse, 'currentOrderJson': _json(items), if (closed != null) 'closedBillId': closed});

void main() {
  group('Thanh toán: chỉ chặn khi server có món mà hóa đơn thiếu', () {
    final bill = [_it('Trà tắc', 2), _it('Bánh', 1)];

    test('không đọc được (lỗi / hết giờ / mất mạng) → không chặn', () {
      expect(OrderGuards.missingFromBill(ServerTableRead.failed, bill), isEmpty);
    });

    test('bàn tách tự động chưa có trên server (node không tồn tại) → không chặn', () {
      expect(OrderGuards.missingFromBill(ServerTableRead.fromNode(null), bill), isEmpty);
    });

    test('một máy, đơn treo đã gửi bếp: server có cờ gửi bếp / mã dòng khác → không chặn', () {
      final server = _server([_it('Trà tắc', 2, sent: true, key: 'x1'), _it('Bánh', 1, sent: true, key: 'x2')]);
      expect(OrderGuards.missingFromBill(server, bill), isEmpty);
    });

    test('server chia cùng món thành nhiều dòng (gọi thêm sau) → cộng dồn, không chặn', () {
      final server = _server([_it('Trà tắc', 1, sent: true), _it('Trà tắc', 1), _it('Bánh', 1)]);
      expect(OrderGuards.missingFromBill(server, bill), isEmpty);
    });

    test('khác giảm giá / ghi chú → không chặn', () {
      expect(OrderGuards.missingFromBill(_server([_it('Trà tắc', 2, discount: 5000), _it('Bánh', 1)]), bill), isEmpty);
    });

    test('máy khác vừa thêm món chưa có trong hóa đơn → chặn và nêu món thiếu', () {
      final server = _server([_it('Trà tắc', 3), _it('Bánh', 1), _it('Trà chanh', 1)]);
      expect(OrderGuards.missingFromBill(server, bill), ['Trà tắc x1', 'Trà chanh x1']);
    });

    test('bàn trên server đã đóng / trống → không chặn ở bước này', () {
      expect(OrderGuards.missingFromBill(_server([], inUse: false), bill), isEmpty);
    });
  });

  group('Chuyển / gộp bàn: chỉ chặn khi chắc chắn', () {
    ({String? blockReason, bool useServer}) decide(ServerTableRead server, {bool inUse = true, int count = 4, String? bill = 'HD-1'}) =>
        OrderGuards.sourceForMove(tableName: 'LỀ 05', localInUse: inUse, localItemCount: count, localBillId: bill, server: server);

    test('bàn đang có 4 phần, đọc server bị lỗi / hết giờ → vẫn chuyển (dùng bản trên máy)', () {
      final d = decide(ServerTableRead.failed);
      expect(d.blockReason, isNull);
      expect(d.useServer, isFalse);
    });

    test('bàn tách tự động chưa có node trên server → vẫn chuyển', () {
      expect(decide(ServerTableRead.fromNode(null)).blockReason, isNull);
    });

    test('server có món → dùng bản server (gồm món máy khác vừa thêm)', () {
      final d = decide(_server([_it('Trà tắc', 4)]));
      expect(d.blockReason, isNull);
      expect(d.useServer, isTrue);
    });

    test('server trống nhưng chưa xác nhận đã chuyển (closedBillId khác) → không chặn', () {
      expect(decide(_server([], inUse: false, closed: 'HD-khác')).blockReason, isNull);
    });

    test('bấm 2 lần: server xác nhận đơn đã chuyển (closedBillId trùng) → chặn', () {
      expect(decide(_server([], inUse: false, closed: 'HD-1')).blockReason, isNotNull);
    });

    test('bàn trên máy không còn món → chặn', () {
      expect(decide(ServerTableRead.failed, inUse: false, count: 0).blockReason, isNotNull);
    });
  });
}
