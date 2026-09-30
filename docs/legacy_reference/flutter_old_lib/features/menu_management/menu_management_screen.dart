// lib/features/menu_management/menu_management_screen.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class MenuManagementScreen extends StatefulWidget {
  const MenuManagementScreen({super.key});

  @override
  State<MenuManagementScreen> createState() => _MenuManagementScreenState();
}

class _MenuManagementScreenState extends State<MenuManagementScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  final _picker = ImagePicker();
  String _categoryFilter = 'Tất cả';
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];

  @override
  void initState() {
    super.initState();
    _fb.productsStream().listen((p) { if (mounted) setState(() => _products = p); });
    _fb.categoriesStream().listen((c) { if (mounted) setState(() => _categories = c); });
  }

  List<ProductModel> get _filtered => _products.where((p) =>
    _categoryFilter == 'Tất cả' || p.category == _categoryFilter
  ).toList();

  Future<String?> _pickAndEncodeImage() async {
    try {
      final img = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 70);
      if (img == null) return null;
      final bytes = await File(img.path).readAsBytes();
      return base64Encode(bytes);
    } catch (_) { return null; }
  }

  void _showProductDialog({ProductModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '');
    String selectedCat = existing?.category ?? (_categories.isNotEmpty ? _categories.first.name : '');
    String? base64Image = existing?.imageBase64;
    
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm',
            style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Image picker
                GestureDetector(
                  onTap: () async {
                    final img = await _pickAndEncodeImage();
                    if (img != null) setSt(() => base64Image = img);
                  },
                  child: Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: AppColors.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: base64Image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.memory(base64Decode(base64Image!.contains(',') ? base64Image!.split(',').last : base64Image!), fit: BoxFit.cover))
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 32),
                            SizedBox(height: 4),
                            Text('Chọn ảnh', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm *')),
                const SizedBox(height: 12),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Giá (đ) *')),
                const SizedBox(height: 12),
                TextField(controller: unitCtrl, style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Đơn vị (ly, phần, ...)')),
                const SizedBox(height: 12),
                if (_categories.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: selectedCat.isEmpty ? null : selectedCat,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Danh mục'),
                    items: _categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                    onChanged: (v) => setSt(() => selectedCat = v ?? ''),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary))),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                final product = ProductModel(
                  name: nameCtrl.text.trim(),
                  price: int.tryParse(priceCtrl.text.trim()) ?? 0,
                  unit: unitCtrl.text.trim().isEmpty ? 'phần' : unitCtrl.text.trim(),
                  category: selectedCat,
                  imageBase64: base64Image,
                );
                await _fb.saveProduct(product);
                await _fb.logAction(AuditLogModel(
                  action: existing == null ? 'ADD_PRODUCT' : 'EDIT_PRODUCT',
                  username: _auth.currentUser?.username ?? '',
                  userRole: _auth.currentUser?.role ?? '',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  details: '${existing == null ? "Thêm" : "Sửa"} sản phẩm: ${product.name}',
                  targetId: product.name,
                ));
                if (mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Thêm' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa sản phẩm',
      message: 'Xóa "${product.name}"?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _fb.deleteProduct(product);
      await _fb.logAction(AuditLogModel(
        action: 'DELETE_PRODUCT',
        username: _auth.currentUser?.username ?? '',
        userRole: _auth.currentUser?.role ?? '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Xóa sản phẩm: ${product.name}',
        targetId: product.name,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Quản lý thực đơn', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined, color: AppColors.textSecondary),
            onPressed: () => context.push('/category-management'),
            tooltip: 'Quản lý danh mục',
          ),
        ],
      ),
      body: Column(
        children: [
          // Category filter
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              itemCount: _categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = i == 0 ? 'Tất cả' : _categories[i - 1].name;
                final sel = _categoryFilter == cat;
                return GestureDetector(
                  onTap: () => setState(() => _categoryFilter = cat),
                  child: AnimatedContainer(
                    duration: 200.ms,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: sel ? AppColors.primary : AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? AppColors.primary : AppColors.border),
                    ),
                    child: Text(cat, style: GoogleFonts.beVietnamPro(
                      color: sel ? Colors.white : AppColors.textSecondary,
                      fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 13,
                    )),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
              ? EmptyState(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'Chưa có sản phẩm',
                  action: ElevatedButton.icon(
                    onPressed: () => _showProductDialog(),
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm sản phẩm'),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filtered.length,
                  separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 12),
                  itemBuilder: (_, i) => _ProductItem(
                    product: _filtered[i],
                    onEdit: () => _showProductDialog(existing: _filtered[i]),
                    onDelete: () => _deleteProduct(_filtered[i]),
                  ).animate(delay: (i * 30).ms).fadeIn(duration: 200.ms),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        icon: const Icon(Icons.add),
        label: Text('Thêm món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _ProductItem extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ProductItem({required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 60, height: 60,
              child: product.imageBase64 != null && product.imageBase64!.isNotEmpty
                ? Image.memory(base64Decode(product.imageBase64!.contains(',') ? product.imageBase64!.split(',').last : product.imageBase64!), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.cardElevated,
                      child: const Icon(Icons.restaurant, color: AppColors.textHint),
                    ))
                : Container(
                    color: AppColors.cardElevated,
                    child: const Icon(Icons.restaurant, color: AppColors.textHint),
                  ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14,
                )),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(FormatUtils.currency(product.price), style: GoogleFonts.beVietnamPro(
                      color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14,
                    )),
                    const SizedBox(width: 8),
                    Text('• ${product.unit}', style: GoogleFonts.beVietnamPro(
                      color: AppColors.textSecondary, fontSize: 12,
                    )),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(product.category, style: GoogleFonts.beVietnamPro(
                        color: AppColors.textSecondary, fontSize: 10,
                      )),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                tooltip: 'Sửa',
              ),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                tooltip: 'Xóa',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
