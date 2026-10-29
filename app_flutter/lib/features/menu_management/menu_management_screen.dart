// lib/features/menu_management/menu_management_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/domain/item_options.dart';
import '../../core/domain/menu_copy.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';
import 'attachment_picker.dart';
import 'copy_menu_dialog.dart';
import 'note_catalog_access.dart';
import 'note_catalog_screen.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

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
  Timer? _safetyTimer;

  StreamSubscription<List<ProductModel>>? _prodSub;
  StreamSubscription<List<CategoryModel>>? _catSub;
  StreamSubscription<ItemCatalog>? _catalogSub;
  ItemCatalog _catalog = const ItemCatalog();
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
    _safetyTimer?.cancel();
    _prodSub?.cancel();
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
              _subscribeToStoreMenu(_selectedStoreCode);
            }
          }
        });
      }
    });
  }

  void _subscribeToStoreMenu(String storeCode) {
    setState(() => _loading = true);
    _safetyTimer?.cancel();
    _safetyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _loading) setState(() => _loading = false);
    });

    _prodSub?.cancel();
    _catSub?.cancel();
    _catalogSub?.cancel();
    _catalogSub = _fb.itemCatalogStream(storeCode: storeCode).listen((c) {
      if (mounted) setState(() => _catalog = c);
    });

    _prodSub = _fb.productsStream(storeCode: storeCode).listen((p) {
      _safetyTimer?.cancel();
      if (mounted) {
        setState(() {
          _products = p;
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
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
    final codeCtrl = TextEditingController(
      text: existing?.code.isNotEmpty == true
          ? existing!.code
          : (existing == null ? 'SP${(_products.length + 1).toString().padLeft(3, '0')}' : ''),
    );
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(text: existing?.price.toString() ?? '');
    final costPriceCtrl = TextEditingController(text: existing?.costPrice != null ? existing!.costPrice.toString() : '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? '');
    String selectedCat = existing?.category ?? (_categories.isNotEmpty ? _categories.first.name : '');
    String? base64Image = existing?.imageBase64;
    bool isTopping = existing?.isTopping ?? false;
    final canCatalog = canManageNoteCatalog(_auth);
    List<String>? noteIds = existing?.noteGroupIds; // null = kế thừa nhóm món
    List<String>? toppingIds = existing?.toppingGroupIds;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: context.tc.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'Thêm sản phẩm' : 'Sửa sản phẩm',
                style: GoogleFonts.beVietnamPro(color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
              Text('Chi nhánh: $_selectedStoreCode',
                style: GoogleFonts.beVietnamPro(color: context.tc.primary, fontSize: 12, fontWeight: FontWeight.bold)),
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
                      color: context.tc.cardElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.tc.border),
                    ),
                    child: base64Image != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: Image.memory(base64Decode(base64Image!.contains(',') ? base64Image!.split(',').last : base64Image!), fit: BoxFit.cover))
                      : (existing?.assetPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.asset(existing!.assetPath!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(LucideIcons.imagePlus, color: context.tc.textSecondary, size: 32),
                                  const SizedBox(height: 4),
                                  Text('Chọn ảnh', style: TextStyle(color: context.tc.textSecondary, fontSize: 11)),
                                ],
                              )))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.imagePlus, color: context.tc.textSecondary, size: 32),
                                const SizedBox(height: 4),
                                Text('Chọn ảnh', style: TextStyle(color: context.tc.textSecondary, fontSize: 11)),
                              ],
                            )),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: codeCtrl,
                  style: TextStyle(color: context.tc.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Mã món / SKU',
                    hintText: 'VD: SP001, TRA01...',
                    prefixIcon: Icon(LucideIcons.qrCode),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, style: TextStyle(color: context.tc.textPrimary),
                  decoration: const InputDecoration(labelText: 'Tên sản phẩm *')),
                const SizedBox(height: 12),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number,
                  style: TextStyle(color: context.tc.textPrimary),
                  decoration: const InputDecoration(labelText: 'Giá bán (đ) *')),
                const SizedBox(height: 12),
                TextField(controller: costPriceCtrl, keyboardType: TextInputType.number,
                  style: TextStyle(color: context.tc.textPrimary),
                  decoration: const InputDecoration(labelText: 'Giá vốn (đ, để tính lãi gộp)')),
                const SizedBox(height: 12),
                TextField(controller: unitCtrl, style: TextStyle(color: context.tc.textPrimary),
                  decoration: const InputDecoration(labelText: 'Đơn vị (ly, phần, ...)')),
                const SizedBox(height: 12),
                if (_categories.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey<Object?>(selectedCat.isEmpty ? null : selectedCat),
                    initialValue: selectedCat.isEmpty ? null : selectedCat,
                    dropdownColor: context.tc.card,
                    style: TextStyle(color: context.tc.textPrimary),
                    decoration: const InputDecoration(labelText: 'Danh mục'),
                    items: _categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name))).toList(),
                    onChanged: (v) => setSt(() => selectedCat = v ?? ''),
                  ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Món này là Topping', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Có thể thêm vào các món nước/trà khác', style: TextStyle(fontSize: 12)),
                  value: isTopping,
                  activeColor: context.tc.primary,
                  onChanged: (val) => setSt(() => isTopping = val ?? false),
                ),
                if (canCatalog && !isTopping) ...[
                  Builder(builder: (_) {
                    CategoryModel? cat;
                    for (final c in _categories) {
                      if (c.name == selectedCat) cat = c;
                    }
                    String names(List<String>? ids, Map<String, String> byId) {
                      final l = (ids ?? const <String>[]).map((i) => byId[i]).whereType<String>().toList();
                      return l.isEmpty ? 'không có' : l.join(', ');
                    }
                    final noteById = {for (final g in _catalog.noteGroups) g.id: g.name};
                    final topById = {for (final g in _catalog.toppingGroups) g.id: g.name};
                    return Column(children: [
                      AttachmentPicker(
                        title: 'Danh mục note áp dụng',
                        icon: LucideIcons.stickyNote,
                        options: [for (final g in _catalog.noteGroups) (g.id, g.active ? g.name : '${g.name} (đã tắt)')],
                        value: noteIds,
                        inheritedLabel: names(cat?.noteGroupIds, noteById),
                        onChanged: (v) => setSt(() => noteIds = v),
                      ),
                      AttachmentPicker(
                        title: 'Nhóm topping áp dụng',
                        icon: LucideIcons.circlePlus,
                        options: [for (final g in _catalog.toppingGroups) (g.id, g.active ? g.name : '${g.name} (đã tắt)')],
                        value: toppingIds,
                        inheritedLabel: names(cat?.toppingGroupIds, topById),
                        onChanged: (v) => setSt(() => toppingIds = v),
                      ),
                    ]);
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary))),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                final costParsed = int.tryParse(costPriceCtrl.text.trim());
                final baseProd = existing ?? ProductModel(
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  price: int.tryParse(priceCtrl.text.trim()) ?? 0,
                  unit: unitCtrl.text.trim().isEmpty ? 'phần' : unitCtrl.text.trim(),
                  category: selectedCat.isEmpty ? 'Món khác' : selectedCat,
                  isTopping: isTopping,
                );
                final product = baseProd.copyWith(
                  name: nameCtrl.text.trim(),
                  code: codeCtrl.text.trim(),
                  price: int.tryParse(priceCtrl.text.trim()) ?? 0,
                  costPrice: costParsed,
                  unit: unitCtrl.text.trim().isEmpty ? 'phần' : unitCtrl.text.trim(),
                  category: selectedCat.isEmpty ? 'Món khác' : selectedCat,
                  imageBase64: base64Image,
                  imageResourceName: base64Image == null ? existing?.imageResourceName : null,
                  isAvailable: existing?.isAvailable ?? true,
                  isTopping: isTopping,
                  // Chỉ người có quyền quản lý danh mục mới đổi phần gắn note/topping
                  noteGroupIds: canCatalog ? noteIds : null,
                  toppingGroupIds: canCatalog ? toppingIds : null,
                  clearNoteGroupIds: canCatalog && noteIds == null,
                  clearToppingGroupIds: canCatalog && toppingIds == null,
                );
                await _fb.saveProduct(product, storeCode: _selectedStoreCode);
                await _fb.logAction(AuditLogModel(
                  action: existing == null ? 'ADD_PRODUCT' : 'EDIT_PRODUCT',
                  username: _auth.currentUser?.username ?? '',
                  userFullName: _auth.currentUser?.fullName ?? 'Quản Lý',
                  userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  targetType: 'PRODUCT',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  details: '${existing == null ? "Thêm" : "Sửa"} sản phẩm [$_selectedStoreCode]: ${product.name} (SKU: ${product.code}, giá vốn: ${product.costPrice ?? 0}đ)',
                  targetId: product.name,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Thêm' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  void _openNoteCatalog() {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoteCatalogScreen(storeCode: _selectedStoreCode)));
  }

  Future<void> _toggleProductAvailability(ProductModel product) async {
    final updated = product.copyWith(isAvailable: !product.isAvailable); // giữ nguyên mọi trường (topping, giá vốn, gắn note...)
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

  /// Chủ / Quản lý (khớp rules) VÀ có mã quyền COPY_MENU (Chủ + Quản lý mặc định có).
  bool get _canCopyMenu => MenuCopy.canCopyMenu(
        isOwnerOrManager: _auth.isOwner || _auth.isManager,
        canEditMenu: _auth.can(AppPermissions.copyMenu),
      );

  Future<void> _showCopyMenuDialog() async {
    if (!_canCopyMenu) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền sao chép thực đơn.')),
      );
      return;
    }
    List<StoreInfoModel> stores = _availableStores;
    try {
      final all = await _fb.getAllStores();
      if (all.isNotEmpty) stores = all;
    } catch (_) {}
    if (!mounted) return;
    if (stores.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có chi nhánh khác để sao chép!')),
      );
      return;
    }
    await showCopyMenuDialog(context, stores: stores, defaultSource: _selectedStoreCode);
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
            backgroundColor: AppColors.warningInk,
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
      backgroundColor: context.tc.background,
      appBar: AppBar(
        title: Text('Quản lý thực đơn', style: GoogleFonts.beVietnamPro(
          color: Colors.white, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.shapes, color: Colors.white),
            onPressed: () => context.push('/category-management', extra: _selectedStoreCode),
            tooltip: 'Quản lý danh mục',
          ),
          if (canManageNoteCatalog(_auth))
            IconButton(
              icon: const Icon(LucideIcons.stickyNote, color: Colors.white),
              tooltip: 'Danh mục note & topping',
              onPressed: _openNoteCatalog,
            ),
          PopupMenuButton<String>(
            icon: const Icon(LucideIcons.ellipsisVertical, color: Colors.white),
            onSelected: (val) {
              if (val == 'COPY') _showCopyMenuDialog();
              if (val == 'CLEAR') _showClearMenuDialog();
            },
            itemBuilder: (_) => [
              if (_canCopyMenu)
              PopupMenuItem(
                value: 'COPY',
                child: Row(
                  children: [
                    Icon(LucideIcons.copy, size: 18, color: context.tc.primary),
                    const SizedBox(width: 8),
                    const Text('Sao chép từ chi nhánh khác...'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'CLEAR',
                child: Row(
                  children: [
                    Icon(LucideIcons.trash, size: 18, color: context.tc.danger),
                    const SizedBox(width: 8),
                    Text('Làm trống menu chi nhánh này', style: TextStyle(color: context.tc.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_catalog.isLegacy && canManageNoteCatalog(_auth))
            InkWell(
              onTap: _openNoteCatalog,
              child: Container(
                width: double.infinity,
                color: Colors.amber.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Chưa cấu hình danh mục note/topping — bấm để thiết lập',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.brown.shade900),
                ),
              ),
            ),
          // Store Selector Bar
          Container(
            color: context.tc.cardElevated,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(LucideIcons.store, color: context.tc.primary, size: 20),
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
            color: context.tc.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Thực đơn [$_selectedStoreCode]: ${_products.length} món • ${_categories.length} nhóm',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Đang bán: ${_products.where((p) => p.isAvailable).length}',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.success, fontWeight: FontWeight.bold),
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
                      color: sel ? context.tc.primary : context.tc.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? context.tc.primary : context.tc.border),
                    ),
                    child: Text(cat, style: GoogleFonts.beVietnamPro(
                      color: sel ? Colors.white : context.tc.textSecondary,
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
                    icon: LucideIcons.utensils,
                    title: 'Chưa có sản phẩm cho chi nhánh $_selectedStoreCode',
                    subtitle: 'Thêm món mới hoặc sao chép từ chi nhánh khác.',
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _showProductDialog(),
                          icon: const Icon(LucideIcons.plus, color: Colors.white),
                          label: Text('Thêm sản phẩm', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(64, AppSpacing.minTapTarget),
                            backgroundColor: context.tc.primary,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_canCopyMenu) OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
                          onPressed: _showCopyMenuDialog,
                          icon: const Icon(LucideIcons.copy),
                          label: const Text('Sao chép món'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(color: context.tc.border, height: 12),
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
        icon: const Icon(LucideIcons.plus, color: Colors.white),
        label: Text('Thêm món mới', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
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
                        color: context.tc.cardElevated,
                        child: Icon(LucideIcons.utensilsCrossed, color: context.tc.textHint),
                      ))
                  : (product.assetPath != null
                      ? Image.asset(
                          product.assetPath!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: context.tc.cardElevated,
                            child: Icon(LucideIcons.utensilsCrossed, color: context.tc.textHint),
                          ),
                        )
                      : Container(
                          color: context.tc.cardElevated,
                          child: Icon(LucideIcons.utensilsCrossed, color: context.tc.textHint),
                        )),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hàng 1: Tên món hiển thị đầy đủ, không bị mã món chèn ép
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: GoogleFonts.beVietnamPro(
                            color: product.isAvailable ? context.tc.textPrimary : context.tc.textHint,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            decoration: product.isAvailable ? null : TextDecoration.lineThrough,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (product.isTopping) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: AppColors.managerAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Topping',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.managerAccent),
                          ),
                        ),
                      ],
                      if (!product.isAvailable) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.bg(Colors.red.shade100),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Tạm ngưng',
                            style: GoogleFonts.beVietnamPro(
                              color: context.ink(Colors.red.shade800),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Hàng 2: Mã món & Phân loại dạng tag tự co giãn
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (product.code.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: context.tc.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.code,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: context.tc.primary,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.tc.card,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.tc.border),
                        ),
                        child: Text(
                          product.category,
                          style: GoogleFonts.beVietnamPro(
                            color: context.tc.textSecondary,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Hàng 3: Giá bán, Đơn vị tính và Giá vốn
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        FormatUtils.currency(product.price),
                        style: GoogleFonts.beVietnamPro(
                          color: context.tc.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        '• ${product.unit}',
                        style: GoogleFonts.beVietnamPro(
                          color: context.tc.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      if (product.costPrice != null && product.costPrice! > 0)
                        Text(
                          '• Vốn: ${FormatUtils.currency(product.costPrice!)}',
                          style: GoogleFonts.beVietnamPro(
                            color: context.tc.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),

            // Các nút thao tác nhỏ gọn, không lấn chiếm diện tích văn bản
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onToggleAvailability,
                  icon: Icon(
                    product.isAvailable ? LucideIcons.circleCheck : LucideIcons.circlePause,
                    color: product.isAvailable ? context.tc.success : context.tc.textHint,
                    size: 20,
                  ),
                  tooltip: product.isAvailable ? 'Đang bán (Bấm để tạm ngưng)' : 'Tạm ngưng (Bấm để mở bán)',
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onEdit,
                  icon: Icon(LucideIcons.pencil, color: context.tc.textSecondary, size: 20),
                  tooltip: 'Sửa món',
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onDelete,
                  icon: Icon(LucideIcons.trash2, color: context.tc.danger, size: 20),
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
