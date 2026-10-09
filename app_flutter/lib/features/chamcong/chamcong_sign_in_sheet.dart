// lib/features/chamcong/chamcong_sign_in_sheet.dart
// Bottom sheet chọn phương thức đăng nhập tài khoản Chấm Công Trạm (Google / Apple / Email)
// dùng chung cho màn đăng nhập POS và màn Liên kết Chấm Công Trạm của chủ quán.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/chamcong_auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Mở sheet; [onSubmit] thực hiện công việc (có loading/lỗi ngay trong sheet).
/// Trả về kết quả của [onSubmit] khi thành công, hoặc null nếu người dùng đóng sheet.
Future<T?> showChamCongSignInSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Future<T> Function(ChamCongCredentialRequest req) onSubmit,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.tc.card,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ChamCongSignInSheet<T>(title: title, subtitle: subtitle, onSubmit: onSubmit),
  );
}

class _ChamCongSignInSheet<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Future<T> Function(ChamCongCredentialRequest req) onSubmit;
  const _ChamCongSignInSheet({required this.title, this.subtitle, required this.onSubmit});

  @override
  State<_ChamCongSignInSheet<T>> createState() => _ChamCongSignInSheetState<T>();
}

class _ChamCongSignInSheetState<T> extends State<_ChamCongSignInSheet<T>> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _showEmailForm = false;
  bool _obscure = true;
  ChamCongMethod? _busy;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(ChamCongCredentialRequest req) async {
    if (_busy != null) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = req.method;
      _error = null;
    });
    try {
      final result = await widget.onSubmit(req);
      if (mounted) Navigator.of(context).pop(result);
      return;
    } on ChamCongAuthException catch (e) {
      if (mounted && !e.isCancelled) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
    if (mounted) setState(() => _busy = null);
  }

  void _submitEmail() {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Vui lòng nhập Email và Mật khẩu Chấm Công Trạm.');
      return;
    }
    _run(ChamCongCredentialRequest(ChamCongMethod.email, email: email, password: pass));
  }

  Widget _optionButton({
    required ChamCongMethod method,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final loading = _busy == method && method != ChamCongMethod.email;
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: context.tc.textPrimary,
          side: BorderSide(color: context.tc.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _busy != null ? null : onTap,
        child: Row(
          children: [
            Icon(icon, size: 22, color: context.tc.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.beVietnamPro(
                      fontSize: 14, fontWeight: FontWeight.w600, color: context.tc.textPrimary)),
            ),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: context.tc.primary),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: context.tc.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.badge_outlined, color: context.tc.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(widget.title,
                      style: GoogleFonts.beVietnamPro(
                          fontSize: 17, fontWeight: FontWeight.w700, color: context.tc.textPrimary)),
                ),
              ],
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 6),
              Text(widget.subtitle!,
                  style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
            ],
            const SizedBox(height: 16),
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.tc.dangerLight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.tc.danger.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: context.tc.danger, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: GoogleFonts.beVietnamPro(
                              color: context.tc.danger, fontSize: 13, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (ChamCongAuthService.supportsGoogle) ...[
              _optionButton(
                method: ChamCongMethod.google,
                icon: Icons.g_mobiledata,
                label: 'Tiếp tục với Google',
                onTap: () => _run(const ChamCongCredentialRequest(ChamCongMethod.google)),
              ),
              const SizedBox(height: 10),
            ],
            if (ChamCongAuthService.supportsApple) ...[
              _optionButton(
                method: ChamCongMethod.apple,
                icon: Icons.apple,
                label: 'Tiếp tục với Apple',
                onTap: () => _run(const ChamCongCredentialRequest(ChamCongMethod.apple)),
              ),
              const SizedBox(height: 10),
            ],
            _optionButton(
              method: ChamCongMethod.email,
              icon: Icons.email_outlined,
              label: 'Đăng nhập bằng Email',
              onTap: () => setState(() {
                _showEmailForm = !_showEmailForm;
                _error = null;
              }),
            ),
            if (_showEmailForm) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(
                  labelText: 'Email Chấm Công Trạm',
                  prefixIcon: Icon(Icons.alternate_email),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _submitEmail(),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, color: context.tc.textSecondary),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.tc.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _busy != null ? null : _submitEmail,
                  child: _busy == ChamCongMethod.email
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Đăng nhập',
                          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy != null ? null : () => Navigator.of(context).pop(),
              child: Text('Hủy', style: TextStyle(color: context.tc.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hộp chọn một mục trong danh sách (dùng cho CHOOSE_STORE / CHOOSE_CHAMCONG_STORE)
Future<String?> showChamCongChoiceDialog(
  BuildContext context, {
  required String title,
  required List<({String id, String title, String subtitle})> items,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ctx.tc.card,
      title: Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 17)),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: 380,
        child: ListView(
          shrinkWrap: true,
          children: items
              .map((it) => ListTile(
                    leading: Icon(Icons.storefront_outlined, color: ctx.tc.primary),
                    title: Text(it.title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                    subtitle: it.subtitle.isEmpty
                        ? null
                        : Text(it.subtitle, style: TextStyle(color: ctx.tc.textSecondary, fontSize: 12)),
                    onTap: () => Navigator.of(ctx).pop(it.id),
                  ))
              .toList(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Hủy')),
      ],
    ),
  );
}

/// Chọn cửa hàng POS khi tài khoản chấm công thuộc nhiều cửa hàng đã liên kết
Future<String?> pickPosStore(BuildContext context, List<ChamCongStoreOption> stores) {
  return showChamCongChoiceDialog(
    context,
    title: 'Chọn cửa hàng để đăng nhập',
    items: stores.map((s) => (id: s.storeCode, title: s.storeName, subtitle: 'Mã: ${s.storeCode}')).toList(),
  );
}

/// Chọn cửa hàng chấm công để liên kết (chủ quán sở hữu nhiều cửa hàng chấm công)
Future<String?> pickChamCongWorkplace(BuildContext context, List<ChamCongWorkplaceOption> stores) {
  return showChamCongChoiceDialog(
    context,
    title: 'Chọn cửa hàng Chấm Công',
    items: stores
        .map((s) => (id: s.chamCongStoreId, title: s.name, subtitle: s.code.isEmpty ? '' : 'Mã: ${s.code}'))
        .toList(),
  );
}
