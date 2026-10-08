// lib/features/orders/widgets/payment_widgets.dart
//
// Các khối giao diện của bảng thanh toán (bottom sheet) trong OrderCartScreen.
// Chỉ hiển thị – trạng thái và nghiệp vụ thanh toán nằm ở màn hình cha.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';

/// Ô tổng tiền cần thu – cỡ chữ lớn để thu ngân và khách cùng nhìn.
class PaymentTotalHeader extends StatelessWidget {
  final String tableName;
  final int total;
  final String? customerLine;

  const PaymentTotalHeader({super.key, required this.tableName, required this.total, this.customerLine});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Thanh toán • $tableName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              FormatUtils.vnd(total),
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 34, color: Colors.white),
            ),
          ),
          if (customerLine != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.person, size: 16, color: Colors.white70),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    customerLine!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Chọn phương thức: Tiền mặt / VietQR / Hỗn hợp – ô lớn dễ bấm.
class PaymentMethodSelector extends StatelessWidget {
  final String selected; // 'CASH' | 'TRANSFER_QR' | 'SPLIT'
  final ValueChanged<String> onChanged;

  const PaymentMethodSelector({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, IconData icon, String label) {
      final isSel = selected == key;
      return Expanded(
        child: Semantics(
          selected: isSel,
          button: true,
          child: InkWell(
            onTap: () => onChanged(key),
            borderRadius: AppRadius.brMd,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 64,
              decoration: BoxDecoration(
                color: isSel ? AppColors.primaryLight : Colors.white,
                borderRadius: AppRadius.brMd,
                border: Border.all(color: isSel ? AppColors.primary : AppColors.border, width: isSel ? 2 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: isSel ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                      color: isSel ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tile('CASH', Icons.payments_outlined, 'Tiền mặt'),
        const SizedBox(width: 8),
        tile('TRANSFER_QR', Icons.qr_code_2, 'VietQR'),
        const SizedBox(width: 8),
        tile('SPLIT', Icons.call_split, 'Hỗn hợp'),
      ],
    );
  }
}

/// Gợi ý nhanh số tiền khách đưa (đúng tiền + các mệnh giá làm tròn lên).
class QuickCashAmounts extends StatelessWidget {
  final int amountDue;
  final ValueChanged<int> onPick;

  const QuickCashAmounts({super.key, required this.amountDue, required this.onPick});

  static List<int> suggestions(int due) {
    if (due <= 0) return const [];
    final set = <int>{due};
    for (final step in const [10000, 50000, 100000, 200000, 500000]) {
      final rounded = ((due + step - 1) ~/ step) * step;
      if (rounded > due) set.add(rounded);
    }
    final list = set.toList()..sort();
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = suggestions(amountDue);
    if (list.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in list)
          ActionChip(
            label: Text(v == amountDue ? 'Đủ ${FormatUtils.vnd(v)}' : FormatUtils.vnd(v)),
            labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            avatar: v == amountDue ? const Icon(Icons.check, size: 16, color: AppColors.success) : null,
            onPressed: () => onPick(v),
          ),
      ],
    );
  }
}

/// Dòng tiền thừa / khách đưa thiếu.
class ChangeDueRow extends StatelessWidget {
  final int change;
  final int shortBy;
  const ChangeDueRow({super.key, required this.change, this.shortBy = 0});

  @override
  Widget build(BuildContext context) {
    final isShort = shortBy > 0;
    final color = isShort ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isShort ? AppColors.dangerLight : AppColors.successLight,
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isShort ? 'Khách đưa còn thiếu:' : 'Tiền thừa trả khách:',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, color: color),
            ),
          ),
          Text(
            FormatUtils.vnd(isShort ? shortBy : change),
            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 20, color: color),
          ),
        ],
      ),
    );
  }
}

/// Ảnh mã VietQR có trạng thái tải & lỗi (trước đây lỗi mạng hiện ảnh vỡ).
class VietQrImage extends StatelessWidget {
  final String url;
  final double height;
  const VietQrImage({super.key, required this.url, this.height = 220});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.brMd,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(6),
        child: Image.network(
          url,
          height: height,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : SizedBox(height: height, width: height, child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (_, __, ___) => Container(
            height: height,
            width: height,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: AppRadius.brMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: AppColors.danger, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Không tải được mã QR.\nKiểm tra kết nối mạng.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.danger, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Công tắc "In hóa đơn khi thanh toán".
class AutoPrintToggleTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const AutoPrintToggleTile({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: value ? AppColors.primaryLight : AppColors.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: value ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: InkWell(
        borderRadius: AppRadius.brMd,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: value ? AppColors.primary : AppColors.textDisabled,
                  borderRadius: AppRadius.brSm,
                ),
                child: Icon(value ? Icons.print : Icons.print_disabled_outlined, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'In hóa đơn khi thanh toán',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    Text(
                      value ? 'Tự động gửi lệnh in bill ra máy in nhiệt' : 'Tắt in bill (chỉ chốt đơn, không in giấy)',
                      style: GoogleFonts.beVietnamPro(fontSize: 12, color: value ? AppColors.primary : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hộp báo lỗi ngay trong bảng thanh toán (SnackBar bị bottom sheet che khuất).
class PaymentErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const PaymentErrorBox({super.key, required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.danger, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18, color: AppColors.danger),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
