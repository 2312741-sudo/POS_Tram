import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/data/services/loyalty_service.dart';

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

  group('Điểm dùng chung - ánh xạ phản hồi callable', () {
    test('LoyaltyResult.fromMap đọc trạng thái và số liệu', () {
      final r = LoyaltyResult.fromMap({'status': 'applied', 'applied': 20, 'before': 50, 'after': 70, 'memberKey': '0912345678'});
      expect(r.applied, isTrue);
      expect([r.points, r.before, r.after, r.memberKey], [20, 50, 70, '0912345678']);
      expect(LoyaltyResult.fromMap({'status': 'alreadyApplied'}).status, LoyaltyTxnStatus.alreadyApplied);
      expect(LoyaltyResult.fromMap({'status': 'insufficient', 'before': 3}).status, LoyaltyTxnStatus.insufficient);
      expect(LoyaltyResult.fromMap({'status': 'nothingToRefund'}).status, LoyaltyTxnStatus.nothingToRefund);
    });

    test('SharedMember.fromMap và giá trị rỗng', () {
      final m = SharedMember.fromMap({'found': true, 'memberKey': '0912345678', 'name': 'An', 'points': 110, 'totalPoints': 600, 'branchCount': 2, 'local': false});
      expect(m.found, isTrue);
      expect([m.points, m.totalPoints, m.branchCount], [110, 600, 2]);
      expect(SharedMember.fromMap({}).found, isFalse);
      expect(SharedMember.none.points, 0);
    });

    test('mapError: không đủ điểm → InsufficientPointsException, lỗi khác → LoyaltyException', () {
      final insufficient = LoyaltyService.mapError(
        FirebaseFunctionsException(message: 'Khách chỉ còn 10 điểm', code: 'failed-precondition', details: {'code': 'insufficient', 'balance': 10, 'requested': 50}),
      );
      expect(insufficient, isA<InsufficientPointsException>());
      expect((insufficient as InsufficientPointsException).available, 10);
      expect(insufficient.requested, 50);
      final other = LoyaltyService.mapError(FirebaseFunctionsException(message: 'Không tìm thấy khách', code: 'not-found'));
      expect(other, isA<LoyaltyException>());
      expect(other.toString(), 'Không tìm thấy khách');
    });
  });

  group('StoreInfoModel.withChainLoyalty (cấu hình điểm toàn chuỗi)', () {
    test('chuỗi ghi đè từng trường; thiếu thì giữ cấu hình chi nhánh', () {
      final store = StoreInfoModel(storeCode: 'A', storeName: 'A', pointEarnRate: 2, pointRedeemRate: 500);
      final merged = store.withChainLoyalty({
        'pointEarnRate': 3,
        'loyaltyTiers': [
          {'name': 'Vàng', 'minPoints': 500}
        ],
      });
      expect(merged.pointEarnRate, 3);
      expect(merged.pointRedeemRate, 500);
      expect(merged.loyaltyTiers.map((t) => t.name), contains('Vàng'));
      expect(store.withChainLoyalty(null).pointEarnRate, 2);
    });
  });
}
