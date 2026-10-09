// lib/features/chamcong/chamcong_link_screen.dart
// Màn "Liên kết Chấm Công Trạm" (chỉ Chủ quán): liên kết cửa hàng POS hiện tại với
// cửa hàng trên ứng dụng Chấm Công Trạm để nhân viên đăng nhập POS bằng tài khoản chấm công.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/chamcong_auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import 'chamcong_sign_in_sheet.dart';

class ChamCongLinkScreen extends StatefulWidget {
  const ChamCongLinkScreen({super.key});

  @override
  State<ChamCongLinkScreen> createState() => _ChamCongLinkScreenState();
}

class _ChamCongLinkScreenState extends State<ChamCongLinkScreen> {
  final _auth = AuthService();
  final _svc = ChamCongAuthService();

  ChamCongLinkStatus? _status;
  bool _loading = true;
  bool _busy = false;
  bool _configured = false;
  String? _error;

  String get _storeCode => _auth.currentStoreCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final configured = await _svc.isConfigured();
    try {
      final status = await _svc.getLinkStatus(_storeCode);
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _status = status;
        _loading = false;
      });
    } on ChamCongAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _configured = configured;
        _error = 'Không tải được trạng thái liên kết: $e';
        _loading = false;
      });
    }
  }

  Future<void> _link() async {
    final result = await showChamCongSignInSheet<ChamCongLinkResponse>(
      context,
      title: 'Đăng nhập Chấm Công Trạm (Chủ quán)',
      subtitle: 'Đăng nhập bằng tài khoản CHỦ cửa hàng trên ứng dụng Chấm Công Trạm để liên kết với cửa hàng POS $_storeCode.',
      onSubmit: (req) => _svc.linkStore(
        req,
        storeCode: _storeCode,
        pickWorkplace: (stores) => pickChamCongWorkplace(context, stores),
      ),
    );
    if (result == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Đã liên kết với cửa hàng chấm công "${result.chamCongStoreName.isEmpty ? result.chamCongStoreId : result.chamCongStoreName}".'),
      backgroundColor: context.tc.success,
    ));
    _load();
  }

  Future<void> _unlink() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.tc.card,
        title: const Text('Hủy liên kết Chấm Công Trạm?'),
        content: const Text(
          'Nhân viên sẽ không thể đăng nhập POS bằng tài khoản chấm công nữa. '
          'Các tài khoản POS đã tạo vẫn được giữ lại (có thể khóa trong Quản lý nhân viên).',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Không')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.tc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hủy liên kết'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final wasLinked = await _svc.unlinkStore(_storeCode);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(wasLinked ? 'Đã hủy liên kết Chấm Công Trạm.' : 'Cửa hàng hiện không liên kết Chấm Công Trạm.')));
      await _load();
    } on ChamCongAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: context.tc.danger));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.tc.textSecondary),
          const SizedBox(width: 10),
          Text('$label: ', style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
          Expanded(
            child: Text(value,
                style: GoogleFonts.beVietnamPro(
                    fontSize: 13, fontWeight: FontWeight.w600, color: context.tc.textPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final linked = status?.linked ?? false;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Text('Liên kết Chấm Công Trạm', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Làm mới', onPressed: _loading ? null : _load),
        ],
      ),
      body: !_auth.isOwner
          ? Center(
              child: Text('Chỉ Chủ quán mới được quản lý liên kết Chấm Công Trạm.',
                  style: TextStyle(color: context.tc.textSecondary)))
          : _loading
              ? Center(child: CircularProgressIndicator(color: context.tc.primary))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (!_configured)
                              _banner(
                                icon: Icons.info_outline,
                                color: context.tc.warning,
                                bg: context.tc.warningLight,
                                ink: context.tc.warningInk,
                                text: 'Thiết bị này chưa được cấu hình Firebase Chấm Công Trạm nên không thể đăng nhập '
                                    'tài khoản chấm công để liên kết. Vẫn có thể xem trạng thái và hủy liên kết.',
                              ),
                            if (_error != null)
                              _banner(
                                icon: Icons.error_outline,
                                color: context.tc.danger,
                                bg: context.tc.dangerLight,
                                ink: context.tc.danger,
                                text: _error!,
                              ),
                            Card(
                              color: context.tc.card,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(color: context.tc.border),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(linked ? Icons.link : Icons.link_off,
                                            color: linked ? context.tc.success : context.tc.textSecondary),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            linked ? 'Đã liên kết' : 'Chưa liên kết',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: linked ? context.tc.success : context.tc.textPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    _infoRow(Icons.storefront_outlined, 'Cửa hàng POS', _storeCode),
                                    if (linked) ...[
                                      _infoRow(Icons.badge_outlined, 'Cửa hàng chấm công',
                                          status?.chamCongStoreName ?? status?.chamCongStoreId ?? '—'),
                                      if (status?.linkedAt != null)
                                        _infoRow(Icons.schedule, 'Liên kết lúc', FormatUtils.dateTime(status!.linkedAt!)),
                                      _infoRow(Icons.group_outlined, 'Tài khoản đã tự cấp',
                                          '${status?.provisionedCount ?? 0} nhân viên'),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            _banner(
                              icon: Icons.lightbulb_outline,
                              color: context.tc.info,
                              bg: context.tc.infoLight,
                              ink: context.tc.textPrimary,
                              text: 'Sau khi liên kết, nhân viên đang hoạt động trong cửa hàng chấm công có thể bấm '
                                  '"Đăng nhập bằng Chấm Công Trạm" ở màn đăng nhập POS. Tài khoản POS được tạo tự động '
                                  'với vai trò Phục vụ — Chủ quán có thể nâng quyền trong Quản lý nhân viên, nhưng chỉ lên các vai trò '
                                  'nhân viên (Thu ngân, Bếp…). Người là nhân viên bên Chấm Công không thể giữ vai trò Chủ quán/Quản lý '
                                  'trên POS (máy chủ tự hạ quyền mỗi lần đăng nhập) — muốn làm Quản lý phải đổi vai trò bên Chấm Công.',
                            ),
                            const SizedBox(height: 16),
                            if (!linked)
                              SizedBox(
                                height: 50,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: context.tc.primary,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: (_busy || !_configured || _error != null) ? null : _link,
                                  icon: const Icon(Icons.link, color: Colors.white),
                                  label: Text('Liên kết',
                                      style: GoogleFonts.beVietnamPro(
                                          fontWeight: FontWeight.bold, color: Colors.white)),
                                ),
                              )
                            else
                              SizedBox(
                                height: 50,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: context.tc.danger,
                                    side: BorderSide(color: context.tc.danger),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _busy ? null : _unlink,
                                  icon: _busy
                                      ? SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.danger))
                                      : const Icon(Icons.link_off),
                                  label: Text('Hủy liên kết',
                                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required Color bg,
    required Color ink,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.beVietnamPro(fontSize: 13, color: ink, height: 1.4))),
        ],
      ),
    );
  }
}
