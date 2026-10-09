import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  group('Cash Shifts Performance & Replay Cache Tests', () {
    test('Stream.multi with cached list replays latest list immediately to new subscribers', () async {
      List<CashShiftModel>? cachedList;
      final controller = StreamController<List<CashShiftModel>>.broadcast();

      Stream<List<CashShiftModel>> createReplayingStream() {
        return Stream<List<CashShiftModel>>.multi((multiCtrl) {
          if (cachedList != null) {
            multiCtrl.add(cachedList!);
          }
          final sub = controller.stream.listen(
            (data) => multiCtrl.add(data),
            onError: (err, st) => multiCtrl.addError(err, st),
            onDone: () => multiCtrl.close(),
          );
          multiCtrl.onCancel = () {
            sub.cancel();
          };
        }, isBroadcast: true);
      }

      final stream = createReplayingStream();

      // First listener subscribes before data exists
      List<CashShiftModel>? listener1FirstData;
      final sub1 = stream.listen((data) {
        listener1FirstData = data;
      });

      // Emit initial data
      final initialShifts = [
        CashShiftModel(
          id: 'shift_1',
          shiftCode: 'CA-001',
          storeCode: 'TRAM01',
          staffUsername: 'cashier1',
          staffFullName: 'Thu Ngân 1',
          openedAt: 1000,
          initialCash: 1000000,
          status: 'OPEN',
        ),
      ];
      cachedList = initialShifts;
      controller.add(initialShifts);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(listener1FirstData, isNotNull);
      expect(listener1FirstData!.length, 1);
      expect(listener1FirstData!.first.shiftCode, 'CA-001');

      // Now a SECOND listener (simulating user opening CashShiftsScreen later) subscribes:
      // It MUST receive the cached list immediately without waiting for a new event!
      List<CashShiftModel>? listener2ImmediateData;
      final sub2 = stream.listen((data) {
        listener2ImmediateData = data;
      });

      // Events from Stream.multi are delivered on microtask loop
      await Future<void>.delayed(Duration.zero);
      expect(listener2ImmediateData, isNotNull);
      expect(listener2ImmediateData!.length, 1);
      expect(listener2ImmediateData!.first.shiftCode, 'CA-001');

      // Both listeners receive subsequent updates
      final updatedShifts = [
        CashShiftModel(
          id: 'shift_2',
          shiftCode: 'CA-002',
          storeCode: 'TRAM01',
          staffUsername: 'cashier2',
          staffFullName: 'Thu Ngân 2',
          openedAt: 2000,
          initialCash: 500000,
          status: 'OPEN',
        ),
        ...initialShifts,
      ];
      cachedList = updatedShifts;
      controller.add(updatedShifts);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(listener1FirstData!.length, 2);
      expect(listener2ImmediateData!.length, 2);
      expect(listener2ImmediateData!.first.shiftCode, 'CA-002');

      await sub1.cancel();
      await sub2.cancel();
      await controller.close();
    });

    test('Cash shift bills filtering: matches by shiftId or time range', () {
      final shift = CashShiftModel(
        id: 'shift_100',
        shiftCode: 'CA-100',
        storeCode: 'TRAM01',
        staffUsername: 'staff1',
        staffFullName: 'Staff 1',
        openedAt: 10000,
        closedAt: 20000,
        initialCash: 500000,
        status: 'CLOSED',
      );

      final bills = [
        BillModel(
          id: 'b1',
          billCode: 'HD-001',
          tableName: 'Bàn 1',
          zone: 'Tầng 1',
          staffUsername: 'staff1',
          staffFullName: 'Staff 1',
          items: [],
          subTotal: 100000,
          finalAmount: 100000,
          shiftId: 'shift_100',
          createdAt: 9000, // even outside time, matches shiftId
          status: 'PAID',
        ),
        BillModel(
          id: 'b2',
          billCode: 'HD-002',
          tableName: 'Bàn 2',
          zone: 'Tầng 1',
          staffUsername: 'staff1',
          staffFullName: 'Staff 1',
          items: [],
          subTotal: 150000,
          finalAmount: 150000,
          createdAt: 15000, // inside time range
          status: 'PAID',
        ),
        BillModel(
          id: 'b3',
          billCode: 'HD-003',
          tableName: 'Bàn 3',
          zone: 'Tầng 1',
          staffUsername: 'staff1',
          staffFullName: 'Staff 1',
          items: [],
          subTotal: 200000,
          finalAmount: 200000,
          createdAt: 30000, // outside time range
          status: 'PAID',
        ),
      ];

      final filtered = bills.where((b) {
        if (b.shiftId != null && b.shiftId!.isNotEmpty) {
          return b.shiftId == shift.id || b.shiftId == shift.shiftCode;
        }
        final closeT = shift.closedAt ?? 9999999999999;
        return b.createdAt >= shift.openedAt && b.createdAt <= closeT;
      }).toList();

      expect(filtered.length, 2);
      expect(filtered.map((b) => b.id), containsAll(['b1', 'b2']));
      expect(filtered.map((b) => b.id), isNot(contains('b3')));
    });

    test('Promo stats for a shift correctly aggregate line discounts, vouchers, and points', () {
      final shift = CashShiftModel(
        id: 'shift_test',
        shiftCode: 'CA-TEST',
        storeCode: 'TRAM01',
        staffUsername: 'staff',
        staffFullName: 'Staff',
        openedAt: 1000,
        status: 'OPEN',
      );

      final shiftBills = [
        BillModel(
          id: 'b1',
          billCode: 'HD-1',
          tableName: 'Bàn 1',
          zone: 'Tầng 1',
          staffUsername: 'staff',
          staffFullName: 'Staff',
          subTotal: 100000,
          finalAmount: 85000,
          shiftId: 'shift_test',
          createdAt: 1100,
          status: 'PAID',
          items: [
            OrderItemModel(
              productId: 1,
              name: 'Món 1',
              price: 50000,
              quantity: 2,
              discountPercent: 10,
              discountAmount: 10000,
            ),
          ],
          discounts: [
            BillDiscountModel(
              promoId: 'v1',
              description: 'Voucher 5k',
              amount: 5000,
            ),
          ],
          pointsUsed: 0,
          pointsDiscount: 0,
        ),
        BillModel(
          id: 'b2',
          billCode: 'HD-2',
          tableName: 'Bàn 2',
          zone: 'Tầng 1',
          staffUsername: 'staff',
          staffFullName: 'Staff',
          subTotal: 200000,
          finalAmount: 180000,
          shiftId: 'shift_test',
          createdAt: 1200,
          status: 'PAID',
          items: [
            OrderItemModel(
              productId: 2,
              name: 'Món 2',
              price: 200000,
              quantity: 1,
            ),
          ],
          discounts: [],
          pointsUsed: 20,
          pointsDiscount: 20000,
        ),
      ];

      int discountedItemsCount = 0;
      int discountedItemsTotal = 0;
      int voucherCount = 0;
      int voucherTotal = 0;
      int pointsUsedTotal = 0;
      int pointsDiscountTotal = 0;

      for (final b in shiftBills) {
        for (final it in b.items) {
          if (it.lineDiscountTotal > 0) {
            discountedItemsCount += it.discountedQuantity;
            discountedItemsTotal += it.lineDiscountTotal.toInt();
          }
        }
        for (final d in b.discounts) {
          voucherCount += 1;
          voucherTotal += d.amount.toInt();
        }
        if (b.pointsDiscount > 0 || b.pointsUsed > 0) {
          pointsUsedTotal += b.pointsUsed.toInt();
          pointsDiscountTotal += b.pointsDiscount.toInt();
        }
      }

      final totalPromoDiscount = discountedItemsTotal + voucherTotal + pointsDiscountTotal;

      expect(discountedItemsCount, 2);
      expect(discountedItemsTotal, 10000);
      expect(voucherCount, 1);
      expect(voucherTotal, 5000);
      expect(pointsUsedTotal, 20);
      expect(pointsDiscountTotal, 20000);
      expect(totalPromoDiscount, 35000);
    });

    test('Safe timeout timer completes and sets loading false after duration', () async {
      bool loading = true;
      Timer? safetyTimer;

      safetyTimer = Timer(const Duration(milliseconds: 50), () {
        loading = false;
      });

      expect(loading, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(loading, isFalse);
      safetyTimer.cancel();
    });
  });
}
