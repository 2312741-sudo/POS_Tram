// test/theme_mode_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/core/theme/theme_mode_controller.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeController', () {
    test('mặc định là Sáng khi chưa lưu lựa chọn', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeModeController.instance.load();
      expect(ThemeModeController.instance.value, ThemeMode.light);
    });

    test('lưu và đọc lại chế độ Tối / Theo hệ thống', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeModeController.instance.setMode(ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_theme_mode'), 'dark');

      SharedPreferences.setMockInitialValues({'app_theme_mode': 'system'});
      await ThemeModeController.instance.load();
      expect(ThemeModeController.instance.value, ThemeMode.system);
      await ThemeModeController.instance.setMode(ThemeMode.light);
    });
  });

  group('TramTokens dark palette', () {
    const t = TramTokens.dark;

    test('chữ chính/phụ đạt tương phản AA trên nền thẻ tối', () {
      expect(_contrast(t.textPrimary, t.card), greaterThan(7));
      expect(_contrast(t.textSecondary, t.card), greaterThan(4.5));
    });

    test('màu trạng thái đọc được trên nền tối và giữ chữ trắng trên nút', () {
      for (final c in [t.primary, t.success, t.danger, t.info]) {
        expect(_contrast(c, t.card), greaterThan(3), reason: '$c trên nền thẻ');
        expect(_contrast(Colors.white, c), greaterThan(3.5), reason: 'chữ trắng trên $c');
      }
      expect(_contrast(t.warningInk, t.warningLight), greaterThan(4.5));
      expect(_contrast(t.primaryDark, t.primaryLight), greaterThan(4.5));
    });

    test('darkTint giữ nền tối cho màu nhạt bất kỳ', () {
      for (final c in [Colors.amber.shade50, Colors.red.shade50, Colors.white, const Color(0xFFEFF6FF)]) {
        final tinted = TramTokens.darkTint(c, 0.17);
        expect(_contrast(t.textPrimary, tinted), greaterThan(7), reason: '$c');
      }
    });
  });
}
