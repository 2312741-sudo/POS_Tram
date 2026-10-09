// lib/data/services/loyalty_service.dart
//
// Tích / đổi điểm khách hàng khi thanh toán - nguyên tử & idempotent theo hóa đơn.
//
// Nguồn số dư chuẩn: RTDB stores/{s}/customers/{customerId} (diem_hien_tai = currentPoints).
// - Mọi thay đổi điểm chạy bằng runTransaction trên node khách; khóa thao tác
//   "{billId}:{redeem|award|refund}" được lưu trong vòng khóa loyaltyOps của chính node
//   → gọi lại cho cùng hóa đơn không cộng/trừ 2 lần.
// - Sổ cái stores/{s}/loyalty_applied/{billId}/{op} (chỉ tạo mới) ghi sau khi commit,
//   dùng để tra cứu nhanh và để rules chặn cộng điểm lặp lại cho 1 hóa đơn.
// - Firestore kmt_customers / kmt_point_history là bản sao CHỈ ĐỌC: Cloud Function
//   mirrorCustomerToFirestore đồng bộ từ RTDB; client không ghi điểm vào Firestore.
// - Khách chỉ có trên Firestore được nhập vào RTDB qua callable importCustomerToStore.
import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

import '../../core/domain/order_integrity.dart';
import 'customer_import_service.dart';

class LoyaltyResult {
  final LoyaltyTxnStatus status;
  final int before;
  final int after;
  final int points;

  /// true nếu transaction chưa được server xác nhận trong thời gian chờ (đang đồng bộ nền)
  final bool unverified;

  /// Ghi chú lỗi phụ (sổ cái, Firestore) - không ảnh hưởng số dư
  final List<String> notes;

  LoyaltyResult(this.status, {this.before = 0, this.after = 0, this.points = 0, this.unverified = false, List<String>? notes})
      : notes = notes ?? [];

  bool get applied => status == LoyaltyTxnStatus.applied;
}

class LoyaltyService {
  final DatabaseReference Function() _getRoot;
  LoyaltyService(this._getRoot);

  static const Duration _readTimeout = Duration(seconds: 3);

  DatabaseReference _customerRef(String storeCode, String customerId) =>
      _getRoot().child('stores/$storeCode/customers/$customerId');

  DatabaseReference _ledgerRef(String storeCode, String billId, LoyaltyOp op) =>
      _getRoot().child('stores/$storeCode/loyalty_applied/$billId/${op.name}');

  /// Khách có thể chỉ có trên Firestore (kmt_customers): nhờ Cloud Function importCustomerToStore
  /// chép sang RTDB với số dư thật (rules không cho Thu ngân tự tạo khách có điểm).
  Future<void> _ensureCustomerNode(String storeCode, String customerId) async {
    final ref = _customerRef(storeCode, customerId);
    try {
      final snap = await ref.get().timeout(_readTimeout);
      if (snap.value != null) return;
    } catch (_) {
      return; // Mất mạng: để transaction tự xử lý theo cache / server
    }
    try {
      await CustomerImportService.importToStore(storeCode: storeCode, customerId: customerId);
    } catch (_) {
      // not-found / mất mạng: transaction bên dưới sẽ báo missingCustomer
    }
  }

  /// Chạy transaction điểm. [timeout] = null: chờ tới khi server xác nhận.
  /// Khi quá [timeout], trả về unverified và transaction tiếp tục chạy nền ([onLate] báo lỗi muộn).
  Future<LoyaltyResult> _run({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required LoyaltyOp op,
    required int points,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
  }) async {
    if (points <= 0) return LoyaltyResult(LoyaltyTxnStatus.applied);

    // Sổ cái đã có → đã áp dụng
    try {
      final ledger = await _ledgerRef(storeCode, billId, op).get().timeout(_readTimeout);
      if (ledger.value != null) {
        return LoyaltyResult(LoyaltyTxnStatus.alreadyApplied, points: points);
      }
    } catch (_) {}

    await _ensureCustomerNode(storeCode, customerId);

    LoyaltyTxnOutcome? last;
    final now = DateTime.now().millisecondsSinceEpoch;
    final fut = _customerRef(storeCode, customerId).runTransaction((Object? current) {
      // Cache trống: ghi null để server trả dữ liệu thật rồi chạy lại
      if (current == null) {
        last = LoyaltyTxnOutcome(LoyaltyTxnStatus.missingCustomer);
        return Transaction.success(null);
      }
      final o = LoyaltyMath.apply(current, billId: billId, op: op, points: points, now: now, by: by);
      last = o;
      if (o.status != LoyaltyTxnStatus.applied || o.next == null) return Transaction.abort();
      return Transaction.success(o.next);
    });

    Future<LoyaltyResult> finish(TransactionResult res) async {
      final o = last;
      if (o == null) throw LoyaltyException('Không đọc được điểm của khách $customerId');
      if (o.status == LoyaltyTxnStatus.missingCustomer || (res.committed && res.snapshot.value == null)) {
        return LoyaltyResult(LoyaltyTxnStatus.missingCustomer);
      }
      if (!res.committed && o.status == LoyaltyTxnStatus.applied) {
        throw LoyaltyException('Transaction điểm của khách $customerId không được commit');
      }
      final r = LoyaltyResult(o.status, before: o.before, after: o.after, points: o.points);
      if (o.status == LoyaltyTxnStatus.applied || o.status == LoyaltyTxnStatus.alreadyApplied) {
        await _writeLedger(storeCode, customerId, billId, op, r, by, r.notes);
      }
      // Firestore kmt_customers / kmt_point_history: do Cloud Function mirrorCustomerToFirestore đồng bộ
      return r;
    }

    if (timeout == null) return finish(await fut);
    try {
      final res = await fut.timeout(timeout);
      return await finish(res);
    } on TimeoutException {
      unawaited(fut.then(finish).then((r) {
        if (r.status == LoyaltyTxnStatus.insufficient) {
          onLate?.call('Đổi ${r.points} điểm thất bại khi đồng bộ: khách chỉ còn ${r.before} điểm');
        } else if (r.status == LoyaltyTxnStatus.missingCustomer) {
          onLate?.call('Không tìm thấy khách $customerId khi đồng bộ điểm (${op.name})');
        } else if (r.notes.isNotEmpty) {
          onLate?.call(r.notes.join('; '));
        }
      }, onError: (Object e) {
        onLate?.call('Cập nhật điểm (${op.name}) cho khách $customerId lỗi: $e');
      }));
      return LoyaltyResult(LoyaltyTxnStatus.applied, points: points, unverified: true);
    }
  }

  Future<void> _writeLedger(
    String storeCode,
    String customerId,
    String billId,
    LoyaltyOp op,
    LoyaltyResult r,
    String by,
    List<String> notes,
  ) async {
    final ref = _ledgerRef(storeCode, billId, op);
    try {
      await ref.set({
        'customerId': customerId,
        'points': r.points,
        'before': r.before,
        'after': r.after,
        'at': DateTime.now().millisecondsSinceEpoch,
        'by': by,
      }).timeout(const Duration(seconds: 6));
    } catch (e) {
      // Chỉ tạo mới: nếu đã có (thiết bị khác vừa ghi) thì không phải lỗi
      try {
        final snap = await ref.get().timeout(_readTimeout);
        if (snap.value != null) return;
      } catch (_) {}
      notes.add('Không ghi được sổ cái điểm $billId/${op.name}: $e');
    }
  }

  /// Đổi điểm cho hóa đơn - gọi TRƯỚC khi ghi hóa đơn.
  /// Ném [InsufficientPointsException] nếu không đủ điểm, [LoyaltyException] nếu không tìm thấy khách.
  Future<LoyaltyResult> redeemForBill({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required int points,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
  }) async {
    final r = await _run(
      storeCode: storeCode,
      customerId: customerId,
      billId: billId,
      billCode: billCode,
      op: LoyaltyOp.redeem,
      points: points,
      by: by,
      timeout: timeout,
      onLate: onLate,
    );
    if (r.status == LoyaltyTxnStatus.insufficient) throw InsufficientPointsException(points, r.before);
    if (r.status == LoyaltyTxnStatus.missingCustomer) {
      throw LoyaltyException('Không tìm thấy khách hàng $customerId để đổi điểm');
    }
    return r;
  }

  /// Hoàn lại điểm đã đổi khi ghi hóa đơn thất bại.
  Future<LoyaltyResult> refundRedeem({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required int points,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
  }) =>
      _run(
        storeCode: storeCode,
        customerId: customerId,
        billId: billId,
        billCode: billCode,
        op: LoyaltyOp.refund,
        points: points,
        by: by,
        timeout: timeout,
        onLate: onLate,
      );

  /// Tích điểm sau khi hóa đơn đã ghi (PAID). Ném lỗi để người gọi ghi audit log.
  Future<LoyaltyResult> awardForBill({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required int billAmount,
    required double earnRatePercent,
    required int redeemRate,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
  }) async {
    final points = LoyaltyMath.pointsToAward(billAmount: billAmount, earnRatePercent: earnRatePercent, redeemRate: redeemRate);
    if (points <= 0) return LoyaltyResult(LoyaltyTxnStatus.applied);
    final r = await _run(
      storeCode: storeCode,
      customerId: customerId,
      billId: billId,
      billCode: billCode,
      op: LoyaltyOp.award,
      points: points,
      by: by,
      timeout: timeout,
      onLate: onLate,
    );
    if (r.status == LoyaltyTxnStatus.missingCustomer) {
      throw LoyaltyException('Không tìm thấy khách hàng $customerId để tích điểm');
    }
    return r;
  }
}
