// lib/widgets/theme_mode_selector.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_mode_controller.dart';

/// Bộ chọn chế độ giao diện: Theo hệ thống / Sáng / Tối.
/// Lựa chọn lưu trên thiết bị (SharedPreferences) và áp dụng ngay.
class ThemeModeSelector extends StatelessWidget {
  const ThemeModeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeModeController.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: controller,
      builder: (context, mode, _) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ThemeMode.system,
              icon: Icon(Icons.brightness_auto_outlined, size: 18),
              label: Text('Hệ thống'),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              icon: Icon(Icons.light_mode_outlined, size: 18),
              label: Text('Sáng'),
            ),
            ButtonSegment(
              value: ThemeMode.dark,
              icon: Icon(Icons.dark_mode_outlined, size: 18),
              label: Text('Tối'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => controller.setMode(s.first),
        ),
      ),
    );
  }
}

/// Thẻ "Giao diện" dùng trong màn hình cài đặt thiết bị.
class ThemeModeCard extends StatelessWidget {
  const ThemeModeCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.palette_outlined, color: context.tc.primary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Giao diện',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Chọn chế độ sáng/tối cho thiết bị này.',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            const ThemeModeSelector(),
          ],
        ),
      ),
    );
  }
}

/// Hộp thoại chọn chế độ giao diện (dùng từ menu tuỳ chọn).
Future<void> showThemeModeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Giao diện'),
      content: const SizedBox(width: 360, child: ThemeModeSelector()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
      ],
    ),
  );
}
