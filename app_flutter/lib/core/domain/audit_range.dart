// Khoảng ngày cho Nhật ký thao tác (màn Giám sát). Mặc định chỉ có 150 thao tác MỚI NHẤT (luồng thời gian thực);
// chọn khoảng ngày thì tải ĐỦ mọi thao tác trong khoảng (truy vấn audit_logs theo timestamp — đã có chỉ mục).
// Ngày theo giờ Việt Nam (UTC+7), không phụ thuộc múi giờ máy. Khớp web/lib/audit-range.ts.

enum AuditRangePreset { recent, today, yesterday, last7Days, thisMonth, lastMonth }

extension AuditRangePresetLabel on AuditRangePreset {
  String get label => switch (this) {
        AuditRangePreset.recent => '150 thao tác gần nhất',
        AuditRangePreset.today => 'Hôm nay',
        AuditRangePreset.yesterday => 'Hôm qua',
        AuditRangePreset.last7Days => '7 ngày qua',
        AuditRangePreset.thisMonth => 'Tháng này',
        AuditRangePreset.lastMonth => 'Tháng trước',
      };
}

class AuditRange {
  static const int _vn = 7 * 3600000;
  static const int _day = 86400000;

  static int _vnDayStart(int ms) => ((ms + _vn) ~/ _day) * _day - _vn;
  static int _monthStart(int y, int m) => DateTime.utc(y, m, 1).millisecondsSinceEpoch - _vn;

  /// (from, to) tính bằng ms, gồm cả hai đầu; null = chế độ 150 thao tác gần nhất
  static ({int from, int to})? of(AuditRangePreset p, int nowMs) {
    final today = _vnDayStart(nowMs);
    final vnNow = DateTime.fromMillisecondsSinceEpoch(nowMs + _vn, isUtc: true);
    switch (p) {
      case AuditRangePreset.recent:
        return null;
      case AuditRangePreset.today:
        return (from: today, to: today + _day - 1);
      case AuditRangePreset.yesterday:
        return (from: today - _day, to: today - 1);
      case AuditRangePreset.last7Days:
        return (from: today - 6 * _day, to: today + _day - 1);
      case AuditRangePreset.thisMonth:
        return (from: _monthStart(vnNow.year, vnNow.month), to: today + _day - 1);
      case AuditRangePreset.lastMonth:
        final y = vnNow.month == 1 ? vnNow.year - 1 : vnNow.year;
        final m = vnNow.month == 1 ? 12 : vnNow.month - 1;
        return (from: _monthStart(y, m), to: _monthStart(vnNow.year, vnNow.month) - 1);
    }
  }
}
