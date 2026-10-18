import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/features/splash/splash_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestWidget() {
    final router = GoRouter(
      initialLocation: '/splash',
      routes: [
        GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login Screen'))),
        GoRoute(path: '/tables', builder: (_, __) => const Scaffold(body: Text('Tables Screen'))),
      ],
    );
    return MaterialApp.router(
      theme: AppTheme.lightTheme,
      routerConfig: router,
    );
  }

  group('SplashScreen Widget Tests', () {
    testWidgets('hiển thị logo, tên ứng dụng POS Trạm, khẩu hiệu và spinner rồi điều hướng', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Tên ứng dụng
      expect(find.text('POS Trạm'), findsOneWidget);

      // Khẩu hiệu thương hiệu
      expect(find.text('Luôn tươi ngon vì sức khỏe'), findsOneWidget);

      // Spinner tải trang
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Logo Image container
      expect(find.byType(Image), findsOneWidget);

      // Sau khi timer hoàn tất, điều hướng tới Login Screen
      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pumpAndSettle();
      expect(find.text('Login Screen'), findsOneWidget);
    });
  });
}
