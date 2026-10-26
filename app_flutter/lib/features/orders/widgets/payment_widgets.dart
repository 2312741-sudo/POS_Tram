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
      decoration: const BoxDecoration(
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
                color: isSel ? context.tc.primaryLight : context.tc.card,
                borderRadius: AppRadius.brMd,
                border: Border.all(color: isSel ? context.tc.primary : context.tc.border, width: isSel ? 2 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 24, color: isSel ? context.tc.primary : context.tc.textSecondary),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 13,
                      fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                      color: isSel ? context.tc.primary : context.tc.textPrimary,
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
            labelStyle: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: context.tc.textPrimary),
            avatar: v == amountDue ? Icon(Icons.check, size: 16, color: context.tc.success) : null,
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
    final color = isShort ? context.tc.danger : context.tc.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isShort ? context.tc.dangerLight : context.tc.successLight,
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

/// Ảnh mã VietQR có trạng thái tải & lỗi và tính năng chạm để phóng to toàn màn hình.
class VietQrImage extends StatelessWidget {
  final String url;
  final double height;
  final double? width;
  final int? amount;
  final String? bankInfo;
  final String? orderInfo;
  final bool enableZoom;

  const VietQrImage({
    super.key,
    required this.url,
    this.height = 280,
    this.width,
    this.amount,
    this.bankInfo,
    this.orderInfo,
    this.enableZoom = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveWidth = width ?? height;
    final imageWidget = ClipRRect(
      borderRadius: AppRadius.brMd,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(8),
        child: Image.network(
          url,
          height: height,
          width: effectiveWidth,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : SizedBox(height: height, width: effectiveWidth, child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (_, __, ___) => Container(
            height: height,
            width: effectiveWidth,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.tc.dangerLight, borderRadius: AppRadius.brMd),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off, color: context.tc.danger, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Không tải được mã QR.\nKiểm tra kết nối mạng.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.danger, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!enableZoom) return imageWidget;

    return Stack(
      children: [
        InkWell(
          onTap: () => FullScreenQrDialog.show(
            context,
            url: url,
            amount: amount,
            bankInfo: bankInfo,
            orderInfo: orderInfo,
          ),
          borderRadius: AppRadius.brMd,
          child: imageWidget,
        ),
        Positioned(
          right: 6,
          bottom: 6,
          child: InkWell(
            onTap: () => FullScreenQrDialog.show(
              context,
              url: url,
              amount: amount,
              bankInfo: bankInfo,
              orderInfo: orderInfo,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in, color: Colors.white, size: 13),
                  const SizedBox(width: 3),
                  Text(
                    'Phóng to',
                    style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Hộp thoại phóng to mã VietQR toàn màn hình với độ tương phản cao, số tiền to rõ.
class FullScreenQrDialog extends StatelessWidget {
  final String url;
  final int? amount;
  final String? bankInfo;
  final String? orderInfo;

  const FullScreenQrDialog({
    super.key,
    required this.url,
    this.amount,
    this.bankInfo,
    this.orderInfo,
  });

  static Future<void> show(
    BuildContext context, {
    required String url,
    int? amount,
    String? bankInfo,
    String? orderInfo,
  }) {
    return showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => FullScreenQrDialog(
        url: url,
        amount: amount,
        bankInfo: bankInfo,
        orderInfo: orderInfo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final qrSize = (size.width * 0.85).clamp(280.0, 360.0);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.qr_code_2, color: Color(0xFF2563EB), size: 20),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Quét mã VietQR',
                        style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (amount != null && amount! > 0) ...[
                Text(
                  'Số tiền thanh toán',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 2),
                Text(
                  FormatUtils.vnd(amount!),
                  style: GoogleFonts.beVietnamPro(fontSize: 30, fontWeight: FontWeight.w900, color: const Color(0xFF2563EB)),
                ),
                const SizedBox(height: 12),
              ],

              // Ảnh QR cỡ lớn
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4))],
                ),
                child: Image.network(
                  url,
                  width: qrSize,
                  height: qrSize,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) => progress == null
                      ? child
                      : SizedBox(width: qrSize, height: qrSize, child: const Center(child: CircularProgressIndicator())),
                  errorBuilder: (_, __, ___) => SizedBox(
                    width: qrSize,
                    height: qrSize,
                    child: const Center(child: Text('Không tải được mã QR', style: TextStyle(color: Colors.red))),
                  ),
                ),
              ),

              if (bankInfo != null && bankInfo!.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    bankInfo!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.beVietnamPro(fontSize: 12.5, fontWeight: FontWeight.w700, color: const Color(0xFF334155)),
                  ),
                ),
              ],

              const SizedBox(height: 14),
              const PaymentBotWatchingBox(),
            ],
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
      color: value ? context.tc.primaryLight : context.tc.cardElevated,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.brMd,
        side: BorderSide(color: value ? context.tc.primary.withValues(alpha: 0.4) : context.tc.border),
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
                  color: value ? context.tc.primary : context.tc.textDisabled,
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
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: context.tc.textPrimary),
                    ),
                    Text(
                      value ? 'Tự động gửi lệnh in bill ra máy in nhiệt' : 'Tắt in bill (chỉ chốt đơn, không in giấy)',
                      style: GoogleFonts.beVietnamPro(fontSize: 12, color: value ? context.tc.primary : context.tc.textSecondary),
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
        color: context.tc.dangerLight,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: context.tc.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.error_outline, color: context.tc.danger, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.danger, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            tooltip: 'Đóng',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 18, color: context.tc.danger),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

/// Hộp trạng thái "Trạm Payment Bot đang dò tiền vào..." dưới mã QR.
class PaymentBotWatchingBox extends StatelessWidget {
  const PaymentBotWatchingBox({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.tc.successLight,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: context.tc.success.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.success),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Trạm Payment Bot đang dò tiền vào... Khi khách quét xong, hóa đơn sẽ tự đóng & in bill ngay lập tức.',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.success, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
