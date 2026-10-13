// lib/features/zone_management/zone_management_screen.dart
// Thiết lập khu vực bàn: thêm khu (kèm N bàn), đổi tên khu, thêm bàn vào khu, xóa khu trống.
// Logic kế hoạch & kiểm tra nằm ở core/domain/zone_plan.dart (cùng quy tắc với web/lib/zones.ts).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/zone_plan.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class ZoneManagementScreen extends StatefulWidget {
  const ZoneManagementScreen({super.key});

  @override
  State<ZoneManagementScreen> createState() => _ZoneManagementScreenState();
}

class _ZoneManagementScreenState extends State<ZoneManagementScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  List<ZoneModel> _zones = [];
  List<TableModel> _tables = [];
  bool _busy = false;
  StreamSubscription<List<ZoneModel>>? _zonesSub;
  StreamSubscription<List<TableModel>>? _tablesSub;

  @override
  void initState() {
    super.initState();
    _zonesSub = _fb.zonesStream().listen((z) { if (mounted) setState(() => _zones = z); });
    _tablesSub = _fb.tablesStream().listen((t) { if (mounted) setState(() => _tables = t); });
  }

  @override
  void dispose() {
    _zonesSub?.cancel();
    _tablesSub?.cancel();
    super.dispose();
  }

  /// Tên khu: khu khai báo + khu đang có bàn
  List<String> get _zoneNames {
    final names = <String>{};
    for (final z in _zones) {
      final n = z.name.trim();
      if (n.isNotEmpty) names.add(n);
    }
    for (final t in _tables) {
      final n = t.zone.trim();
      if (n.isNotEmpty) names.add(n);
    }
    return names.toList()..sort();
  }

  int _countIn(String zone) => _tables.where((t) => t.zone == zone).length;
  bool _busyIn(String zone) => _tables.any((t) => t.zone == zone && (t.inUse || t.currentOrderJson.isNotEmpty));

  ZoneAuditActor get _actor => ZoneAuditActor(
        username: _auth.currentUser?.username ?? '',
        fullName: _auth.currentUser?.fullName ?? '',
        role: _auth.currentUser?.roleId ?? '',
      );

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? context.tc.danger : null,
    ));
  }

  /// Chạy một thao tác ghi; trả về true khi thành công (để đóng hộp thoại)
  Future<bool> _run(Future<ZonePlan> Function() op, {String okMessage = 'Đã lưu'}) async {
    setState(() => _busy = true);
    try {
      final plan = await op();
      if (!plan.isOk) {
        _snack(plan.error!, error: true);
        return false;
      }
      _snack(okMessage);
      return true;
    } catch (e) {
      _snack('Không ghi được dữ liệu: $e', error: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, color: context.tc.textSecondary),
      );

  Widget _dialogShell({required String title, required List<Widget> body, required List<Widget> actions}) {
    return AlertDialog(
      backgroundColor: context.tc.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: GoogleFonts.beVietnamPro(color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: body)),
      actions: actions,
    );
  }

  Widget _cancelButton(BuildContext ctx) => TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary)),
      );

  void _showCreateDialog() {
    final nameCtrl = TextEditingController();
    final countCtrl = TextEditingController(text: '5');
    final prefixCtrl = TextEditingController(text: 'Bàn');
    showDialog(
      context: context,
      builder: (ctx) => _dialogShell(
        title: 'Thêm khu vực',
        body: [
          TextField(
            controller: nameCtrl,
            autofocus: true,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Tên khu vực (VD: Khu A, Tầng 2)', icon: Icons.map_outlined),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: countCtrl,
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Tạo nhanh số bàn (0–100)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: prefixCtrl,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Tiền tố tên bàn'),
          ),
        ],
        actions: [
          _cancelButton(ctx),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await _run(() => _fb.createZone(
                          name: nameCtrl.text,
                          prefix: prefixCtrl.text,
                          count: int.tryParse(countCtrl.text.trim()) ?? -1,
                          actor: _actor,
                        ));
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(String zone) {
    final ctrl = TextEditingController(text: zone);
    showDialog(
      context: context,
      builder: (ctx) => _dialogShell(
        title: 'Đổi tên khu vực',
        body: [
          TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Tên khu mới', icon: Icons.edit_outlined),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 8),
          Text('Mọi bàn trong khu sẽ được chuyển sang tên khu mới.',
              style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary, fontSize: 12)),
        ],
        actions: [
          _cancelButton(ctx),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await _run(
                      () => _fb.renameZone(oldName: zone, newName: ctrl.text, actor: _actor),
                      okMessage: 'Đã đổi tên khu vực',
                    );
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showAddTablesDialog(String zone) {
    final countCtrl = TextEditingController(text: '5');
    final prefixCtrl = TextEditingController(text: 'Bàn');
    showDialog(
      context: context,
      builder: (ctx) => _dialogShell(
        title: 'Thêm bàn vào "$zone"',
        body: [
          TextField(
            controller: countCtrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Số bàn thêm (1–100)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: prefixCtrl,
            style: TextStyle(color: context.tc.textPrimary),
            decoration: _field('Tiền tố tên bàn'),
          ),
        ],
        actions: [
          _cancelButton(ctx),
          ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await _run(
                      () => _fb.addTablesToZone(
                        zone: zone,
                        prefix: prefixCtrl.text,
                        count: int.tryParse(countCtrl.text.trim()) ?? -1,
                        actor: _actor,
                      ),
                      okMessage: 'Đã thêm bàn',
                    );
                    if (ok && ctx.mounted) Navigator.pop(ctx);
                  },
            child: const Text('Thêm bàn'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteZone(String zone) async {
    final n = _countIn(zone);
    if (n > 0) {
      _snack('Khu "$zone" còn $n bàn — hãy chuyển hoặc xóa các bàn trước', error: true);
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa khu vực',
      message: 'Xóa khu vực "$zone"?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _run(() => _fb.deleteZone(zone: zone, actor: _actor), okMessage: 'Đã xóa khu vực');
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = _zoneNames;
    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        title: Text('Quản lý khu vực', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: zones.isEmpty
          ? EmptyState(
              icon: Icons.map_outlined,
              title: 'Chưa có khu vực',
              subtitle: 'Thêm khu vực để phân loại bàn',
              action: ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: const Text('Thêm khu vực'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: zones.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final zone = zones[i];
                final n = _countIn(zone);
                final busy = _busyIn(zone);
                return Container(
                  decoration: BoxDecoration(
                    color: context.tc.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.tc.border),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(26),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.location_on_outlined, color: AppColors.secondary, size: 18),
                    ),
                    title: Text(zone, style: GoogleFonts.beVietnamPro(
                        color: context.tc.textPrimary, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      busy ? '$n bàn • đang có bàn dùng' : '$n bàn',
                      style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary, fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: busy ? 'Còn bàn đang dùng — không đổi tên' : 'Đổi tên khu',
                          icon: Icon(Icons.edit_outlined, color: context.tc.primary, size: 20),
                          onPressed: _busy || busy ? null : () => _showRenameDialog(zone),
                        ),
                        IconButton(
                          tooltip: 'Thêm bàn vào khu',
                          icon: Icon(Icons.add_circle_outline, color: context.tc.primary, size: 20),
                          onPressed: _busy ? null : () => _showAddTablesDialog(zone),
                        ),
                        IconButton(
                          tooltip: n > 0 ? 'Khu còn bàn — không thể xóa' : 'Xóa khu',
                          icon: Icon(Icons.delete_outline, color: context.tc.danger, size: 20),
                          onPressed: _busy || n > 0 ? null : () => _deleteZone(zone),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: zones.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _showCreateDialog,
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Thêm khu', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: context.tc.primary,
              foregroundColor: Colors.white,
            ),
    );
  }
}
