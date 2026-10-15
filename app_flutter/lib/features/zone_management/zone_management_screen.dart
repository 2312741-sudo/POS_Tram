// lib/features/zone_management/zone_management_screen.dart
// Thiết lập khu vực bàn: thêm khu (kèm N bàn), đổi tên khu, thêm bàn vào khu, xóa khu trống.
// Logic kế hoạch & kiểm tra nằm ở core/domain/zone_plan.dart (cùng quy tắc với web/lib/zones.ts).
import 'dart:async';

import 'package:flutter/material.dart';
import '../../data/models/zone_model.dart';
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
    return sortZoneNames(names, _zones);
  }

  bool _isPinned(String zone) => _zones.any((z) => z.name.trim() == zone && z.pinned);

  Future<void> _togglePin(String zone, bool pin) async {
    try {
      await _fb.setZonePinned(zone, pin);
    } catch (e) {
      _snack('Không ghim được khu: $e', error: true);
    }
  }

  /// Kéo thả: khu ghim luôn nằm trên khu thường, nên không cho kéo qua ranh giới ghim
  Future<void> _reorder(List<String> zones, int oldI, int newI) async {
    if (newI > oldI) newI -= 1;
    final moved = zones[oldI];
    final next = [...zones]..removeAt(oldI);
    next.insert(newI, moved);
    final pinnedFirst = [
      ...next.where(_isPinned),
      ...next.where((z) => !_isPinned(z)),
    ];
    try {
      await _fb.setZoneOrder(pinnedFirst);
    } catch (e) {
      _snack('Không lưu được thứ tự: $e', error: true);
    }
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

  Future<void> _deleteTable(String zone, TableModel t) async {
    if (t.inUse || t.currentOrderJson.isNotEmpty) {
      _snack('Bàn "${t.name}" đang dùng hoặc còn món — hãy thanh toán / dọn bàn trước', error: true);
      return;
    }
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa bàn',
      message: 'Xóa bàn "${t.name}" khỏi khu "$zone"?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _run(() => _fb.deleteTableByName(zone: zone, tableName: t.name, actor: _actor), okMessage: 'Đã xóa bàn');
    }
  }

  Future<void> _dedupe() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Dọn bàn trùng',
      message: 'Gộp các bàn trùng khu + tên (chỉ giữ 1 bàn mỗi tên, không xóa bàn đang dùng)?',
      confirmText: 'Dọn',
    );
    if (confirm == true) {
      await _run(() => _fb.dedupeTables(actor: _actor), okMessage: 'Đã dọn bàn trùng');
    }
  }

  /// Danh sách bàn của một khu, có nút xóa từng bàn
  void _showTables(String zone) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.tc.surface,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheet) {
        final list = _tables.where((t) => t.zone == zone).toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Bàn trong "$zone" (${list.length})',
                    style: GoogleFonts.beVietnamPro(
                        color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Flexible(
                child: list.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('Khu chưa có bàn', style: TextStyle(color: context.tc.textSecondary)))
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final t in list)
                            ListTile(
                              title: Text(t.name, style: TextStyle(color: context.tc.textPrimary)),
                              subtitle: (t.inUse || t.currentOrderJson.isNotEmpty)
                                  ? Text('Đang dùng', style: TextStyle(color: context.tc.textSecondary, fontSize: 12))
                                  : null,
                              trailing: IconButton(
                                tooltip: 'Xóa bàn',
                                icon: Icon(Icons.delete_outline, color: context.tc.danger),
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        await _deleteTable(zone, t);
                                        if (ctx.mounted) setSheet(() {});
                                      },
                              ),
                            ),
                        ],
                      ),
              ),
            ]),
          ),
        );
      }),
    );
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
        actions: [
          IconButton(
            tooltip: 'Dọn bàn trùng',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: _busy ? null : _dedupe,
          ),
        ],
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
          : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: zones.length,
              buildDefaultDragHandles: false,
              onReorder: (oldI, newI) => _reorder(zones, oldI, newI),
              itemBuilder: (_, i) {
                final zone = zones[i];
                final pinned = _isPinned(zone);
                final n = _countIn(zone);
                final busy = _busyIn(zone);
                return Container(
                  key: ValueKey('zone_$zone'),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: context.tc.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.tc.border),
                  ),
                  child: ListTile(
                    leading: IconButton(
                      tooltip: pinned ? 'Bỏ ghim khu' : 'Ghim khu lên đầu',
                      icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined,
                          color: pinned ? context.tc.primary : context.tc.textHint, size: 22),
                      onPressed: _busy ? null : () => _togglePin(zone, !pinned),
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
                          tooltip: 'Xem / xóa bàn',
                          icon: Icon(Icons.table_restaurant_outlined, color: context.tc.primary, size: 20),
                          onPressed: _busy ? null : () => _showTables(zone),
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
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.drag_handle, color: context.tc.textHint, size: 22),
                          ),
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
