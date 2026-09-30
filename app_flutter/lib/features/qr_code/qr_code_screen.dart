// lib/features/qr_code/qr_code_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

class QRCodeScreen extends StatelessWidget {
  final String tableName;
  final String tableZone;

  const QRCodeScreen({
    super.key,
    required this.tableName,
    required this.tableZone,
  });

  String get _qrData =>
      '${AppConstants.onlineOrderWebUrl}/?table=${Uri.encodeComponent(tableName)}&zone=${Uri.encodeComponent(tableZone)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
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
        ),
        title: Text('Mã QR bàn', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined, color: AppColors.textPrimary),
            onPressed: () => _share(context),
            tooltip: 'Chia sẻ',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Table info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.table_restaurant, color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bàn $tableName', style: GoogleFonts.beVietnamPro(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 18,
                      )),
                      Text(tableZone, style: GoogleFonts.beVietnamPro(
                        color: AppColors.textSecondary, fontSize: 13,
                      )),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 24),
          // QR Code
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                QrImageView(
                  data: _qrData,
                  version: QrVersions.auto,
                  size: 220,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Color(0xFF0F1117),
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Color(0xFF0F1117),
                  ),
                ),
                const SizedBox(height: 12),
                Text('Bàn $tableName • $tableZone',
                  style: GoogleFonts.beVietnamPro(
                    color: const Color(0xFF0F1117),
                    fontWeight: FontWeight.w600, fontSize: 14,
                  ), textAlign: TextAlign.center),
              ],
            ),
          ).animate().scale(delay: 200.ms, duration: 400.ms).fadeIn(),
          const SizedBox(height: 24),
          // URL display
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đường dẫn', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textSecondary, fontSize: 12,
                )),
                const SizedBox(height: 6),
                Text(_qrData, style: GoogleFonts.beVietnamPro(
                  color: AppColors.info, fontSize: 13,
                ), overflow: TextOverflow.ellipsis, maxLines: 2),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 16),
          // Instructions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.primary.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('Hướng dẫn sử dụng', style: GoogleFonts.beVietnamPro(
                      color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13,
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                _Instruction('1. In mã QR và đặt lên bàn $tableName'),
                _Instruction('2. Khách hàng quét mã bằng camera điện thoại'),
                _Instruction('3. Khách có thể đặt món hoặc gọi nhân viên'),
                _Instruction('4. Đơn sẽ hiện trong mục "Đơn online"'),
              ],
            ),
          ).animate().fadeIn(delay: 400.ms),
          const SizedBox(height: 24),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  label: Text('Sao chép link', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã sao chép link!', style: GoogleFonts.beVietnamPro()),
                        backgroundColor: AppColors.cardElevated,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: Text('Chia sẻ', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _share(context),
                ),
              ),
            ],
          ).animate().fadeIn(delay: 500.ms),
        ],
      ),
    );
  }

  void _share(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Link đã được sao chép vào clipboard!', style: GoogleFonts.beVietnamPro()),
        backgroundColor: AppColors.cardElevated,
      ),
    );
  }
}

class _Instruction extends StatelessWidget {
  final String text;
  const _Instruction(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: GoogleFonts.beVietnamPro(
        color: AppColors.textSecondary, fontSize: 12,
      )),
    );
  }
}
