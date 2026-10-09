import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';

void main() {
  group('IdempotencyRing', () {
    test('push bỏ trùng, giữ tối đa N phần tử mới nhất', () {
      var ring = IdempotencyRing.push(null, 'a');
      ring = IdempotencyRing.push(ring, 'b');
      ring = IdempotencyRing.push(ring, 'a');
      expect(ring, ['b', 'a']);
      var big = <String>[];
      for (var i = 0; i < 30; i++) {
        big = IdempotencyRing.push(big, 'k$i', max: 5);
      }
      expect(big, ['k25', 'k26', 'k27', 'k28', 'k29']);
    });

    test('đọc được mảng RTDB trả về dạng Map', () {
      expect(IdempotencyRing.read({'1': 'y', '0': 'x'}), ['x', 'y']);
      expect(IdempotencyRing.contains({'0': 'x'}, 'x'), isTrue);
      expect(IdempotencyRing.contains('rác', 'x'), isFalse);
    });
  });

  group('LoyaltyMath', () {
    Map<String, dynamic> customer({int points = 50, int total = 80}) =>
        {'id': 'KH1', 'diem_hien_tai': points, 'currentPoints': points, 'totalPoints': total};

    test('pointsToAward: tiền × rate% / đ-điểm, làm tròn; cấu hình sai → 0', () {
      expect(LoyaltyMath.pointsToAward(billAmount: 2000000, earnRatePercent: 1, redeemRate: 1000), 20);
      expect(LoyaltyMath.pointsToAward(billAmount: 149000, earnRatePercent: 1, redeemRate: 1000), 1);
      expect(LoyaltyMath.pointsToAward(billAmount: 10000, earnRatePercent: 0, redeemRate: 1000), 0);
      expect(LoyaltyMath.pointsToAward(billAmount: 10000, earnRatePercent: 1, redeemRate: 0), 0);
    });

    test('đổi điểm: trừ đúng, ghi lastRedeem + khóa thao tác; không đủ điểm → insufficient', () {
      final o = LoyaltyMath.apply(customer(), billId: 'B1', op: LoyaltyOp.redeem, points: 20, now: 1);
      expect(o.status, LoyaltyTxnStatus.applied);
      expect(o.before, 50);
      expect(o.after, 30);
      expect(o.next!['diem_hien_tai'], 30);
      expect(o.next!['currentPoints'], 30);
      expect(o.next!['totalPoints'], 80, reason: 'đổi điểm không giảm tổng điểm lịch sử');
      expect(o.next!['lastRedeem'], {'billId': 'B1', 'points': 20});
      expect(o.next!['lastLoyaltyOp'], 'B1:redeem');
      expect(o.next!['lastLoyaltyType'], 'redeem');

      final bad = LoyaltyMath.apply(customer(points: 10), billId: 'B2', op: LoyaltyOp.redeem, points: 20, now: 1);
      expect(bad.status, LoyaltyTxnStatus.insufficient);
      expect(bad.next, isNull);
      expect(bad.before, 10);
    });

    test('idempotent theo hóa đơn: chạy lại cùng billId/op không trừ/cộng 2 lần', () {
      final first = LoyaltyMath.apply(customer(), billId: 'B1', op: LoyaltyOp.award, points: 20, now: 1);
      expect(first.after, 70);
      expect(first.next!['totalPoints'], 100);
      final again = LoyaltyMath.apply(first.next, billId: 'B1', op: LoyaltyOp.award, points: 20, now: 2);
      expect(again.status, LoyaltyTxnStatus.alreadyApplied);
      expect(again.next, isNull);
      // Thao tác khác của cùng hóa đơn vẫn được
      final redeem = LoyaltyMath.apply(first.next, billId: 'B1', op: LoyaltyOp.redeem, points: 5, now: 3);
      expect(redeem.status, LoyaltyTxnStatus.applied);
      expect(redeem.after, 65);
    });

    test('hoàn điểm: chỉ hoàn cho đúng hóa đơn vừa đổi, tối đa số đã đổi, xóa lastRedeem', () {
      final r = LoyaltyMath.apply(customer(), billId: 'B1', op: LoyaltyOp.redeem, points: 20, now: 1);
      final wrong = LoyaltyMath.apply(r.next, billId: 'B9', op: LoyaltyOp.refund, points: 20, now: 2);
      expect(wrong.status, LoyaltyTxnStatus.nothingToRefund);
      final ref = LoyaltyMath.apply(r.next, billId: 'B1', op: LoyaltyOp.refund, points: 999, now: 2);
      expect(ref.status, LoyaltyTxnStatus.applied);
      expect(ref.points, 20);
      expect(ref.after, 50);
      expect(ref.next!.containsKey('lastRedeem'), isFalse);
      expect(ref.next!['totalPoints'], 80);
      final twice = LoyaltyMath.apply(ref.next, billId: 'B1', op: LoyaltyOp.refund, points: 20, now: 3);
      expect(twice.status, LoyaltyTxnStatus.alreadyApplied);
    });

    test('khách không tồn tại → missingCustomer', () {
      expect(LoyaltyMath.apply(null, billId: 'B1', op: LoyaltyOp.award, points: 1, now: 1).status,
          LoyaltyTxnStatus.missingCustomer);
    });

    test('ưu tiên diem_hien_tai giống rules', () {
      expect(LoyaltyMath.pointsOf({'diem_hien_tai': 7, 'currentPoints': 9}), 7);
      expect(LoyaltyMath.pointsOf({'currentPoints': 9}), 9);
      expect(LoyaltyMath.totalOf({'diem_hien_tai': 7}), 7);
    });
  });

  group('StockRetryPlanner', () {
    test('remaining: chỉ còn các dòng chưa có marker', () {
      final plan = {'MILK': 100, 'COFFEE': 20, 'SUGAR': 10};
      expect(StockRetryPlanner.remaining(plan, null), plan);
      expect(StockRetryPlanner.remaining(plan, {'MILK': 100}), {'COFFEE': 20, 'SUGAR': 10});
      expect(StockRetryPlanner.isComplete(plan, {'MILK': 100, 'COFFEE': 20, 'SUGAR': 10}), isTrue);
      expect(StockRetryPlanner.isComplete(plan, {'MILK': 100}), isFalse);
    });

    test('lineKey làm sạch ký tự cấm của Firebase và remaining so khớp theo lineKey', () {
      expect(StockRetryPlanner.lineKey('a.b#c\$d[e]/f'), 'a_b_c_d_e__f');
      expect(StockRetryPlanner.remaining({'a.b': 1, 'c': 2}, {'a_b': 1}), {'c': 2});
    });

    test('applyConsumptionOnce: trừ 1 lần, lần 2 cùng hóa đơn → null (không trừ lại)', () {
      final cur = {'balanceId': 'S_MILK', 'itemId': 'MILK', 'onHandQty': 1000, 'inventoryValue': 500000, 'averageCostScaled': 50000};
      final first = StockRetryPlanner.applyConsumptionOnce(cur,
          billId: 'B1', balanceId: 'S_MILK', branchId: 'S', itemId: 'MILK', consumeQty: 100, now: 1);
      expect(first, isNotNull);
      expect(first!['onHandQty'], 900);
      expect(first['averageCostScaled'], 50000);
      expect(IdempotencyRing.contains(first[StockRetryPlanner.ringField], 'B1'), isTrue);

      final retry = StockRetryPlanner.applyConsumptionOnce(first,
          billId: 'B1', balanceId: 'S_MILK', branchId: 'S', itemId: 'MILK', consumeQty: 100, now: 2);
      expect(retry, isNull);

      final other = StockRetryPlanner.applyConsumptionOnce(first,
          billId: 'B2', balanceId: 'S_MILK', branchId: 'S', itemId: 'MILK', consumeQty: 50, now: 3);
      expect(other!['onHandQty'], 850);
      expect(IdempotencyRing.read(other[StockRetryPlanner.ringField]), ['B1', 'B2']);
    });

    test('mô phỏng thử lại sau lỗi giữa chừng: tổng trừ đúng bằng kế hoạch, không trừ đôi', () {
      final plan = {'MILK': 100, 'COFFEE': 20};
      final balances = <String, Map<String, dynamic>>{
        'MILK': {'onHandQty': 1000, 'averageCostScaled': 0},
        'COFFEE': {'onHandQty': 500, 'averageCostScaled': 0},
      };
      final markers = <String, int>{};

      void attempt({Set<String> failBefore = const {}, Set<String> crashAfterBalance = const {}}) {
        for (final e in StockRetryPlanner.remaining(plan, markers).entries) {
          if (failBefore.contains(e.key)) continue; // transaction lỗi → chưa trừ
          final next = StockRetryPlanner.applyConsumptionOnce(balances[e.key],
              billId: 'B1', balanceId: e.key, branchId: 'S', itemId: e.key, consumeQty: e.value, now: 1);
          if (next != null) balances[e.key] = next;
          if (crashAfterBalance.contains(e.key)) continue; // app tắt trước khi ghi marker dòng
          markers[StockRetryPlanner.lineKey(e.key)] = e.value;
        }
      }

      attempt(failBefore: {'COFFEE'}, crashAfterBalance: {'MILK'});
      expect(balances['MILK']!['onHandQty'], 900);
      expect(balances['COFFEE']!['onHandQty'], 500);
      expect(StockRetryPlanner.isComplete(plan, markers), isFalse);

      attempt(); // thử lại: MILK bị vòng khóa chặn, COFFEE được trừ
      attempt(); // thử lại lần nữa: không còn gì
      expect(balances['MILK']!['onHandQty'], 900);
      expect(balances['COFFEE']!['onHandQty'], 480);
      expect(StockRetryPlanner.isComplete(plan, markers), isTrue);
    });

    test('encode/decode kế hoạch trong hàng đợi', () {
      final plan = {'MILK': 100, 'COFFEE': 20};
      expect(StockRetryPlanner.decodePlan(StockRetryPlanner.encodePlan(plan)), plan);
      expect(StockRetryPlanner.decodePlan({'0': {'itemId': 'A', 'qty': 3}, '1': {'itemId': '', 'qty': 1}}), {'A': 3});
      expect(StockRetryPlanner.decodePlan(null), isNull);
    });

    test('canRunRetry khớp nhóm Thu ngân trở lên của rules', () {
      expect(StockRetryPlanner.canRunRetry('cashier'), isTrue);
      expect(StockRetryPlanner.canRunRetry('employee'), isTrue);
      expect(StockRetryPlanner.canRunRetry('ROLE_MANAGER_1'), isTrue);
      expect(StockRetryPlanner.canRunRetry('waiter'), isFalse);
      expect(StockRetryPlanner.canRunRetry('ROLE_KITCHEN'), isFalse);
      expect(StockRetryPlanner.canRunRetry('anything', isRootOwner: true), isTrue);
    });
  });
}
