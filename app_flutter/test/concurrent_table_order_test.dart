import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
