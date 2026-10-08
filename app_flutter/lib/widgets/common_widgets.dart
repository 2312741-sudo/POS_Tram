// lib/widgets/common_widgets.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/format_utils.dart';

// ==================== SECTION HEADER ====================
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? action;

  const SectionHeader({super.key, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.beVietnamPro(
                color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700,
              )),
              if (subtitle != null) Text(subtitle!, style: GoogleFonts.beVietnamPro(
                color: AppColors.textSecondary, fontSize: 12,
              )),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

// ==================== STAT CARD ====================
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.08), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (onTap != null)
                  Icon(Icons.arrow_forward_ios, color: AppColors.textHint, size: 14),
              ],
            ),
            const Spacer(),
            Text(value, style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 4),
            Text(title, style: GoogleFonts.beVietnamPro(
              color: AppColors.textSecondary, fontSize: 12,
            )),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: GoogleFonts.beVietnamPro(
                color: color, fontSize: 11, fontWeight: FontWeight.w600,
              )),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== APP SCREEN WRAPPER ====================
class AppScreen extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showBack;
  final Color? backgroundColor;

  const AppScreen({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showBack = true,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor ?? AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text(title),
        leading: showBack
          ? IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Icon(Icons.arrow_back_ios_new, size: 14, color: AppColors.textPrimary),
              ),
              onPressed: () => Navigator.of(context).pop(),
            )
          : null,
        actions: actions != null ? [...actions!, const SizedBox(width: 8)] : null,
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: body,
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

// ==================== EMPTY STATE ====================
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.textHint, size: 48),
            ),
            const SizedBox(height: 20),
            Text(title, style: GoogleFonts.beVietnamPro(
              color: AppColors.textSecondary, fontSize: 18, fontWeight: FontWeight.w600,
            ), textAlign: TextAlign.center),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: GoogleFonts.beVietnamPro(
                color: AppColors.textHint, fontSize: 13,
              ), textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== LOADING SHIMMER ====================
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

// ==================== ROLE BADGE ====================
class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label = FormatUtils.roleLabel(role);
    switch (role.toUpperCase()) {
      case 'MANAGER': color = AppColors.primary; break;
      case 'KITCHEN': color = AppColors.warning; break;
      default: color = AppColors.info; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(label, style: GoogleFonts.beVietnamPro(
        color: color, fontSize: 12, fontWeight: FontWeight.w600,
      )),
    );
  }
}

// ==================== CONFIRM DIALOG ====================
Future<bool?> showConfirmDialog(BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Xác nhận',
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: GoogleFonts.beVietnamPro(
        color: AppColors.textPrimary, fontWeight: FontWeight.w700,
      )),
      content: Text(message, style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? AppColors.danger : AppColors.primary,
          ),
          child: Text(confirmText, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ==================== MANAGER PIN DIALOG ====================
Future<bool> showManagerPinDialog(BuildContext context, String managerPin) async {
  final ctrl = TextEditingController();
  bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) {
        bool wrong = false;
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: AppColors.warning, size: 24),
              const SizedBox(width: 10),
              Text('Xác nhận Quản lý', style: GoogleFonts.beVietnamPro(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17,
              )),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nhập PIN quản lý để xác nhận hành động này',
                style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 8, fontSize: 20),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '• • • •',
                  hintStyle: TextStyle(color: AppColors.textHint),
                  counterText: '',
                  errorText: wrong ? 'PIN không đúng!' : null,
                ),
                onSubmitted: (v) {
                  if (v == managerPin) Navigator.pop(ctx, true);
                  else setSt(() => wrong = true);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                if (ctrl.text == managerPin) Navigator.pop(ctx, true);
                else setSt(() {});
              },
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    ),
  );
  return result == true;
}
