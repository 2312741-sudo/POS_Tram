// lib/core/domain/business_day.dart
//
// NGÀY KINH DOANH: cửa hàng hoạt động qua 0h có thể đặt "giờ bắt đầu ngày kinh doanh" (vd. 04:00).
// Hóa đơn chốt trước giờ này tính vào ngày kinh doanh TRƯỚC (01:30 sáng 23/10 → ngày 22/10).
// Cách làm: lùi mốc thời gian đi [startMinutes] phút rồi dùng lại logic "ngày" sẵn có.
// Cấu hình: stores/{store}/storeInfo/businessDayStartMinute (phút từ 0h, 0..720; 0 = như cũ).
// Bản TypeScript song song: web/lib/business-day.ts. Thuần Dart (không import Flutter).

class BusinessDay {
  BusinessDay._();

  static const int maxStartMinute = 12 * 60;

  /// Giờ bắt đầu ngày của cửa hàng đang dùng (phút từ 0h). Được nạp khi tải thông tin cửa hàng.
  static int startMinutes = 0;

  /// Chuẩn hóa về số nguyên phút trong [0, 720] (sai/thiếu → 0)
  static int normalize(Object? v) {
    final n = v is num ? v : num.tryParse(v?.toString() ?? '');
    if (n == null || n.isNaN || n.isInfinite) return 0;
    return n.truncate().clamp(0, maxStartMinute).toInt();
  }

  static int get offsetMs => startMinutes * 60000;

  /// Mốc thời gian để xếp NGÀY KINH DOANH (lùi [startMinutes] phút)
  static int shiftMs(int ts, [int? start]) => ts - (start ?? startMinutes) * 60000;

  /// "Bây giờ" theo ngày kinh doanh, ở dạng DateTime địa phương (dùng để so sánh với [shiftMs])
  static DateTime now() => DateTime.now().subtract(Duration(milliseconds: offsetMs));

  /// Ngày kinh doanh "YYYY-MM-DD" (giờ Việt Nam) của một thời điểm
  static String dateOf(int ts, int start) {
    final d = DateTime.fromMillisecondsSinceEpoch(shiftMs(ts, start), isUtc: true).add(const Duration(hours: 7));
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// "HH:mm" → số phút từ 0h; sai định dạng → null
  static int? parseTime(String text) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return h * 60 + mi;
  }

  static String formatMinutes(int minutes) {
    final v = normalize(minutes);
    return '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  }
}
