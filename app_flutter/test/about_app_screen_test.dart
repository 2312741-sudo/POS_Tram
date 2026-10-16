// test/about_app_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/features/about/about_app_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget() {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: const AboutAppScreen(),
    );
  }

  group('AboutAppScreen Widget Tests', () {
    testWidgets('hiển thị đầy đủ thông tin tên ứng dụng và phiên bản 1.0.1+2', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tiêu đề AppBar
      expect(find.text('Thông Tin Ứng Dụng'), findsOneWidget);

      // Tên thương hiệu
      expect(find.text('POS TRẠM'), findsOneWidget);

      // Phiên bản và bản dựng
      expect(find.text('Phiên bản 1.0.1 (Bản dựng 2)'), findsOneWidget);

      // Bundle ID & Apple Team
      expect(find.text('com.tramapp.tramFlutter'), findsOneWidget);
      expect(find.text('W97CS7VC54'), findsOneWidget);
    });

    testWidgets('hiển thị đầy đủ kênh hỗ trợ hotline 0865.062.205 và email', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Hotline
      expect(find.text('0865.062.205'), findsOneWidget);

      // Email
      expect(find.text('hotro.postram@gmail.com'), findsOneWidget);

      // Giờ trực
      expect(find.text('08:00 – 22:00 (Hàng ngày, kể cả Lễ, Tết)'), findsOneWidget);
    });

    testWidgets('hiển thị đầy đủ chính sách pháp lý và nút xóa tài khoản', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Pháp lý
      expect(find.text('Chính Sách Quyền Riêng Tư'), findsOneWidget);
      expect(find.text('Quyền Lựa Chọn Dữ Liệu Cá Nhân'), findsOneWidget);

      // Nút xóa tài khoản tuân thủ Apple Guideline 5.1.1(v)
      expect(find.text('Xóa Tài Khoản Của Tôi'), findsOneWidget);
      expect(find.text('Xóa'), findsOneWidget);
    });

    testWidgets('hiển thị danh sách tính năng và bản quyền © 2026 POS Trạm', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tính năng
      expect(find.text('Sơ đồ phòng bàn thông minh thời gian thực'), findsOneWidget);
      expect(find.text('Thanh toán động VietQR Napas247 chính xác 100%'), findsOneWidget);

      // Copyright
      expect(find.textContaining('© 2026 POS Trạm'), findsOneWidget);
    });
  });
}
