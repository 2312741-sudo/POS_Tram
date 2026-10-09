// lib/core/theme/theme_mode_controller.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lưu & phát chế độ giao diện (Theo hệ thống / Sáng / Tối) của thiết bị.
///
/// Giá trị lưu cục bộ bằng SharedPreferences (mỗi máy POS tự chọn),
/// không đồng bộ lên Firebase.
class ThemeModeController extends ValueNotifier<ThemeMode> {
  ThemeModeController._() : super(ThemeMode.light);

  static final ThemeModeController instance = ThemeModeController._();

  static const String _prefKey = 'app_theme_mode';

  /// Đọc lựa chọn đã lưu. Mặc định: Sáng (giữ nguyên giao diện cũ).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = _decode(prefs.getString(_prefKey));
    } catch (_) {
      // Không đọc được bộ nhớ cục bộ → giữ chế độ sáng.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (value == mode) return;
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, mode.name);
    } catch (_) {}
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'system':
        return ThemeMode.system;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.light;
    }
  }

  static String label(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'Theo hệ thống';
      case ThemeMode.light:
        return 'Sáng';
      case ThemeMode.dark:
        return 'Tối';
    }
  }
}
