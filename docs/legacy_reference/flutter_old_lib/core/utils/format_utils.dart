// lib/core/utils/format_utils.dart
import 'package:intl/intl.dart';

class FormatUtils {
  static final _vnd = NumberFormat('#,###', 'vi_VN');
  static final _dayFmt = DateFormat('dd/MM/yyyy', 'vi_VN');
  static final _timeFmt = DateFormat('HH:mm', 'vi_VN');
  static final _fullFmt = DateFormat('HH:mm dd/MM/yyyy', 'vi_VN');
  static final _orderCodeFmt = DateFormat('yyMMddHHmmss');

  static String currency(int amount) => '${_vnd.format(amount)}đ';
  static String currencyShort(int amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}tr';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(0)}k';
    return '${amount}đ';
  }
  
  static String dateTime(int timestamp) => _fullFmt.format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  static String date(int timestamp) => _dayFmt.format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  static String time(int timestamp) => _timeFmt.format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  
  static String orderCode() {
    final now = DateTime.now();
    final rand = (100 + (now.millisecond % 900));
    return 'HD${_orderCodeFmt.format(now)}$rand';
  }

  static String waitTime(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}p';
    if (d.inMinutes > 0) return '${d.inMinutes}p ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  static String roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'MANAGER': return 'Quản lý';
      case 'STAFF': return 'Nhân viên';
      case 'KITCHEN': return 'Đầu bếp';
      default: return role;
    }
  }
}

// lib/core/utils/viet_qr.dart
class VietQRUtils {
  static String buildQRUrl({
    required String bankId,
    required String bankAccount,
    required String accountName,
    required int amount,
    required String description,
  }) {
    final encodedName = Uri.encodeComponent(accountName);
    final encodedDesc = Uri.encodeComponent(description);
    return 'https://img.vietqr.io/image/$bankId-$bankAccount-compact2.png'
        '?amount=$amount&addInfo=$encodedDesc&accountName=$encodedName';
  }
}
