// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'data/services/firebase_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('vi_VN', null);
  } catch (_) {}

  // Allow both portrait and landscape (phone & tablet)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  // Kiểm tra tính đồng nhất của cấu hình Firebase khi khởi động
  final options = DefaultFirebaseOptions.currentPlatform;
  final projectId = options.projectId;
  final databaseUrl = options.databaseURL ?? '';
  final isMismatch = databaseUrl.isNotEmpty && !databaseUrl.contains(projectId);

  if (isMismatch) {
    final errorMsg =
        'LỖI CẤU HÌNH DỰ ÁN FIREBASE: projectId ("$projectId") không khớp với project trong databaseURL ("$databaseUrl"). '
        'Vui lòng chạy "flutterfire configure --project=tramapp-36f53" để đồng nhất cấu hình!';
    if (kDebugMode) {
      throw StateError(errorMsg);
    } else {
      runApp(FirebaseConfigErrorApp(
        projectId: projectId,
        databaseUrl: databaseUrl,
      ));
      return;
    }
  }

  // Initialize Firebase
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Safely ignore if already initialized natively
  }

  // Initialize Core Services
  FirebaseService().init();
  await AuthService().checkAutoLogin();

  runApp(const ProviderScope(child: TramApp()));
}

class FirebaseConfigErrorApp extends StatelessWidget {
  final String projectId;
  final String databaseUrl;

  const FirebaseConfigErrorApp({
    super.key,
    required this.projectId,
    required this.databaseUrl,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, size: 72, color: Colors.amber),
                const SizedBox(height: 16),
                const Text(
                  'LỖI CẤU HÌNH DỰ ÁN FIREBASE',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tài khoản xác thực (Auth) thuộc project "$projectId" nhưng cơ sở dữ liệu (Database) trỏ về "$databaseUrl".\n\n'
                  'Vui lòng liên hệ quản trị viên chạy "flutterfire configure --project=tramapp-36f53" để đồng nhất dự án.',
                  style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TramApp extends ConsumerWidget {
  const TramApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'POS Trạm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
    );
  }
}
