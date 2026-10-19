// test/printer_lan_test.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tram_flutter/core/printer/printer_types.dart';
import 'package:tram_flutter/core/printer/receipt_printer.dart';
import 'package:tram_flutter/core/printer/print_queue_service.dart';
import 'package:tram_flutter/features/printer/printer_settings_screen.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'tram_pos_printer_type': 'LAN',
      'tram_pos_lan_bill_printer_ip': '192.168.1.201',
      'tram_pos_lan_kitchen_printer_ip': '192.168.1.200',
      'tram_pos_auto_print_bill': true,
    });
  });

  group('LAN Printer IP & Connection Tests', () {
    test('testLanConnection trả về false với IP rỗng', () async {
      final res = await ReceiptPrinter.testLanConnection(printerIp: '   ');
      expect(res, isFalse);
    });

    test('testLanConnection trả về false với IP không tới được', () async {
      final res = await ReceiptPrinter.testLanConnection(
        printerIp: '127.0.0.1',
        port: 59998,
        timeout: const Duration(milliseconds: 100),
      );
      expect(res, isFalse);
    });

    test('PrintQueueService clearFailedJobs dọn dẹp các phiếu lỗi', () async {
      final queue = PrintQueueService.instance;
      await queue.init();

      // Thêm job lỗi
      await queue.enqueueAndPrint(
        title: 'Phiếu lỗi test',
        type: 'TEST',
        bytes: Uint8List.fromList([0x1B, 0x40]),
      );

      expect(queue.failedCount, greaterThanOrEqualTo(1));

      // Dọn dẹp
      await queue.clearFailedJobs();
      expect(queue.failedCount, equals(0));
    });
  });

  group('PrinterSettingsScreen Widget Tests', () {
    testWidgets('Giao diện Cài đặt máy in hiển thị đầy đủ cấu hình IP mạng LAN', (tester) async {
      tester.view.physicalSize = const Size(390, 844); // iPhone 12/13/14
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const PrinterSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề AppBar
      expect(find.text('Cài Đặt Máy In'), findsOneWidget);

      // Kiểm tra bộ chọn chế độ (Segmented control)
      expect(find.text('Mạng LAN / Wi-Fi'), findsOneWidget);
      expect(find.text('Bluetooth'), findsOneWidget);

      // Kiểm tra các trường nhập IP
      expect(find.text('IP Máy In Hóa Đơn (Thu Ngân)'), findsOneWidget);
      expect(find.text('IP Máy In Bếp / Pha Chế (Tùy chọn)'), findsOneWidget);

      // Kiểm tra các nút kiểm tra IP & lưu cài đặt
      expect(find.text('Lưu Cài Đặt Máy In LAN'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('In Thử Hóa Đơn'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('In Thử Hóa Đơn'), findsOneWidget);
      expect(find.text('In Thử Phiếu Bếp'), findsOneWidget);

      // Kiểm tra không có lỗi tràn màn hình (RenderFlex overflow)
      expect(tester.takeException(), isNull);
    });
  });
}
