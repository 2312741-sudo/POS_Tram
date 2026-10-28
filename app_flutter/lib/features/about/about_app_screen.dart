// lib/features/about/about_app_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/share_utils.dart';
import '../../data/models/user_model.dart';
import '../auth/delete_account_dialog.dart';

/// Màn hình Thông tin ứng dụng POS Trạm (About App Screen)
/// Cung cấp thông tin phiên bản, bản quyền, kênh hỗ trợ, pháp lý và tuân thủ Apple App Store Review.
class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const String appVersion = '1.0.3';
  static const String appBuild = '4';
  static const String bundleId = 'com.tramapp.tramFlutter';
  static const String teamId = 'W97CS7VC54';
  static const String hotline = '0865.062.205';
  static const String hotlineRaw = '0865062205';
  static const String supportEmail = 'hotro.postram@gmail.com';
  static const String websiteUrl = 'https://pos-tram.vercel.app';
  static const String privacyUrl = 'https://pos-tram.vercel.app/privacy';
  static const String privacyChoicesUrl = 'https://pos-tram.vercel.app/privacy-choices';
  static const String copyrightOwner = 'Nguyễn Thanh Tâm';
  static const String copyright = '© 2026 Nguyễn Thanh Tâm';

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutAppScreen()),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $text'),
        backgroundColor: context.tc.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final user = auth.currentUser;
    final storeCode = auth.currentStoreCode;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Text(
          'Thông Tin Ứng Dụng',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Chia sẻ thông tin ứng dụng',
            icon: const Icon(Icons.share_outlined),
            onPressed: () {
              shareTextSafe(
                'POS Trạm - Hệ thống Quản lý Bán hàng & Vận hành F&B (v$appVersion+$appBuild)\n'
                'Website: $websiteUrl\n'
                'Hotline hỗ trợ: $hotline',
                subject: 'Thông tin ứng dụng POS Trạm',
                context: context,
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Hero Brand Header
            _buildHeroHeader(context),
            const SizedBox(height: 20),

            // 2. Thẻ phiên làm việc & tài khoản
            _buildSessionCard(context, user, storeCode),
            const SizedBox(height: 16),

            // 3. Thẻ thông số kỹ thuật & phiên bản
            _buildSpecsCard(context),
            const SizedBox(height: 16),

            // 4. Thẻ kênh hỗ trợ & Hotline
            _buildSupportCard(context),
            const SizedBox(height: 16),

            // 5. Thẻ chính sách pháp lý & Apple Guidelines
            _buildLegalCard(context),
            const SizedBox(height: 16),

            // 6. Thẻ tính năng nổi bật
            _buildFeaturesCard(context),
            const SizedBox(height: 24),

            // Footer Copyright
            Center(
              child: Text(
                '$copyright • POS Trạm\nBảo lưu mọi quyền',
                textAlign: TextAlign.center,
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  color: context.tc.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    return Card(
      elevation: 1,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Logo / Icon
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 76,
                  height: 76,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/logo.jpg',
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: context.tc.primary,
                      child: const Icon(
                        Icons.restaurant_menu,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // App Name
            Text(
              'POS TRẠM',
              style: GoogleFonts.beVietnamPro(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.tc.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),

            // Subtitle
            Text(
              'Hệ Thống Quản Lý Bán Hàng & Vận Hành F&B',
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.tc.textSecondary,
              ),
            ),
            const SizedBox(height: 12),

            // Version Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: context.tc.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: context.tc.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                'Phiên bản $appVersion (Bản dựng $appBuild)',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.tc.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionCard(BuildContext context, UserModel? user, String storeCode) {
    final fullName = (user?.fullName.isNotEmpty == true)
        ? user!.fullName
        : (user?.username.isNotEmpty == true)
            ? user!.username
            : 'Khách';
    final username = (user?.username.isNotEmpty == true)
        ? user!.username
        : '—';
    final role = user != null ? FormatUtils.roleLabel(user.roleId) : 'Nhân viên';

    return Card(
      elevation: 0.8,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.badge_outlined, size: 20, color: context.tc.primary),
                const SizedBox(width: 8),
                Text(
                  'Phiên Làm Việc Hiện Tại',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildInfoRow(context, 'Tài khoản đăng nhập', fullName),
            const Divider(height: 18),
            _buildInfoRow(context, 'Tên đăng nhập', username, isMonospace: true),
            const Divider(height: 18),
            _buildInfoRow(context, 'Vai trò phân quyền', role),
            const Divider(height: 18),
            _buildInfoRow(context, 'Mã chi nhánh', storeCode.isEmpty ? 'Chưa chọn' : storeCode, isHighlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecsCard(BuildContext context) {
    return Card(
      elevation: 0.8,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.developer_board_outlined, size: 20, color: context.tc.primary),
                const SizedBox(width: 8),
                Text(
                  'Thông Số Kỹ Thuật Ứng Dụng',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildInfoRow(context, 'Phiên bản (App Version)', appVersion),
            const Divider(height: 18),
            _buildInfoRow(context, 'Số hiệu bản dựng (Build)', appBuild),
            const Divider(height: 18),
            _buildInfoRow(context, 'Apple Bundle Identifier', bundleId, isMonospace: true),
            const Divider(height: 18),
            _buildInfoRow(context, 'Apple Team Identifier', teamId, isMonospace: true),
            const Divider(height: 18),
            _buildInfoRow(context, 'Đồng bộ dữ liệu', 'Firebase Realtime (Trực tuyến)'),
            const Divider(height: 18),
            _buildInfoRow(context, 'Bản quyền phát hành', copyright, isHighlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportCard(BuildContext context) {
    return Card(
      elevation: 0.8,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.support_agent_outlined, size: 20, color: context.tc.primary),
                const SizedBox(width: 8),
                Text(
                  'Hỗ Trợ Kỹ Thuật & Khẩn Cấp',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Hotline item
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.tc.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.phone, size: 18, color: context.tc.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hotline Khẩn Cấp 24/7',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                      ),
                      Text(
                        hotline,
                        style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w700, color: context.tc.primary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép Hotline',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyToClipboard(context, hotlineRaw, 'Hotline'),
                ),
              ],
            ),
            const Divider(height: 18),

            // Email item
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.tc.info.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.email_outlined, size: 18, color: context.tc.info),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hòm Thư Kỹ Thuật',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                      ),
                      Text(
                        supportEmail,
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: context.tc.textPrimary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép Email',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () => _copyToClipboard(context, supportEmail, 'Email'),
                ),
              ],
            ),
            const Divider(height: 18),

            // Working hours
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.tc.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.schedule, size: 18, color: context.tc.success),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Khung Giờ Hỗ Trợ Trực',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                      ),
                      Text(
                        '08:00 – 22:00 (Hàng ngày, kể cả Lễ, Tết)',
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalCard(BuildContext context) {
    return Card(
      elevation: 0.8,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: context.tc.primary),
                const SizedBox(width: 8),
                Text(
                  'Pháp Lý & Quyền Riêng Tư',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Privacy Policy link
            Row(
              children: [
                Icon(Icons.privacy_tip_outlined, color: context.tc.primary, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chính Sách Quyền Riêng Tư',
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        privacyUrl,
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép liên kết',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copyToClipboard(context, privacyUrl, 'Liên kết bảo mật'),
                ),
              ],
            ),
            const Divider(height: 18),

            // Privacy Choices link
            Row(
              children: [
                Icon(Icons.tune_outlined, color: context.tc.info, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quyền Lựa Chọn Dữ Liệu Cá Nhân',
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        privacyChoicesUrl,
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sao chép liên kết',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => _copyToClipboard(context, privacyChoicesUrl, 'Liên kết quyền dữ liệu'),
                ),
              ],
            ),
            const Divider(height: 18),

            // Account deletion (Apple 5.1.1)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.no_accounts_outlined, color: context.tc.danger, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xóa Tài Khoản Của Tôi',
                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700, color: context.tc.danger),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tuân thủ Apple Guideline 5.1.1(v). Xóa vĩnh viễn tài khoản và đăng xuất khỏi máy.',
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => DeleteAccountDialog.start(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.tc.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.tc.danger.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Xóa',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: context.tc.danger,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesCard(BuildContext context) {
    final features = [
      'Sơ đồ phòng bàn thông minh thời gian thực',
      'Báo bếp / Pha chế KDS tự động & In nhiệt ESC/POS',
      'Thanh toán động VietQR Napas247 chính xác 100%',
      'Quản lý ca két, chốt két & kiểm soát thất thoát',
      'Chiến dịch khuyến mãi, voucher & tích điểm KMT',
      'Đồng bộ hệ sinh thái Chấm Công Trạm',
    ];

    return Card(
      elevation: 0.8,
      color: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, size: 20, color: context.tc.primary),
                const SizedBox(width: 8),
                Text(
                  'Hệ Sinh Thái Tính Năng POS Trạm',
                  style: GoogleFonts.beVietnamPro(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.tc.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...features.map(
              (f) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, size: 16, color: context.tc.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 13,
                          color: context.tc.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    bool isMonospace = false,
    bool isHighlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            color: context.tc.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: isMonospace
                ? TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
                    color: isHighlight ? context.tc.primary : context.tc.textPrimary,
                  )
                : GoogleFonts.beVietnamPro(
                    fontSize: 13,
                    fontWeight: isHighlight ? FontWeight.w800 : FontWeight.w600,
                    color: isHighlight ? context.tc.primary : context.tc.textPrimary,
                  ),
          ),
        ),
      ],
    );
  }
}
