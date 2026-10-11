import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/services/pooled_loyalty_service.dart';

void main() {
  group('LoyaltyTier (mốc hạng do Chủ quán đặt)', () {
    test('chưa cấu hình: chỉ có hạng gốc', () {
      expect(LoyaltyTier.parseList(null), LoyaltyTier.defaults);
      expect(LoyaltyTier.nameFor(99999, LoyaltyTier.defaults), 'Thành viên');
    });

    test('đọc mảng/map, sắp xếp, ép hạng thấp nhất về 0 điểm', () {
      final tiers = LoyaltyTier.parseList({
        'a': {'name': 'Vàng', 'minPoints': 500},
        'b': {'name': 'Bạc', 'minPoints': 100},
        'bad': 'x',
      });
      expect(tiers.map((t) => '${t.name}:${t.minPoints}').toList(), ['Bạc:0', 'Vàng:500']);
    });

    test('xếp hạng theo tổng điểm tích lũy', () {
      final tiers = [const LoyaltyTier('Thành viên', 0), const LoyaltyTier('Bạc', 200), const LoyaltyTier('Vàng', 500)];
      expect(LoyaltyTier.nameFor(199, tiers), 'Thành viên');
      expect(LoyaltyTier.nameFor(200, tiers), 'Bạc');
      expect(LoyaltyTier.nameFor(900, tiers), 'Vàng');
      final c = KmtCustomerModel(id: 'c', phone: '0900000000', currentPoints: 10, totalPoints: 600);
      expect(c.tierName(tiers), 'Vàng'); // đổi điểm không làm tụt hạng
    });
  });

  group('PooledLoyaltyService.shortfall', () {
    test('chỉ kéo phần thiếu', () {
      expect(PooledLoyaltyService.shortfall(needed: 50, local: 80), 0);
      expect(PooledLoyaltyService.shortfall(needed: 50, local: 20), 30);
    });
  });
}
