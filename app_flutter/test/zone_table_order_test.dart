import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/table_model.dart';
import 'package:tram_flutter/data/models/zone_model.dart';

List<String> _sorted(List<TableModel> tables, List<ZoneModel> zones) => sortTablesByZoneOrder<TableModel>(
      tables,
      zones,
      zoneOf: (t) => t.zone,
      baseNameOf: (t) => t.baseName,
    ).map((t) => '${t.zone}/${t.name}').toList();

TableModel _t(String zone, String name) => TableModel(name: name, zone: zone);

void main() {
  group('sortTablesByZoneOrder', () {
    test('không có thứ tự → giữ nguyên', () {
      final ts = [_t('A', 'B2'), _t('A', 'B1')];
      expect(_sorted(ts, [ZoneModel(name: 'A')]), ['A/B2', 'A/B1']);
    });

    test('xếp theo tableOrder trong khu, bàn mới xếp sau', () {
      final ts = [_t('A', 'B1'), _t('A', 'B2'), _t('A', 'B3'), _t('A', 'B4')];
      final z = [ZoneModel(name: 'A', tableOrder: ['B3', 'B1'])];
      expect(_sorted(ts, z), ['A/B3', 'A/B1', 'A/B2', 'A/B4']);
    });

    test('không đổi thứ tự giữa các khu', () {
      final ts = [_t('A', 'B1'), _t('B', 'C1'), _t('A', 'B2'), _t('B', 'C2')];
      final z = [ZoneModel(name: 'B', tableOrder: ['C2', 'C1'])];
      expect(_sorted(ts, z), ['A/B1', 'A/B2', 'B/C2', 'B/C1']);
    });

    test('bàn tách đi theo bàn gốc', () {
      final ts = [_t('A', 'B1'), _t('A', 'B2'), _t('A', 'B2 (2)')];
      final z = [ZoneModel(name: 'A', tableOrder: ['B2', 'B1'])];
      expect(_sorted(ts, z), ['A/B2', 'A/B2 (2)', 'A/B1']);
    });

    test('ZoneModel đọc/ghi tableOrder (list hoặc map)', () {
      expect(ZoneModel.fromMap({'name': 'A', 'tableOrder': ['x', 'y']}).tableOrder, ['x', 'y']);
      expect(ZoneModel.fromMap({'name': 'A', 'tableOrder': {'0': 'x', '1': 'y'}}).tableOrder, ['x', 'y']);
      expect(ZoneModel(name: 'A', tableOrder: ['x']).toMap()['tableOrder'], ['x']);
      expect(ZoneModel(name: 'A').toMap().containsKey('tableOrder'), false);
    });
  });
}
