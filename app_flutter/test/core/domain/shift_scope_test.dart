import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/shift_scope.dart';
import 'package:tram_flutter/data/models/app_models.dart';

CashShiftModel shift(String id, {String uid = '', required String user, int openedAt = 1000, bool open = true, int cash = 0, int diff = 0}) =>
    CashShiftModel(
      id: id,
      storeCode: 'TRAM01',
      staffUid: uid,
      staffUsername: user,
      staffFullName: user,
      openedAt: openedAt,
      closedAt: open ? null : openedAt + 500,
      status: open ? 'OPEN' : 'CLOSED',
      totalCashSales: cash,
      difference: open ? null : diff,
    );

BillModel bill(String id, {String? uid, required String user, List<OrderActionLogModel> logs = const [], String? shiftId, int createdAt = 1500}) =>
    BillModel(
      id: id,
      billCode: id,
      tableName: 'B1',
      zone: 'A',
      createdAt: createdAt,
      staffUid: uid,
      staffUsername: user,
      staffFullName: user,
      items: const [],
      subTotal: 0,
      finalAmount: 0,
      shiftId: shiftId,
      actionLogs: logs,
    );

OrderActionLogModel log(String action, String user) =>
    OrderActionLogModel(timestamp: 1, staffUsername: user, staffFullName: user, action: action, details: '');

void main() {
  group('Ca/két theo tài khoản', () {
    test('mỗi tài khoản chỉ thấy ca đang mở của mình, không nhập vào ca của admin', () {
      final shifts = [
        shift('s_admin', uid: 'uA', user: 'admin', openedAt: 2000),
        shift('s_nv', uid: 'uB', user: 'nv1', openedAt: 1000),
      ];
      expect(findOwnOpenShift(shifts, uid: 'uB', username: 'nv1')!.id, 's_nv');
      expect(findOwnOpenShift(shifts, uid: 'uA', username: 'admin')!.id, 's_admin');
      expect(findOwnOpenShift(shifts, uid: 'uC', username: 'nv2'), isNull);
    });

    test('ca cũ không có uid thuộc về tài khoản trùng username (không phân biệt hoa thường)', () {
      final legacy = shift('old', user: 'Admin');
      expect(shiftOwnedBy(legacy, uid: 'uA', username: 'admin'), isTrue);
      expect(shiftOwnedBy(legacy, uid: 'uB', username: 'nv1'), isFalse);
      // uid khác thì KHÔNG khớp dù trùng username khi ca đã có uid
      final modern = shift('new', uid: 'uA', user: 'admin');
      expect(shiftOwnedBy(modern, uid: 'uX', username: 'admin'), isFalse);
    });

    test('nhiều ca treo: lấy ca mở gần nhất của chính chủ', () {
      final shifts = [shift('a', uid: 'u', user: 'x', openedAt: 1), shift('b', uid: 'u', user: 'x', openedAt: 9)];
      expect(findOwnOpenShift(shifts, uid: 'u', username: 'x')!.id, 'b');
    });

    test('nhân viên chỉ thấy ca của mình; quản lý thấy tất cả và lọc theo tài khoản', () {
      final shifts = [
        shift('1', uid: 'uA', user: 'admin'),
        shift('2', uid: 'uB', user: 'nv1', open: false),
        shift('3', user: 'nv1', open: false), // ca cũ
      ];
      expect(scopeShifts(shifts, uid: 'uB', username: 'nv1', canViewAll: false).map((s) => s.id), ['2', '3']);
      expect(scopeShifts(shifts, uid: 'uA', username: 'admin', canViewAll: true).length, 3);
      expect(scopeShifts(shifts, uid: 'uA', username: 'admin', canViewAll: true, filterOwner: 'nv1').map((s) => s.id), ['2', '3']);
      // filterOwner bị bỏ qua với nhân viên: không có cách nào thấy người khác
      expect(scopeShifts(shifts, uid: 'uB', username: 'nv1', canViewAll: false, filterOwner: 'admin').map((s) => s.id), ['2', '3']);
    });

    test('kiểm đếm mù: nhân viên phải nhập tiền, quản lý để trống lấy số kỳ vọng', () {
      expect(resolveActualCash(input: '', expectedCash: 500, canViewHandover: false), isNull);
      expect(resolveActualCash(input: '', expectedCash: 500, canViewHandover: true), 500);
      expect(resolveActualCash(input: '1.200.000đ', expectedCash: 500, canViewHandover: false), 1200000);
    });

    test('hóa đơn cũ không shiftId chỉ gán cho ca cùng người thu tiền trong khoảng thời gian', () {
      final s = shift('s', uid: 'uB', user: 'nv1', openedAt: 1000);
      expect(billBelongsToShift(bill('b1', user: 'nv1', shiftId: 's'), s), isTrue);
      expect(billBelongsToShift(bill('b2', user: 'nv1'), s), isTrue);
      expect(billBelongsToShift(bill('b3', user: 'admin'), s), isFalse);
      expect(billBelongsToShift(bill('b4', user: 'nv1', shiftId: 'other'), s), isFalse);
    });

    test('tổng hợp theo tài khoản', () {
      final r = summarizeShiftsByOwner([
        shift('1', uid: 'uA', user: 'admin', cash: 100),
        shift('2', uid: 'uA', user: 'admin', cash: 50, open: false, diff: -10),
        shift('3', uid: 'uB', user: 'nv1', cash: 400),
      ]);
      expect(r.length, 2);
      expect(r.first.staffUsername, 'nv1');
      final admin = r.firstWhere((e) => e.staffUsername == 'admin');
      expect(admin.shiftCount, 2);
      expect(admin.cashSales, 150);
      expect(admin.difference, -10);
    });
  });

  group('Lịch sử hóa đơn theo tài khoản', () {
    test('hóa đơn của tôi = tôi thu tiền hoặc tôi gửi bếp/thêm món', () {
      final paid = bill('p', user: 'nv1', uid: 'uB');
      final created = bill('c', user: 'admin', uid: 'uA', logs: [log('SEND_KITCHEN', 'nv1')]);
      final other = bill('o', user: 'admin', uid: 'uA', logs: [log('PAY_BILL', 'nv1'), log('CANCEL_ITEM', 'nv1')]);
      expect(billOwnedBy(paid, uid: 'uB', username: 'nv1'), isTrue);
      expect(billOwnedBy(created, uid: 'uB', username: 'nv1'), isTrue);
      expect(billOwnedBy(other, uid: 'uB', username: 'nv1'), isFalse);
    });

    test('HĐ có staffUid thì so khớp theo uid, không theo username trùng', () {
      final b = bill('x', user: 'nv1', uid: 'uOther');
      expect(billOwnedBy(b, uid: 'uB', username: 'nv1'), isFalse);
    });

    test('nhân viên không thấy HĐ của người khác kể cả khi cố lọc; quản lý lọc theo tài khoản', () {
      final bills = [bill('1', user: 'admin', uid: 'uA'), bill('2', user: 'nv1', uid: 'uB'), bill('3', user: 'nv2')];
      expect(scopeBills(bills, uid: 'uB', username: 'nv1', canViewAll: false, filterUsername: 'admin').map((b) => b.id), ['2']);
      expect(scopeBills(bills, uid: 'uA', username: 'admin', canViewAll: true).length, 3);
      expect(scopeBills(bills, uid: 'uA', username: 'admin', canViewAll: true, filterUsername: 'nv2').map((b) => b.id), ['3']);
    });
  });
}
