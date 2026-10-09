// lib/widgets/manager_pin_dialogs.dart
//
// Hộp thoại "Quản lý duyệt bằng PIN" và "Đặt PIN duyệt của tôi".
// PIN được xác minh / lưu phía máy chủ (callable verifyManagerPin / setManagerPin);
// app không bao giờ đọc hay lưu PIN.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/services/auth_service.dart';
import '../core/services/manager_pin_service.dart';
import '../core/theme/app_theme.dart';
import '../data/models/app_models.dart';
import '../data/services/firebase_service.dart';
import 'common_widgets.dart';

/// Yêu cầu Quản lý nhập PIN để duyệt [action]. Trả về lần duyệt (null nếu hủy).
/// [contextText] được gửi lên máy chủ để ghi vào nhật ký duyệt.
Future<ManagerApproval?> showManagerApprovalDialog(
  BuildContext context, {
  required String action,
  String? contextText,
}) {
  return showDialog<ManagerApproval>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ManagerApprovalDialog(action: action, contextText: contextText),
  );
}

class _ManagerApprovalDialog extends StatefulWidget {
  final String action;
  final String? contextText;
  const _ManagerApprovalDialog({required this.action, this.contextText});

  @override
  State<_ManagerApprovalDialog> createState() => _ManagerApprovalDialogState();
}

class _ManagerApprovalDialogState extends State<_ManagerApprovalDialog> {
  final _pinCtrl = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  String? _error;
  int? _lockedUntil;
  List<UserModel> _approvers = const [];
  String? _approverUid;

  @override
  void initState() {
    super.initState();
    _loadApprovers();
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadApprovers() async {
    final me = _auth.currentUser?.uid;
    final users = await FirebaseService().getUsers();
    if (!mounted) return;
    setState(() {
      _approvers = users
          .where((u) => u.isActive && u.uid != me && (u.isOwner || u.isManager))
          .toList()
        ..sort((a, b) => a.fullName.compareTo(b.fullName));
    });
  }

  bool get _locked => _lockedUntil != null && _lockedUntil! > DateTime.now().millisecondsSinceEpoch;

  Future<void> _submit() async {
    if (_busy || _locked) return;
    final pin = _pinCtrl.text.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      setState(() => _error = 'PIN phải gồm 4–8 chữ số.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final approval = await ManagerPinService().verify(
        storeCode: _auth.currentStoreCode,
        pin: pin,
        action: widget.action,
        approverUid: _approverUid,
        context: widget.contextText,
      );
      if (mounted) Navigator.pop(context, approval);
    } on ManagerPinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
        _pinCtrl.clear();
        if (e.isLockedOut) {
          final secs = e.lockoutSeconds ?? 15 * 60;
          _lockedUntil = DateTime.now().millisecondsSinceEpoch + secs * 1000;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: context.bg(Colors.amber.shade100), borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.shield_outlined, color: context.ink(Colors.amber.shade900), size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quản lý duyệt bằng PIN', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(ManagerApprovalAction.label(widget.action),
                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary)),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn không có quyền thực hiện thao tác này. Vui lòng nhờ Quản lý nhập mã PIN duyệt.',
              style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textPrimary),
            ),
            if (widget.contextText != null && widget.contextText!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(widget.contextText!, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
            ],
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _approverUid ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Người duyệt', prefixIcon: Icon(Icons.person_outline)),
              items: [
                const DropdownMenuItem(value: '', child: Text('Tự nhận diện theo PIN')),
                for (final u in _approvers)
                  DropdownMenuItem(value: u.uid, child: Text(u.fullName.isNotEmpty ? u.fullName : u.username)),
              ],
              onChanged: _busy ? null : (v) => setState(() => _approverUid = (v == null || v.isEmpty) ? null : v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              autofocus: true,
              enabled: !_busy && !_locked,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              style: const TextStyle(letterSpacing: 6, fontSize: 18),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                labelText: 'Mã PIN Quản lý',
                hintText: '••••',
                counterText: '',
                errorText: _error,
                errorMaxLines: 3,
                prefixIcon: const Icon(Icons.lock_outline),
              ),
              onChanged: (_) {
                if (_error != null && !_locked) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: dialogActionStyle(),
          onPressed: _busy || _locked ? null : _submit,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Xác Nhận Duyệt'),
        ),
      ],
    );
  }
}

/// Quản lý / Chủ quán đặt, đổi hoặc xóa PIN duyệt của chính mình (callable setManagerPin).
Future<void> showSetApprovalPinDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _SetApprovalPinDialog(),
  );
}

class _SetApprovalPinDialog extends StatefulWidget {
  const _SetApprovalPinDialog();

  @override
  State<_SetApprovalPinDialog> createState() => _SetApprovalPinDialogState();
}

class _SetApprovalPinDialogState extends State<_SetApprovalPinDialog> {
  final _pinCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _auth = AuthService();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save({required bool clear}) async {
    if (_busy) return;
    String? pin;
    if (!clear) {
      pin = _pinCtrl.text.trim();
      final err = ManagerPinLogic.validatePinFormat(pin);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
      if (pin != _confirmCtrl.text.trim()) {
        setState(() => _error = 'PIN nhập lại không khớp.');
        return;
      }
    } else {
      final ok = await showConfirmDialog(
        context,
        title: 'Xóa PIN duyệt?',
        message: 'Sau khi xóa, bạn sẽ không thể duyệt thao tác cho nhân viên bằng PIN cho tới khi đặt PIN mới.',
        confirmText: 'Xóa PIN',
        isDanger: true,
      );
      if (ok != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ManagerPinService().setOwnPin(storeCode: _auth.currentStoreCode, pin: pin);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(clear ? 'Đã xóa PIN duyệt.' : 'Đã lưu PIN duyệt của bạn.')),
      );
    } on ManagerPinException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  InputDecoration _pinDecoration(String label) => InputDecoration(
        labelText: label,
        hintText: '••••',
        counterText: '',
        prefixIcon: const Icon(Icons.lock_outline),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.pin_outlined, color: context.tc.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('PIN duyệt của tôi', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold))),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PIN dùng để duyệt giảm giá / hủy món cho nhân viên. PIN gồm 4–8 chữ số, được lưu mã hóa trên máy chủ và không ai đọc được.',
              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _pinCtrl,
              obscureText: true,
              autofocus: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration: _pinDecoration('PIN mới'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration: _pinDecoration('Nhập lại PIN mới'),
              onSubmitted: (_) => _save(clear: false),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => _save(clear: true),
          child: Text('Xóa PIN', style: TextStyle(color: context.tc.danger)),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: dialogActionStyle(),
          onPressed: _busy ? null : () => _save(clear: false),
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Lưu PIN'),
        ),
      ],
    );
  }
}
