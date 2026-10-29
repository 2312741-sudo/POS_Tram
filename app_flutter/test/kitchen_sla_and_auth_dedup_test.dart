import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/kitchen_sla.dart';
import 'package:tram_flutter/data/models/kitchen_order_model.dart';
import 'package:tram_flutter/data/models/user_model.dart';
import 'package:tram_flutter/data/repositories/auth_repository.dart';

void main() {
  group('KitchenSla.compute tests', () {
    test('computes order and item SLA correctly with overdue threshold', () {
      final nowMs = 1730000000000;
      final t1Created = nowMs;
      final t1Done = nowMs + 10 * 60 * 1000; // 10 minutes (on time for 15m threshold)

      final t2Created = nowMs;
      final t2Done = nowMs + 20 * 60 * 1000; // 20 minutes (overdue for 15m threshold)

      final orders = [
        KitchenOrderModel(
          firebaseKey: 'k1',
          tableName: 'Bàn 1',
          orderCode: 'ORD-1',
          itemsJson: jsonEncode([
            {'name': 'Trà Sữa Oolong', 'quantity': 2, 'category': 'Trà sữa'},
            {'name': 'Bánh Mì Chảo', 'quantity': 1, 'category': 'Bánh mì'},
          ]),
          timestamp: t1Created,
          doneAt: t1Done,
          isDone: true,
        ),
        KitchenOrderModel(
          firebaseKey: 'k2',
          tableName: 'Bàn 2',
          orderCode: 'ORD-2',
          itemsJson: jsonEncode([
            {'name': 'Cà Phê Muối', 'quantity': 1, 'category': 'Cà phê'},
          ]),
          timestamp: t2Created,
          doneAt: t2Done,
          isDone: true,
        ),
      ];

      final summary = KitchenSla.compute(
        orders,
        threshold: const Duration(minutes: 15),
        fromMs: nowMs - 1000,
        toMs: nowMs + 3600 * 1000,
      );

      // Orders: k1 (10 mins, not overdue), k2 (20 mins, overdue)
      expect(summary.orders.length, 2);
      expect(summary.lateOrderCount, 1);
      expect(summary.lateOrders.length, 1);
      expect(summary.lateOrders.first.orderCode, 'ORD-2');

      // Average duration: (10 + 20) / 2 = 15 minutes
      expect(summary.averageOrder.inMinutes, 15);
      expect(summary.maxOrder.inMinutes, 20);

      // Items: total 3 item entries across tickets
      expect(summary.items.length, 3);
      final traSua = summary.items.firstWhere((i) => i.itemName == 'Trà Sữa Oolong');
      expect(traSua.quantity, 2);
      expect(traSua.duration.inMinutes, 10);
      expect(traSua.group, kKitchenGroupDrink);

      final banhMi = summary.items.firstWhere((i) => i.itemName == 'Bánh Mì Chảo');
      expect(banhMi.quantity, 1);
      expect(banhMi.duration.inMinutes, 10);
      expect(banhMi.group, kKitchenGroupFood);

      final caPhe = summary.items.firstWhere((i) => i.itemName == 'Cà Phê Muối');
      expect(caPhe.quantity, 1);
      expect(caPhe.duration.inMinutes, 20);
      expect(caPhe.group, kKitchenGroupDrink);
    });

    test('handles empty tickets gracefully', () {
      final summary = KitchenSla.compute([], threshold: const Duration(minutes: 15));
      expect(summary.orders, isEmpty);
      expect(summary.items, isEmpty);
      expect(summary.averageOrder, Duration.zero);
      expect(summary.lateOrderCount, 0);
    });
  });

  group('AuthRepository.deduplicateUsers tests', () {
    test('deduplicates duplicate username and prioritizes real UID node', () {
      final users = [
        UserModel(
          uid: 'admin',
          username: 'admin',
          fullName: 'Trạm Chanh Admin (Ghost)',
          roleId: 'owner',
          isRootOwner: false,
        ),
        UserModel(
          uid: 'firebase_auth_uid_123',
          username: 'admin',
          fullName: 'Chủ Quán Trạm Chanh (Root)',
          roleId: 'owner',
          isRootOwner: true,
        ),
        UserModel(
          uid: 'staff_1',
          username: 'nhanvien1',
          fullName: 'Nhân viên 1',
          roleId: 'staff',
        ),
      ];

      final deduped = AuthRepository.deduplicateUsers(users);

      expect(deduped.length, 2);
      final adminUser = deduped.firstWhere((u) => u.username == 'admin');
      expect(adminUser.uid, 'firebase_auth_uid_123');
      expect(adminUser.fullName, 'Chủ Quán Trạm Chanh (Root)');
      expect(adminUser.isRootOwner, true);
    });
  });
}
