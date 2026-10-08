// lib/core/utils/format_utils.dart
import 'package:intl/intl.dart';
import '../domain/order_integrity.dart';

class FormatUtils {
  static final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  static String vnd(num amount) {
    return '${_currencyFormat.format(amount)} đ';
  }

  static String currency(num amount) {
    return vnd(amount);
  }

  static String vndWithoutUnit(num amount) {
    return _currencyFormat.format(amount);
  }

  static String number(num amount) {
    return _currencyFormat.format(amount);
  }

  static String dateTime(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  static String timeOnly(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('HH:mm').format(dt);
  }

  static String dateOnly(int timestamp) {
    if (timestamp <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  /// Mã hóa đơn TẠM (HD-yyMMdd-HHmmss-XXXX, có hậu tố ngẫu nhiên để 2 máy không trùng).
  /// Mã chính thức tuần tự HD-yyMMdd-NNNN được cấp khi thanh toán
  /// (OrderRepository.allocateBillCode).
  static String billCode([String prefix = 'HD']) {
    return BillCodeGenerator.fallback(at: DateTime.now(), prefix: prefix);
  }

  /// Mã đặt món / gọi món kiểm soát (OD-yyMMdd-HHmmss-XXXX)
  static String orderCode([String prefix = 'OD']) {
    return BillCodeGenerator.fallback(at: DateTime.now(), prefix: prefix);
  }

  static String roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'ROLE_OWNER':
      case 'OWNER':
        return 'Chủ Quán';
      case 'ROLE_MANAGER':
      case 'MANAGER':
        return 'Quản Lý';
      case 'ROLE_CASHIER':
      case 'CASHIER':
        return 'Thu Ngân';
      case 'ROLE_WAITER':
      case 'WAITER':
      case 'STAFF':
        return 'Nhân Viên Phục Vụ';
      case 'ROLE_KITCHEN':
      case 'KITCHEN':
        return 'Bếp / Bar';
      default:
        return role;
    }
  }

  static String waitTime(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
