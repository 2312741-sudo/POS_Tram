import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/audit_range.dart';

int vn(int y, int m, int d) => DateTime.utc(y, m, d).millisecondsSinceEpoch - 7 * 3600000;

void main() {
  // 14/11/2026 01:16 giờ VN
  final now = DateTime.utc(2026, 11, 13, 18, 16).millisecondsSinceEpoch;
  test('khoảng ngày theo giờ Việt Nam (khớp web)', () {
    expect(AuditRange.of(AuditRangePreset.today, now), (from: vn(2026, 11, 14), to: vn(2026, 11, 15) - 1));
    expect(AuditRange.of(AuditRangePreset.yesterday, now), (from: vn(2026, 11, 13), to: vn(2026, 11, 14) - 1));
    expect(AuditRange.of(AuditRangePreset.thisMonth, now)!.from, vn(2026, 11, 1));
    expect(AuditRange.of(AuditRangePreset.lastMonth, now), (from: vn(2026, 10, 1), to: vn(2026, 11, 1) - 1));
    expect(AuditRange.of(AuditRangePreset.lastMonth, DateTime.utc(2026, 1, 10).millisecondsSinceEpoch)!.from, vn(2025, 12, 1));
    expect(AuditRange.of(AuditRangePreset.recent, now), isNull);
  });
}
