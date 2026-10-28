// lib/features/orders/order_list_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/item_options.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'widgets/item_option_pickers.dart';
import '../../core/utils/format_utils.dart';
import '../cash_shift/cash_shift_dialog.dart';
import '../../core/domain/product_availability.dart';
import '../kitchen/sold_out_actions.dart';

class OrderListScreen extends StatefulWidget {
  final TableModel table;
  final bool isAddingMore;
  const OrderListScreen({super.key, required this.table, this.isAddingMore = false});

  @override
  State<OrderListScreen> createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  String _categoryFilter = 'Tất cả';
  String _search = '';
  List<ProductModel> _products = [];
  List<OrderItemModel> _cart = [];
  List<CategoryModel> _categories = [];
  List<String> _backendNotePresets = [];
  ItemCatalog _catalog = const ItemCatalog(); // danh mục note & topping (chưa cấu hình = hành vi cũ)
  bool _loading = false;
  bool _isShiftOpen = false;
  final _searchCtrl = TextEditingController();
  String? _sessionBillId;
  bool _startedAsNewOrder = false;

  @override
  void initState() {
    super.initState();
    _isShiftOpen = _fb.activeShiftCache != null && _fb.activeShiftCache!.isOpen;
    _products = _fb.defaultProducts;
    _categories = _fb.defaultCategories;
    _loadData();
    _startedAsNewOrder = !widget.isAddingMore && widget.table.currentItems.isEmpty;
    // Ensure table has both Bill Code (Mã hóa đơn) and Order Code (Mã đặt món)
    widget.table.ensureCodes();
    _sessionBillId = widget.table.currentBillId;
    // Carry over existing order items from table
    _cart = List.from(widget.table.currentItems);

    _fb.cashShiftsStream().listen((shifts) {
      final openOne = shifts.where((s) => s.isOpen).firstOrNull;
      if (mounted) {
        setState(() => _isShiftOpen = openOne != null);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
      _isShiftOpen = shift != null && shift.isOpen;
      if (!_isShiftOpen) {
        if (mounted) {
          final ok = await _ensureShiftOpen();
          if (!ok && mounted) {
            Navigator.of(context).pop();
          }
        }
      }
    });
  }

  Future<bool> _ensureShiftOpen() async {
    CashShiftModel? shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
    if (shift == null || !shift.isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Chức năng order đang bị khóa! Vui lòng khai báo tiền két đầu ca.'),
            backgroundColor: AppColors.warningInk,
            duration: Duration(seconds: 3),
          ),
        );
        final opened = await CashShiftDialog.show(context);
        if (opened == true) {
          final recheck = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
          final ok = recheck != null && recheck.isOpen;
          if (mounted) setState(() => _isShiftOpen = ok);
          return ok;
        }
      }
      if (mounted) setState(() => _isShiftOpen = false);
      return false;
    }
    if (mounted && !_isShiftOpen) setState(() => _isShiftOpen = true);
    return true;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _loadData() {
    final storeCode = _auth.currentStoreCode;
    _fb.productsStream(storeCode: storeCode).listen((products) {
      if (mounted) setState(() { _products = products; _loading = false; });
    });
    _fb.categoriesStream(storeCode: storeCode).listen((cats) {
      if (mounted) setState(() => _categories = cats);
    });
    _fb.itemCatalogStream(storeCode: storeCode).listen((c) {
      if (mounted) setState(() => _catalog = c);
    });
    _fb.productNotesStream(storeCode: storeCode).listen((notes) {
      if (mounted) {
        final list = notes
            .map((n) => n['text']?.toString() ?? n['name']?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
        setState(() => _backendNotePresets = list);
      }
    });
  }

  List<ProductModel> get _filteredProducts {
    return _products.where((p) {
      final matchCat = _categoryFilter == 'Tất cả' || p.category == _categoryFilter;
      final matchSearch = _search.isEmpty ||
          p.name.toLowerCase().contains(_search.toLowerCase()) ||
          p.code.toLowerCase().contains(_search.toLowerCase());
      return matchCat && matchSearch;
    }).toList();
  }

  int _productCartCount(ProductModel product) {
    return _cart.where((i) => i.productId == product.id && i.name == product.name).fold(0, (sum, i) => sum + i.quantity);
  }

  /// Món đã báo hết: không cho thêm (kiểm tra theo dữ liệu realtime mới nhất).
  bool _blockIfSoldOut(ProductModel product) {
    ProductModel latest = product;
    for (final p in _products) {
      if (p.name == product.name) { latest = p; break; }
    }
    if (isProductAvailable(latest)) return false;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('${product.name} đã hết hàng'), duration: const Duration(seconds: 2)));
    return true;
  }

  /// Giữ lâu một món để báo hết / bật lại (cần quyền TOGGLE_ITEM_AVAILABILITY).
  Future<void> _toggleSoldOutDialog(ProductModel product) async {
    if (!canToggleAvailability(_auth)) return;
    final soldOutNow = !isProductAvailable(product);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(soldOutNow ? 'Bật lại ${product.name}?' : 'Báo hết ${product.name}?'),
        content: Text(soldOutNow ? 'Món sẽ bán được trở lại trên mọi thiết bị.' : 'Món sẽ hiện "Hết hàng" và không thể thêm vào đơn trên mọi thiết bị.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(soldOutNow ? 'Bật lại' : 'Báo hết')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SoldOutActions(auth: _auth).setSoldOut(product, !soldOutNow);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không cập nhật được ${product.name}: $e'), backgroundColor: AppColors.danger));
    }
  }

  Future<void> _quickAddToCart(ProductModel product) async {
    if (_blockIfSoldOut(product)) return;
    if (!await _ensureShiftOpen() || !mounted) return;

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
    final now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      final idx = _cart.indexWhere((p) =>
          !p.isSentKitchen &&
          !p.hasDiscount &&
          p.productId == product.id &&
          p.name == product.name &&
          p.selectedSize.isEmpty &&
          p.selectedToppings.isEmpty &&
          p.note.isEmpty);
      if (idx >= 0) {
        _cart[idx] = _cart[idx].copyWith(
          quantity: _cart[idx].quantity + 1,
          orderedBy: staffUser,
          orderedByName: staffName,
          orderedAt: now,
        );
      } else {
        _cart.add(OrderItemModel(
          productId: product.id,
          name: product.name,
          price: product.price,
          quantity: 1,
          orderedBy: staffUser,
          orderedByName: staffName,
          orderedAt: now,
          isSentKitchen: false,
        ));
      }
    });
  }

  void _removeFromCart(ProductModel product) {
    setState(() {
      final idx = _cart.lastIndexWhere((p) =>
          !p.isSentKitchen &&
          !p.hasDiscount &&
          p.productId == product.id &&
          p.name == product.name);
      if (idx >= 0) {
        if (_cart[idx].quantity > 1) {
          _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity - 1);
        } else {
          _cart.removeAt(idx);
        }
      } else {
        final hasSentOrDiscounted = _cart.any((p) =>
            p.productId == product.id &&
            p.name == product.name &&
            (p.isSentKitchen || p.hasDiscount));
        if (hasSentOrDiscounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Món đã được gửi bếp hoặc có giảm giá, vui lòng vào giỏ hàng để thao tác.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    });
  }

  int get _cartTotal => _cart.fold(0, (s, p) => s + p.itemTotal);
  int get _cartCount => _cart.fold(0, (s, p) => s + p.quantity);

  /// Nhóm note/topping được gắn cho món (món ghi đè nhóm món). Chưa cấu hình danh mục -> legacy.
  ResolvedItemOptions _resolveOptions(ProductModel product) {
    CategoryModel? cat;
    for (final c in _categories) {
      if (c.name.trim().toLowerCase() == product.category.trim().toLowerCase()) {
        cat = c;
        break;
      }
    }
    return resolveItemOptions(
      productNoteGroupIds: product.noteGroupIds,
      productToppingGroupIds: product.toppingGroupIds,
      categoryNoteGroupIds: cat?.noteGroupIds,
      categoryToppingGroupIds: cat?.toppingGroupIds,
      catalog: _catalog,
    );
  }

  // ==================== KIOTVIET PRODUCT CUSTOMIZER ====================
  Future<void> _showProductCustomizer(ProductModel product) async {
    if (!await _ensureShiftOpen() || !mounted) return;

    final hasSizes = product.sizes.isNotEmpty;

    final isDrinkOrTea = product.category.toLowerCase().contains('trà') ||
        product.category.toLowerCase().contains('tea') ||
        product.category.toLowerCase().contains('cà phê') ||
        product.category.toLowerCase().contains('cafe') ||
        product.category.toLowerCase().contains('coffee') ||
        product.category.toLowerCase().contains('nước') ||
        product.category.toLowerCase().contains('uống') ||
        product.category.toLowerCase().contains('sinh tố') ||
        product.category.toLowerCase().contains('đá xay') ||
        product.category.toLowerCase().contains('sữa') ||
        product.category.toLowerCase().contains('matcha') ||
        product.hasIceSugarOptions ||
        product.sizes.isNotEmpty;

    final hasIceSugar = product.hasIceSugarOptions || isDrinkOrTea;

    // Resolve category and allowed toppings
    CategoryModel? matchedCategory;
    for (final c in _categories) {
      if (c.name.trim().toLowerCase() == product.category.trim().toLowerCase()) {
        matchedCategory = c;
        break;
      }
    }

    final defaultFnbToppings = [
      ProductModel(id: 9001, name: 'Trân châu đen', price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9002, name: 'Trân châu trắng', price: 6000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9003, name: 'Thạch phô mai', price: 8000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9004, name: 'Thạch củ năng', price: 7000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9005, name: 'Kem Cheese', price: 10000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9006, name: 'Pudding trứng', price: 7000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9007, name: 'Đào miếng', price: 8000, unit: 'phần', category: 'Topping', isTopping: true),
      ProductModel(id: 9008, name: 'Thạch chanh', price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
    ];

    final resolved = _resolveOptions(product);
    final catalogMode = !resolved.legacy; // đã cấu hình danh mục: chỉ hiện nhóm được gắn
    final Map<String, ProductModel?> toppingItemMap = {};
    final List<String> availableToppingNames = [];

    if (catalogMode) {
      resolved.toppingPrices.forEach((n, p) {
        toppingItemMap[n] = ProductModel(name: n, price: p, unit: 'phần', category: 'Topping', isTopping: true);
        availableToppingNames.add(n);
      });
    } else if (matchedCategory != null && matchedCategory.allowedToppingIds.isNotEmpty) {
      for (final tId in matchedCategory.allowedToppingIds) {
        final match = _products.firstWhere(
          (p) => p.id.toString() == tId ||
              (p.code.isNotEmpty && p.code.toLowerCase() == tId.toLowerCase()) ||
              p.name.toLowerCase() == tId.toLowerCase(),
          orElse: () => defaultFnbToppings.firstWhere(
            (p) => p.id.toString() == tId || p.name.toLowerCase() == tId.toLowerCase(),
            orElse: () => ProductModel(name: tId, price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
          ),
        );
        toppingItemMap[match.name] = match;
        if (!availableToppingNames.contains(match.name)) {
          availableToppingNames.add(match.name);
        }
      }
    } else if (product.allowedToppings.isNotEmpty) {
      for (final topName in product.allowedToppings) {
        final match = _products.firstWhere(
          (p) => p.name.toLowerCase() == topName.toLowerCase() ||
              (p.code.isNotEmpty && p.code.toLowerCase() == topName.toLowerCase()),
          orElse: () => defaultFnbToppings.firstWhere(
            (p) => p.name.toLowerCase() == topName.toLowerCase(),
            orElse: () => ProductModel(name: topName, price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
          ),
        );
        toppingItemMap[match.name] = match;
        if (!availableToppingNames.contains(match.name)) {
          availableToppingNames.add(match.name);
        }
      }
    } else {
      // 1. Tìm tất cả topping có trong menu hệ thống
      for (final p in _products) {
        if (p.isTopping || p.category.toLowerCase().contains('topping')) {
          toppingItemMap[p.name] = p;
          if (!availableToppingNames.contains(p.name)) {
            availableToppingNames.add(p.name);
          }
        }
      }
      // 2. Bổ sung topping chuẩn nếu chưa có topping hoặc là đồ uống/trà
      if (availableToppingNames.isEmpty || isDrinkOrTea) {
        for (final top in defaultFnbToppings) {
          if (!availableToppingNames.contains(top.name)) {
            toppingItemMap[top.name] = top;
            availableToppingNames.add(top.name);
          }
        }
      }
    }

    final hasToppings = availableToppingNames.isNotEmpty;

    String selectedSize = hasSizes ? (product.sizes.containsKey('M') ? 'M' : product.sizes.keys.first) : 'Chuẩn';
    int sizeExtra = hasSizes ? (product.sizes[selectedSize] ?? 0) : 0;

    String selectedSugar = '100% đường';
    String selectedIce = '100% đá';
    final List<String> selectedToppings = [];
    final noteCtrl = TextEditingController();
    int quantity = 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int toppingPrice = 0;
          for (final topName in selectedToppings) {
            toppingPrice += toppingItemMap[topName]?.price ?? (catalogMode ? 0 : 5000);
          }
          final int unitPrice = product.price + sizeExtra + toppingPrice;
          final int totalPrice = unitPrice * quantity;

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.tc.border, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 12),

                  // Header: Name & Base Price & Close Button
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold)),
                            if (product.code.isNotEmpty)
                              Text('SKU: ${product.code} • ${product.category}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(FormatUtils.vnd(product.price), style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: context.tc.primary)),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        tooltip: 'Đóng',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // 1. SIZE SELECTION (KiotViet Size)
                  if (hasSizes) ...[
                    Text('Chọn kích cỡ (Size):', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: product.sizes.entries.map((entry) {
                        final isSel = selectedSize == entry.key;
                        final extraText = entry.value > 0 ? ' (+${FormatUtils.vnd(entry.value)})' : '';
                        return ChoiceChip(
                          label: Text('Size ${entry.key}$extraText'),
                          selected: isSel,
                          selectedColor: context.tc.primaryLight,
                          labelStyle: TextStyle(
                            color: isSel ? context.tc.primaryDark : context.tc.textPrimary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setModalState(() {
                                selectedSize = entry.key;
                                sizeExtra = entry.value;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 2. SUGAR & ICE (Đường & Đá)
                  if (hasIceSugar) ...[
                    Text('Mức độ đường:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ['100% đường', '70% đường', '50% đường', '30% đường', 'Không đường'].map((s) {
                        final isSel = selectedSugar == s;
                        return ChoiceChip(
                          label: Text(s),
                          selected: isSel,
                          selectedColor: context.tc.primaryLight,
                          labelStyle: TextStyle(color: isSel ? context.tc.primaryDark : context.tc.textPrimary, fontSize: 11),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedSugar = s);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),

                    Text('Mức độ đá:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: ['100% đá', '70% đá', '50% đá', 'Không đá', 'Uống nóng'].map((ice) {
                        final isSel = selectedIce == ice;
                        return ChoiceChip(
                          label: Text(ice),
                          selected: isSel,
                          selectedColor: context.tc.primaryLight,
                          labelStyle: TextStyle(color: isSel ? context.tc.primaryDark : context.tc.textPrimary, fontSize: 11),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedIce = ice);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. TOPPINGS (theo nhóm đã gắn khi đã cấu hình danh mục; chưa cấu hình = danh sách cũ)
                  if (catalogMode && resolved.toppingGroups.isNotEmpty) ...[
                    ToppingGroupsSection(
                      groups: resolved.toppingGroups,
                      selected: selectedToppings,
                      onToggle: (g, name) => setModalState(() {
                        final next = toggleTopping(selected: selectedToppings, group: g, name: name);
                        selectedToppings
                          ..clear()
                          ..addAll(next);
                      }),
                      onRemoveExtra: (n) => setModalState(() => selectedToppings.remove(n)),
                      onClearAll: () => setModalState(() => selectedToppings.clear()),
                    ),
                  ],
                  if (!catalogMode && hasToppings) ...[
                    Text('Topping thêm:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: availableToppingNames.map((topName) {
                        final isSel = selectedToppings.contains(topName);
                        final topProd = toppingItemMap[topName];
                        final priceStr = topProd != null ? FormatUtils.vnd(topProd.price) : '5.000 đ';
                        return FilterChip(
                          label: Text('$topName (+$priceStr)'),
                          selected: isSel,
                          selectedColor: context.tc.primaryLight,
                          labelStyle: TextStyle(
                            color: isSel ? context.tc.primaryDark : context.tc.textPrimary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedToppings.add(topName);
                              } else {
                                selectedToppings.remove(topName);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. NOTE (Ghi chú món & Ghi chú mẫu từ Backend)
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú cho bếp / pha chế',
                      hintText: 'VD: ít ngọt, pha đậm vị...',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final presets = catalogMode
                        ? resolved.noteChips
                        : (_backendNotePresets.isNotEmpty
                            ? _backendNotePresets
                            : const ['Ít ngọt', 'Nhiều đá', 'Không đá', 'Ít đá', 'Để riêng đá', 'Mang về']);
                    return Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: presets.map((preset) {
                        final isPresetInNote = noteCtrl.text.contains(preset);
                        return ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
                            preset,
                            style: TextStyle(
                              fontSize: 11,
                              color: isPresetInNote ? context.tc.primaryDark : context.tc.textPrimary,
                              fontWeight: isPresetInNote ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                          backgroundColor: isPresetInNote ? context.tc.primaryLight : context.tc.cardElevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: isPresetInNote ? context.tc.primary : context.tc.border),
                          ),
                          onPressed: () {
                            setModalState(() {
                              final current = noteCtrl.text.trim();
                              if (current.isEmpty) {
                                noteCtrl.text = preset;
                              } else if (!current.contains(preset)) {
                                noteCtrl.text = '$current, $preset';
                              } else {
                                noteCtrl.text = current
                                    .replaceAll(', $preset', '')
                                    .replaceAll('$preset, ', '')
                                    .replaceAll(preset, '')
                                    .trim();
                              }
                            });
                          },
                        );
                      }).toList(),
                    );
                  }),
                  const SizedBox(height: 20),

                  // 5. QUANTITY & ADD BUTTON
                  Row(
                    children: [
                      // Quantity Stepper
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: context.tc.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 18),
                              onPressed: quantity > 1 ? () => setModalState(() => quantity--) : null,
                            ),
                            Text('$quantity', style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              onPressed: () => setModalState(() => quantity++),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Add Button
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.tc.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () {
                            final staffUser = _auth.currentUser?.username ?? 'staff';
                            final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
                            final now = DateTime.now().millisecondsSinceEpoch;

                            final newItem = OrderItemModel(
                              productId: product.id,
                              name: product.name,
                              price: product.price,
                              quantity: quantity,
                              selectedSize: hasSizes ? selectedSize : '',
                              sizeExtraPrice: sizeExtra,
                              selectedSugar: hasIceSugar ? selectedSugar : '',
                              selectedIce: hasIceSugar ? selectedIce : '',
                              selectedToppings: selectedToppings,
                              toppingPrice: toppingPrice,
                              note: noteCtrl.text.trim(),
                              orderedBy: staffUser,
                              orderedByName: staffName,
                              orderedAt: now,
                            );

                            setState(() {
                              final existingIdx = _cart.indexWhere((i) =>
                                  !i.isSentKitchen &&
                                  !i.hasDiscount &&
                                  i.productId == newItem.productId &&
                                  i.name == newItem.name &&
                                  i.selectedSize == newItem.selectedSize &&
                                  i.selectedSugar == newItem.selectedSugar &&
                                  i.selectedIce == newItem.selectedIce &&
                                  i.selectedToppings.join(',') == newItem.selectedToppings.join(',') &&
                                  i.note == newItem.note);

                              if (existingIdx >= 0) {
                                _cart[existingIdx] = _cart[existingIdx].copyWith(
                                  quantity: _cart[existingIdx].quantity + quantity,
                                );
                              } else {
                                _cart.add(newItem);
                              }
                            });

                            Navigator.pop(ctx);
                          },
                          child: Text(
                            'Thêm vào đơn • ${FormatUtils.vnd(totalPrice)}',
                            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Handler báo lỗi lưu bàn (lưu nền, không chặn điều hướng). Lấy ScaffoldMessenger
  /// trước khi rời màn hình để vẫn hiển thị được thông báo.
  void Function(Object) _saveErrorHandler() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final tableName = widget.table.name;
    return (Object e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Lỗi lưu bàn $tableName: $e'), backgroundColor: AppColors.danger),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _cartCount > 0;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Nếu chưa chọn món nào khi thoát:
            // - Với phiên mở bàn mới (_startedAsNewOrder): chỉ nhả khóa orderingBy an toàn
            //   (tránh ghi đè nếu đồng nghiệp vừa lưu đơn trên bàn này).
            // - Nếu đã chọn món: dùng saveTableOrderSafe để tự tách bàn nếu trùng lúc lưu.
            if (_cart.isEmpty) {
              if (_startedAsNewOrder) {
                _fb.releaseTableOrderingClaim(
                  widget.table,
                  staffUsername: _auth.currentUser?.username,
                );
              } else {
                widget.table.clearTable();
                _fb.saveTable(widget.table).catchError(_saveErrorHandler());
              }
            } else {
              widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
              widget.table.inUse = true;
              _fb
                  .saveTableOrderSafe(
                    widget.table,
                    sessionBillId: _sessionBillId,
                    isNewOrderSession: _startedAsNewOrder,
                  )
                  .catchError((Object e) {
                _saveErrorHandler()(e);
                return (savedTable: widget.table, wasSplit: false);
              });
            }
            Navigator.of(context).pop(_cart);
          },
        ),
        title: Column(
          children: [
            Text(
              widget.isAddingMore ? 'Thêm Món - ${widget.table.name}' : 'Chọn Món - ${widget.table.name}',
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.table.zone} • ${widget.table.currentBillId ?? widget.table.currentOrderCode ?? ""}',
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.white70),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_isShiftOpen)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: Colors.amber.shade900,
                child: Row(
                  children: [
                    const Icon(Icons.lock, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đang khóa order do chưa nhập két đầu ca.',
                        style: GoogleFonts.beVietnamPro(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => CashShiftDialog.show(context),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.amber.shade900,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Mở két ngay', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            _buildSearchBar(),
            _buildCategoryChips(),
            Expanded(child: _loading ? _buildShimmer() : _buildProductList()),
          ],
        ),
      ),
      bottomNavigationBar: hasItems
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.tc.card,
                boxShadow: [
                  BoxShadow(
                    color: context.tc.shadow,
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(widget.isAddingMore ? Icons.check_circle_outline : Icons.receipt_long, size: 22),
                    label: Text(
                      widget.isAddingMore
                          ? 'Xong, Quay Lại Đơn • ${FormatUtils.vnd(_cartTotal)} ($_cartCount món)'
                          : 'Xem Lại Đơn • ${FormatUtils.vnd(_cartTotal)} ($_cartCount món)',
                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.tc.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (!await _ensureShiftOpen() || !context.mounted) return;

                      final staffUser = _auth.currentUser?.username ?? 'staff';
                      final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
                      final myNewItems = _cart.where((i) => i.orderedBy == staffUser && !i.isSentKitchen).toList();
                      if (myNewItems.isNotEmpty) {
                        widget.table.addActionLog(OrderActionLogModel(
                          timestamp: DateTime.now().millisecondsSinceEpoch,
                          staffUsername: staffUser,
                          staffFullName: staffName,
                          action: 'ADD_ITEMS',
                          details: '$staffName nhập món: ${myNewItems.map((e) => "${e.name} (x${e.quantity})").join(", ")}',
                        ));
                      }
                      // Cập nhật giỏ hàng tạm thời vào bàn
                      widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
                      widget.table.inUse = true;

                      if (widget.isAddingMore) {
                        _fb.saveTable(widget.table).catchError(_saveErrorHandler());
                        Navigator.of(context).pop(_cart);
                      } else {
                        TableModel targetTable = widget.table;
                        bool wasSplit = false;
                        try {
                          final res = await _fb.saveTableOrderSafe(
                            widget.table,
                            sessionBillId: _sessionBillId,
                            isNewOrderSession: _startedAsNewOrder,
                          );
                          targetTable = res.savedTable;
                          wasSplit = res.wasSplit;
                        } catch (e) {
                          _saveErrorHandler()(e);
                        }
                        if (!context.mounted) return;
                        if (wasSplit) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '⚡ ${widget.table.baseName} vừa có đơn khác → Đã tự động tách sang ${targetTable.name} (${targetTable.currentBillId})!',
                              ),
                              backgroundColor: AppColors.primary,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                        context.pushReplacement('/order-cart', extra: {
                          'table': targetTable,
                          'products': _cart,
                        });
                      }
                    },
                  ),
                ),
              ),
            ).animate().slideY(begin: 1, end: 0, duration: 200.ms)
          : null,
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: context.tc.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        style: TextStyle(color: context.tc.textPrimary),
        decoration: InputDecoration(
          hintText: 'Tìm món ăn, thức uống, mã SKU...',
          prefixIcon: Icon(Icons.search, color: context.tc.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: context.tc.textSecondary, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _search = '');
                  },
                )
              : null,
        ),
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  Widget _buildCategoryChips() {
    final Set<String> catSet = {'Tất cả'};
    for (final c in _categories) {
      if (c.name.isNotEmpty) catSet.add(c.name);
    }
    for (final p in _products) {
      if (p.category.isNotEmpty) catSet.add(p.category);
    }
    final cats = catSet.toList();
    return Container(
      color: context.tc.card,
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        itemCount: cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final cat = cats[i];
          final isSelected = _categoryFilter == cat;
          return ChoiceChip(
            label: Text(cat),
            selected: isSelected,
            selectedColor: context.tc.primaryLight,
            labelStyle: GoogleFonts.beVietnamPro(
              color: isSelected ? context.tc.primaryDark : context.tc.textPrimary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            onSelected: (val) {
              if (val) setState(() => _categoryFilter = cat);
            },
          );
        },
      ),
    );
  }

  Widget _buildProductList() {
    final products = _filteredProducts;
    if (products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.no_meals_outlined, size: 64, color: context.tc.textHint),
            const SizedBox(height: 12),
            Text('Không tìm thấy món nào', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final product = products[i];
        final qty = _productCartCount(product);

        final isDrinkOrTea = product.category.toLowerCase().contains('trà') ||
            product.category.toLowerCase().contains('tea') ||
            product.category.toLowerCase().contains('cà phê') ||
            product.category.toLowerCase().contains('cafe') ||
            product.category.toLowerCase().contains('coffee') ||
            product.category.toLowerCase().contains('nước') ||
            product.category.toLowerCase().contains('uống') ||
            product.category.toLowerCase().contains('sinh tố') ||
            product.category.toLowerCase().contains('đá xay') ||
            product.category.toLowerCase().contains('sữa') ||
            product.category.toLowerCase().contains('matcha') ||
            product.hasIceSugarOptions ||
            product.sizes.isNotEmpty;

        final bool hasOptions = product.sizes.isNotEmpty ||
            product.hasIceSugarOptions ||
            product.allowedToppings.isNotEmpty ||
            isDrinkOrTea ||
            (() {
              final r = _resolveOptions(product);
              return !r.legacy && (r.toppingGroups.isNotEmpty || r.noteGroups.isNotEmpty);
            })();

        return _ProductListRow(
          product: product,
          quantity: qty,
          hasOptions: hasOptions,
          soldOut: !isProductAvailable(product),
          onLongPress: canToggleAvailability(_auth) ? () => _toggleSoldOutDialog(product) : null,
          onTap: () {
            if (_blockIfSoldOut(product)) return;
            _showProductCustomizer(product);
          },
          onAdd: () {
            if (_blockIfSoldOut(product)) return;
            if (hasOptions) {
              _showProductCustomizer(product);
            } else {
              _quickAddToCart(product);
            }
          },
          onRemove: () => _removeFromCart(product),
        ).animate(delay: (i * 15).ms).fadeIn(duration: 180.ms);
      },
    );
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, __) => Container(
        height: 76,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: context.tc.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.tc.border),
        ),
      ),
    );
  }
}

class _ProductListRow extends StatelessWidget {
  final ProductModel product;
  final int quantity;
  final bool hasOptions;
  final VoidCallback onTap;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final bool soldOut;
  final VoidCallback? onLongPress;

  const _ProductListRow({
    required this.soldOut,
    this.onLongPress,
    required this.product,
    required this.quantity,
    required this.hasOptions,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final bool isInCart = quantity > 0;

    return Opacity(
      opacity: soldOut ? 0.55 : 1,
      child: Container(
      decoration: BoxDecoration(
        color: isInCart ? context.tc.primaryLight.withValues(alpha: 0.35) : context.tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInCart ? context.tc.primary.withValues(alpha: 0.5) : context.tc.border,
          width: isInCart ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: context.tc.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product Image Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 58,
                    height: 58,
                    child: (product.imageBase64 != null && product.imageBase64!.isNotEmpty)
                        ? _buildBase64Image(context, product.imageBase64!)
                        : (product.assetPath != null
                            ? Image.asset(
                                product.assetPath!,
                                fit: BoxFit.cover,
                                width: 58,
                                height: 58,
                                errorBuilder: (_, __, ___) => Center(
                                  child: Icon(Icons.restaurant_menu, color: context.tc.primary, size: 28),
                                ),
                              )
                            : Center(
                                child: Icon(Icons.restaurant_menu, color: context.tc.primary, size: 28),
                              )),
                  ),
                ),
                const SizedBox(width: 14),

                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              product.name,
                              style: GoogleFonts.beVietnamPro(
                                color: context.tc.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (soldOut) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: context.tc.danger, borderRadius: BorderRadius.circular(6)),
                              child: const Text('Hết hàng', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            FormatUtils.vnd(product.price),
                            style: GoogleFonts.beVietnamPro(
                              color: context.tc.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (product.unit.isNotEmpty)
                            Text(
                              ' / ${product.unit}',
                              style: GoogleFonts.beVietnamPro(
                                color: context.tc.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (product.category.isNotEmpty) ...[
                            Text(' • ', style: TextStyle(color: context.tc.textHint)),
                            Text(
                              product.category,
                              style: GoogleFonts.beVietnamPro(
                                color: context.tc.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Tags for options
                      Row(
                        children: [
                          if (product.sizes.isNotEmpty)
                            _buildPillTag('Size S/M/L', context.ink(Colors.blue.shade700), context.bg(Colors.blue.shade50)),
                          if (product.allowedToppings.isNotEmpty || hasOptions) ...[
                            const SizedBox(width: 4),
                            _buildPillTag('Topping', context.ink(Colors.orange.shade800), context.bg(Colors.orange.shade50)),
                          ],
                          if (product.hasIceSugarOptions || hasOptions) ...[
                            const SizedBox(width: 4),
                            _buildPillTag('Đường/Đá', context.ink(Colors.green.shade800), context.bg(Colors.green.shade50)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Action buttons
                if (!isInCart && soldOut)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: context.tc.border, borderRadius: BorderRadius.circular(10)),
                    child: Text('Thêm', style: GoogleFonts.beVietnamPro(color: context.tc.textHint, fontSize: 13, fontWeight: FontWeight.bold)),
                  )
                else if (!isInCart)
                  InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.tc.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: context.tc.primary.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.add, color: Colors.white, size: 18),
                          const SizedBox(width: 4),
                          Text('Thêm', style: GoogleFonts.beVietnamPro(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: onRemove,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: context.tc.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.tc.primary.withValues(alpha: 0.5)),
                          ),
                          child: Icon(Icons.remove, color: context.tc.primary, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'x$quantity',
                        style: GoogleFonts.beVietnamPro(
                          color: context.tc.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: soldOut ? null : onAdd,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: soldOut ? context.tc.textHint : context.tc.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildPillTag(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildBase64Image(BuildContext context, String base64) {
    try {
      final String cleanBase64 = base64.contains(',') ? base64.split(',').last : base64;
      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: 58,
        height: 58,
        errorBuilder: (_, __, ___) => Center(
          child: Icon(Icons.restaurant_menu, color: context.tc.primary, size: 28),
        ),
      );
    } catch (_) {
      return Center(
        child: Icon(Icons.restaurant_menu, color: context.tc.primary, size: 28),
      );
    }
  }
}
