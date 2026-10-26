// lib/features/qr_code/qr_code_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/firebase_service.dart';

class QRCodeScreen extends StatelessWidget {
  final String tableName;
  final String tableZone;

  const QRCodeScreen({
    super.key,
    required this.tableName,
    required this.tableZone,
  });

  String get _currentStoreCode {
    final authStore = AuthService().currentStoreCode;
    if (authStore.isNotEmpty) return authStore;
    final fbStore = FirebaseService().currentStoreCode;
    return fbStore.isNotEmpty ? fbStore : 'TRAM01';
  }

  String get _qrData {
    String cleanBase = AppConstants.onlineOrderWebUrl.trim();
    while (cleanBase.endsWith('/')) {
      cleanBase = cleanBase.substring(0, cleanBase.length - 1);
    }
    final path = cleanBase.endsWith('/order') ? cleanBase : '$cleanBase/order';
    return '$path?table=${Uri.encodeComponent(tableName)}&zone=${Uri.encodeComponent(tableZone)}&store=${Uri.encodeComponent(_currentStoreCode)}';
  }

  void _share(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _qrData));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: context.tc.primary,
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Link đã được sao chép vào clipboard!',
                style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: context.tc.card,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.tc.border),
            ),
            child: Icon(Icons.arrow_back_ios_new, size: 14, color: context.tc.textPrimary),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Mã QR bàn', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontSize: 17, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: Icon(Icons.share_outlined, color: context.tc.textPrimary),
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
              color: context.tc.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.tc.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: context.tc.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.table_restaurant, color: context.tc.primary, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bàn $tableName', style: GoogleFonts.beVietnamPro(
                        color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 18,
                      )),
                      Text('$tableZone • Chi nhánh: $_currentStoreCode', style: GoogleFonts.beVietnamPro(
                        color: context.tc.textSecondary, fontSize: 13,
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
                  color: context.tc.primary.withValues(alpha: 0.15),
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
              color: context.tc.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.tc.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đường dẫn gọi món', style: GoogleFonts.beVietnamPro(
                  color: context.tc.textSecondary, fontSize: 12,
                )),
                const SizedBox(height: 6),
                Text(_qrData, style: GoogleFonts.beVietnamPro(
                  color: context.tc.info, fontSize: 13,
                ), overflow: TextOverflow.ellipsis, maxLines: 2),
              ],
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 16),
          // Instructions
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.tc.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.tc.primary.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: context.tc.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('Hướng dẫn sử dụng', style: GoogleFonts.beVietnamPro(
                      color: context.tc.primary, fontWeight: FontWeight.w600, fontSize: 13,
                    )),
                  ],
                ),
                const SizedBox(height: 8),
                _Instruction('1. In mã QR và đặt lên bàn $tableName'),
                const _Instruction('2. Khách hàng quét mã bằng camera điện thoại để xem menu & gọi món'),
                const _Instruction('3. Khách có thể tùy chỉnh size, topping, đường/đá, gọi nhân viên'),
                const _Instruction('4. Khi khách gửi đơn, POS báo chuông và hiển thị trong mục "Đơn online"'),
                const _Instruction('5. Thu ngân bấm "Xác nhận", món tự động đồng bộ vào bàn & chuyển xuống bếp'),
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
                    foregroundColor: context.tc.textPrimary,
                    side: BorderSide(color: context.tc.border),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _qrData));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: context.tc.primary,
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Đã sao chép link!',
                                style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
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
}

class _Instruction extends StatelessWidget {
  final String text;
  const _Instruction(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: GoogleFonts.beVietnamPro(
        color: context.tc.textSecondary, fontSize: 12,
      )),
    );
  }
}
