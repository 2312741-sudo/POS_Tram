// lib/features/menu_management/menu_management_screen.dart
import 'dart:async';
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

  late String _selectedStoreCode;
  List<StoreInfoModel> _availableStores = [];
  String _categoryFilter = 'Tất cả';
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;

  StreamSubscription<List<ProductModel>>? _prodSub;
  StreamSubscription<List<CategoryModel>>? _catSub;
  StreamSubscription<List<StoreInfoModel>>? _storesSub;

  @override
  void initState() {
    super.initState();
    _selectedStoreCode = _auth.currentStoreCode;
    _loadStores();
    _subscribeToStoreMenu(_selectedStoreCode);
  }

  @override
  void dispose() {
    _prodSub?.cancel();
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
              _subscribeToStoreMenu(_selectedStoreCode);
            }
          }
        });
      }
    });
  }

  void _subscribeToStoreMenu(String storeCode) {
    setState(() => _loading = true);
    _prodSub?.cancel();
    _catSub?.cancel();

    _prodSub = _fb.productsStream(storeCode: storeCode).listen((p) {
      if (mounted) {
        setState(() {
          _products = p;
          _loading = false;
        });
      }
    });

    _catSub = _fb.categoriesStream(storeCode: storeCode).listen((c) {
      if (mounted) {
        setState(() {
          _categories = c;
        });
      }
    });
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
    final costPriceCtrl = TextEditingController(text: existing?.costPrice != null ? existing!.costPrice.toString() : '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '');
    String selectedCat = existing?.category ?? (_categories.isNotEmpty ? _categories.first.name : '');
    String? base64Image = existing?.imageBase64;
    
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm',
                style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
              Text('Chi nhánh: $_selectedStoreCode',
                style: GoogleFonts.beVietnamPro(color: TramColors.brandPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
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
                      : (existing?.assetPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.asset(existing!.assetPath!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 32),
                                  SizedBox(height: 4),
                                  Text('Chọn ảnh', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                ],
                              )))
                          : const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary, size: 32),
                                SizedBox(height: 4),
                                Text('Chọn ảnh', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                              ],
                            )),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm *')),
                const SizedBox(height: 12),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Giá bán (đ) *')),
                const SizedBox(height: 12),
                TextField(controller: costPriceCtrl, keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(labelText: 'Giá vốn (đ, để tính lãi gộp)')),
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
                final costParsed = int.tryParse(costPriceCtrl.text.trim());
                final baseProd = existing ?? ProductModel(
                  name: nameCtrl.text.trim(),
                  price: int.tryParse(priceCtrl.text.trim()) ?? 0,
                  unit: unitCtrl.text.trim().isEmpty ? 'phần' : unitCtrl.text.trim(),
                  category: selectedCat.isEmpty ? 'Món khác' : selectedCat,
                );
                final product = baseProd.copyWith(
                  name: nameCtrl.text.trim(),
                  price: int.tryParse(priceCtrl.text.trim()) ?? 0,
                  costPrice: costParsed,
                  unit: unitCtrl.text.trim().isEmpty ? 'phần' : unitCtrl.text.trim(),
                  category: selectedCat.isEmpty ? 'Món khác' : selectedCat,
                  imageBase64: base64Image,
                  imageResourceName: base64Image == null ? existing?.imageResourceName : null,
                  isAvailable: existing?.isAvailable ?? true,
                );
                await _fb.saveProduct(product, storeCode: _selectedStoreCode);
                await _fb.logAction(AuditLogModel(
                  action: existing == null ? 'ADD_PRODUCT' : 'EDIT_PRODUCT',
                  username: _auth.currentUser?.username ?? '',
                  userFullName: _auth.currentUser?.fullName ?? 'Quản Lý',
                  userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  targetType: 'PRODUCT',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  details: '${existing == null ? "Thêm" : "Sửa"} sản phẩm [$_selectedStoreCode]: ${product.name} (giá vốn: ${product.costPrice ?? 0}đ)',
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

  Future<void> _toggleProductAvailability(ProductModel product) async {
    final updated = ProductModel(
      id: product.id,
      name: product.name,
      code: product.code,
      price: product.price,
      unit: product.unit,
      category: product.category,
      imageBase64: product.imageBase64,
      imageResourceName: product.imageResourceName,
      isAvailable: !product.isAvailable,
      sizes: product.sizes,
      allowedToppings: product.allowedToppings,
      hasIceSugarOptions: product.hasIceSugarOptions,
    );
    await _fb.saveProduct(updated, storeCode: _selectedStoreCode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.name}: ${updated.isAvailable ? "Đang bán" : "Tạm ngưng bán"}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _deleteProduct(ProductModel product) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa sản phẩm',
      message: 'Xóa "${product.name}" khỏi thực đơn chi nhánh $_selectedStoreCode?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _fb.deleteProduct(product, storeCode: _selectedStoreCode);
      await _fb.logAction(AuditLogModel(
        action: 'DELETE_PRODUCT',
        username: _auth.currentUser?.username ?? '',
        userFullName: _auth.currentUser?.fullName ?? 'Quản Lý',
        userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
        targetType: 'PRODUCT',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Xóa sản phẩm [$_selectedStoreCode]: ${product.name}',
        targetId: product.name,
      ));
    }
  }

  Future<void> _showCopyMenuDialog() async {
    final otherStores = _availableStores.where((s) => s.storeCode != _selectedStoreCode).toList();
    if (otherStores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có chi nhánh khác để sao chép!')),
      );
      return;
    }

    String sourceStore = otherStores.first.storeCode;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Sao Chép Thực Đơn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sao chép toàn bộ món và nhóm danh mục sang chi nhánh hiện tại ($_selectedStoreCode):',
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: sourceStore,
                decoration: const InputDecoration(labelText: 'Chọn chi nhánh nguồn'),
                items: otherStores.map((s) => DropdownMenuItem(
                  value: s.storeCode,
                  child: Text('${s.storeCode} - ${s.storeName}'),
                )).toList(),
                onChanged: (val) {
                  if (val != null) setSt(() => sourceStore = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final count = await _fb.copyMenuBetweenStores(
                  fromStoreCode: sourceStore,
                  toStoreCode: _selectedStoreCode,
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã sao chép $count món từ $sourceStore sang $_selectedStoreCode thành công!'),
                      backgroundColor: TramColors.success,
                    ),
                  );
                }
              },
              child: const Text('Sao chép ngay'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showClearMenuDialog() async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Làm trống thực đơn chi nhánh',
      message: 'CẢNH BÁO: Xóa TOÀN BỘ sản phẩm và danh mục của chi nhánh $_selectedStoreCode?\n(Các chi nhánh khác sẽ không bị ảnh hưởng)',
      confirmText: 'Xóa toàn bộ',
      isDanger: true,
    );
    if (confirm == true) {
      await _fb.clearStoreMenu(_selectedStoreCode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã làm trống thực đơn của chi nhánh $_selectedStoreCode!'),
            backgroundColor: TramColors.warningInk,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> catSet = {'Tất cả'};
    for (final c in _categories) {
      if (c.name.isNotEmpty) catSet.add(c.name);
    }
    for (final p in _products) {
      if (p.category.isNotEmpty) catSet.add(p.category);
    }
    final cats = catSet.toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Quản lý thực đơn', style: GoogleFonts.beVietnamPro(
          color: Colors.white, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.category_outlined, color: Colors.white),
            onPressed: () => context.push('/category-management', extra: _selectedStoreCode),
            tooltip: 'Quản lý danh mục',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'COPY') _showCopyMenuDialog();
              if (val == 'CLEAR') _showClearMenuDialog();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'COPY',
                child: Row(
                  children: [
                    Icon(Icons.copy_all_outlined, size: 18, color: TramColors.brandPrimary),
                    SizedBox(width: 8),
                    Text('Sao chép từ chi nhánh khác...'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'CLEAR',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 18, color: TramColors.danger),
                    SizedBox(width: 8),
                    Text('Làm trống menu chi nhánh này', style: TextStyle(color: TramColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
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
                              _categoryFilter = 'Tất cả';
                            });
                            _subscribeToStoreMenu(val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Menu Stats Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: AppColors.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Thực đơn [$_selectedStoreCode]: ${_products.length} món • ${_categories.length} nhóm',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Đang bán: ${_products.where((p) => p.isAvailable).length}',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.success, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Category filter
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final cat = cats[i];
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
            child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                ? EmptyState(
                    icon: Icons.restaurant_menu_outlined,
                    title: 'Chưa có sản phẩm cho chi nhánh $_selectedStoreCode',
                    subtitle: 'Thêm món mới hoặc sao chép từ chi nhánh khác.',
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showProductDialog(),
                          icon: const Icon(Icons.add),
                          label: const Text('Thêm sản phẩm'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _showCopyMenuDialog,
                          icon: const Icon(Icons.copy_all),
                          label: const Text('Sao chép món'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 12),
                    itemBuilder: (_, i) => _ProductItem(
                      product: _filtered[i],
                      onEdit: () => _showProductDialog(existing: _filtered[i]),
                      onToggleAvailability: () => _toggleProductAvailability(_filtered[i]),
                      onDelete: () => _deleteProduct(_filtered[i]),
                    ).animate(delay: (i * 20).ms).fadeIn(duration: 180.ms),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showProductDialog(),
        icon: const Icon(Icons.add),
        label: Text('Thêm món mới', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

class _ProductItem extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onEdit;
  final VoidCallback onToggleAvailability;
  final VoidCallback onDelete;

  const _ProductItem({
    required this.product,
    required this.onEdit,
    required this.onToggleAvailability,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onEdit,
      child: Container(
        color: Colors.transparent,
        child: Row(
          children: [
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 60, height: 60,
                child: (product.imageBase64 != null && product.imageBase64!.isNotEmpty)
                  ? Image.memory(base64Decode(product.imageBase64!.contains(',') ? product.imageBase64!.split(',').last : product.imageBase64!), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.cardElevated,
                        child: const Icon(Icons.restaurant, color: AppColors.textHint),
                      ))
                  : (product.assetPath != null
                      ? Image.asset(
                          product.assetPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.cardElevated,
                            child: const Icon(Icons.restaurant, color: AppColors.textHint),
                          ),
                        )
                      : Container(
                          color: AppColors.cardElevated,
                          child: const Icon(Icons.restaurant, color: AppColors.textHint),
                        )),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: GoogleFonts.beVietnamPro(
                            color: product.isAvailable ? AppColors.textPrimary : Colors.grey,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            decoration: product.isAvailable ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      if (!product.isAvailable)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                          child: Text('Tạm ngưng', style: GoogleFonts.beVietnamPro(color: Colors.red.shade800, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
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
                      if (product.costPrice != null && product.costPrice! > 0) ...[
                        const SizedBox(width: 8),
                        Text('• Vốn: ${FormatUtils.currency(product.costPrice!)}', style: GoogleFonts.beVietnamPro(
                          color: AppColors.textSecondary, fontSize: 11,
                        )),
                      ],
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
                  onPressed: onToggleAvailability,
                  icon: Icon(
                    product.isAvailable ? Icons.check_circle_outline : Icons.pause_circle_outline,
                    color: product.isAvailable ? TramColors.success : Colors.grey,
                    size: 20,
                  ),
                  tooltip: product.isAvailable ? 'Đang bán (Bấm để tạm ngưng)' : 'Tạm ngưng (Bấm để mở bán)',
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                  tooltip: 'Sửa món',
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                  tooltip: 'Xóa khỏi chi nhánh',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
