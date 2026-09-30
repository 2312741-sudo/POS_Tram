// lib/features/category_management/category_management_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  final _fb = FirebaseService();
  List<CategoryModel> _categories = [];

  @override
  void initState() {
    super.initState();
    _fb.categoriesStream().listen((c) { if (mounted) setState(() => _categories = c); });
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Thêm danh mục', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
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
                await _fb.saveCategory(CategoryModel(name: ctrl.text.trim()));
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
      message: 'Xóa danh mục "${cat.name}"?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) await _fb.deleteCategory(cat);
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
      body: _categories.isEmpty
        ? EmptyState(
            icon: Icons.category_outlined,
            title: 'Chưa có danh mục',
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: Text('Thêm', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}
