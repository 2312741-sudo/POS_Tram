// lib/widgets/common_widgets.dart
//
// Bộ widget dùng chung của POS Trạm. Mọi màu/khoảng cách lấy từ
// core/theme/app_theme.dart (TramColors, AppSpacing, AppRadius) để giữ
// giao diện nhất quán giữa các màn hình.
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
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12),
                ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Ink(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.brLg,
            border: Border.all(color: AppColors.borderLight),
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.08), AppColors.card],
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
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  if (onTap != null)
                    const Icon(Icons.arrow_forward_ios, color: AppColors.textHint, size: 14),
                ],
              ),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: GoogleFonts.beVietnamPro(
                    color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== APP SCREEN WRAPPER ====================
/// Khung màn hình chuẩn: AppBar theo theme (nền thương hiệu, chữ trắng),
/// chạm ra ngoài để ẩn bàn phím.
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
        // Trước đây nền kem + chữ trắng của theme => tiêu đề gần như vô hình.
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        automaticallyImplyLeading: showBack,
        leading: showBack && Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Quay lại',
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        actions: actions != null ? [...actions!, const SizedBox(width: AppSpacing.sm)] : null,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.card,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, color: AppColors.textHint, size: 48),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(
                color: AppColors.textSecondary, fontSize: 18, fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle!,
                style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== ERROR STATE ====================
/// Trạng thái lỗi chuẩn (VD: stream Firebase lỗi quyền) kèm nút thử lại tuỳ chọn.
class ErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final VoidCallback? onRetry;
  final Color? foreground;

  const ErrorState({
    super.key,
    this.title = 'Đã xảy ra lỗi',
    this.message,
    this.onRetry,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final fg = foreground ?? AppColors.textPrimary;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: const BoxDecoration(color: AppColors.dangerLight, shape: BoxShape.circle),
                child: const Icon(Icons.cloud_off_rounded, color: AppColors.danger, size: 40),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
              ),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(fontSize: 13, color: fg.withValues(alpha: 0.7), height: 1.4),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: 200,
                  child: OutlinedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử lại'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================== LOADING STATE ====================
class LoadingState extends StatelessWidget {
  final String? message;
  final Color? color;
  const LoadingState({super.key, this.message, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: color),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: color ?? AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

// ==================== INFO BANNER ====================
enum BannerTone { info, success, warning, danger }

/// Băng thông báo ngang (VD: "Đang khóa order do chưa mở ca").
class InfoBanner extends StatelessWidget {
  final String title;
  final String? message;
  final IconData? icon;
  final BannerTone tone;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;
  /// true: băng full-width nền đậm (đầu màn hình); false: hộp bo góc nền nhạt.
  final bool solid;

  const InfoBanner({
    super.key,
    required this.title,
    this.message,
    this.icon,
    this.tone = BannerTone.info,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.solid = false,
  });

  (Color fg, Color bg) get _colors {
    switch (tone) {
      case BannerTone.success:
        return (AppColors.success, AppColors.successLight);
      case BannerTone.warning:
        return (AppColors.warningInk, AppColors.warningLight);
      case BannerTone.danger:
        return (AppColors.danger, AppColors.dangerLight);
      case BannerTone.info:
        return (AppColors.info, AppColors.infoLight);
    }
  }

  IconData get _defaultIcon {
    switch (tone) {
      case BannerTone.success:
        return Icons.check_circle_outline;
      case BannerTone.warning:
        return Icons.warning_amber_rounded;
      case BannerTone.danger:
        return Icons.error_outline;
      case BannerTone.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _colors;
    final textColor = solid ? Colors.white : fg;
    final background = solid ? fg : bg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: solid ? null : AppRadius.brMd,
        border: solid ? null : Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon ?? _defaultIcon, color: textColor, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    message!,
                    style: GoogleFonts.beVietnamPro(color: textColor.withValues(alpha: 0.9), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: AppSpacing.sm),
            TextButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.arrow_forward, size: 16),
              label: Text(actionLabel!),
              style: TextButton.styleFrom(
                backgroundColor: solid ? Colors.white : fg,
                foregroundColor: solid ? fg : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                minimumSize: const Size(0, 40),
                textStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ==================== STATUS BADGE ====================
/// Nhãn trạng thái nhỏ (Trống / Có khách / Đã gửi bếp...).
class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool filled;
  final IconData? icon;
  final double fontSize;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.filled = false,
    this.icon,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: filled ? null : Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: fg),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(fontSize: fontSize, fontWeight: FontWeight.w700, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== QUANTITY STEPPER ====================
/// Bộ tăng/giảm số lượng với vùng chạm >= 40dp (dễ bấm khi bận rộn).
class QuantityStepper extends StatelessWidget {
  final int value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;
  final VoidCallback? onTapValue;
  final String? suffix;
  final double buttonSize;

  const QuantityStepper({
    super.key,
    required this.value,
    this.onDecrement,
    this.onIncrement,
    this.onTapValue,
    this.suffix,
    this.buttonSize = 40,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, VoidCallback? onTap, Color color, String tooltip) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.brSm,
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Icon(icon, size: 20, color: onTap == null ? AppColors.textDisabled : color),
          ),
        ),
      );
    }

    final valueText = Text(
      suffix == null ? '$value' : '$value $suffix',
      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardElevated,
        borderRadius: AppRadius.brSm,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          btn(Icons.remove, onDecrement, AppColors.danger, 'Giảm'),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 28),
            child: onTapValue == null
                ? Center(child: valueText)
                : InkWell(
                    onTap: onTapValue,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Center(child: valueText),
                    ),
                  ),
          ),
          btn(Icons.add, onIncrement, AppColors.primary, 'Tăng'),
        ],
      ),
    );
  }
}

// ==================== AMOUNT ROW ====================
/// Dòng "nhãn ....... số tiền" không bao giờ tràn (nhãn tự xuống dòng/cắt bớt).
class AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool emphasize;
  final double fontSize;

  const AmountRow({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.emphasize = false,
    this.fontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(
                fontSize: fontSize,
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w400,
                color: color ?? (emphasize ? AppColors.textPrimary : AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: GoogleFonts.beVietnamPro(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
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
        color: AppColors.borderLight,
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
      case 'MANAGER':
        color = AppColors.primary;
        break;
      case 'KITCHEN':
        color = AppColors.warningInk;
        break;
      default:
        color = AppColors.info;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: GoogleFonts.beVietnamPro(
        color: color, fontSize: 12, fontWeight: FontWeight.w600,
      )),
    );
  }
}

/// Kiểu nút gọn cho hàng actions của AlertDialog (theme mặc định của
/// ElevatedButton là full-width 52dp nên các nút sẽ bị xếp chồng dọc).
ButtonStyle dialogActionStyle({Color? background}) => ElevatedButton.styleFrom(
      backgroundColor: background,
      minimumSize: const Size(96, 44),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    );

// ==================== CONFIRM DIALOG ====================
Future<bool?> showConfirmDialog(BuildContext context, {
  required String title,
  required String message,
  String confirmText = 'Xác nhận',
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Row(
        children: [
          Icon(
            isDanger ? Icons.warning_amber_rounded : Icons.help_outline,
            color: isDanger ? AppColors.danger : AppColors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(title, style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17,
            )),
          ),
        ],
      ),
      content: Text(message, style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx, false),
          child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogCtx, true),
          style: dialogActionStyle(background: isDanger ? AppColors.danger : AppColors.primary),
          child: Text(confirmText, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

// ==================== MANAGER PIN DIALOG ====================
Future<bool> showManagerPinDialog(BuildContext context, String managerPin) async {
  final ctrl = TextEditingController();
  // Lưu ý: biến trạng thái phải nằm NGOÀI builder, nếu không mỗi lần
  // setState sẽ reset về false và lỗi "PIN không đúng" không bao giờ hiện.
  bool wrong = false;
  final bool? result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSt) {
        void submit() {
          if (ctrl.text == managerPin) {
            Navigator.pop(ctx, true);
          } else {
            setSt(() => wrong = true);
          }
        }

        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.warning, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Xác nhận Quản lý', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 17,
                )),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nhập PIN quản lý để xác nhận hành động này',
                style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: AppColors.textPrimary, letterSpacing: 8, fontSize: 20),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '• • • •',
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  counterText: '',
                  errorText: wrong ? 'PIN không đúng!' : null,
                ),
                onChanged: (_) {
                  if (wrong) setSt(() => wrong = false);
                },
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              style: dialogActionStyle(),
              onPressed: submit,
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    ),
  );
  return result == true;
}
