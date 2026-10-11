// lib/core/permissions/staff_password_policy.dart
import 'app_permissions.dart';

/// Chính sách mật khẩu nhân viên + ai được đặt lại mật khẩu cho ai.
/// PHẢI khớp functions/src/permissions.ts (canCallerResetPassword) và web/lib/staff-password.ts.
const int kMinStaffPasswordLength = 6;
const int kMaxStaffPasswordLength = 128;

/// Trả về thông báo lỗi tiếng Việt, hoặc null nếu mật khẩu hợp lệ theo máy chủ.
String? validateStaffPassword(String password) {
  if (password.isEmpty) return 'Vui lòng nhập mật khẩu mới.';
  if (password.length < kMinStaffPasswordLength) {
    return 'Mật khẩu mới phải có tối thiểu $kMinStaffPasswordLength ký tự.';
  }
  if (password.length > kMaxStaffPasswordLength) {
    return 'Mật khẩu tối đa $kMaxStaffPasswordLength ký tự.';
  }
  return null;
}

/// - Chính mình: được. Chủ quán gốc: chỉ chính chủ.
/// - Chủ quán: mọi tài khoản khác. Quản lý: chỉ Nhân viên / Bếp (không Chủ quán, không Quản lý khác).
/// - Tài khoản đăng nhập bằng Chấm Công không có mật khẩu POS để đặt lại.
bool canResetStaffPassword({
  required String callerRoleId,
  required bool callerIsRootOwner,
  required String targetRoleId,
  required bool targetIsRootOwner,
  required bool targetIsChamCong,
  required bool isSelf,
}) {
  if (targetIsChamCong) return false;
  if (isSelf) return true;
  if (targetIsRootOwner) return false;
  final caller = normalizeRoleId(callerRoleId);
  final target = normalizeRoleId(targetRoleId);
  if (callerIsRootOwner || caller == kRoleOwner) return true;
  if (caller == kRoleManager) {
    return target != kRoleOwner && target != kRoleManager;
  }
  return false;
}

/// Thông báo cho lỗi Cloud Functions: giữ nguyên thông báo tiếng Việt của máy chủ (HttpsError),
/// thay các lỗi hạ tầng chung chung ("internal", "unavailable"...) bằng câu dễ hiểu.
String callableErrorMessage(String? code, String? message, {String fallback = 'Không thực hiện được thao tác. Vui lòng thử lại.'}) {
  final c = (code ?? '').replaceFirst('functions/', '');
  final m = (message ?? '').trim();
  switch (c) {
    case 'unauthenticated':
      return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    case 'unavailable':
    case 'deadline-exceeded':
      return 'Không kết nối được máy chủ. Vui lòng kiểm tra mạng và thử lại.';
    case 'internal':
    case 'unknown':
    case '':
      final generic = m.isEmpty || RegExp(r'^(internal|unknown)$', caseSensitive: false).hasMatch(m);
      return generic ? fallback : m;
    default:
      return m.isEmpty ? fallback : m;
  }
}
