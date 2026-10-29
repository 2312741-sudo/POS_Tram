// lib/features/menu_management/note_catalog_screen.dart
//
// Danh mục note & topping của chi nhánh: nhóm note (câu ghi chú nhanh) và nhóm topping (tên + giá).
// Gắn vào nhóm món / món ở hộp thoại sửa nhóm món & sửa món. Xem docs/NOTE_CATALOG.md.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/item_options.dart';
import '../../core/domain/note_catalog_migration.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';
import 'note_catalog_access.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class NoteCatalogScreen extends StatefulWidget {
  final String storeCode;
  const NoteCatalogScreen({super.key, required this.storeCode});

  @override
  State<NoteCatalogScreen> createState() => _NoteCatalogScreenState();
}

class _NoteCatalogScreenState extends State<NoteCatalogScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  ItemCatalog _catalog = const ItemCatalog();
  bool _loaded = false;
  StreamSubscription<ItemCatalog>? _sub;

  bool get _allowed => canManageNoteCatalog(_auth);

  @override
  void initState() {
    super.initState();
    _sub = _fb.itemCatalogStream(storeCode: widget.storeCode).listen((c) {
      if (mounted) {
        setState(() {
          _catalog = c;
          _loaded = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String _newId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _importLegacy() async {
    try {
      final raw = await _fb.loadLegacyNoteConfig(storeCode: widget.storeCode);
      final plan = planNoteCatalogMigration(
        products: raw['products'],
        categories: raw['categories'],
        productNotes: raw['product_notes'],
        noteGroups: raw['note_groups'],
        toppingGroups: raw['topping_groups'],
      );
      if (!mounted) return;
      if (plan.isEmpty) {
        _snack('Không có gì để nhập thêm (đã nhập hoặc chưa có cấu hình cũ).');
        return;
      }
      final ok = await showConfirmDialog(
        context,
        title: 'Nhập từ cấu hình cũ',
        message: '${plan.summary.join('\n')}\n\nChỉ THÊM mới, không ghi đè nhóm/gắn kết đã có. Chạy lại an toàn.',
        confirmText: 'Nhập',
      );
      if (ok != true) return;
      await _fb.updateStorePaths(plan.updates, storeCode: widget.storeCode);
      if (mounted) _snack('Đã nhập: ${plan.newNoteGroups} nhóm note, ${plan.newToppingGroups} nhóm topping, ${plan.attachments} lượt gắn.');
    } catch (e) {
      if (mounted) _snack('Không nhập được: $e');
    }
  }

  // ---------- Nhóm note ----------
  Future<void> _editNoteGroup(NoteGroup? g) async {
    final nameCtrl = TextEditingController(text: g?.name ?? '');
    final items = <TextEditingController>[for (final n in g?.items ?? const <NoteTemplate>[]) TextEditingController(text: n.text)];
    var active = g?.active ?? true;
    final ids = <String>[for (final n in g?.items ?? const <NoteTemplate>[]) n.id];
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(g == null ? 'Thêm nhóm note' : 'Sửa nhóm note'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên nhóm * (VD: Đồ uống, Bánh)')),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Đang dùng'), value: active, onChanged: (v) => setSt(() => active = v)),
                const Align(alignment: Alignment.centerLeft, child: Text('Câu note mẫu', style: TextStyle(fontWeight: FontWeight.bold))),
                for (var i = 0; i < items.length; i++)
                  Row(children: [
                    Expanded(child: TextField(controller: items[i], decoration: InputDecoration(hintText: 'Câu note ${i + 1}'))),
                    IconButton(icon: const Icon(LucideIcons.x, size: 18), onPressed: () => setSt(() {
                          items.removeAt(i);
                          ids.removeAt(i);
                        })),
                  ]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setSt(() {
                      items.add(TextEditingController());
                      ids.add(_newId('n'));
                    }),
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Thêm câu note'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final list = <NoteTemplate>[
                  for (var i = 0; i < items.length; i++)
                    if (items[i].text.trim().isNotEmpty) NoteTemplate(id: ids[i], text: items[i].text.trim()),
                ];
                final saved = NoteGroup(
                  id: g?.id ?? _newId('ng'),
                  name: name,
                  sortOrder: g?.sortOrder ?? (_catalog.noteGroups.length + 1),
                  active: active,
                  items: list,
                );
                await _fb.saveNoteGroup(saved, storeCode: widget.storeCode);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Nhóm topping ----------
  Future<void> _editToppingGroup(ToppingGroup? g) async {
    final nameCtrl = TextEditingController(text: g?.name ?? '');
    final maxCtrl = TextEditingController(text: (g?.max ?? 0) > 0 ? '${g!.max}' : '');
    final names = <TextEditingController>[for (final t in g?.items ?? const <ToppingItem>[]) TextEditingController(text: t.name)];
    final prices = <TextEditingController>[for (final t in g?.items ?? const <ToppingItem>[]) TextEditingController(text: '${t.price}')];
    final ids = <String>[for (final t in g?.items ?? const <ToppingItem>[]) t.id];
    var active = g?.active ?? true;
    var multi = g?.multi ?? true;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(g == null ? 'Thêm nhóm topping' : 'Sửa nhóm topping'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Tên nhóm * (VD: Topping trà, Sốt)')),
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Đang dùng'), value: active, onChanged: (v) => setSt(() => active = v)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho chọn nhiều topping'),
                    subtitle: const Text('Tắt = chỉ chọn một trong nhóm'),
                    value: multi,
                    onChanged: (v) => setSt(() => multi = v)),
                if (multi)
                  TextField(controller: maxCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Tối đa (để trống = không giới hạn)')),
                const SizedBox(height: 8),
                const Align(alignment: Alignment.centerLeft, child: Text('Topping', style: TextStyle(fontWeight: FontWeight.bold))),
                for (var i = 0; i < names.length; i++)
                  Row(children: [
                    Expanded(flex: 3, child: TextField(controller: names[i], decoration: const InputDecoration(hintText: 'Tên'))),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: TextField(controller: prices[i], keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Giá (đ)'))),
                    IconButton(icon: const Icon(LucideIcons.x, size: 18), onPressed: () => setSt(() {
                          names.removeAt(i);
                          prices.removeAt(i);
                          ids.removeAt(i);
                        })),
                  ]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setSt(() {
                      names.add(TextEditingController());
                      prices.add(TextEditingController(text: '0'));
                      ids.add(_newId('t'));
                    }),
                    icon: const Icon(LucideIcons.plus),
                    label: const Text('Thêm topping'),
                  ),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final list = <ToppingItem>[
                  for (var i = 0; i < names.length; i++)
                    if (names[i].text.trim().isNotEmpty)
                      ToppingItem(id: ids[i], name: names[i].text.trim(), price: (int.tryParse(prices[i].text.trim()) ?? 0).clamp(0, 100000000)),
                ];
                final saved = ToppingGroup(
                  id: g?.id ?? _newId('tg'),
                  name: name,
                  sortOrder: g?.sortOrder ?? (_catalog.toppingGroups.length + 1),
                  active: active,
                  multi: multi,
                  max: multi ? (int.tryParse(maxCtrl.text.trim()) ?? 0).clamp(0, 99) : 0,
                  items: list,
                );
                await _fb.saveToppingGroup(saved, storeCode: widget.storeCode);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _delete(String what, String name, Future<void> Function() run) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Xóa $what',
      message: 'Xóa "$name"? Các món/nhóm món đang gắn sẽ không còn hiện nhóm này.',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (ok == true) await run();
  }

  Future<void> _reorderNotes(int oldIndex, int newIndex) async {
    final list = List<NoteGroup>.from(_catalog.noteGroups);
    list.insert(newIndex, list.removeAt(oldIndex));
    for (var i = 0; i < list.length; i++) {
      if (list[i].sortOrder != i + 1) await _fb.saveNoteGroup(list[i].copyWith(sortOrder: i + 1), storeCode: widget.storeCode);
    }
  }

  Future<void> _reorderToppings(int oldIndex, int newIndex) async {
    final list = List<ToppingGroup>.from(_catalog.toppingGroups);
    list.insert(newIndex, list.removeAt(oldIndex));
    for (var i = 0; i < list.length; i++) {
      if (list[i].sortOrder != i + 1) await _fb.saveToppingGroup(list[i].copyWith(sortOrder: i + 1), storeCode: widget.storeCode);
    }
  }

  Widget _tile({required Key key, required String title, required String subtitle, required bool active, required VoidCallback onTap, required VoidCallback onDelete}) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: context.tc.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: context.tc.border)),
      child: ListTile(
        onTap: onTap,
        title: Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, color: active ? context.tc.textPrimary : context.tc.textHint)),
        subtitle: Text(active ? subtitle : 'Đã tắt • $subtitle', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
        trailing: IconButton(icon: Icon(LucideIcons.trash2, color: context.tc.danger, size: 20), onPressed: onDelete),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Danh mục note & topping')),
        body: const Center(child: Text('Bạn không có quyền quản lý danh mục note & topping (MANAGE_NOTE_CATALOG).')),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: context.tc.background,
        appBar: AppBar(
          backgroundColor: context.tc.surface,
          foregroundColor: context.tc.textPrimary,
          title: Text('Note & topping [${widget.storeCode}]', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: context.tc.textPrimary)),
          actions: [
            IconButton(tooltip: 'Nhập từ cấu hình cũ', icon: const Icon(LucideIcons.circleArrowDown), onPressed: _importLegacy),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Danh mục note'), Tab(text: 'Nhóm topping')]),
        ),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                if (_catalog.isLegacy)
                  Container(
                    width: double.infinity,
                    color: Colors.amber.shade100,
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      'Chưa cấu hình: màn gọi món vẫn dùng danh sách cũ. Tạo nhóm đầu tiên (hoặc bấm nút nhập ở góc trên) rồi gắn vào nhóm món/món — từ đó chỉ hiện đúng nhóm đã gắn.',
                      style: TextStyle(fontSize: 12, color: Colors.brown.shade900),
                    ),
                  ),
                Expanded(
                  child: TabBarView(children: [
                    _list(
                      empty: 'Chưa có nhóm note',
                      addLabel: 'Thêm nhóm note',
                      onAdd: () => _editNoteGroup(null),
                      count: _catalog.noteGroups.length,
                      onReorder: _reorderNotes,
                      builder: (i) {
                        final g = _catalog.noteGroups[i];
                        return _tile(
                          key: ValueKey('n_${g.id}'),
                          title: g.name,
                          subtitle: g.items.map((e) => e.text).join(' • '),
                          active: g.active,
                          onTap: () => _editNoteGroup(g),
                          onDelete: () => _delete('nhóm note', g.name, () => _fb.deleteNoteGroup(g.id, storeCode: widget.storeCode)),
                        );
                      },
                    ),
                    _list(
                      empty: 'Chưa có nhóm topping',
                      addLabel: 'Thêm nhóm topping',
                      onAdd: () => _editToppingGroup(null),
                      count: _catalog.toppingGroups.length,
                      onReorder: _reorderToppings,
                      builder: (i) {
                        final g = _catalog.toppingGroups[i];
                        final rule = !g.multi ? 'chọn 1' : (g.max > 0 ? 'tối đa ${g.max}' : 'chọn nhiều');
                        return _tile(
                          key: ValueKey('t_${g.id}'),
                          title: '${g.name} ($rule)',
                          subtitle: g.items.map((e) => '${e.name} ${FormatUtils.vnd(e.price)}').join(' • '),
                          active: g.active,
                          onTap: () => _editToppingGroup(g),
                          onDelete: () => _delete('nhóm topping', g.name, () => _fb.deleteToppingGroup(g.id, storeCode: widget.storeCode)),
                        );
                      },
                    ),
                  ]),
                ),
              ]),
      ),
    );
  }

  Widget _list({
    required String empty,
    required String addLabel,
    required VoidCallback onAdd,
    required int count,
    required Future<void> Function(int, int) onReorder,
    required Widget Function(int) builder,
  }) {
    return Stack(children: [
      count == 0
          ? EmptyState(icon: LucideIcons.stickyNote, title: empty)
          : ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: count,
              onReorderItem: (o, n) => onReorder(o, n),
              itemBuilder: (_, i) => builder(i),
            ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: addLabel,
          onPressed: onAdd,
          icon: const Icon(LucideIcons.plus, color: Colors.white),
          label: Text(addLabel, style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: context.tc.primary,
        ),
      ),
    ]);
  }
}
