import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/table_customer.dart';
import 'package:tram_flutter/data/models/table_model.dart';

TableModel _t(String n, {bool inUse = true}) => TableModel(name: n, zone: 'Khu A', inUse: inUse);

void main() {
  test('toMap/fromMap giữ khách; không có khách thì không có key', () {
    final t = _t('A1')..setCustomer(id: 'C1', name: 'Lan', phone: '0901');
    final back = TableModel.fromMap(t.toMap(), t.firebaseKey);
    expect([back.customerId, back.customerName, back.customerPhone], ['C1', 'Lan', '0901']);
    final empty = _t('A2').toMap();
    expect(empty.containsKey('customerId'), false);
    expect(empty.containsKey('customerName'), false);
    expect(empty.containsKey('customerPhone'), false);
  });

  test('clearTable xóa khách', () {
    final t = _t('A1')..setCustomer(id: 'C1', name: 'Lan', phone: '0901');
    t.clearTable();
    expect(t.hasCustomer, false);
    expect(t.toMap().containsKey('customerId'), false);
  });

  test('chuyển bàn: bàn đích nhận khách, nguồn bị xóa khi clearTable', () {
    final src = _t('A1')..setCustomer(id: 'C1', name: 'Lan', phone: '0901');
    final dst = _t('A2', inUse: false)..setCustomer(id: 'OLD');
    dst.takeCustomerFrom(src);
    src.clearTable();
    expect(dst.customerId, 'C1');
    expect(src.hasCustomer, false);
  });

  test('gộp bàn: giữ khách bàn đích, chỉ lấy của nguồn khi đích chưa có', () {
    final src = _t('A1')..setCustomer(id: 'S', name: 'Nguồn');
    final dstHas = _t('A2')..setCustomer(id: 'D', name: 'Đích');
    dstHas.adoptCustomerIfNone(src);
    expect(dstHas.customerId, 'D');
    final dstNone = _t('A3');
    dstNone.adoptCustomerIfNone(src);
    expect(dstNone.customerId, 'S');
    expect(dstNone.customerName, 'Nguồn');
  });

  test('phục hồi khách từ bàn: hiện ngay tên/SĐT, tra điểm lỗi thì giữ thông tin', () {
    final t = _t('A1')..setCustomer(id: 'C1', name: 'Lan', phone: '0901');
    final c = TableCustomerLogic.restore(t)!;
    expect([c.id, c.fullName, c.phone], ['C1', 'Lan', '0901']);
    expect(TableCustomerLogic.applyMember(c, found: false), false);
    expect(c.fullName, 'Lan');
    expect(TableCustomerLogic.applyMember(c, found: true, points: 120, totalPoints: 500), true);
    expect([c.currentPoints, c.totalPoints], [120, 500]);
  });

  test('bàn trống còn khách sót -> không phục hồi và dọn sót', () {
    final t = _t('A1', inUse: false)..setCustomer(id: 'C1');
    expect(TableCustomerLogic.restore(t), isNull);
    expect(t.hasCustomer, false);
    expect(TableCustomerLogic.restore(_t('A2')), isNull);
  });

  test('writeToTable', () {
    final t = _t('A1');
    final c = TableCustomerLogic.restore(_t('X')..setCustomer(id: 'C9', name: 'N', phone: 'P'))!;
    TableCustomerLogic.writeToTable(t, c);
    expect(t.customerId, 'C9');
    TableCustomerLogic.writeToTable(t, null);
    expect(t.hasCustomer, false);
  });
}
