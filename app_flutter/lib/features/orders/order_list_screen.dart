// lib/features/orders/order_list_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/utils/format_utils.dart';
import '../cash_shift/cash_shift_dialog.dart';

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
  bool _loading = false;
  bool _isSendingKitchen = false;
  bool _isShiftOpen = false;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _isShiftOpen = _fb.activeShiftCache != null && _fb.activeShiftCache!.isOpen;
    _products = _fb.defaultProducts;
    _categories = _fb.defaultCategories;
    _loadData();
    // Ensure table has both Bill Code (Mã hóa đơn) and Order Code (Mã đặt món)
    widget.table.ensureCodes();
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
            backgroundColor: TramColors.warningInk,
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

  Future<void> _quickAddToCart(ProductModel product) async {
    if (!await _ensureShiftOpen()) return;

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
    final now = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      final idx = _cart.indexWhere((p) =>
          p.productId == product.id &&
          p.name == product.name &&
          p.selectedSize.isEmpty &&
          p.selectedToppings.isEmpty);
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
        ));
      }
    });
  }

  void _removeFromCart(ProductModel product) {
    setState(() {
      final idx = _cart.lastIndexWhere((p) => p.productId == product.id && p.name == product.name);
      if (idx >= 0) {
        if (_cart[idx].quantity > 1) {
          _cart[idx] = _cart[idx].copyWith(quantity: _cart[idx].quantity - 1);
        } else {
          _cart.removeAt(idx);
        }
      }
    });
  }

  int get _cartTotal => _cart.fold(0, (s, p) => s + p.itemTotal);
  int get _cartCount => _cart.fold(0, (s, p) => s + p.quantity);

  // ==================== KIOTVIET PRODUCT CUSTOMIZER ====================
  Future<void> _showProductCustomizer(ProductModel product) async {
    if (!await _ensureShiftOpen()) return;

    final hasSizes = product.sizes.isNotEmpty;
    final hasIceSugar = product.hasIceSugarOptions;
    final hasToppings = product.allowedToppings.isNotEmpty;

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
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final int toppingPrice = selectedToppings.length * 5000;
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
                    child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
                  ),
                  const SizedBox(height: 12),

                  // Header: Name & Base Price
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(product.name, style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold)),
                            if (product.code.isNotEmpty)
                              Text('SKU: ${product.code} • ${product.category}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      Text(FormatUtils.vnd(product.price), style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary)),
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
                          selectedColor: AppColors.primaryLight,
                          labelStyle: TextStyle(
                            color: isSel ? AppColors.primaryDark : AppColors.textPrimary,
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
                          selectedColor: AppColors.primaryLight,
                          labelStyle: TextStyle(color: isSel ? AppColors.primaryDark : AppColors.textPrimary, fontSize: 11),
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
                          selectedColor: AppColors.primaryLight,
                          labelStyle: TextStyle(color: isSel ? AppColors.primaryDark : AppColors.textPrimary, fontSize: 11),
                          onSelected: (val) {
                            if (val) setModalState(() => selectedIce = ice);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 3. TOPPINGS (Topping đi kèm)
                  if (hasToppings) ...[
                    Text('Topping thêm (+5.000đ/phần):', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: product.allowedToppings.map((top) {
                        final isSel = selectedToppings.contains(top);
                        return FilterChip(
                          label: Text(top),
                          selected: isSel,
                          selectedColor: AppColors.primaryLight,
                          labelStyle: TextStyle(
                            color: isSel ? AppColors.primaryDark : AppColors.textPrimary,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            setModalState(() {
                              if (val) {
                                selectedToppings.add(top);
                              } else {
                                selectedToppings.remove(top);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. NOTE (Ghi chú món)
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú cho bếp / pha chế',
                      hintText: 'VD: ít ngọt, pha đậm vị...',
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 5. QUANTITY & ADD BUTTON
                  Row(
                    children: [
                      // Quantity Stepper
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
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
                            backgroundColor: AppColors.primary,
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

  // ==================== SEND TO KITCHEN LOGIC ====================
  Future<void> _sendToKitchen() async {
    if (!await _ensureShiftOpen()) return;

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn món trước khi gửi bếp!')),
      );
      return;
    }

    final unsentItems = _cart.where((i) => !i.isSentKitchen).toList();
    if (unsentItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tất cả món đã được gửi bếp trước đó rồi!')),
      );
      return;
    }

    setState(() => _isSendingKitchen = true);

    try {
      final updatedCart = _cart.map((i) => i.copyWith(isSentKitchen: true)).toList();

      widget.table.ensureCodes();
      final kitchenOrder = KitchenOrderModel(
        tableName: widget.table.name,
        orderCode: widget.table.currentOrderCode ?? widget.table.currentBillId,
        billCode: widget.table.currentBillId,
        itemsJson: jsonEncode(unsentItems.map((e) => e.toMap()).toList()),
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );

      // 1. Lưu trạng thái bàn và giỏ hàng ngay lập tức
      final t = widget.table;
      t.inUse = true;
      if (t.openedAt == null) t.openedAt = DateTime.now().millisecondsSinceEpoch;
      t.currentOrderJson = jsonEncode(updatedCart.map((e) => e.toMap()).toList());

      // 2. Gửi phiếu sang bếp và lưu bàn song song (không treo UI)
      await Future.wait([
        _fb.sendKitchenOrder(kitchenOrder).catchError((_) {}),
        _fb.saveTable(t).catchError((_) {}),
      ]);

      // 3. Ghi nhật ký thao tác (Audit Log)
      _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: _auth.currentUser?.username ?? 'staff',
        userFullName: _auth.currentUser?.fullName ?? 'Nhân Viên',
        userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
        action: 'SEND_KITCHEN',
        targetType: 'TABLE',
        targetId: widget.table.name,
        details: 'Gửi bếp bàn ${widget.table.name} (Mã: ${widget.table.currentBillId ?? ""}): ${unsentItems.length} món mới',
      ));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã gửi ${unsentItems.length} món đến Bếp thành công! 🍽️'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );

        // 4. Ngay lập tức tự động thoát ra màn hình danh sách bàn
        context.go('/tables');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi gửi bếp: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingKitchen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = _cartCount > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // If cart is empty, return table to completely EMPTY state
            if (_cart.isEmpty) {
              widget.table.clearTable();
            } else {
              widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
              widget.table.inUse = true;
            }
            _fb.saveTable(widget.table);
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
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 10,
                    offset: Offset(0, -3),
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
                          ? 'Xong, Quay Lại Đơn • ${FormatUtils.vnd(_cartTotal)} (${_cartCount} món)'
                          : 'Xem Lại Đơn • ${FormatUtils.vnd(_cartTotal)} (${_cartCount} món)',
                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      if (!await _ensureShiftOpen()) return;

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
                      _fb.saveTable(widget.table);

                      if (widget.isAddingMore) {
                        Navigator.of(context).pop(_cart);
                      } else {
                        context.pushReplacement('/order-cart', extra: {
                          'table': widget.table,
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
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Tìm món ăn, thức uống, mã SKU...',
          prefixIcon: const Icon(Icons.search, color: AppColors.primary),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textSecondary, size: 18),
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
      color: Colors.white,
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
            selectedColor: AppColors.primaryLight,
            labelStyle: GoogleFonts.beVietnamPro(
              color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
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
            const Icon(Icons.no_meals_outlined, size: 64, color: AppColors.textHint),
            const SizedBox(height: 12),
            Text('Không tìm thấy món nào', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
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

        final bool hasOptions = product.sizes.isNotEmpty || product.hasIceSugarOptions || product.allowedToppings.isNotEmpty;

        return _ProductListRow(
          product: product,
          quantity: qty,
          hasOptions: hasOptions,
          onTap: () {
            if (hasOptions) {
              _showProductCustomizer(product);
            } else {
              _quickAddToCart(product);
            }
          },
          onAdd: () {
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
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

  const _ProductListRow({
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

    return Container(
      decoration: BoxDecoration(
        color: isInCart ? AppColors.primaryLight.withOpacity(0.35) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isInCart ? AppColors.primary.withOpacity(0.5) : AppColors.border,
          width: isInCart ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Product Image Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 58,
                    height: 58,
                    child: (product.imageBase64 != null && product.imageBase64!.isNotEmpty)
                        ? _buildBase64Image(product.imageBase64!)
                        : (product.assetPath != null
                            ? Image.asset(
                                product.assetPath!,
                                fit: BoxFit.cover,
                                width: 58,
                                height: 58,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
                                ),
                              )
                            : const Center(
                                child: Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
                              )),
                  ),
                ),
                const SizedBox(width: 14),

                // Product Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: GoogleFonts.beVietnamPro(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            FormatUtils.vnd(product.price),
                            style: GoogleFonts.beVietnamPro(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (product.unit.isNotEmpty)
                            Text(
                              ' / ${product.unit}',
                              style: GoogleFonts.beVietnamPro(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          if (product.category.isNotEmpty) ...[
                            Text(' • ', style: TextStyle(color: Colors.grey.shade400)),
                            Text(
                              product.category,
                              style: GoogleFonts.beVietnamPro(
                                color: AppColors.textSecondary,
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
                            _buildPillTag('Size S/M/L', Colors.blue.shade700, Colors.blue.shade50),
                          if (product.allowedToppings.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            _buildPillTag('Topping', Colors.orange.shade800, Colors.orange.shade50),
                          ],
                          if (product.hasIceSugarOptions) ...[
                            const SizedBox(width: 4),
                            _buildPillTag('Đường/Đá', Colors.green.shade800, Colors.green.shade50),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Action buttons
                if (!isInCart)
                  InkWell(
                    onTap: onAdd,
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.3),
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
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary.withOpacity(0.5)),
                          ),
                          child: const Icon(Icons.remove, color: AppColors.primary, size: 16),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'x$quantity',
                        style: GoogleFonts.beVietnamPro(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: onAdd,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
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

  Widget _buildBase64Image(String base64) {
    try {
      final String cleanBase64 = base64.contains(',') ? base64.split(',').last : base64;
      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: 58,
        height: 58,
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
        ),
      );
    } catch (_) {
      return const Center(
        child: Icon(Icons.restaurant_menu, color: AppColors.primary, size: 28),
      );
    }
  }
}
