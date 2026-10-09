// test/kitchen_service_workflow_test.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/features/tables/widgets/ready_kitchen_orders_banner.dart';

void main() {
  group('KitchenOrderModel Service Fields & Serialization', () {
    test('Round-trip serialization preserves all service notification fields', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final done = now + 60000;
      final picked = done + 30000;

      final original = KitchenOrderModel(
        firebaseKey: '-Nxyz123',
        tableName: 'A1',
        orderCode: 'OD-261009-001',
        billCode: 'HD-261009-001',
        itemsJson: jsonEncode([
          {'productId': 1, 'name': 'Cà phê sữa', 'price': 25000, 'quantity': 2}
        ]),
        timestamp: now,
        isDone: true,
        note: 'Ít đường',
        orderedBy: 'staff_tam',
        orderedByName: 'Nguyễn Văn Tâm',
        doneAt: done,
        pickedUp: true,
        pickedUpAt: picked,
        pickedUpBy: 'Trần Thị Thu',
      );

      final map = original.toMap();
      expect(map['tableName'], 'A1');
      expect(map['orderCode'], 'OD-261009-001');
      expect(map['billCode'], 'HD-261009-001');
      expect(map['isDone'], true);
      expect(map['note'], 'Ít đường');
      expect(map['orderedBy'], 'staff_tam');
      expect(map['orderedByName'], 'Nguyễn Văn Tâm');
      expect(map['doneAt'], done);
      expect(map['pickedUp'], true);
      expect(map['pickedUpAt'], picked);
      expect(map['pickedUpBy'], 'Trần Thị Thu');

      final deserialized = KitchenOrderModel.fromMap(map, key: '-Nxyz123');
      expect(deserialized.firebaseKey, '-Nxyz123');
      expect(deserialized.tableName, 'A1');
      expect(deserialized.orderCode, 'OD-261009-001');
      expect(deserialized.billCode, 'HD-261009-001');
      expect(deserialized.isDone, true);
      expect(deserialized.note, 'Ít đường');
      expect(deserialized.orderedBy, 'staff_tam');
      expect(deserialized.orderedByName, 'Nguyễn Văn Tâm');
      expect(deserialized.doneAt, done);
      expect(deserialized.pickedUp, true);
      expect(deserialized.pickedUpAt, picked);
      expect(deserialized.pickedUpBy, 'Trần Thị Thu');
      expect(deserialized.items.length, 1);
      expect(deserialized.items.first.name, 'Cà phê sữa');
      expect(deserialized.doneDateTime?.millisecondsSinceEpoch, done);
    });

    test('Default values for isDone and pickedUp are false', () {
      final order = KitchenOrderModel(
        tableName: 'B2',
        itemsJson: '[]',
        timestamp: 1000,
      );

      expect(order.isDone, false);
      expect(order.pickedUp, false);
      expect(order.orderedBy, isNull);
      expect(order.orderedByName, isNull);
      expect(order.doneAt, isNull);
      expect(order.pickedUpAt, isNull);
      expect(order.pickedUpBy, isNull);
    });

    test('copyWith updates fields correctly', () {
      final order = KitchenOrderModel(
        tableName: 'C3',
        itemsJson: '[]',
        timestamp: 1000,
        isDone: false,
        pickedUp: false,
      );

      final updated = order.copyWith(
        isDone: true,
        doneAt: 2000,
        pickedUp: true,
        pickedUpAt: 3000,
        pickedUpBy: 'Phục Vụ 1',
      );

      expect(updated.tableName, 'C3');
      expect(updated.isDone, true);
      expect(updated.doneAt, 2000);
      expect(updated.pickedUp, true);
      expect(updated.pickedUpAt, 3000);
      expect(updated.pickedUpBy, 'Phục Vụ 1');
    });
  });

  group('ReadyToServe Filtering Logic', () {
    test('Filters orders by isDone == true and pickedUp != true and within maxAge', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final oneHourAgo = now - 60 * 60 * 1000;
      final threeHoursAgo = now - 3 * 60 * 60 * 1000;
      const maxAgeMs = 2 * 60 * 60 * 1000;

      final orders = [
        // 1. Đang nấu (chưa xong) -> KHÔNG sẵn sàng
        KitchenOrderModel(
          firebaseKey: '1',
          tableName: 'A1',
          itemsJson: '[]',
          timestamp: now,
          isDone: false,
          pickedUp: false,
        ),
        // 2. Đã nấu xong, chưa lấy món, trong vòng 1 tiếng -> SẴN SÀNG
        KitchenOrderModel(
          firebaseKey: '2',
          tableName: 'A2',
          itemsJson: '[]',
          timestamp: oneHourAgo,
          isDone: true,
          doneAt: oneHourAgo,
          pickedUp: false,
          orderedByName: 'Nhân viên A',
        ),
        // 3. Đã nấu xong, ĐÃ LẤY MÓN -> KHÔNG sẵn sàng
        KitchenOrderModel(
          firebaseKey: '3',
          tableName: 'A3',
          itemsJson: '[]',
          timestamp: now,
          isDone: true,
          doneAt: now,
          pickedUp: true,
          pickedUpBy: 'Nhân viên B',
        ),
        // 4. Đã nấu xong nhưng quá 2 tiếng trước -> KHÔNG sẵn sàng (hết hạn hiển thị)
        KitchenOrderModel(
          firebaseKey: '4',
          tableName: 'A4',
          itemsJson: '[]',
          timestamp: threeHoursAgo,
          isDone: true,
          doneAt: threeHoursAgo,
          pickedUp: false,
        ),
      ];

      final readyOrders = orders.where((o) {
        if (!o.isDone || o.pickedUp) return false;
        final itemTime = o.doneAt ?? o.timestamp;
        return (now - itemTime) <= maxAgeMs;
      }).toList();

      expect(readyOrders.length, 1);
      expect(readyOrders.first.firebaseKey, '2');
      expect(readyOrders.first.tableName, 'A2');
      expect(readyOrders.first.orderedByName, 'Nhân viên A');
    });
  });

  group('ReadyKitchenOrdersBanner UI Widget', () {
    testWidgets('Displays notification banner for a single finished order', (tester) async {
      bool pickedUpCalled = false;
      KitchenOrderModel? pickedOrder;

      final readyOrder = KitchenOrderModel(
        firebaseKey: 'key_1',
        tableName: 'A1',
        itemsJson: jsonEncode([
          {'productId': 10, 'name': 'Trà đào cam sả', 'price': 35000, 'quantity': 2}
        ]),
        timestamp: DateTime.now().millisecondsSinceEpoch - 120000,
        doneAt: DateTime.now().millisecondsSinceEpoch - 60000,
        isDone: true,
        pickedUp: false,
        orderedByName: 'Chủ Quán',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadyKitchenOrdersBanner(
              orders: [readyOrder],
              onPickUp: (order) async {
                pickedUpCalled = true;
                pickedOrder = order;
              },
              onViewAll: () {},
            ),
          ),
        ),
      );

      // Kiểm tra tiêu đề hiển thị tên bàn
      expect(find.text('[A1] ĐÃ XONG MÓN!'), findsOneWidget);
      // Kiểm tra nội dung mời người order vào lấy món
      expect(find.textContaining('Mời Chủ Quán vào lấy món mang cho khách!'), findsOneWidget);
      // Nút "Đã lấy món"
      expect(find.text('Đã lấy món'), findsOneWidget);

      // Bấm nút Đã lấy món
      await tester.tap(find.text('Đã lấy món'));
      await tester.pump();

      expect(pickedUpCalled, true);
      expect(pickedOrder?.tableName, 'A1');
    });

    testWidgets('Displays multi-order notification banner when 2+ tables are ready', (tester) async {
      bool viewAllCalled = false;

      final orders = [
        KitchenOrderModel(
          firebaseKey: 'key_1',
          tableName: 'B1',
          itemsJson: '[]',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isDone: true,
          pickedUp: false,
        ),
        KitchenOrderModel(
          firebaseKey: 'key_2',
          tableName: 'B2',
          itemsJson: '[]',
          timestamp: DateTime.now().millisecondsSinceEpoch,
          isDone: true,
          pickedUp: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadyKitchenOrdersBanner(
              orders: orders,
              onPickUp: (_) async {},
              onViewAll: () {
                viewAllCalled = true;
              },
            ),
          ),
        ),
      );

      // Kiểm tra tiêu đề có 1 bàn khác
      expect(find.text('[B1] & 1 BÀN KHÁC ĐÃ XONG!'), findsOneWidget);
      expect(find.text('Xem (2)'), findsOneWidget);

      // Bấm Xem
      await tester.tap(find.text('Xem (2)'));
      await tester.pump();

      expect(viewAllCalled, true);
    });

    testWidgets('Returns SizedBox.shrink() when orders list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReadyKitchenOrdersBanner(
              orders: const [],
              onPickUp: (_) async {},
              onViewAll: () {},
            ),
          ),
        ),
      );

      expect(find.byType(ReadyKitchenOrdersBanner), findsOneWidget);
      expect(find.textContaining('ĐÃ XONG MÓN'), findsNothing);
    });
  });
}
