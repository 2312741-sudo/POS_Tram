// Ca/két tiền và lịch sử hóa đơn ĐỘC LẬP THEO TÀI KHOẢN (thuần logic, không phụ thuộc Firebase).
//
// Quy ước:
// - Mỗi tài khoản có tối đa 1 ca đang mở; ca thuộc về tài khoản có uid == staffUid.
//   Ca cũ (trước khi tách, không có staffUid) thuộc về tài khoản có username == staffUsername.
// - Hóa đơn "của tôi" = tôi là người thu tiền (staffUid/staffUsername) HOẶC tôi đã gửi bếp / thêm món
//   vào đơn đó (actionLogs: SEND_KITCHEN, ADD_ITEMS).
// - Chỉ người có VIEW_ALL_SHIFTS / VIEW_ALL_BILLS_HISTORY (chủ, quản lý) thấy dữ liệu tài khoản khác.
import '../../data/models/bill_model.dart';
import '../../data/models/shift_model.dart';

String _norm(String? s) => (s ?? '').trim().toLowerCase();

/// Ca [s] có thuộc tài khoản ([uid], [username]) không.
bool shiftOwnedBy(CashShiftModel s, {required String uid, required String username}) {
  if (s.staffUid.isNotEmpty) return uid.isNotEmpty && s.staffUid == uid;
  final u = _norm(username);
  return u.isNotEmpty && _norm(s.staffUsername) == u;
}

/// Khóa nhóm chủ ca: uid nếu có, nếu không dùng username (chữ thường).
String shiftOwnerKey(CashShiftModel s) => s.staffUid.isNotEmpty ? s.staffUid : _norm(s.staffUsername);

/// Ca đang mở của chính tài khoản (mới nhất nếu có nhiều ca treo do lỗi cũ).
CashShiftModel? findOwnOpenShift(Iterable<CashShiftModel> shifts, {required String uid, required String username}) {
  CashShiftModel? best;
  for (final s in shifts) {
    if (!s.isOpen || !shiftOwnedBy(s, uid: uid, username: username)) continue;
    if (best == null || s.openedAt > best.openedAt) best = s;
  }
  return best;
}

/// Danh sách ca được phép thấy: tài khoản thường chỉ thấy ca của mình;
/// [canViewAll] thấy tất cả, tùy chọn lọc theo tài khoản [filterOwner] (username hoặc uid).
List<CashShiftModel> scopeShifts(
  Iterable<CashShiftModel> shifts, {
  required String uid,
  required String username,
  required bool canViewAll,
  String? filterOwner,
}) {
  final f = _norm(filterOwner);
  return shifts.where((s) {
    if (!canViewAll) return shiftOwnedBy(s, uid: uid, username: username);
    if (f.isEmpty) return true;
    return _norm(s.staffUid) == f || _norm(s.staffUsername) == f;
  }).toList();
}

/// Hóa đơn [b] có phải "của" tài khoản không (người thu tiền hoặc người tạo/thêm món).
bool billOwnedBy(BillModel b, {required String uid, required String username}) {
  final u = _norm(username);
  if (b.staffUid != null && b.staffUid!.isNotEmpty && uid.isNotEmpty) {
    if (b.staffUid == uid) return true;
  } else if (u.isNotEmpty && _norm(b.staffUsername) == u) {
    return true;
  }
  if (u.isEmpty) return false;
  for (final l in b.actionLogs) {
    if ((l.action == 'SEND_KITCHEN' || l.action == 'ADD_ITEMS') && _norm(l.staffUsername) == u) return true;
  }
  return false;
}

/// Hóa đơn được phép thấy (xem [billOwnedBy]); [filterUsername] chỉ có tác dụng khi [canViewAll].
List<BillModel> scopeBills(
  Iterable<BillModel> bills, {
  required String uid,
  required String username,
  required bool canViewAll,
  String? filterUsername,
}) {
  final f = _norm(filterUsername);
  return bills.where((b) {
    if (!canViewAll) return billOwnedBy(b, uid: uid, username: username);
    if (f.isEmpty) return true;
    return _norm(b.staffUsername) == f || billOwnedBy(b, uid: '', username: f);
  }).toList();
}

/// Hóa đơn [b] có thuộc ca [shift] không: ưu tiên shiftId; HĐ cũ thiếu shiftId → theo khoảng thời gian
/// VÀ cùng tài khoản thu tiền (nhiều ca của nhiều tài khoản có thể chồng thời gian).
bool billBelongsToShift(BillModel b, CashShiftModel shift) {
  if (b.shiftId != null && b.shiftId!.isNotEmpty) {
    return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
  }
  final closeT = shift.closedAt ?? 9999999999999;
  if (b.createdAt < shift.openedAt || b.createdAt > closeT) return false;
  final bu = _norm(b.staffUsername), su = _norm(shift.staffUsername);
  return bu.isEmpty || su.isEmpty || bu == su;
}

/// Staff không có VIEW_SHIFT_HANDOVER: kiểm đếm mù (không thấy số kỳ vọng/chênh lệch/phiếu bàn giao).
/// Trả về số tiền kiểm đếm dùng để chốt ca; nhân viên PHẢI nhập (null nếu để trống khi kiểm đếm mù).
int? resolveActualCash({required String input, required int expectedCash, required bool canViewHandover}) {
  final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isNotEmpty) return int.tryParse(digits);
  return canViewHandover ? expectedCash : null;
}

/// Tổng hợp các ca theo TÀI KHOẢN (báo cáo cuối ngày của chủ/quản lý: gộp + chi tiết từng tài khoản).
class ShiftOwnerSummary {
  final String ownerKey;
  final String staffUsername;
  final String staffFullName;
  final int shiftCount;
  final int cashSales;
  final int qrSales;
  final int cardSales;
  final int cashIn;
  final int cashOut;
  final int expectedCash;

  /// Tổng chênh lệch của các ca ĐÃ CHỐT (ca đang mở không tính).
  final int difference;
  const ShiftOwnerSummary({
    required this.ownerKey,
    required this.staffUsername,
    required this.staffFullName,
    required this.shiftCount,
    required this.cashSales,
    required this.qrSales,
    required this.cardSales,
    required this.cashIn,
    required this.cashOut,
    required this.expectedCash,
    required this.difference,
  });
  int get totalRevenue => cashSales + qrSales + cardSales;
}

List<ShiftOwnerSummary> summarizeShiftsByOwner(Iterable<CashShiftModel> shifts) {
  final groups = <String, List<CashShiftModel>>{};
  for (final s in shifts) {
    groups.putIfAbsent(shiftOwnerKey(s), () => []).add(s);
  }
  final out = groups.entries.map((e) {
    final l = e.value;
    int sum(int Function(CashShiftModel) f) => l.fold(0, (a, s) => a + f(s));
    return ShiftOwnerSummary(
      ownerKey: e.key,
      staffUsername: l.first.staffUsername,
      staffFullName: l.first.staffFullName,
      shiftCount: l.length,
      cashSales: sum((s) => s.totalCashSales),
      qrSales: sum((s) => s.totalQrSales),
      cardSales: sum((s) => s.totalCardSales),
      cashIn: sum((s) => s.cashIn),
      cashOut: sum((s) => s.cashOut),
      expectedCash: sum((s) => s.expectedCash),
      difference: l.where((s) => !s.isOpen).fold(0, (a, s) => a + (s.difference ?? 0)),
    );
  }).toList()
    ..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));
  return out;
}
