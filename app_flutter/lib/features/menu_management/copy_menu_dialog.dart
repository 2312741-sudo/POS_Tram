// lib/features/menu_management/copy_menu_dialog.dart
// Sao chép thực đơn giữa chi nhánh: chọn nguồn -> nhiều đích -> phạm vi (tất cả / theo nhóm / từng món)
// -> tùy chọn + cách xử lý món trùng -> XEM TRƯỚC -> xác nhận. Không xóa gì ở chi nhánh đích.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/menu_copy.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

Future<void> showCopyMenuDialog(
  BuildContext context, {
  required List<StoreInfoModel> stores,
  required String defaultSource,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CopyMenuDialog(stores: stores, defaultSource: defaultSource),
  );
}

enum _Step { config, preview, running, done }

class _CopyMenuDialog extends StatefulWidget {
  final List<StoreInfoModel> stores;
  final String defaultSource;
  const _CopyMenuDialog({required this.stores, required this.defaultSource});

  @override
  State<_CopyMenuDialog> createState() => _CopyMenuDialogState();
}

class _CopyMenuDialogState extends State<_CopyMenuDialog> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  _Step _step = _Step.config;
  late String _source;
  final Set<String> _targets = {};
  bool _pickMode = false;
  final Set<String> _pickedKeys = {};
  String _search = '';
  bool _copyCategories = true, _copyOptions = true, _copyNotes = true, _copyCatalog = true, _copyImages = true;
  ConflictPolicy _conflict = ConflictPolicy.skip;

  MenuSnapshot? _snapshot;
  String? _loadError;
  bool _busy = false;
  final Map<String, CopyPlan> _plans = {};
  final Map<String, String> _planErrors = {};
  final List<String> _results = [];
  String _progress = '';

  @override
  void initState() {
    super.initState();
    final codes = widget.stores.map((s) => s.storeCode).toList();
    _source = codes.contains(widget.defaultSource) ? widget.defaultSource : (codes.isNotEmpty ? codes.first : '');
    _loadSource();
  }

  Future<void> _loadSource() async {
    final src = _source;
    setState(() {
      _snapshot = null;
      _loadError = null;
      _pickedKeys.clear();
      _targets.remove(src);
    });
    try {
      final snap = await _fb.loadMenuSnapshot(src);
      if (mounted && src == _source) setState(() => _snapshot = snap);
    } catch (e) {
      if (mounted && src == _source) setState(() => _loadError = 'Không đọc được thực đơn chi nhánh nguồn: $e');
    }
  }

  CopyOptions get _options => CopyOptions(
        copyCategories: _copyCategories,
        copyOptions: _copyOptions,
        copyNotes: _copyNotes,
        copyCatalog: _copyCatalog,
        copyImages: _copyImages,
        conflict: _conflict,
      );

  CopySelection get _selection => _pickMode ? CopySelection(productKeys: _pickedKeys.toList()) : CopySelection.everything;

  List<({String key, String name, String category, int price})> get _sourceProducts {
    final list = MenuCopy.toRecord(_snapshot?.products).entries.where((e) => e.value is Map).map((e) {
      final m = Map<dynamic, dynamic>.from(e.value as Map);
      final cat = (m['category']?.toString().trim() ?? '');
      return (
        key: e.key,
        name: (m['name']?.toString().trim().isNotEmpty ?? false) ? m['name'].toString().trim() : e.key,
        category: cat.isEmpty ? 'Chưa phân loại' : cat,
        price: (m['price'] as num?)?.toInt() ?? 0,
      );
    }).toList();
    list.sort((a, b) {
      final c = a.category.compareTo(b.category);
      return c != 0 ? c : a.name.compareTo(b.name);
    });
    return list;
  }

  int get _selectedCount => _pickMode ? _pickedKeys.length : _sourceProducts.length;

  Future<void> _preview() async {
    final snap = _snapshot;
    if (snap == null) return;
    setState(() => _busy = true);
    _plans.clear();
    _planErrors.clear();
    for (final t in _targets) {
      try {
        _plans[t] = await _fb.planMenuCopy(source: snap, toStoreCode: t, selection: _selection, options: _options);
      } catch (e) {
        _planErrors[t] = '$e';
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.preview;
    });
  }

  Future<void> _run() async {
    setState(() {
      _step = _Step.running;
      _busy = true;
    });
    final user = _auth.currentUser;
    var i = 0;
    for (final t in _targets) {
      i++;
      final plan = _plans[t];
      if (plan == null) {
        _results.add('$t: ${_planErrors[t] ?? 'không dựng được kế hoạch'}');
        continue;
      }
      try {
        await _fb.applyMenuCopyPlan(
          fromStoreCode: _source,
          toStoreCode: t,
          plan: plan,
          username: user?.username ?? '',
          fullName: user?.fullName ?? '',
          role: user?.roleId ?? '',
          onProgress: (d, total) {
            if (mounted) setState(() => _progress = 'Đang sao chép sang $t ($i/${_targets.length}) — lô $d/$total');
          },
        );
        _results.add('$t: tạo ${plan.created + plan.duplicated} • ghi đè ${plan.overwritten} • bỏ qua ${plan.skipped}');
      } catch (e) {
        _results.add('$t: $e');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.done;
    });
  }

  String _label(String code) {
    final s = widget.stores.where((x) => x.storeCode == code);
    return s.isEmpty ? code : '$code - ${s.first.storeName}';
  }

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(t, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13, color: context.tc.textSecondary)),
      );

  Widget _config() {
    final products = _sourceProducts;
    final q = MenuCopy.normalizeName(_search);
    final visible = q.isEmpty ? products : products.where((p) => MenuCopy.normalizeName('${p.name} ${p.category}').contains(q)).toList();
    final byCat = <String, List<({String key, String name, String category, int price})>>{};
    for (final p in visible) {
      byCat.putIfAbsent(p.category, () => []).add(p);
    }
    final others = widget.stores.where((s) => s.storeCode != _source).toList();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('1. Chi nhánh nguồn'),
      DropdownButtonFormField<String>(
        key: ValueKey<String>(_source),
        initialValue: _source,
        items: widget.stores.map((s) => DropdownMenuItem(value: s.storeCode, child: Text(_label(s.storeCode)))).toList(),
        onChanged: (v) {
          if (v != null) {
            _source = v;
            _loadSource();
          }
        },
      ),
      if (_loadError != null) Text(_loadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
      if (_snapshot == null && _loadError == null) const Padding(padding: EdgeInsets.only(top: 6), child: Text('Đang đọc thực đơn...')),
      if (_snapshot != null)
        Text('${products.length} món • ${MenuCopy.toRecord(_snapshot!.categories).length} nhóm • ${MenuCopy.toRecord(_snapshot!.notes).length} ghi chú mẫu',
            style: TextStyle(fontSize: 12, color: context.tc.textSecondary)),
      _title('2. Chi nhánh đích (chọn nhiều)'),
      if (others.isEmpty) const Text('Cần có ít nhất 2 chi nhánh.'),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final s in others)
          FilterChip(
            label: Text(_label(s.storeCode)),
            selected: _targets.contains(s.storeCode),
            onSelected: (v) => setState(() => v ? _targets.add(s.storeCode) : _targets.remove(s.storeCode)),
          ),
      ]),
      _title('3. Món cần sao chép'),
      RadioGroup<bool>(
        groupValue: _pickMode,
        onChanged: (v) => setState(() => _pickMode = v ?? false),
        child: Column(children: [
          RadioListTile<bool>(dense: true, contentPadding: EdgeInsets.zero, value: false, title: Text('Tất cả món (${products.length})')),
          RadioListTile<bool>(dense: true, contentPadding: EdgeInsets.zero, value: true, title: Text('Chọn nhóm / món cụ thể (${_pickedKeys.length})')),
        ]),
      ),
      if (_pickMode) ...[
        TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm món hoặc nhóm...', isDense: true),
          onChanged: (v) => setState(() => _search = v),
        ),
        SizedBox(
          height: 240,
          child: ListView(children: [
            for (final e in byCat.entries) ...[
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                value: e.value.every((p) => _pickedKeys.contains(p.key)),
                title: Text('${e.key} (${e.value.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                onChanged: (v) => setState(() {
                  for (final p in e.value) {
                    v == true ? _pickedKeys.add(p.key) : _pickedKeys.remove(p.key);
                  }
                }),
              ),
              for (final p in e.value)
                CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.only(left: 24),
                  value: _pickedKeys.contains(p.key),
                  title: Text(p.name),
                  secondary: Text('${p.price}đ', style: TextStyle(fontSize: 12, color: context.tc.textSecondary)),
                  onChanged: (v) => setState(() => v == true ? _pickedKeys.add(p.key) : _pickedKeys.remove(p.key)),
                ),
            ],
          ]),
        ),
      ],
      _title('4. Sao chép kèm (giá, tên, đơn vị luôn được sao chép)'),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _copyCategories, onChanged: (v) => setState(() => _copyCategories = v ?? true), title: const Text('Tạo nhóm còn thiếu ở đích (theo tên)')),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _copyOptions, onChanged: (v) => setState(() => _copyOptions = v ?? true), title: const Text('Size, topping, đường/đá')),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _copyNotes, onChanged: (v) => setState(() => _copyNotes = v ?? true), title: const Text('Ghi chú mẫu')),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _copyCatalog, onChanged: (v) => setState(() => _copyCatalog = v ?? true), title: const Text('Danh mục note & topping (và phần gắn vào món)')),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _copyImages, onChanged: (v) => setState(() => _copyImages = v ?? true), title: const Text('Hình ảnh')),
      _title('5. Món đã có ở đích (trùng tên + nhóm)'),
      RadioGroup<ConflictPolicy>(
        groupValue: _conflict,
        onChanged: (v) => setState(() => _conflict = v ?? ConflictPolicy.skip),
        child: const Column(children: [
          RadioListTile<ConflictPolicy>(dense: true, contentPadding: EdgeInsets.zero, value: ConflictPolicy.skip, title: Text('Bỏ qua (giữ món đang có)')),
          RadioListTile<ConflictPolicy>(dense: true, contentPadding: EdgeInsets.zero, value: ConflictPolicy.overwrite, title: Text('Ghi đè giá & thông tin')),
          RadioListTile<ConflictPolicy>(dense: true, contentPadding: EdgeInsets.zero, value: ConflictPolicy.duplicate, title: Text('Tạo bản sao (thêm hậu tố)')),
        ]),
      ),
      Text('Không có thao tác nào xóa dữ liệu ở chi nhánh đích. Mã món ở đích được cấp mới, không trùng.',
          style: TextStyle(fontSize: 11, color: context.tc.textSecondary)),
    ]);
  }

  Widget _previewView() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Nguồn $_source • $_selectedCount món được chọn. Xem lại rồi bấm Xác nhận.'),
      const SizedBox(height: 8),
      for (final t in _targets)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label(t), style: const TextStyle(fontWeight: FontWeight.w700)),
              if (_planErrors.containsKey(t))
                Text('Không đọc được chi nhánh đích: ${_planErrors[t]}', style: const TextStyle(color: Colors.red))
              else if (_plans[t] != null)
                Text(
                  'Tạo mới: ${_plans[t]!.created}'
                  '${_conflict == ConflictPolicy.overwrite ? ' • Ghi đè: ${_plans[t]!.overwritten}' : ''}'
                  '${_conflict == ConflictPolicy.duplicate ? ' • Bản sao: ${_plans[t]!.duplicated}' : ''}'
                  ' • Bỏ qua: ${_plans[t]!.skipped}'
                  ' • Nhóm mới: ${_plans[t]!.categoriesCreated}'
                  ' • Ghi chú mới: ${_plans[t]!.notesToAdd} • Nhóm note/topping mới: ${_plans[t]!.groupsToAdd}',
                ),
            ]),
          ),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final canPreview = _snapshot != null && _targets.isNotEmpty && _selectedCount > 0 && !_busy;
    final canRun = _plans.values.any((p) => p.updates.isNotEmpty);
    Widget body;
    List<Widget> actions;
    switch (_step) {
      case _Step.config:
        body = _config();
        actions = [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(onPressed: canPreview ? _preview : null, child: Text(_busy ? 'Đang tính...' : 'Xem trước')),
        ];
      case _Step.preview:
        body = _previewView();
        actions = [
          TextButton(onPressed: () => setState(() => _step = _Step.config), child: const Text('Quay lại')),
          ElevatedButton(onPressed: canRun ? _run : null, child: const Text('Xác nhận sao chép')),
        ];
      case _Step.running:
        body = Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Expanded(child: Text(_progress.isEmpty ? 'Đang sao chép...' : _progress))]);
        actions = const [];
      case _Step.done:
        body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final r in _results) Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text(r))]);
        actions = [ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))];
    }
    return AlertDialog(
      title: Text('Sao chép thực đơn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: body)),
      actions: actions,
    );
  }
}
