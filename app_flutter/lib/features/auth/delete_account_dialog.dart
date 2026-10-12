// lib/features/auth/delete_account_dialog.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';

/// Luồng "Xóa tài khoản của tôi" (Apple 5.1.1(v)) — dùng chung cho mọi vai trò.
/// Lối vào: Quản lý/Chủ quán → Trung tâm quản lý → menu ⋮ (góc phải) → "Xóa tài khoản của tôi";
/// Thu ngân/Phục vụ → màn hình Bàn → menu → "Xóa tài khoản của tôi".
class DeleteAccountDialog {
  DeleteAccountDialog._();

  static Future<void> start(BuildContext context) async {
    final outcome = await showDialog<_DeleteOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountConfirmDialog(),
    );
    if (outcome == null || !context.mounted) return;

    switch (outcome.kind) {
      case _DeleteKind.deleted:
        final messenger = ScaffoldMessenger.of(context);
        await AuthService().endSessionAfterAccountDeletion();
        messenger.showSnackBar(const SnackBar(content: Text('Tài khoản đã được xóa.')));
        if (context.mounted) context.go('/login');
      case _DeleteKind.blocked:
        await _showMessage(context, 'Không thể xóa tài khoản', outcome.message);
      case _DeleteKind.failed:
        await _showMessage(context, 'Xóa tài khoản thất bại', outcome.message);
    }
  }

  static Future<void> _showMessage(BuildContext context, String title, String message) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đã hiểu')),
        ],
      ),
    );
  }
}

enum _DeleteKind { deleted, blocked, failed }

class _DeleteOutcome {
  const _DeleteOutcome(this.kind, [this.message = '']);
  final _DeleteKind kind;
  final String message;
}

class _DeleteAccountConfirmDialog extends StatefulWidget {
  const _DeleteAccountConfirmDialog();

  @override
  State<_DeleteAccountConfirmDialog> createState() => _DeleteAccountConfirmDialogState();
}

class _DeleteAccountConfirmDialogState extends State<_DeleteAccountConfirmDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool get _canConfirm => !_busy && _ctrl.text.trim() == 'XOA';

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      await AuthService().deleteOwnAccount();
      if (mounted) Navigator.pop(context, const _DeleteOutcome(_DeleteKind.deleted));
    } on AccountDeletionBlockedException catch (e) {
      if (mounted) Navigator.pop(context, _DeleteOutcome(_DeleteKind.blocked, e.message));
    } on AuthException catch (e) {
      if (mounted) Navigator.pop(context, _DeleteOutcome(_DeleteKind.failed, e.message));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tc = context.tc;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Row(
          children: [
            Icon(Icons.no_accounts_outlined, color: tc.danger),
            const SizedBox(width: 8),
            const Expanded(child: Text('Xóa tài khoản của tôi')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tc.dangerLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Hành động này KHÔNG thể hoàn tác.',
                  style: TextStyle(color: tc.danger, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '• Bạn sẽ mất quyền truy cập tại TẤT CẢ chi nhánh và bị đăng xuất ngay.\n'
                '• Hồ sơ cá nhân (họ tên, SĐT, email, ảnh) sẽ bị xóa; lịch sử bán hàng, hóa đơn và nhật ký vẫn được giữ lại nhưng không còn gắn với thông tin cá nhân của bạn.\n'
                '• Muốn dùng lại, cần được Quản lý/Chủ quán tạo tài khoản mới.',
                style: TextStyle(color: tc.textSecondary, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ctrl,
                enabled: !_busy,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nhập XOA để xác nhận',
                  prefixIcon: Icon(Icons.warning_amber_rounded),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: tc.danger),
            onPressed: _canConfirm ? _submit : null,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Xóa tài khoản'),
          ),
        ],
      ),
    );
  }
}
