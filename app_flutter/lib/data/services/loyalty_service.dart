// lib/data/services/loyalty_service.dart
//
// Điểm tích lũy DÙNG CHUNG toàn chuỗi - client chỉ GỌI Cloud Functions, không ghi điểm.
//
// Nguồn chuẩn duy nhất: RTDB loyalty_members/{SĐT chuẩn hóa} (+ sổ cái loyalty_ledger/{SĐT}/{opId}).
// - Đổi / hoàn / tích điểm đi qua callable redeemLoyaltyPoints / refundLoyaltyPoints / applyLoyaltyEarn
//   (transaction + idempotent theo (hóa đơn, thao tác) ở máy chủ; số điểm tích tính ở máy chủ từ hóa đơn PAID).
// - Node khách của chi nhánh stores/{s}/customers/{id} chỉ còn là BẢN SAO đọc của số dư
//   (trigger mirrorMemberToBranches cập nhật) nên màn hình cũ vẫn hiển thị đúng.
// - Tra số dư dùng chung (kể cả điểm tích ở chi nhánh khác): callable lookupMember.
// - Cần mạng để đổi/tích điểm: lỗi mạng khi đổi điểm → ném lỗi TRƯỚC khi ghi hóa đơn.
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'dart:convert';

import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/domain/order_integrity.dart';
import 'customer_import_service.dart';

class LoyaltyResult {
  final LoyaltyTxnStatus status;
  final int before;
  final int after;

  /// Số điểm đã áp dụng (hoàn điểm có thể ít hơn yêu cầu)
  final int points;
  final String memberKey;

  /// Luôn false (giữ để tương thích mã cũ): thao tác chỉ thành công khi máy chủ xác nhận
  final bool unverified;

  /// Ghi chú lỗi phụ - không ảnh hưởng số dư
  final List<String> notes;

  LoyaltyResult(this.status, {this.before = 0, this.after = 0, this.points = 0, this.memberKey = '', this.unverified = false, List<String>? notes})
      : notes = notes ?? [];

  bool get applied => status == LoyaltyTxnStatus.applied;

  /// Chuyển phản hồi callable ({status, applied, before, after, memberKey}) sang kết quả.
  factory LoyaltyResult.fromMap(Map<dynamic, dynamic> m) {
    int i(Object? v) => v is num ? v.toInt() : 0;
    final status = switch (m['status']?.toString()) {
      'alreadyApplied' => LoyaltyTxnStatus.alreadyApplied,
      'insufficient' => LoyaltyTxnStatus.insufficient,
      'nothingToRefund' => LoyaltyTxnStatus.nothingToRefund,
      _ => LoyaltyTxnStatus.applied,
    };
    return LoyaltyResult(
      status,
      before: i(m['before']),
      after: i(m['after']),
      points: i(m['applied']),
      memberKey: m['memberKey']?.toString() ?? '',
    );
  }
}

/// Bản ghi điểm dùng chung của một khách (gộp mọi chi nhánh).
class SharedMember {
  final bool found;
  final String memberKey;
  final String name;
  final String phone;
  final int points;
  final int totalPoints;

  /// true: khách chưa có SĐT hợp lệ nên điểm chỉ thuộc 1 chi nhánh (không gộp)
  final bool local;
  final int branchCount;
  final String lastStoreCode;

  const SharedMember({
    required this.found,
    this.memberKey = '',
    this.name = '',
    this.phone = '',
    this.points = 0,
    this.totalPoints = 0,
    this.local = false,
    this.branchCount = 0,
    this.lastStoreCode = '',
  });

  static const SharedMember none = SharedMember(found: false);

  factory SharedMember.fromMap(Map<dynamic, dynamic> m) {
    int i(Object? v) => v is num ? v.toInt() : 0;
    return SharedMember(
      found: m['found'] == true,
      memberKey: m['memberKey']?.toString() ?? '',
      name: m['name']?.toString() ?? '',
      phone: m['phone']?.toString() ?? '',
      points: i(m['points']),
      totalPoints: i(m['totalPoints']),
      local: m['local'] == true,
      branchCount: i(m['branchCount']),
      lastStoreCode: m['lastStoreCode']?.toString() ?? '',
    );
  }
}

class LoyaltyService {
  /// [getRoot] chỉ dùng để KIỂM TRA node khách của chi nhánh còn thiếu (nhập từ Firestore); dịch vụ không ghi điểm vào RTDB.
  final DatabaseReference Function()? _getRoot;
  LoyaltyService([this._getRoot]);

  /// Khách có thể chỉ có trên Firestore (kmt_customers) hoặc ở chi nhánh khác: nhờ importCustomerToStore
  /// tạo node khách tại chi nhánh này (máy chủ gắn vào bản ghi điểm dùng chung theo SĐT).
  Future<void> _ensureCustomerNode(String storeCode, String customerId) async {
    final root = _getRoot;
    if (root == null) return;
    try {
      final snap = await root().child('stores/$storeCode/customers/$customerId').get().timeout(const Duration(seconds: 3));
      if (snap.value != null) return;
    } catch (_) {
      return; // Mất mạng: để callable báo lỗi rõ ràng
    }
    try {
      await CustomerImportService.importToStore(storeCode: storeCode, customerId: customerId);
    } catch (_) {
      // not-found / mất mạng: callable bên dưới sẽ báo lỗi
    }
  }

  static const String _region = 'asia-southeast1';
  static FirebaseFunctions? _functionsMock;

  static void setFunctionsMock(FirebaseFunctions? mock) => _functionsMock = mock;

  static FirebaseFunctions get _functions => _functionsMock ?? FirebaseFunctions.instanceFor(region: _region);

  static const Duration _defaultTimeout = Duration(seconds: 12);

  /// Gọi callable; lỗi máy chủ được chuyển thành [InsufficientPointsException] / [LoyaltyException].
  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data, {Duration? timeout, int requested = 0}) async {
    try {
      final callable = _functions.httpsCallable(name, options: HttpsCallableOptions(timeout: timeout ?? _defaultTimeout));
      final res = await callable.call<dynamic>(data);
      final raw = res.data;
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      throw mapError(e, requested: requested);
    } on TimeoutException {
      throw LoyaltyException('Quá thời gian chờ máy chủ điểm ($name). Kiểm tra kết nối mạng.');
    }
  }

  /// Chuyển lỗi callable sang ngoại lệ miền. Công khai để test.
  static Exception mapError(FirebaseFunctionsException e, {int requested = 0}) {
    final d = e.details;
    if (d is Map && d['code'] == 'insufficient') {
      final bal = d['balance'];
      final req = d['requested'];
      return InsufficientPointsException(req is num ? req.toInt() : requested, bal is num ? bal.toInt() : 0);
    }
    return LoyaltyException(e.message ?? e.code);
  }

  /// Đổi điểm cho hóa đơn - gọi TRƯỚC khi ghi hóa đơn.
  /// Ném [InsufficientPointsException] nếu tổng điểm dùng chung không đủ, [LoyaltyException] khi lỗi khác.
  /// [timeout]/[onLate] giữ để tương thích (thao tác luôn chờ máy chủ xác nhận).
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
    if (points <= 0) return LoyaltyResult(LoyaltyTxnStatus.applied);
    await _ensureCustomerNode(storeCode, customerId);
    final data = await _call(
      'redeemLoyaltyPoints',
      {'storeCode': storeCode, 'customerId': customerId, 'billId': billId, 'billCode': billCode, 'points': points},
      timeout: timeout != null && timeout > _defaultTimeout ? timeout : _defaultTimeout,
      requested: points,
    );
    final r = LoyaltyResult.fromMap(data);
    if (r.status == LoyaltyTxnStatus.insufficient) throw InsufficientPointsException(points, r.before);
    return r;
  }

  /// Hoàn lại điểm đã đổi khi ghi hóa đơn thất bại (máy chủ hoàn đúng số đã đổi cho hóa đơn, tối đa 1 lần).
  Future<LoyaltyResult> refundRedeem({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required int points,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
  }) async {
    if (points <= 0) return LoyaltyResult(LoyaltyTxnStatus.applied);
    final data = await _call(
      'refundLoyaltyPoints',
      {'storeCode': storeCode, 'customerId': customerId, 'billId': billId, 'points': points},
      timeout: timeout != null && timeout > _defaultTimeout ? timeout : _defaultTimeout,
    );
    return LoyaltyResult.fromMap(data);
  }

  /// Tích điểm sau khi hóa đơn đã ghi (PAID). Số điểm do MÁY CHỦ tính từ finalAmount của hóa đơn và cấu hình chuỗi.
  /// Hóa đơn chưa đồng bộ lên máy chủ (failed-precondition) → thử lại vài lần.
  Future<LoyaltyResult> awardForBill({
    required String storeCode,
    required String customerId,
    required String billId,
    String? billCode,
    required String by,
    Duration? timeout,
    void Function(String msg)? onLate,
    int attempts = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    await _ensureCustomerNode(storeCode, customerId);
    Object? last;
    for (var i = 0; i < attempts; i++) {
      try {
        final data = await _call(
          'applyLoyaltyEarn',
          {'storeCode': storeCode, 'billId': billId},
          timeout: timeout != null && timeout > _defaultTimeout ? timeout : _defaultTimeout,
        );
        return LoyaltyResult.fromMap(data);
      } on LoyaltyException catch (e) {
        last = e;
        if (i < attempts - 1) await Future<void>.delayed(retryDelay);
      }
    }
    throw last as LoyaltyException;
  }

  /// Số dư dùng chung của khách (theo khách của chi nhánh hoặc SĐT). Lỗi mạng/quyền → [SharedMember.none].
  Future<SharedMember> lookupMember({
    required String storeCode,
    String? customerId,
    String? phone,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final data = await _call(
        'lookupMember',
        {'storeCode': storeCode, if (customerId != null && customerId.isNotEmpty) 'customerId': customerId, if (phone != null && phone.isNotEmpty) 'phone': phone},
        timeout: timeout,
      );
      return SharedMember.fromMap(data);
    } catch (_) {
      return SharedMember.none;
    }
  }
}

/// Hàng đợi thử lại tích điểm (giống stock_retry_queue): tích điểm lỗi KHÔNG được im lặng.
/// Lưu cục bộ (SharedPreferences) theo hóa đơn; applyLoyaltyEarn idempotent theo hóa đơn nên thử lại an toàn.
class LoyaltyEarnQueue {
  static const String _key = 'loyalty_earn_retry_queue';

  /// Thông báo cho thu ngân (màn hình giỏ hàng lắng nghe và hiện SnackBar)
  static final StreamController<String> failures = StreamController<String>.broadcast();

  static Future<List<Map<String, dynamic>>> _read() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<Map<String, dynamic>> v) async {
    try {
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(v));
    } catch (_) {}
  }

  static Future<int> pending() async => (await _read()).length;

  /// Ghi nhận 1 hóa đơn chưa cộng được điểm và báo cho thu ngân.
  static Future<void> add({required String storeCode, required String billId, required String customerId, String? billCode, required Object error}) async {
    final q = await _read();
    q.removeWhere((e) => e['storeCode'] == storeCode && e['billId'] == billId);
    q.add({'storeCode': storeCode, 'billId': billId, 'customerId': customerId, 'billCode': billCode ?? '', 'error': error.toString(), 'at': DateTime.now().millisecondsSinceEpoch});
    await _write(q);
    failures.add('Chưa cộng được điểm cho HĐ ${billCode ?? billId}, sẽ thử lại');
  }

  /// Thử lại toàn bộ; trả về số mục còn lại.
  static Future<int> retryAll(LoyaltyService service, {String? onlyStoreCode}) async {
    final q = await _read();
    final left = <Map<String, dynamic>>[];
    for (final e in q) {
      if (onlyStoreCode != null && e['storeCode'] != onlyStoreCode) {
        left.add(e);
        continue;
      }
      try {
        await service.awardForBill(
          storeCode: e['storeCode'].toString(),
          customerId: e['customerId'].toString(),
          billId: e['billId'].toString(),
          billCode: e['billCode']?.toString(),
          by: 'retry',
          attempts: 1,
        );
      } catch (err) {
        e['error'] = err.toString();
        left.add(e);
      }
    }
    await _write(left);
    return left.length;
  }
}
