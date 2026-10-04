// test/printer_test.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tram_flutter/core/printer/printer_types.dart';
import 'package:tram_flutter/core/printer/receipt_printer.dart';
import 'package:tram_flutter/core/printer/esc_pos_raster_helper.dart';
import 'package:tram_flutter/core/printer/print_queue_service.dart';
import 'package:tram_flutter/data/models/app_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Khổ Giấy & Mã Hóa Tiếng Việt (Paper Size & Encoding)', () {
    test('PrinterPaperSize charWidth và dotWidth chuẩn xác cho 58mm và 80mm', () {
      expect(PrinterPaperSize.mm58.charWidth, equals(32));
      expect(PrinterPaperSize.mm58.dotWidth, equals(384));
      expect(PrinterPaperSize.mm58.label, equals('Khổ 58mm'));

      expect(PrinterPaperSize.mm80.charWidth, equals(48));
      expect(PrinterPaperSize.mm80.dotWidth, equals(576));
      expect(PrinterPaperSize.mm80.label, equals('Khổ 80mm'));

      expect(PrinterPaperSize.fromString('mm80'), equals(PrinterPaperSize.mm80));
      expect(PrinterPaperSize.fromString('80mm'), equals(PrinterPaperSize.mm80));
      expect(PrinterPaperSize.fromString('80'), equals(PrinterPaperSize.mm80));
      expect(PrinterPaperSize.fromString('mm58'), equals(PrinterPaperSize.mm58));
      expect(PrinterPaperSize.fromString('anything_else'), equals(PrinterPaperSize.mm58));
      expect(PrinterPaperSize.fromString(null), equals(PrinterPaperSize.mm58));
    });

    test('PrinterTextEncoding parser & label', () {
      expect(PrinterTextEncoding.fromString('rasterImage'), equals(PrinterTextEncoding.rasterImage));
      expect(PrinterTextEncoding.fromString('RASTER'), equals(PrinterTextEncoding.rasterImage));
      expect(PrinterTextEncoding.fromString('utf8Direct'), equals(PrinterTextEncoding.utf8Direct));
      expect(PrinterTextEncoding.fromString('UTF8'), equals(PrinterTextEncoding.utf8Direct));
      expect(PrinterTextEncoding.fromString('vietnameseAscii'), equals(PrinterTextEncoding.vietnameseAscii));
      expect(PrinterTextEncoding.fromString('unknown'), equals(PrinterTextEncoding.vietnameseAscii));

      expect(PrinterTextEncoding.vietnameseAscii.label, contains('Không dấu'));
      expect(PrinterTextEncoding.utf8Direct.label, contains('UTF-8'));
      expect(PrinterTextEncoding.rasterImage.label, contains('Raster'));
    });
  });

  group('2. Tạo Byte ESC/POS Hóa Đơn (Bill Receipt ESC/POS Bytes)', () {
    final store = StoreInfoModel(
      storeCode: 'TRAM01',
      storeName: 'Trạm Cà Phê & Trà',
      address: '123 Đường 3/4, Đà Lạt',
      phone: '0901234567',
      wifiName: 'Tram_Coffee_Free',
    );

    final bill = BillModel(
      id: 'B1001',
      billCode: 'HD-1001',
      orderCode: 'OD-1001',
      tableName: 'Bàn 05',
      zone: 'Sân Vườn',
      createdAt: 1771900000000,
      staffUsername: 'thungan01',
      staffFullName: 'Nguyễn Văn Thu Ngân',
      items: [
        OrderItemModel(
          productId: 1,
          name: 'Trà Chanh Giã Tay',
          price: 25000,
          quantity: 2,
          selectedSize: 'L',
          selectedSugar: '70% đường',
          selectedIce: '50% đá',
          note: 'Giao ly giấy',
        ),
        OrderItemModel(
          productId: 2,
          name: 'Cà Phê Muối Đặc Biệt Trạm',
          price: 35000,
          quantity: 1,
        ),
      ],
      subTotal: 85000,
      finalAmount: 85000,
      paymentMethod: 'CASH',
    );

    test('buildBillReceiptBytes khổ 58mm: Chứa đủ các lệnh ESC/POS chuẩn', () {
      final bytes = ReceiptPrinter.buildBillReceiptBytes(
        store: store,
        bill: bill,
        paperSize: PrinterPaperSize.mm58,
        removeAccents: true,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));

      // 1. ESC @ (0x1B, 0x40): Initialize printer
      expect(bytes[0], equals(0x1B));
      expect(bytes[1], equals(0x40));

      // 2. Chứa đường gạch nét đứt 32 ký tự cho khổ 58mm
      final contentAscii = ascii.decode(bytes.where((b) => b >= 32 && b <= 126).toList());
      expect(contentAscii, contains('--------------------------------'));
      expect(contentAscii, contains('================================'));

      // 3. Chứa thông tin quán và hóa đơn (đã lọc dấu tiếng Việt)
      expect(contentAscii, contains('TRAM CA PHE & TRA'));
      expect(contentAscii, contains('HOA DON THANH TOAN'));
      expect(contentAscii, contains('So HD: HD-1001'));
      expect(contentAscii, contains('Ban: Ban 05 (San Vuon)'));
      expect(contentAscii, contains('Thu ngan: Nguyen Van Thu Ngan'));

      // 4. Lệnh cắt giấy GS V B 0 (0x1D, 0x56, 0x42, 0x00) ở cuối mảng byte
      final len = bytes.length;
      expect(bytes[len - 4], equals(0x1D));
      expect(bytes[len - 3], equals(0x56));
      expect(bytes[len - 2], equals(0x42));
      expect(bytes[len - 1], equals(0x00));
    });

    test('buildBillReceiptBytes khổ 80mm: Đường phân cách 48 ký tự', () {
      final bytes = ReceiptPrinter.buildBillReceiptBytes(
        store: store,
        bill: bill,
        paperSize: PrinterPaperSize.mm80,
        removeAccents: true,
      );

      final contentAscii = ascii.decode(bytes.where((b) => b >= 32 && b <= 126).toList());
      expect(contentAscii, contains('------------------------------------------------'));
      expect(contentAscii, contains('================================================'));
    });

    test('buildBillReceiptBytes với isPrePrint = true sinh tiêu đề PHIEU TAM TINH', () {
      final bytesPrePrint = ReceiptPrinter.buildBillReceiptBytes(
        store: store,
        bill: bill,
        isPrePrint: true,
      );
      final text = ascii.decode(bytesPrePrint.where((b) => b >= 32 && b <= 126).toList());
      expect(text, contains('PHIEU TAM TINH'));
    });

    test('buildBillReceiptBytes hỗ trợ UTF-8 khi removeAccents = false', () {
      final bytesUtf8 = ReceiptPrinter.buildBillReceiptBytes(
        store: store,
        bill: bill,
        removeAccents: false,
      );
      final utf8Text = utf8.decode(bytesUtf8, allowMalformed: true);
      expect(utf8Text, contains('HÓA ĐƠN THANH TOÁN'));
      expect(utf8Text, contains('Trà Chanh Giã Tay'));
    });
  });

  group('3. Tạo Byte ESC/POS Phiếu Báo Bếp (Kitchen Order ESC/POS Bytes)', () {
    final kitchenOrder = KitchenOrderModel(
      tableName: 'Bàn VIP 02',
      orderCode: 'OD-2026-99',
      itemsJson: jsonEncode([
        {
          'productId': 10,
          'name': 'Lẩu Thái Hải Sản',
          'price': 220000,
          'quantity': 1,
          'note': 'Ăn cay nhiều, thêm nấm',
        },
        {
          'productId': 11,
          'name': 'Bò Nhúng Dấm',
          'price': 180000,
          'quantity': 2,
          'selectedSize': 'Lớn',
          'note': '',
        },
      ]),
      timestamp: 1771905000000,
      note: 'Khách ăn liền, ưu tiên làm trước!',
    );

    test('buildKitchenOrderReceiptBytes khổ 58mm: Đủ thông tin bếp và lệnh cắt giấy', () {
      final bytes = ReceiptPrinter.buildKitchenOrderReceiptBytes(
        kitchenOrder: kitchenOrder,
        paperSize: PrinterPaperSize.mm58,
        removeAccents: true,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(80));

      final text = ascii.decode(bytes.where((b) => b >= 32 && b <= 126).toList());
      expect(text, contains('PHIEU BAO BEP'));
      expect(text, contains('BAN: BAN VIP 02'));
      expect(text, contains('Ma don: OD-2026-99'));
      expect(text, contains('Lau Thai Hai San'));
      expect(text, contains('x1'));
      expect(text, contains('* An cay nhieu, them nam'));
      expect(text, contains('Bo Nhung Dam'));
      expect(text, contains('x2'));
      expect(text, contains('Ghi chu don: Khach an lien, uu tien lam truoc!'));

      // Kiểm tra lệnh cắt giấy
      final len = bytes.length;
      expect(bytes[len - 4], equals(0x1D));
      expect(bytes[len - 3], equals(0x56));
      expect(bytes[len - 2], equals(0x42));
      expect(bytes[len - 1], equals(0x00));
    });

    test('buildKitchenOrderReceiptBytes khổ 80mm: Chiều rộng 48 ký tự', () {
      final bytes80 = ReceiptPrinter.buildKitchenOrderReceiptBytes(
        kitchenOrder: kitchenOrder,
        paperSize: PrinterPaperSize.mm80,
        removeAccents: true,
      );

      final text = ascii.decode(bytes80.where((b) => b >= 32 && b <= 126).toList());
      expect(text, contains('------------------------------------------------'));
    });
  });

  group('4. Đồ Họa Raster Bitmap (GS v 0) Hỗ Trợ Tiếng Việt Có Dấu', () {
    test('monochromeToEscPosRaster tạo đúng mã lệnh GS v 0', () {
      // Giả lập ma trận 384x16 điểm ảnh (58mm, 16 hàng)
      const width = 384;
      const height = 16;
      const widthBytes = width ~/ 8; // 48 bytes
      final monoBytes = Uint8List(widthBytes * height);

      final rasterEscPos = EscPosRasterHelper.monochromeToEscPosRaster(
        monoBytes: monoBytes,
        widthPixels: width,
        heightPixels: height,
        cutPaper: true,
      );

      expect(rasterEscPos, isNotEmpty);

      // ESC @
      expect(rasterEscPos[0], equals(0x1B));
      expect(rasterEscPos[1], equals(0x40));

      // GS v 0 0 xL xH yL yH
      // vị trí bắt đầu GS v 0: sau ESC @ (2 bytes) và ESC a 1 (3 bytes) -> index 5
      expect(rasterEscPos[5], equals(0x1D));
      expect(rasterEscPos[6], equals(0x76));
      expect(rasterEscPos[7], equals(0x30));
      expect(rasterEscPos[8], equals(0x00)); // Mode 0

      // xL = 48, xH = 0
      expect(rasterEscPos[9], equals(48));
      expect(rasterEscPos[10], equals(0));

      // yL = 16, yH = 0
      expect(rasterEscPos[11], equals(16));
      expect(rasterEscPos[12], equals(0));
    });

    test('rgbaToMonochrome chuyển đổi pixel chuẩn xác theo ngưỡng sáng', () {
      // 8 pixel: 4 pixel đầu màu đen (0,0,0,255), 4 pixel sau màu trắng (255,255,255,255)
      final rgba = Uint8List(8 * 4);
      // 4 pixel đen
      for (int i = 0; i < 4; i++) {
        rgba[i * 4 + 0] = 0;
        rgba[i * 4 + 1] = 0;
        rgba[i * 4 + 2] = 0;
        rgba[i * 4 + 3] = 255;
      }
      // 4 pixel trắng
      for (int i = 4; i < 8; i++) {
        rgba[i * 4 + 0] = 255;
        rgba[i * 4 + 1] = 255;
        rgba[i * 4 + 2] = 255;
        rgba[i * 4 + 3] = 255;
      }

      final mono = EscPosRasterHelper.rgbaToMonochrome(
        rgbaBytes: rgba,
        width: 8,
        height: 1,
      );

      expect(mono.length, equals(1));
      // 4 bit đầu là 1 (đen), 4 bit sau là 0 (trắng) -> 11110000b = 0xF0 = 240
      expect(mono[0], equals(0xF0));
    });

    test('buildTestReceiptBytes tạo dữ liệu in thử hợp lệ cho cả hóa đơn và bếp', () {
      final billTest = ReceiptPrinter.buildTestReceiptBytes(
        storeName: 'Trạm Test',
        paperSize: PrinterPaperSize.mm58,
        isKitchen: false,
      );
      expect(billTest, isNotEmpty);
      expect(billTest.length, greaterThan(100));

      final kitchenTest = ReceiptPrinter.buildTestReceiptBytes(
        storeName: 'Trạm Test',
        paperSize: PrinterPaperSize.mm58,
        isKitchen: true,
      );
      expect(kitchenTest, isNotEmpty);
      expect(kitchenTest.length, greaterThan(100));
    });
  });

  group('5. Hàng Đợi In Lại (Print Queue Resilience)', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await PrintQueueService.instance.init();
      await PrintQueueService.instance.clearAll();
    });

    test('PrintJob model serialization & deserialization đầy đủ dữ liệu', () {
      final originalJob = PrintJob(
        id: 'job-12345',
        title: 'Hóa đơn: HD-999',
        type: 'BILL',
        bytes: Uint8List.fromList([0x1B, 0x40, 0x0A]),
        createdAt: 1771910000000,
        status: PrintJobStatus.failed,
        errorMessage: 'Máy in mất kết nối hoặc hết giấy.',
        retryCount: 2,
        tableName: 'Bàn 12',
        orderCode: 'OD-999',
        billCode: 'HD-999',
      );

      final map = originalJob.toMap();
      final restoredJob = PrintJob.fromMap(map);

      expect(restoredJob.id, equals(originalJob.id));
      expect(restoredJob.title, equals(originalJob.title));
      expect(restoredJob.type, equals(originalJob.type));
      expect(restoredJob.bytes, equals(originalJob.bytes));
      expect(restoredJob.createdAt, equals(originalJob.createdAt));
      expect(restoredJob.status, equals(PrintJobStatus.failed));
      expect(restoredJob.errorMessage, equals(originalJob.errorMessage));
      expect(restoredJob.retryCount, equals(2));
      expect(restoredJob.tableName, equals('Bàn 12'));
      expect(restoredJob.orderCode, equals('OD-999'));
      expect(restoredJob.billCode, equals('HD-999'));
    });

    test('enqueueAndPrint bảo lưu phiếu trong hàng đợi khi in thất bại (Phiếu không bị mất)', () async {
      final queue = PrintQueueService.instance;
      expect(queue.jobs.length, equals(0));

      // Thực thi enqueue và in (khi chưa kết nối BT máy in, lệnh sẽ trả về false và ghi nhận lỗi)
      final success = await queue.enqueueAndPrint(
        title: 'Hóa đơn: HD-001',
        type: 'BILL',
        bytes: Uint8List.fromList([0x1B, 0x40, 0x0A]),
        tableName: 'Bàn 01',
        billCode: 'HD-001',
      );

      // Kỳ vọng: Quá trình in trả về false vì không có máy in Bluetooth thật
      expect(success, isFalse);

      // QUAN TRỌNG: Phiếu không bị mất, vẫn nằm nguyên vẹn trong hàng đợi
      expect(queue.jobs.length, equals(1));
      final job = queue.jobs.first;
      expect(job.title, equals('Hóa đơn: HD-001'));
      expect(job.status, equals(PrintJobStatus.failed));
      expect(job.retryCount, equals(1));
      expect(job.errorMessage, isNotEmpty);
      expect(queue.failedCount, equals(1));
      expect(queue.failedJobs.length, equals(1));
    });

    test('retryJob tăng số lần thử lại retryCount', () async {
      final queue = PrintQueueService.instance;
      await queue.enqueueAndPrint(
        title: 'Phiếu bếp: Bàn 03',
        type: 'KITCHEN',
        bytes: Uint8List.fromList([0x1B, 0x40]),
      );

      final job = queue.jobs.first;
      expect(job.retryCount, equals(1));

      // Thử in lại
      await queue.retryJob(job.id);
      expect(job.retryCount, equals(2));
    });

    test('Quản lý hàng đợi: removeJob và clearCompletedJobs', () async {
      final queue = PrintQueueService.instance;

      await queue.enqueueAndPrint(
        title: 'Job 1',
        type: 'BILL',
        bytes: Uint8List.fromList([1, 2, 3]),
      );
      await queue.enqueueAndPrint(
        title: 'Job 2',
        type: 'BILL',
        bytes: Uint8List.fromList([4, 5, 6]),
      );

      expect(queue.jobs.length, equals(2));

      // Xóa Job 2
      final job2Id = queue.jobs.first.id;
      await queue.removeJob(job2Id);
      expect(queue.jobs.length, equals(1));

      // Đánh dấu thành công và dọn dẹp
      queue.jobs.first.status = PrintJobStatus.success;
      await queue.clearCompletedJobs();
      expect(queue.jobs.length, equals(0));
    });
  });
}
