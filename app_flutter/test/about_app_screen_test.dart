import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/services/auth_service.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/data/models/user_model.dart';
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
    testWidgets('hiển thị đầy đủ thông tin tên ứng dụng và phiên bản 1.0.3+4', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tiêu đề AppBar
      expect(find.text('Thông Tin Ứng Dụng'), findsOneWidget);

      // Tên thương hiệu
      expect(find.text('POS TRẠM'), findsOneWidget);

      // Phiên bản và bản dựng
      expect(find.text('Phiên bản 1.0.3 (Bản dựng 4)'), findsOneWidget);

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

    testWidgets('hiển thị danh sách tính năng và bản quyền © 2026 Nguyễn Thanh Tâm', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Tính năng
      expect(find.text('Sơ đồ phòng bàn thông minh thời gian thực'), findsOneWidget);
      expect(find.text('Thanh toán động VietQR Napas247 chính xác 100%'), findsOneWidget);

      // Copyright
      expect(find.textContaining('© 2026 Nguyễn Thanh Tâm'), findsAtLeastNWidgets(1));
    });

    testWidgets('hiển thị đúng phiên làm việc khi người dùng đã đăng nhập với UserModel', (tester) async {
      final auth = AuthService();
      final mockUser = UserModel(
        uid: 'user_123',
        username: 'thanhtam',
        fullName: 'Nguyễn Thanh Tâm',
        roleId: 'ROLE_OWNER',
        isRootOwner: true,
      );
      auth.setCurrentUserForTesting(mockUser, 'TRAM_TEST');

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      // Kiểm tra tên hiển thị, tên đăng nhập, vai trò đã được format tiếng Việt chuẩn
      expect(find.text('Nguyễn Thanh Tâm'), findsOneWidget);
      expect(find.text('thanhtam'), findsOneWidget);
      expect(find.text('Chủ cửa hàng'), findsOneWidget);
      expect(find.text('TRAM_TEST'), findsOneWidget);

      // Dọn dẹp sau test
      auth.setCurrentUserForTesting(null, '');
    });
  });
}
