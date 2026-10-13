import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/zone_plan.dart';

ZoneTableRecord t(String zone, String name, {Map<String, dynamic> extra = const {}}) => ZoneTableRecord(
      '${zone}_$name',
      {'name': name, 'zone': zone, 'inUse': false, 'currentOrderJson': '', 'capacity': 4, ...extra},
    );

void main() {
  group('kiểm tra đầu vào', () {
    test('tên khu', () {
      expect(validateZoneName('', []), contains('nhập'));
      expect(validateZoneName('Tầng 1/2', []), contains('ký tự'));
      expect(validateZoneName('khu a', ['Khu A']), contains('đã tồn tại'));
      expect(validateZoneName('x' * 41, []), contains('40'));
      expect(validateZoneName('Sân vườn', ['Khu A']), isNull);
    });

    test('tiền tố và số bàn', () {
      expect(validateTablePrefix('Bàn'), isNull);
      expect(validateTablePrefix('Bàn/1'), contains('ký tự'));
      expect(validateTablePrefix('T.2'), contains('ký tự'));
      expect(validateTablePrefix('x' * 21), contains('20'));
      expect(validateTableCount(0), isNull);
      expect(validateTableCount(101), contains('100'));
      expect(validateTableCount(0, min: 1), contains('1 đến'));
    });

    test('bàn đang dùng: inUse hoặc còn giỏ món', () {
      expect(isTableInUse({'inUse': true}), isTrue);
      expect(isTableInUse({'inUse': false, 'currentOrderJson': '[{}]'}), isTrue);
      expect(isTableInUse({'inUse': false, 'currentOrderJson': ''}), isFalse);
    });
  });

  test('đặt tên bàn tuần tự và tránh trùng', () {
    expect(nextTableNames('Bàn', 3, []), ['Bàn 01', 'Bàn 02', 'Bàn 03']);
    expect(nextTableNames('Bàn', 2, ['Bàn 01', 'bàn 02']), ['Bàn 03', 'Bàn 04']);
  });

  group('tạo khu', () {
    test('tạo khu kèm bàn, khóa khu_tên, hình dạng giống web', () {
      final p = planZoneCreate(zoneName: ' Tầng 2 ', prefix: 'Bàn', count: 2, declaredZones: [], tables: []);
      expect(p.isOk, isTrue);
      expect(p.affected, 2);
      expect(p.updates['zones/Tầng 2'], {'name': 'Tầng 2'});
      expect(p.updates['tables/Tầng 2_Bàn 01'], {'name': 'Bàn 01', 'zone': 'Tầng 2', 'inUse': false, 'currentOrderJson': ''});
    });

    test('từ chối khu trùng và tiền tố sai; count 0 chỉ tạo khu', () {
      expect(planZoneCreate(zoneName: 'khu a', prefix: 'Bàn', count: 1, declaredZones: ['Khu A'], tables: []).isOk, isFalse);
      expect(planZoneCreate(zoneName: 'Khu B', prefix: 'B/', count: 1, declaredZones: [], tables: []).isOk, isFalse);
      final p = planZoneCreate(zoneName: 'Sân', prefix: 'Bàn', count: 0, declaredZones: [], tables: []);
      expect(p.updates.keys.toList(), ['zones/Sân']);
    });
  });

  group('thêm bàn vào khu', () {
    test('tiếp nối số thứ tự, bỏ qua tên đã có trong khu', () {
      final tables = [t('A', 'Bàn 01'), t('A', 'Bàn 02'), t('B', 'Bàn 03')];
      final p = planAddTables(zoneName: 'A', prefix: 'Bàn', count: 2, declaredZones: ['A', 'B'], tables: tables);
      expect(p.isOk, isTrue);
      expect(p.updates.containsKey('tables/A_Bàn 03'), isTrue);
      expect(p.updates.containsKey('tables/A_Bàn 04'), isTrue);
      expect(p.updates['tables/A_Bàn 03'], {'name': 'Bàn 03', 'zone': 'A', 'inUse': false, 'currentOrderJson': ''});
    });

    test('từ chối khu không tồn tại và số bàn < 1', () {
      expect(planAddTables(zoneName: 'Ma', prefix: 'Bàn', count: 1, declaredZones: [], tables: []).isOk, isFalse);
      expect(planAddTables(zoneName: 'A', prefix: 'Bàn', count: 0, declaredZones: ['A'], tables: []).isOk, isFalse);
    });
  });

  group('đổi tên khu', () {
    test('chuyển khu node và mọi bàn trong MỘT bản kế hoạch, giữ trường khác', () {
      final tables = [t('Khu A', 'Bàn 01', extra: {'capacity': 6}), t('Khu A', 'Bàn 02'), t('Khu B', 'Bàn 01')];
      final p = planZoneRename(oldName: 'Khu A', newName: 'Tầng 1', declaredZones: ['Khu A', 'Khu B'], tables: tables);
      expect(p.isOk, isTrue);
      expect(p.affected, 2);
      expect(p.updates['zones/Khu A'], isNull);
      expect(p.updates['zones/Tầng 1'], {'name': 'Tầng 1'});
      expect(p.updates.containsKey('tables/Khu A_Bàn 01'), isTrue);
      expect(p.updates['tables/Khu A_Bàn 01'], isNull);
      expect(p.updates['tables/Tầng 1_Bàn 01'],
          {'name': 'Bàn 01', 'zone': 'Tầng 1', 'inUse': false, 'currentOrderJson': '', 'capacity': 6});
      expect(p.updates.containsKey('tables/Khu B_Bàn 01'), isFalse);
    });

    test('từ chối khi có bàn đang dùng hoặc còn giỏ món', () {
      expect(planZoneRename(oldName: 'A', newName: 'B', declaredZones: ['A'], tables: [t('A', 'Bàn 01', extra: {'inUse': true})]).isOk, isFalse);
      expect(
          planZoneRename(oldName: 'A', newName: 'B', declaredZones: ['A'], tables: [t('A', 'Bàn 01', extra: {'currentOrderJson': '[{"x":1}]'})]).isOk,
          isFalse);
    });

    test('từ chối tên trùng khu khác (không phân biệt hoa thường) và tên không đổi', () {
      expect(planZoneRename(oldName: 'A', newName: 'b', declaredZones: ['A', 'B'], tables: []).isOk, isFalse);
      expect(planZoneRename(oldName: 'A', newName: ' A ', declaredZones: ['A'], tables: []).isOk, isFalse);
    });

    test('từ chối khi khóa bàn đích đã bị bàn khác chiếm', () {
      final tables = [t('A', 'Bàn 01'), t('B', 'Bàn 01')];
      expect(planZoneRename(oldName: 'A', newName: 'B', declaredZones: ['A'], tables: tables).isOk, isFalse);
    });

    test('đổi hoa/thường tên khu vẫn hợp lệ (khóa khác)', () {
      final p = planZoneRename(oldName: 'khu a', newName: 'Khu A', declaredZones: ['khu a'], tables: [t('khu a', 'Bàn 01')]);
      expect(p.isOk, isTrue);
      expect(p.updates['tables/khu a_Bàn 01'], isNull);
      expect(p.updates.containsKey('tables/Khu A_Bàn 01'), isTrue);
    });
  });

  group('xóa khu', () {
    test('chỉ xóa khu trống', () {
      expect(planZoneDelete(zoneName: 'A', tables: [t('A', 'Bàn 01')]).isOk, isFalse);
      final p = planZoneDelete(zoneName: 'A', tables: [t('B', 'Bàn 01')]);
      expect(p.isOk, isTrue);
      expect(p.updates, {'zones/A': null});
    });
  });

  test('nhật ký thao tác khớp rules audit_logs (timestamp, action, targetType)', () {
    final e = zoneAuditEntry(
      action: 'ZONE_RENAME',
      targetType: 'ZONE',
      targetId: 'A',
      details: 'x',
      actor: const ZoneAuditActor(username: 'boss'),
      storeCode: 'T1',
      now: 1000,
    );
    expect(e['timestamp'], 1000);
    expect(e['userFullName'], 'boss');
    expect(e['action'], 'ZONE_RENAME');
    expect(e['storeCode'], 'T1');
  });
}
