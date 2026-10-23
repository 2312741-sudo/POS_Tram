import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/business_day.dart';

int vn(int y, int mo, int d, int h, [int mi = 0]) => DateTime.utc(y, mo, d, h - 7, mi).millisecondsSinceEpoch;

void main() {
  group('BusinessDay', () {
    test('mốc 04:00: 01:30 sáng 23/10 vẫn là ngày 22/10; 04:00 trở đi là 23/10', () {
      expect(BusinessDay.dateOf(vn(2026, 10, 23, 1, 30), 240), '2026-10-22');
      expect(BusinessDay.dateOf(vn(2026, 10, 23, 3, 59), 240), '2026-10-22');
      expect(BusinessDay.dateOf(vn(2026, 10, 23, 4, 0), 240), '2026-10-23');
      expect(BusinessDay.dateOf(vn(2026, 10, 22, 23, 0), 240), '2026-10-22');
    });
    test('mặc định 00:00: 01:30 sáng thuộc ngày mới', () {
      expect(BusinessDay.dateOf(vn(2026, 10, 23, 1, 30), 0), '2026-10-23');
    });
    test('chuẩn hóa và định dạng', () {
      expect(BusinessDay.normalize('abc'), 0);
      expect(BusinessDay.normalize(-5), 0);
      expect(BusinessDay.normalize(99999), 720);
      expect(BusinessDay.normalize(240.7), 240);
      expect(BusinessDay.parseTime('04:30'), 270);
      expect(BusinessDay.parseTime('24:00'), isNull);
      expect(BusinessDay.parseTime(''), isNull);
      expect(BusinessDay.formatMinutes(270), '04:30');
    });
  });
}
