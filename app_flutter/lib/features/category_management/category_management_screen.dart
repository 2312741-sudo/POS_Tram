// lib/features/category_management/category_management_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

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
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thêm danh mục', style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            Text('Chi nhánh: $_selectedStoreCode',
              style: GoogleFonts.beVietnamPro(color: TramColors.brandPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            labelText: 'Tên danh mục',
            prefixIcon: Icon(Icons.category_outlined, color: AppColors.textSecondary),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary))),
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Quản lý danh mục', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // Store Selector Bar
          Container(
            color: AppColors.cardElevated,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.storefront, color: TramColors.brandPrimary, size: 20),
                const SizedBox(width: 8),
                Text('Chi nhánh:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableStores.any((s) => s.storeCode == _selectedStoreCode) ? _selectedStoreCode : null,
                        hint: Text(_selectedStoreCode),
                        isExpanded: true,
                        dropdownColor: AppColors.card,
                        items: _availableStores.map((s) => DropdownMenuItem(
                          value: s.storeCode,
                          child: Text(
                            '${s.storeCode} • ${s.storeName}',
                            style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
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
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _categories.removeAt(oldIndex);
                        _categories.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (_, i) => Container(
                      key: ValueKey(_categories[i].name),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.category_outlined, color: AppColors.primary, size: 18),
                        ),
                        title: Text(_categories[i].name, style: GoogleFonts.beVietnamPro(
                          color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.drag_handle, color: AppColors.textHint, size: 20),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
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
        icon: const Icon(Icons.add),
        label: Text('Thêm danh mục vào [$_selectedStoreCode]', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
