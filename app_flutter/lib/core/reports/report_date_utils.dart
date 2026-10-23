// Pure Dart date utilities for reports (UTC+7 / Asia/Ho_Chi_Minh)
// Không import Flutter framework
import '../../data/models/bill_model.dart';
import '../domain/business_day.dart';

class ReportDateUtils {
  static const Duration utc7Offset = Duration(hours: 7);

  /// Chuyển timestamp (ms) sang DateTime ở múi giờ UTC+7
  static DateTime toUtc7(int timestampMs) {
    return DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true).add(utc7Offset);
  }

  /// Lấy mốc thời gian của hóa đơn (docs/REPORT_SPEC.md §3.4):
  /// - CANCELLED: cancelledAt → closedAt → createdAt (đơn hủy thuộc NGÀY HỦY)
  /// - PAID / REFUNDED: closedAt → createdAt
  static DateTime getBillDateTime(int? closedAt, int createdAt, [String? status, int? cancelledAt]) {
    bool ok(int? v) => v != null && v > 0;
    int ms;
    if (status == 'CANCELLED') {
      ms = ok(cancelledAt) ? cancelledAt! : (ok(closedAt) ? closedAt! : createdAt);
    } else {
      ms = ok(closedAt) ? closedAt! : createdAt;
    }
    return toUtc7(ms);
  }

  /// Mốc xếp NGÀY KINH DOANH của một hóa đơn theo quy tắc §3.4: mốc thực lùi đi "giờ bắt đầu ngày"
  /// của cửa hàng (Cài đặt cửa hàng → Ngày kinh doanh; 0 = như cũ). Dùng để chia ngày/tháng.
  static DateTime billDateTime(BillModel b) => toUtc7(BusinessDay.shiftMs(b.reportTimeMs));

  /// Giờ thực của hóa đơn (UTC+7) — dùng cho biểu đồ theo khung giờ, KHÔNG lùi theo ngày kinh doanh.
  static DateTime billClockTime(BillModel b) => toUtc7(b.reportTimeMs);

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
