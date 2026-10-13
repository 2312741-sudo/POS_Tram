import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/zone_model.dart';

void main() {
  test('ghim trước, rồi theo thứ tự, rồi theo tên; khu chưa khai báo xếp cuối', () {
    final zones = [
      ZoneModel(name: 'Sân', order: 0),
      ZoneModel(name: 'Tầng 1', order: 1),
      ZoneModel(name: 'Tầng 2', pinned: true, order: 5),
      ZoneModel(name: 'VIP'),
    ];
    expect(sortZoneNames(['VIP', 'Tầng 1', 'Mới', 'Sân', 'Tầng 2'], zones),
        ['Tầng 2', 'Sân', 'Tầng 1', 'VIP', 'Mới']);
  });

  test('ZoneModel giữ pinned/order khi ghi lại', () {
    final z = ZoneModel.fromMap({'name': 'A', 'pinned': true, 'order': 3});
    expect(z.toMap(), {'name': 'A', 'pinned': true, 'order': 3});
    expect(ZoneModel.fromMap({'name': 'B'}).toMap(), {'name': 'B'});
  });
}
