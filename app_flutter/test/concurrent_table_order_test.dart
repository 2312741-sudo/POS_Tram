import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/shift_scope.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/repositories/order_repository.dart';

void main() {
  group('Kết hợp Phương án 1 + 2: Chống trùng bàn & Tự động tách 2 không gian bàn / 2 đơn riêng', () {
    test('TableModel.extractBaseName & nextSplitTableName cấp tên tuần tự chuẩn xác', () {
      expect(TableModel.extractBaseName('Bàn 01'), 'Bàn 01');
      expect(TableModel.extractBaseName('Bàn 01 (2)'), 'Bàn 01');
      expect(TableModel.extractBaseName('Mang về (3)'), 'Mang về');

      expect(
        TableModel.nextSplitTableName('Bàn 01', ['Bàn 01']),
        'Bàn 01 (2)',
      );
      expect(
        TableModel.nextSplitTableName('Bàn 01', ['Bàn 01', 'Bàn 01 (2)']),
        'Bàn 01 (3)',
      );
      expect(
        TableModel.nextSplitTableName('Mang về (2)', ['Mang về', 'Mang về (2)']),
        'Mang về (3)',
      );
    });

    test('Phương án 2 + 1 khi chạm bàn: NV A vừa bấm vào Bàn 01 -> NV B bấm tiếp sẽ tự tách ra Bàn 01 (2) & đơn riêng', () {
      const now = 1700000000000;
      final ban01 = TableModel(name: 'Bàn 01', zone: 'Tầng 1', capacity: 4);

      // 1. Nhân viên A bấm vào Bàn 01 đang trống -> chiếm khóa tạm orderingBy = 'nv_a'
      final resA = OrderRepository.resolveTableForNewOrder(
        ban01,
        [ban01],
        staffUsername: 'nv_a',
        staffName: 'Nhân viên A',
        nowMs: now,
      );
      expect(resA.wasSplit, isFalse);
      expect(resA.targetTable.name, 'Bàn 01');
      expect(resA.targetTable.orderingBy, 'nv_a');
      expect(resA.targetTable.isActivelyOrdering(excludeUsername: 'nv_b', nowMs: now + 500), isTrue);

      // 2. Nhân viên B bấm vào Bàn 01 khi NV A đang chọn món -> tự động tạo Bàn 01 (2) và mã HĐ riêng
      final resB = OrderRepository.resolveTableForNewOrder(
        ban01,
        [resA.targetTable],
        staffUsername: 'nv_b',
        staffName: 'Nhân viên B',
        nowMs: now + 500,
      );
      expect(resB.wasSplit, isTrue);
      expect(resB.occupiedBy, 'Nhân viên A');
      expect(resB.targetTable.name, 'Bàn 01 (2)');
      expect(resB.targetTable.zone, 'Tầng 1');
      expect(resB.targetTable.isSplitTable, isTrue);
      expect(resB.targetTable.orderingBy, 'nv_b');
      expect(resB.targetTable.currentBillId, isNotNull);
      expect(resB.targetTable.currentOrderCode, isNotNull);
    });

    test('Phương án 1 khi 2 NV bấm vào cùng 1 mili-giây: Lúc bấm Lưu sẽ tự tách thành 2 bàn riêng & 2 đơn riêng', () {
      const now = 1700000000000;
      final itemA = OrderItemModel(
        productId: 1,
        name: 'Trà Đào',
        price: 30000,
        quantity: 1,
        orderedBy: 'nv_a',
      );
      final itemB = OrderItemModel(
        productId: 2,
        name: 'Cà Phê Sữa',
        price: 25000,
        quantity: 2,
        orderedBy: 'nv_b',
      );

      // Giả sử NV A và NV B cùng mở đơn "Mang về" ở cùng 1 tích tắc (chưa kịp nhận khóa của nhau)
      // NV A bấm "Xem lại đơn" trước -> lưu lên Firebase với currentBillId = HD-AAA
      final remoteMangVeAfterA = TableModel(
        name: 'Mang về',
        zone: 'Mang về',
        inUse: true,
        currentBillId: 'HD-261028-100000-AAAA',
        currentOrderCode: 'OD-261028-100000-AAAA',
        currentOrderJson: jsonEncode([itemA.toMap()]),
      );

      // NV B chọn xong Cà Phê Sữa cho khách thứ 2 và bấm "Xem lại đơn" (phiên của B có mã HD-BBBB)
      final localMangVeOfB = TableModel(
        name: 'Mang về',
        zone: 'Mang về',
        inUse: true,
        currentBillId: 'HD-261028-100000-BBBB',
        currentOrderCode: 'OD-261028-100000-BBBB',
        currentOrderJson: jsonEncode([itemB.toMap()]),
      );

      final saveResB = OrderRepository.resolveConcurrentOrderSave(
        localMangVeOfB,
        [remoteMangVeAfterA],
        sessionBillId: 'HD-261028-100000-BBBB',
        isNewOrderSession: true,
        nowMs: now,
      );

      // Bắt buộc KHÔNG ghi đè đơn A và KHÔNG gộp vào đơn A -> tự tách sang "Mang về (2)"
      expect(saveResB.wasSplit, isTrue);
      expect(saveResB.tableToSave.name, 'Mang về (2)');
      expect(saveResB.tableToSave.zone, 'Mang về');
      expect(saveResB.tableToSave.isSplitTable, isTrue);
      expect(saveResB.tableToSave.inUse, isTrue);
      expect(saveResB.tableToSave.currentItems.length, 1);
      expect(saveResB.tableToSave.currentItems.first.name, 'Cà Phê Sữa');
      expect(saveResB.tableToSave.currentBillId, isNot(equals(remoteMangVeAfterA.currentBillId)));

      // Đơn của NV A trên "Mang về" vẫn nguyên vẹn 100%
      expect(remoteMangVeAfterA.currentItems.length, 1);
      expect(remoteMangVeAfterA.currentItems.first.name, 'Trà Đào');
    });

    test('normalizeTablesList: Tự động sinh ô Mang về (2) trống khi Mang về đang bận, và tự ẩn bàn tách khi đã thanh toán/trống', () {
      const now = 1700000000000;
      final item = OrderItemModel(productId: 1, name: 'Trà Olong', price: 20000, quantity: 1);

      final mangVeBusy = TableModel(
        name: 'Mang về',
        zone: 'Mang về',
        inUse: true,
        currentOrderJson: jsonEncode([item.toMap()]),
      );
      final ban01 = TableModel(name: 'Bàn 01', zone: 'Khu A', inUse: false);
      final ban01SplitPaid = TableModel(
        name: 'Bàn 01 (2)',
        zone: 'Khu A',
        inUse: false,
        isSplitTable: true,
      );

      final normalized = OrderRepository.normalizeTablesList(
        [mangVeBusy, ban01, ban01SplitPaid],
        nowMs: now,
      );

      // 1. "Bàn 01 (2)" đã thanh toán (inUse = false) phải tự động biến mất khỏi sơ đồ bàn
      expect(normalized.any((t) => t.name == 'Bàn 01 (2)'), isFalse);
      expect(normalized.any((t) => t.name == 'Bàn 01'), isTrue);

      // 2. Vì "Mang về" đang bận, hệ thống tự động hiển thị thêm 1 ô "Mang về (2)" trống sẵn sàng cho NV khác
      expect(normalized.any((t) => t.name == 'Mang về' && t.inUse), isTrue);
      expect(normalized.any((t) => t.name == 'Mang về (2)' && !t.inUse), isTrue);
    });

    test('planSplitTableItems: Hỗ trợ đủ 3 chế độ Tách đơn (Thanh toán trước / Chuyển bàn trống / Ghép vào bàn có khách) mà không bao giờ mất món', () {
      const now = 1700000000000;
      final item1 = OrderItemModel(productId: 1, name: 'Trà Đào', price: 30000, quantity: 3);
      final item2 = OrderItemModel(productId: 2, name: 'Bạc Xỉu', price: 25000, quantity: 1);

      final source = TableModel(
        name: 'Bàn 01',
        zone: 'Khu A',
        inUse: true,
        currentBillId: 'HD-SRC-01',
        currentOrderCode: 'OD-SRC-01',
        currentOrderJson: jsonEncode([item1.toMap(), item2.toMap()]),
      );

      // Tách 1 phần Trà Đào ra khỏi 3 phần Trà Đào
      final (taken1, rest1) = item1.splitQuantity(1);
      final splitItems = [taken1!];
      final remainingItems = [rest1!, item2];

      // 1. Tách để Thanh toán trước hoặc Tạo bàn tách mới (Bàn 01 (2))
      final splitTarget = TableModel(name: 'Bàn 01 (2)', zone: 'Khu A', isSplitTable: true);
      final plannedSplit = OrderRepository.planSplitTableItems(
        sourceTable: source,
        splitItems: splitItems,
        remainingItems: remainingItems,
        targetTable: splitTarget,
        mergeIntoTarget: false,
        staffUsername: 'thungan',
        staffName: 'Thu Ngân',
        nowMs: now,
      );

      expect(plannedSplit.updatedSource.inUse, isTrue);
      expect(plannedSplit.updatedSource.currentTotal, 2 * 30000 + 25000);
      expect(plannedSplit.updatedTarget.inUse, isTrue);
      expect(plannedSplit.updatedTarget.isSplitTable, isTrue);
      expect(plannedSplit.updatedTarget.currentTotal, 30000);
      expect(plannedSplit.updatedTarget.currentBillId, isNot(equals('HD-SRC-01')));

      // 2. Tách và Ghép vào bàn đang có khách khác (Bàn 03 đang có sẵn 2 Trà Đào)
      final existingOnBan03 = OrderItemModel(productId: 1, name: 'Trà Đào', price: 30000, quantity: 2);
      final ban03 = TableModel(
        name: 'Bàn 03',
        zone: 'Khu A',
        inUse: true,
        currentBillId: 'HD-BAN03',
        currentOrderCode: 'OD-BAN03',
        currentOrderJson: jsonEncode([existingOnBan03.toMap()]),
      );

      final plannedMerge = OrderRepository.planSplitTableItems(
        sourceTable: source,
        splitItems: splitItems,
        remainingItems: remainingItems,
        targetTable: ban03,
        mergeIntoTarget: true,
        staffUsername: 'thungan',
        staffName: 'Thu Ngân',
        nowMs: now,
      );

      expect(plannedMerge.updatedTarget.inUse, isTrue);
      expect(plannedMerge.updatedTarget.currentBillId, 'HD-BAN03');
      // 2 Trà Đào cũ + 1 Trà Đào tách sang = 3 Trà Đào (90.000đ)
      expect(plannedMerge.updatedTarget.currentItems.length, 1);
      expect(plannedMerge.updatedTarget.currentItems.first.quantity, 3);
      expect(plannedMerge.updatedTarget.currentTotal, 90000);
    });

    test('Tách đơn Thanh Toán Trước (planPaySplitItemsNow) tạo hóa đơn PAID ngay, có mã HĐ và tính vào doanh thu', () {
      const now = 1700000120000;
      final item1 = OrderItemModel(
        productId: 1,
        name: 'Trà Đào',
        price: 30000,
        quantity: 3,
      );
      final item2 = OrderItemModel(
        productId: 2,
        name: 'Bạc Xỉu',
        price: 25000,
        quantity: 1,
      );

      final source = TableModel(
        name: 'Bàn 01',
        zone: 'Khu A',
        inUse: true,
        openedAt: now - 60000,
        currentBillId: 'HD-SRC-01',
        currentOrderCode: 'OD-SRC-01',
        currentOrderJson: jsonEncode([item1.toMap(), item2.toMap()]),
      )..addActionLog(OrderActionLogModel(
          timestamp: now - 50000,
          staffUsername: 'phucvu_a',
          staffFullName: 'Phục Vụ A',
          action: 'SEND_KITCHEN',
          details: 'Gửi bếp',
        ));

      final (taken1, rest1) = item1.splitQuantity(2);
      final splitItems = [taken1!]; // 2 Trà Đào = 60.000đ
      final remainingItems = [rest1!, item2]; // 1 Trà Đào + 1 Bạc Xỉu = 55.000đ

      final res = OrderRepository.planPaySplitItemsNow(
        sourceTable: source,
        splitItems: splitItems,
        remainingItems: remainingItems,
        billCode: 'HD-261028-0009',
        paymentMethod: 'CASH',
        shiftId: 'SHIFT_01',
        staffUid: 'uid_thungan',
        staffUsername: 'thungan',
        staffFullName: 'Thu Ngân',
        nowMs: now,
      );

      expect(res.paidBill.status, 'PAID');
      expect(res.paidBill.billCode, 'HD-261028-0009');
      expect(res.paidBill.closedAt, now);
      expect(res.paidBill.subTotal, 60000);
      expect(res.paidBill.finalAmount, 60000);
      expect(res.paidBill.tableName, 'Bàn 01 (Tách)');
      expect(res.paidBill.parentBillId, 'HD-SRC-01');
      expect(res.updatedSource.inUse, isTrue);
      expect(res.updatedSource.currentTotal, 55000);

      // Tính vào doanh thu tổng quan (ReportCalculator)
      final overview = ReportCalculator.calculateOverviewReport([res.paidBill]);
      expect(overview.paidBillsCount, 1);
      expect(overview.grossRevenue, 60000);
      expect(overview.netRevenue, 60000);

      // Cả Thu Ngân lẫn Phục Vụ A (người gửi bếp ban đầu) đều thấy hóa đơn tách trong Lịch sử hóa đơn
      expect(
        scopeBills([res.paidBill], uid: 'uid_thungan', username: 'thungan', canViewAll: false).length,
        1,
      );
      expect(
        scopeBills([res.paidBill], uid: 'uid_pv_a', username: 'phucvu_a', canViewAll: false).length,
        1,
      );
    });

    test('BillModel.fromMap tự động khôi phục các hóa đơn tách cũ bị lưu status OPEN thành PAID để tính doanh thu', () {
      const createdAt = 1700000000000;
      final legacySplitBill = BillModel.fromMap({
        'billCode': 'HD-OLD-SPLIT',
        'tableName': 'Bàn 02 (Tách)',
        'zone': 'Tầng 1',
        'createdAt': createdAt,
        'status': 'OPEN',
        'parentBillId': 'Bàn 02',
        'subTotal': 45000,
        'finalAmount': 45000,
        'paymentMethod': 'CASH',
        'items': [
          {
            'productId': 10,
            'name': 'Cà phê sữa',
            'price': 45000,
            'quantity': 1,
          }
        ],
      }, 'BILL_LEGACY_1');

      expect(legacySplitBill.status, 'PAID');
      expect(legacySplitBill.closedAt, createdAt);

      final overview = ReportCalculator.calculateOverviewReport([legacySplitBill]);
      expect(overview.paidBillsCount, 1);
      expect(overview.netRevenue, 45000);
    });
  });
}
