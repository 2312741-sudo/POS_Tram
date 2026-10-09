// lib/core/services/manager_pin_service.dart
//
// "Quản lý duyệt bằng PIN" phía POS Flutter.
//
// PIN KHÔNG BAO GIỜ được đọc/lưu ở client: app gọi callable verifyManagerPin
// (functions/src/managerPin.ts). Máy chủ so PIN (băm scrypt, lưu ở
// manager_pins/{storeCode}/{uid} — ngoài stores/{storeCode}), giới hạn số lần thử
// (khóa tạm 15 phút sau 5 lần sai), tự ghi audit log MANAGER_PIN_APPROVED và
// trả về một lần duyệt có hiệu lực 5 phút.
// Quản lý / Chủ quán đặt, đổi hoặc xóa PIN duyệt của CHÍNH MÌNH qua callable setManagerPin.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Hành động hỗ trợ duyệt bằng PIN (khớp APPROVABLE_ACTIONS trong managerPinLogic.ts)
class ManagerApprovalAction {
  static const String discountItem = 'DISCOUNT_ITEM';
  static const String cancelKitchenItem = 'CANCEL_KITCHEN_ITEM';

  static const Map<String, String> labels = {
    discountItem: 'Giảm giá món',
    cancelKitchenItem: 'Hủy/giảm món đã gửi bếp',
  };

  static String label(String action) => labels[action] ?? action;
}

/// Một lần duyệt do máy chủ cấp
class ManagerApproval {
  final String approvalId;
  final String approverUid;
  final String approverName;
  final String? approverUsername;
  final String action;
  final int approvedAt;
  final int expiresAt;

  const ManagerApproval({
    required this.approvalId,
    required this.approverUid,
    required this.approverName,
    this.approverUsername,
    required this.action,
    required this.approvedAt,
    required this.expiresAt,
  });

  /// Kiểm tra dữ liệu callable trả về có đúng hình dạng; sai → null
  static ManagerApproval? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final approvalId = raw['approvalId'];
    final approverUid = raw['approverUid'];
    final action = raw['action'];
    if (approvalId is! String || approvalId.isEmpty) return null;
    if (approverUid is! String || approverUid.isEmpty) return null;
    if (action is! String || !ManagerApprovalAction.labels.containsKey(action)) return null;
    final approvedAt = raw['approvedAt'];
    final expiresAt = raw['expiresAt'];
    if (approvedAt is! num || expiresAt is! num) return null;
    final name = raw['approverName'];
    final username = raw['approverUsername'];
    return ManagerApproval(
      approvalId: approvalId,
      approverUid: approverUid,
      approverName: name is String && name.isNotEmpty ? name : 'Quản lý',
      approverUsername: username is String ? username : null,
      action: action,
      approvedAt: approvedAt.toInt(),
      expiresAt: expiresAt.toInt(),
    );
  }

  /// Còn hiệu lực cho đúng hành động
  bool isValidFor(String forAction, {int? now}) =>
      action == forAction && expiresAt > (now ?? DateTime.now().millisecondsSinceEpoch);
}

/// Lỗi duyệt/đặt PIN đã chuyển sang thông báo tiếng Việt
class ManagerPinException implements Exception {
  final String message;

  /// Mã lỗi gốc của callable (VD: permission-denied)
  final String code;

  /// Lý do bổ sung từ máy chủ (LOCKED_OUT, AMBIGUOUS, ...)
  final String? reason;

  /// Số giây còn bị khóa (khi reason = LOCKED_OUT)
  final int? lockoutSeconds;

  const ManagerPinException(this.message, {this.code = 'unknown', this.reason, this.lockoutSeconds});

  bool get isLockedOut => reason == 'LOCKED_OUT';
  bool get needsApproverSelection => reason == 'AMBIGUOUS';

  @override
  String toString() => message;
}

/// Logic thuần (không gọi Firebase) — unit test được
class ManagerPinLogic {
  ManagerPinLogic._();

  static final RegExp _pinPattern = RegExp(r'^\d{4,8}$');
  static final RegExp _repeatedDigits = RegExp(r'^(\d)\1+$');

  /// Khớp validatePinFormat phía máy chủ: 4–8 chữ số, không phải dãy một chữ số lặp lại
  static String? validatePinFormat(String pin) {
    if (!_pinPattern.hasMatch(pin)) return 'PIN phải gồm 4–8 chữ số.';
    if (_repeatedDigits.hasMatch(pin)) return 'PIN không được là dãy một chữ số lặp lại.';
    return null;
  }

  /// Chuyển lỗi callable sang ManagerPinException với thông báo tiếng Việt
  static ManagerPinException mapError(String code, String? message, Object? details, {bool settingPin = false}) {
    final c = code.replaceFirst(RegExp(r'^functions/'), '');
    final reason = details is Map ? details['reason']?.toString() : null;
    final secondsRaw = details is Map ? details['remainingSeconds'] : null;
    final seconds = secondsRaw is num ? secondsRaw.toInt() : null;
    final msg = (message ?? '').trim();

    switch (c) {
      case 'resource-exhausted':
        final minutes = seconds != null && seconds > 0 ? (seconds / 60).ceil() : 15;
        return ManagerPinException(
          'Nhập sai PIN quá nhiều lần. Chức năng duyệt bằng PIN bị khóa tạm $minutes phút.',
          code: c,
          reason: reason ?? 'LOCKED_OUT',
          lockoutSeconds: seconds,
        );
      case 'failed-precondition':
        if (reason == 'AMBIGUOUS') {
          return ManagerPinException('Vui lòng chọn người duyệt rồi nhập lại PIN.', code: c, reason: reason);
        }
        return ManagerPinException(msg.isNotEmpty ? msg : 'Không thể thực hiện thao tác này.', code: c, reason: reason);
      case 'permission-denied':
        if (settingPin) {
          return ManagerPinException(
            msg.isNotEmpty ? msg : 'Chỉ Chủ quán hoặc Quản lý mới được đặt PIN duyệt.',
            code: c,
            reason: reason,
          );
        }
        return ManagerPinException(
          msg.isNotEmpty ? msg : 'PIN không đúng hoặc người duyệt không có quyền cho thao tác này.',
          code: c,
          reason: reason,
        );
      case 'invalid-argument':
        return ManagerPinException(msg.isNotEmpty ? msg : 'PIN không hợp lệ.', code: c, reason: reason);
      case 'unauthenticated':
        return ManagerPinException('Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.', code: c);
      case 'not-found':
      case 'unimplemented':
        return ManagerPinException('Máy chủ chưa triển khai chức năng duyệt bằng PIN.', code: c);
      case 'unavailable':
      case 'deadline-exceeded':
      case 'network-request-failed':
        return ManagerPinException('Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.', code: c);
      default:
        return ManagerPinException(
          msg.isNotEmpty ? msg : (settingPin ? 'Không lưu được PIN duyệt.' : 'Không xác minh được PIN.'),
          code: c,
        );
    }
  }

  /// Hậu tố mô tả trong nhật ký, VD " — QL Lan duyệt bằng PIN"
  static String approvalSuffix(ManagerApproval? a) => a == null ? '' : ' — ${a.approverName} duyệt bằng PIN';
}

/// Gọi các callable verifyManagerPin / setManagerPin (region asia-southeast1)
class ManagerPinService {
  static final ManagerPinService _instance = ManagerPinService._internal();
  factory ManagerPinService() => _instance;
  ManagerPinService._internal();

  static const String _functionsRegion = 'asia-southeast1';
  FirebaseFunctions? _functionsMock;
  FirebaseFunctions get _functions => _functionsMock ?? FirebaseFunctions.instanceFor(region: _functionsRegion);

  @visibleForTesting
  void setFunctionsMock(FirebaseFunctions? mock) {
    _functionsMock = mock;
  }

  static const _timeout = Duration(seconds: 20);

  /// Xác minh PIN quản lý cho [action]. Ném [ManagerPinException] khi thất bại.
  Future<ManagerApproval> verify({
    required String storeCode,
    required String pin,
    required String action,
    String? approverUid,
    String? context,
  }) async {
    try {
      final callable = _functions.httpsCallable('verifyManagerPin', options: HttpsCallableOptions(timeout: _timeout));
      final result = await callable.call<dynamic>({
        'storeCode': storeCode,
        'pin': pin.trim(),
        'action': action,
        if (approverUid != null && approverUid.isNotEmpty) 'approverUid': approverUid,
        if (context != null && context.isNotEmpty) 'context': context,
      });
      final approval = ManagerApproval.tryParse(result.data);
      if (approval == null || approval.action != action) {
        throw const ManagerPinException('Máy chủ trả về kết quả duyệt không hợp lệ.', code: 'invalid-response');
      }
      return approval;
    } on FirebaseFunctionsException catch (e) {
      throw ManagerPinLogic.mapError(e.code, e.message, e.details);
    } on ManagerPinException {
      rethrow;
    } catch (_) {
      throw const ManagerPinException('Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.', code: 'unavailable');
    }
  }

  /// Đặt/đổi PIN duyệt của chính mình; [pin] = null để xóa PIN. Trả về true nếu còn PIN.
  Future<bool> setOwnPin({required String storeCode, required String? pin}) async {
    if (pin != null) {
      final err = ManagerPinLogic.validatePinFormat(pin.trim());
      if (err != null) throw ManagerPinException(err, code: 'invalid-argument');
    }
    try {
      final callable = _functions.httpsCallable('setManagerPin', options: HttpsCallableOptions(timeout: _timeout));
      final result = await callable.call<dynamic>({
        'storeCode': storeCode,
        'pin': pin?.trim(),
      });
      final data = result.data;
      if (data is Map && data['hasPin'] is bool) return data['hasPin'] as bool;
      return pin != null;
    } on FirebaseFunctionsException catch (e) {
      throw ManagerPinLogic.mapError(e.code, e.message, e.details, settingPin: true);
    } on ManagerPinException {
      rethrow;
    } catch (_) {
      throw const ManagerPinException('Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.', code: 'unavailable');
    }
  }
}
