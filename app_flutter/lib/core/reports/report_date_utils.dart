// Pure Dart date utilities for reports (UTC+7 / Asia/Ho_Chi_Minh)
// Không import Flutter framework

class ReportDateUtils {
  static const Duration utc7Offset = Duration(hours: 7);

  /// Chuyển timestamp (ms) sang DateTime ở múi giờ UTC+7
  static DateTime toUtc7(int timestampMs) {
    return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).add(utc7Offset);
  }

  /// Lấy mốc thời gian của hóa đơn theo thứ tự ưu tiên:
  /// 1. closedAt (cho PAID / REFUNDED)
  /// 2. createdAt
  static DateTime getBillDateTime(int? closedAt, int createdAt, [String? status]) {
    final ms = (closedAt != null && closedAt > 0) ? closedAt : createdAt;
    return toUtc7(ms);
  }

  /// Bắt đầu của ngày (00:00:00.000) ở UTC+7
  static DateTime startOfDay(DateTime dt) {
    return DateTime.utc(dt.year, dt.month, dt.day, 0, 0, 0, 0);
  }

  /// Kết thúc của ngày (23:59:59.999) ở UTC+7
  static DateTime endOfDay(DateTime dt) {
    return DateTime.utc(dt.year, dt.month, dt.day, 23, 59, 59, 999);
  }

  /// Kiểm tra xem thời điểm có nằm trong khoảng [startDate, endDate] (theo UTC+7) không
  static bool isInRange(DateTime dt, DateTime startDate, DateTime endDate) {
    final start = DateTime.utc(startDate.year, startDate.month, startDate.day, 0, 0, 0, 0);
    final end = DateTime.utc(endDate.year, endDate.month, endDate.day, 23, 59, 59, 999);
    final currentUtc = DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.millisecond);
    return !currentUtc.isBefore(start) && !currentUtc.isAfter(end);
  }

  /// Định dạng YYYY-MM-DD
  static String formatYmd(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Định dạng YYYYMMDD cho tên file
  static String formatFileDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Định dạng HHmmss cho tên file
  static String formatFileTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h$m$s';
  }

  /// Định dạng dd/MM/yyyy
  static String formatDisplayDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }

  /// Định dạng dd/MM/yyyy HH:mm
  static String formatDisplayDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }
}
