// lib/features/category_management/category_management_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/item_options.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';
import '../menu_management/attachment_picker.dart';
import '../menu_management/note_catalog_access.dart';

class CategoryManagementScreen extends StatefulWidget {
  final String? initialStoreCode;
  const CategoryManagementScreen({super.key, this.initialStoreCode});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  late String _selectedStoreCode;
  List<StoreInfoModel> _availableStores = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;

  StreamSubscription<List<CategoryModel>>? _catSub;
  StreamSubscription<ItemCatalog>? _catalogSub;
  ItemCatalog _catalog = const ItemCatalog();
  StreamSubscription<List<StoreInfoModel>>? _storesSub;

  @override
  void initState() {
    super.initState();
    _selectedStoreCode = widget.initialStoreCode ?? _auth.currentStoreCode;
    _loadStores();
    _subscribeToCategories(_selectedStoreCode);
  }

  @override
  void dispose() {
    _catSub?.cancel();
    _catalogSub?.cancel();
    _storesSub?.cancel();
    super.dispose();
  }

  void _loadStores() {
    _storesSub = _fb.storesStream().listen((stores) {
      if (mounted) {
        setState(() {
          _availableStores = stores;
          if (!_availableStores.any((s) => s.storeCode == _selectedStoreCode)) {
            if (_availableStores.isNotEmpty) {
              _selectedStoreCode = _availableStores.first.storeCode;
              _subscribeToCategories(_selectedStoreCode);
            }
          }
        });
      }
    });
  }

  void _subscribeToCategories(String storeCode) {
    setState(() => _loading = true);
    _catSub?.cancel();
    _catalogSub?.cancel();
    _catalogSub = _fb.itemCatalogStream(storeCode: storeCode).listen((c) {
      if (mounted) setState(() => _catalog = c);
    });
    _catSub = _fb.categoriesStream(storeCode: storeCode).listen((c) {
      if (mounted) {
        setState(() {
          _categories = c;
          _loading = false;
        });
      }
    });
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thêm danh mục', style: GoogleFonts.beVietnamPro(
              color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
            Text('Chi nhánh: $_selectedStoreCode',
              style: GoogleFonts.beVietnamPro(color: context.tc.primary, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: context.tc.textPrimary),
          decoration: InputDecoration(
            labelText: 'Tên danh mục',
            prefixIcon: Icon(Icons.category_outlined, color: context.tc.textSecondary),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await _fb.saveCategory(
                  CategoryModel(name: ctrl.text.trim()),
                  storeCode: _selectedStoreCode,
                );
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  /// Gắn danh mục note / nhóm topping cho cả nhóm món (món có thể ghi đè riêng)
  void _editAttachments(CategoryModel cat) {
    List<String>? noteIds = cat.noteGroupIds;
    List<String>? toppingIds = cat.toppingGroupIds;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Note & topping: ${cat.name}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Áp dụng cho mọi món trong nhóm, trừ món đã tùy chỉnh riêng.',
                    style: TextStyle(fontSize: 12, color: context.tc.textSecondary)),
                AttachmentPicker(
                  title: 'Danh mục note áp dụng',
                  icon: Icons.sticky_note_2_outlined,
                  isProduct: false,
                  options: [for (final g in _catalog.noteGroups) (g.id, g.active ? g.name : '${g.name} (đã tắt)')],
                  value: noteIds,
                  onChanged: (v) => setSt(() => noteIds = v),
                ),
                AttachmentPicker(
                  title: 'Nhóm topping áp dụng',
                  icon: Icons.add_circle_outline,
                  isProduct: false,
                  options: [for (final g in _catalog.toppingGroups) (g.id, g.active ? g.name : '${g.name} (đã tắt)')],
                  value: toppingIds,
                  onChanged: (v) => setSt(() => toppingIds = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                final n = (noteIds ?? const <String>[]).where((e) => e != kNoGroups).toList();
                final t = (toppingIds ?? const <String>[]).where((e) => e != kNoGroups).toList();
                await _fb.saveCategory(
                  cat.copyWith(
                    noteGroupIds: n,
                    toppingGroupIds: t,
                    clearNoteGroupIds: n.isEmpty,
                    clearToppingGroupIds: t.isEmpty,
                  ),
                  storeCode: _selectedStoreCode,
                );
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCategory(CategoryModel cat) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa danh mục',
      message: 'Xóa danh mục "${cat.name}" khỏi chi nhánh $_selectedStoreCode?\n(Các món thuộc danh mục này trong chi nhánh khác không bị ảnh hưởng)',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _fb.deleteCategory(cat, storeCode: _selectedStoreCode);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        title: Text('Quản lý danh mục', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Store Selector Bar
          Container(
            color: context.tc.cardElevated,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.storefront, color: context.tc.primary, size: 20),
                const SizedBox(width: 8),
                Text('Chi nhánh:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: context.tc.textPrimary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.tc.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.tc.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableStores.any((s) => s.storeCode == _selectedStoreCode) ? _selectedStoreCode : null,
                        hint: Text(_selectedStoreCode),
                        isExpanded: true,
                        dropdownColor: context.tc.card,
                        items: _availableStores.map((s) => DropdownMenuItem(
                          value: s.storeCode,
                          child: Text(
                            '${s.storeCode} • ${s.storeName}',
                            style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textPrimary, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null && val != _selectedStoreCode) {
                            setState(() {
                              _selectedStoreCode = val;
                            });
                            _subscribeToCategories(val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _categories.isEmpty
                ? EmptyState(
                    icon: Icons.category_outlined,
                    title: 'Chưa có danh mục cho chi nhánh $_selectedStoreCode',
                    action: ElevatedButton.icon(
                      onPressed: _showAddDialog,
                      icon: const Icon(Icons.add),
                      label: const Text('Thêm danh mục'),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _categories.length,
                    // onReorderItem đã tự hiệu chỉnh newIndex sau khi bỏ phần tử ở oldIndex.
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _categories.removeAt(oldIndex);
                        _categories.insert(newIndex, item);
                      });
                      // Lưu lên máy chủ để web và các máy khác thấy cùng thứ tự
                      _fb.setCategoryOrder(_categories.map((c) => c.name).toList(), storeCode: _selectedStoreCode).catchError((Object e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Không lưu được thứ tự danh mục: $e'), backgroundColor: Colors.red),
                        );
                      });
                    },
                    itemBuilder: (_, i) => Container(
                      key: ValueKey(_categories[i].name),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: context.tc.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.tc.border),
                      ),
                      child: ListTile(
                        onTap: canManageNoteCatalog(_auth) ? () => _editAttachments(_categories[i]) : null,
                        subtitle: canManageNoteCatalog(_auth)
                            ? Text(
                                (_categories[i].noteGroupIds?.isNotEmpty ?? false) || (_categories[i].toppingGroupIds?.isNotEmpty ?? false)
                                    ? 'Đã gắn note/topping • bấm để sửa'
                                    : 'Chưa gắn note/topping • bấm để thiết lập',
                                style: const TextStyle(fontSize: 11),
                              )
                            : null,
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: context.tc.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.category_outlined, color: context.tc.primary, size: 18),
                        ),
                        title: Text(_categories[i].name, style: GoogleFonts.beVietnamPro(
                          color: context.tc.textPrimary, fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.drag_handle, color: context.tc.textHint, size: 20),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Icon(Icons.delete_outline, color: context.tc.danger, size: 20),
                              onPressed: () => _deleteCategory(_categories[i]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Thêm danh mục vào [$_selectedStoreCode]', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
