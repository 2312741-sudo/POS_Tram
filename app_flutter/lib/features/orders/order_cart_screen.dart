// lib/features/orders/order_cart_screen.dart
import 'package:intl/intl.dart';
import '../../core/domain/order_integrity.dart';
import '../../core/domain/product_availability.dart';
import '../crm/customer_management_screen.dart';
import '../../core/domain/customer_search.dart';
import 'widgets/customer_picker_sheet.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/printer/receipt_printer.dart';
import '../../core/domain/item_options.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/manager_pin_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/utils/text_formatters.dart';
import '../../core/vietqr/vietqr_generator.dart';
import '../../data/models/app_models.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/firebase_service.dart';
import 'widgets/item_option_pickers.dart';
import '../../data/services/campaign_service.dart';
import '../../data/services/loyalty_service.dart';
import '../promotions/voucher_check.dart';
import 'widgets/campaign_pricing.dart';
import 'widgets/combo_reward_picker_sheet.dart';
import '../../core/domain/deleted_items.dart';
import '../cash_shift/cash_shift_dialog.dart';
import 'widgets/cart_item_card.dart';
import 'widgets/cart_tree_group_card.dart';
import 'widgets/delete_reason_dialog.dart';
import 'widgets/cart_panels.dart';
import '../../core/domain/table_customer.dart';
import 'widgets/payment_widgets.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/manager_pin_dialogs.dart';

class OrderCartScreen extends StatefulWidget {
  final TableModel table;
  final List<OrderItemModel> initialProducts;
  final bool autoOpenCheckout;
  final bool returnToParentOnPay;

  const OrderCartScreen({
    super.key,
    required this.table,
    this.initialProducts = const [],
    this.autoOpenCheckout = false,
    this.returnToParentOnPay = false,
  });

  @override
  State<OrderCartScreen> createState() => _OrderCartScreenState();
}

class _OrderCartScreenState extends State<OrderCartScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  late List<OrderItemModel> _cart;
  List<BillDiscountModel> _appliedDiscounts = [];
  double _vatRate = 0.0;
  final String _billNotes = '';
  StoreInfoModel? _storeInfo;
  List<PromotionModel> _allPromotions = [];
  // Chương trình khuyến mãi mới (tính bằng Pricing Engine) + cache theo id (gồm cả CT của mã voucher)
  List<CampaignModel> _campaigns = [];
  final Map<String, CampaignModel> _campaignById = {};
  bool _isLoading = false;
  bool _isShiftOpen = false;
  bool _autoPrintBill = true;
  // Chế độ hiển thị giỏ hàng: dạng cây phân cấp (mặc định) hay danh sách phẳng
  bool _treeViewMode = true;

  // Products, Categories and Backend Note Presets for Toppings & Notes editing
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  List<String> _backendNotePresets = [];
  ItemCatalog _catalog = const ItemCatalog(); // danh mục note & topping (chưa cấu hình = hành vi cũ)

  // KiotViet CRM Customer Loyalty
  KmtCustomerModel? _selectedCustomer;
  bool _customerPointsUnknown = false; // khách phục hồi từ bàn nhưng chưa tra được số dư
  StreamSubscription<String>? _earnFailSub;
  int _pointsUsed = 0;
  late int _guestCount;

  // Huỷ các listener Firebase khi rời màn hình (trước đây bị rò rỉ listener)
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    _earnFailSub?.cancel();
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _earnFailSub = LoyaltyEarnQueue.failures.stream.listen((msg) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.orange.shade800));
    });
    // Tích điểm còn tồn từ các hóa đơn trước (mất mạng / hóa đơn chưa đồng bộ)
    unawaited(LoyaltyEarnQueue.retryAll(LoyaltyService(), onlyStoreCode: _fb.currentStoreCode));
    _isShiftOpen = _fb.activeShiftCache != null && _fb.activeShiftCache!.isOpen;
    widget.table.ensureCodes();
    _cart = List.from(widget.initialProducts.isNotEmpty ? widget.initialProducts : widget.table.currentItems);
    _guestCount = widget.table.guestCount ?? 2;
    // Phục hồi ưu đãi khuyến mãi đã áp dụng từ bàn (giúp treo đơn qua giờ combo không bị mất)
    _appliedDiscounts = List.from(widget.table.currentDiscounts);
    if (_cart.isNotEmpty) {
      widget.table.openedAt ??= DateTime.now().millisecondsSinceEpoch;
    }
    _selectedCustomer = TableCustomerLogic.restore(widget.table);
    if (_selectedCustomer != null) {
      _customerPointsUnknown = true;
      unawaited(_refreshCustomerPoints());
      unawaited(_ensureCustomerBirthday().then((_) {
        if (mounted) _autoApplyBirthdayCampaigns();
      }));
    }
    _storeInfo = _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _fb.currentStoreCode, storeName: 'POS Trạm');
    _loadStoreAndPromotions();
    _loadAutoPrintSetting();
    _loadTreeViewSetting();

    final storeCode = _fb.currentStoreCode;
    _subscriptions.add(_fb.productsStream(storeCode: storeCode).listen((products) {
      if (mounted) setState(() => _products = products);
    }));
    _subscriptions.add(_fb.categoriesStream(storeCode: storeCode).listen((cats) {
      if (mounted) setState(() => _categories = cats);
    }));
    _subscriptions.add(_fb.productNotesStream(storeCode: storeCode).listen((notes) {
      if (mounted) {
        final list = notes
            .map((n) => n['text']?.toString() ?? n['name']?.toString() ?? '')
            .where((s) => s.trim().isNotEmpty)
            .toList();
        if (mounted) setState(() => _backendNotePresets = list);
      }
    }));

    _subscriptions.add(_fb.itemCatalogStream(storeCode: storeCode).listen((c) {
      if (mounted) setState(() => _catalog = c);
    }));

    _subscriptions.add(_fb.cashShiftsStream().listen((shifts) {
      final openOne = _fb.ownOpenShiftIn(shifts);
      if (mounted) {
        setState(() => _isShiftOpen = openOne != null);
      }
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
      final ok = shift != null && shift.isOpen;
      if (mounted) setState(() => _isShiftOpen = ok);
      if (!ok && mounted) {
        await _ensureShiftOpen();
      }
      if (widget.autoOpenCheckout && mounted && _cart.isNotEmpty) {
        await _showPaymentSheet();
      }
    });
  }

  Future<void> _loadAutoPrintSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _autoPrintBill = prefs.getBool('auto_print_bill_on_checkout') ?? (_storeInfo?.autoPrintBill ?? true);
        });
      }
    } catch (_) {}
  }

  Future<void> _saveAutoPrintSetting(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('auto_print_bill_on_checkout', value);
    } catch (_) {}
  }

  Future<void> _loadTreeViewSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _treeViewMode = prefs.getBool('cart_tree_view_mode') ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _setTreeViewMode(bool mode) async {
    setState(() => _treeViewMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('cart_tree_view_mode', mode);
    } catch (_) {}
  }

  Future<void> _loadStoreAndPromotions() async {
    try {
      final info = await _fb.getStoreInfo();
      // Lỗi tải KM cũ không được chặn việc hiển thị các CTKM mới (và ngược lại)
      List<PromotionModel> promos = const [];
      try {
        promos = await _fb.getPromotions();
      } catch (e) {
        debugPrint('Error loading promotions into cart: $e');
      }

      // Chương trình KM mới (CampaignModel) được tính bằng Pricing Engine, không qua PromotionModel cũ.
      // Chương trình chuyển đổi từ KM cũ (legacyPromotionId trùng KM cũ đang có) vẫn đi đường cũ.
      final campaigns = <CampaignModel>[];
      try {
        final all = await CampaignService().getCampaigns();
        final storeCode = _fb.currentStoreCode;
        for (final c in all) {
          if (!c.active) continue;
          if (!c.isEligibleForBranch(storeCode)) continue;
          if (c.legacyPromotionId != null && promos.any((p) => p.id == c.legacyPromotionId)) continue;
          campaigns.add(c);
        }
      } catch (e) {
        debugPrint('Error loading campaigns into cart: $e');
      }

      if (_products.isEmpty) {
        try {
          final prods = await _fb.getProducts(storeCode: _fb.currentStoreCode);
          if (mounted && prods.isNotEmpty && _products.isEmpty) {
            setState(() => _products = prods);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _storeInfo = info;
          _vatRate = (info.defaultVatRate == 8.0) ? 0.0 : info.defaultVatRate;
          _allPromotions = promos;
          _campaigns = campaigns;
          for (final c in campaigns) {
            _campaignById[c.campaignId] = c;
          }
        });
        _recalculateDiscounts();
      }
    } catch (_) {}
  }

  int get _rawSubTotal => _cart.fold(0, (s, p) => s + (p.unitPrice * p.quantity));

  int get _itemDiscountTotal => _cart.fold(0, (s, p) => s + p.lineDiscountTotal);

  int get _voucherDiscountTotal => _appliedDiscounts.fold(0, (s, d) => s + d.amount);

  int get _pointRedeemRate => _storeInfo?.pointRedeemRate ?? 1000;

  int get _pointsDiscount => _pointsUsed * _pointRedeemRate;

  int get _subTotal => _rawSubTotal;

  int get _totalDiscount => _itemDiscountTotal + _voucherDiscountTotal + _pointsDiscount;

  int get _afterDiscount {
    final diff = _subTotal - _totalDiscount;
    return diff > 0 ? diff : 0;
  }

  int get _vatAmount => (_afterDiscount * (_vatRate / 100)).round();

  int get _finalTotal => _afterDiscount + _vatAmount;

  /// Điểm sẽ được tích khi thanh toán: tính từ số tiền khách thực trả, theo cấu hình chuỗi/chi nhánh
  /// (máy chủ tính lại từ hóa đơn PAID - cùng công thức)
  double get _earnRate => _storeInfo?.pointEarnRate ?? 1.0;
  int get _earnPreview => _pointsBlockedByPromo ? 0 : LoyaltyMath.pointsToAward(billAmount: _finalTotal, earnRatePercent: _earnRate, redeemRate: _pointRedeemRate);

  void _openLoyaltyConfig() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CustomerManagementScreen()));
  }

  int get _cartCount => _cart.fold(0, (s, p) => s + p.quantity);

  // ==================== CART ACTIONS ====================
  Future<void> _incrementItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    if (item.isSentKitchen || item.hasDiscount) {
      // Dòng này đã gửi bếp hoặc đã có giảm giá món: không cộng dồn trực tiếp vào dòng này
      // (vì phần tăng thêm chưa gửi bếp và không tự động được hưởng giảm giá).
      // Tìm xem đã có dòng mới chưa gửi bếp & không giảm giá cùng loại món này chưa:
      final existingNewIdx = _cart.indexWhere((i) =>
          !i.isSentKitchen &&
          !i.hasDiscount &&
          i.productId == item.productId &&
          i.name == item.name &&
          i.selectedSize == item.selectedSize &&
          i.selectedSugar == item.selectedSugar &&
          i.selectedIce == item.selectedIce &&
          i.selectedToppings.join(',') == item.selectedToppings.join(',') &&
          i.note == item.note);
      if (existingNewIdx >= 0) {
        setState(() {
          _cart[existingNewIdx] = _cart[existingNewIdx].copyWith(
            quantity: _cart[existingNewIdx].quantity + 1,
          );
        });
      } else {
        final staffUser = _auth.currentUser?.username ?? 'staff';
        final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
        final newItem = OrderItemModel(
          productId: item.productId,
          name: item.name,
          price: item.price,
          quantity: 1,
          selectedSize: item.selectedSize,
          sizeExtraPrice: item.sizeExtraPrice,
          selectedSugar: item.selectedSugar,
          selectedIce: item.selectedIce,
          selectedToppings: List.from(item.selectedToppings),
          toppingPrice: item.toppingPrice,
          note: item.note,
          orderedBy: staffUser,
          orderedByName: staffName,
          orderedAt: DateTime.now().millisecondsSinceEpoch,
          isSentKitchen: false,
        );
        setState(() {
          _cart.add(newItem);
        });
      }
    } else {
      setState(() {
        _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity + 1);
      });
    }
    widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
    await _fb.saveTable(widget.table).catchError((_) {});
    _recalculateDiscounts();
  }

  /// Số phần (trong [qty] phần sắp xóa khỏi [item]) thuộc đơn ĐÃ LƯU trên bàn.
  int _savedPortion(OrderItemModel item, int qty) => DeletedItemsLogic.persistedPortion(
        persisted: widget.table.currentItems,
        cart: _cart,
        line: item,
        removeQty: qty,
      );

  /// Cổng hủy món đã gửi bếp: quyền CANCEL_KITCHEN_ITEM hoặc quyền DELETE_ITEM (nhân viên được xóa món trong bàn),
  /// hoặc Quản lý duyệt bằng PIN.
  Future<bool> _ensureCanCancelKitchenItem(OrderItemModel item) async {
    if (!item.isSentKitchen || _auth.can(AppPermissions.cancelKitchenItem) || _auth.can(AppPermissions.deleteItem)) return true;
    final approval = await showManagerApprovalDialog(
      context,
      action: ManagerApprovalAction.cancelKitchenItem,
      contextText: 'Hủy/giảm "${item.name}" đã gửi bếp tại ${widget.table.name}',
    );
    if (approval == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền hủy món đã gửi bếp!'), backgroundColor: AppColors.danger),
      );
    }
    return approval != null;
  }

  /// Xóa/giảm phần món ĐÃ LƯU trên bàn cần quyền DELETE_ITEM (món mới thêm trong giỏ, chưa lưu, thì không cần).
  bool _ensureCanDeleteSaved(int savedPortion) {
    if (savedPortion <= 0 || _auth.can(AppPermissions.deleteItem)) return true;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền xóa món khỏi đơn (DELETE_ITEM).'), backgroundColor: AppColors.danger),
      );
    }
    return false;
  }

  /// Ghi nhận 1 lần xóa món đã lưu: entry vào bàn (deletedItemsJson), lịch sử thao tác
  /// của đơn và audit log DELETE_ITEM.
  DeletedItemEntry _recordDeletion(OrderItemModel line, {required int removeQty, required int savedQty, required String reason}) {
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';
    final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = DeletedItemsLogic.buildEntry(
      line: line,
      removeQty: removeQty,
      savedQty: savedQty,
      reason: reason,
      staffUsername: staffUser,
      staffFullName: staffName,
      timestamp: now,
    );
    widget.table.addDeletedItem(entry);
    final details = DeletedItemsLogic.auditDetails(entry, widget.table.name);
    widget.table.addActionLog(OrderActionLogModel(
      timestamp: now,
      staffUsername: staffUser,
      staffFullName: staffName,
      action: 'DELETE_ITEM',
      details: '$staffName: $details',
    ));
    _fb.logAction(AuditLogModel(
      timestamp: now,
      username: staffUser,
      userFullName: staffName,
      userRole: staffRole,
      action: 'DELETE_ITEM',
      targetType: 'ORDER_ITEM',
      targetId: widget.table.currentOrderCode ?? widget.table.name,
      details: details,
      isSuspicious: line.isSentKitchen,
      extra: DeletedItemsLogic.auditFields(entry, tableName: widget.table.name, orderCode: widget.table.currentOrderCode),
    ));
    return entry;
  }

  Future<void> _decrementItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    if (item.quantity <= 1) {
      await _removeItem(index);
      return;
    }
    if (!await _ensureCanCancelKitchenItem(item) || !mounted) return;

    final saved = _savedPortion(item, 1);
    if (!_ensureCanDeleteSaved(saved)) return;
    String? reason;
    if (saved > 0) {
      reason = await showDeleteItemReasonDialog(
        context,
        itemName: item.name,
        quantity: 1,
        amount: DeletedItemsLogic.removedAmount(item, 1),
        tableName: widget.table.name,
        sentToKitchen: item.isSentKitchen,
        isReduce: true,
      );
      if (reason == null || !mounted) return;
    }
    if (index >= _cart.length || _cart[index] != item) return;

    setState(() {
      _cart[index] = item.copyWith(quantity: item.quantity - 1);
    });
    _recalculateDiscounts();

    if (saved > 0) {
      _recordDeletion(item, removeQty: 1, savedQty: saved, reason: reason!);
      widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
      await _fb.saveTable(widget.table).catchError((_) {});
    }
  }

  Future<void> _confirmRemoveItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    final bool isKitchen = item.isSentKitchen;
    if (!await _ensureCanCancelKitchenItem(item) || !mounted) return;

    // Món đã lưu: hộp thoại chọn lý do thay cho xác nhận thường.
    if (_savedPortion(item, item.quantity) > 0) {
      await _removeItem(index, kitchenGatePassed: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: context.tc.danger, size: 24),
            const SizedBox(width: 8),
            Text('Xác nhận xóa món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc muốn xóa món "${item.name}" (x${item.quantity}) khỏi bàn ${widget.table.name}?',
              style: GoogleFonts.beVietnamPro(fontSize: 14),
            ),
            if (isKitchen) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.bg(Colors.amber.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Món này đã gửi bếp, việc hủy món sẽ được ghi nhật ký kiểm toán.',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.ink(Colors.amber.shade900)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_cart.length == 1) ...[
              const SizedBox(height: 10),
              Text(
                '💡 Đây là món cuối cùng. Xóa xong bàn sẽ tự động về trạng thái TRỐNG.',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.primary, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bỏ qua'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _removeItem(index, kitchenGatePassed: true);
    }
  }

  Future<void> _confirmRemoveGroup(CartProductGroup group) async {
    if (!await _ensureShiftOpen() || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_sweep_outlined, color: context.tc.danger, size: 24),
            const SizedBox(width: 8),
            Text('Xóa toàn bộ món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Bạn có chắc muốn xóa tất cả ${group.totalQuantity} phần của món "${group.productName}" (${group.branches.length} nhánh biến thể) khỏi bàn ${widget.table.name}?',
          style: GoogleFonts.beVietnamPro(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bỏ qua'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa tất cả', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final sortedIndices = group.branches.expand((b) => b.cartIndices).toSet().toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sortedIndices) {
      if (idx < _cart.length) {
        await _removeItem(idx, kitchenGatePassed: true);
      }
    }
  }

  Future<void> _confirmRemoveBranch(CartBranchItem branch) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    if (branch.cartIndices.length <= 1) {
      await _confirmRemoveItem(branch.cartIndex);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_outline, color: context.tc.danger, size: 24),
            const SizedBox(width: 8),
            Text('Xác nhận xóa món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(
          'Bạn có chắc muốn xóa tất cả ${branch.totalQuantity} phần của nhánh "${branch.item.name}" khỏi bàn ${widget.table.name}?',
          style: GoogleFonts.beVietnamPro(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Bỏ qua'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final sortedIndices = List<int>.from(branch.cartIndices)..sort((a, b) => b.compareTo(a));
    for (final idx in sortedIndices) {
      if (idx < _cart.length) {
        await _removeItem(idx, kitchenGatePassed: true);
      }
    }
  }

  Future<void> _incrementBranch(CartBranchItem branch) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final unsentIdx = branch.cartIndices.lastWhere(
      (idx) => idx < _cart.length && !_cart[idx].isSentKitchen && !_cart[idx].hasDiscount,
      orElse: () => -1,
    );
    if (unsentIdx >= 0) {
      await _incrementItem(unsentIdx);
    } else {
      final targetIdx = branch.cartIndices.lastWhere((idx) => idx < _cart.length, orElse: () => branch.cartIndex);
      await _incrementItem(targetIdx);
    }
  }

  Future<void> _decrementBranch(CartBranchItem branch) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final unsentIdx = branch.cartIndices.lastWhere(
      (idx) => idx < _cart.length && !_cart[idx].isSentKitchen,
      orElse: () => -1,
    );
    if (unsentIdx >= 0) {
      await _decrementItem(unsentIdx);
    } else {
      final targetIdx = branch.cartIndices.lastWhere((idx) => idx < _cart.length, orElse: () => branch.cartIndex);
      await _decrementItem(targetIdx);
    }
  }

  Future<void> _showEditBranchNoteAndToppingDialog(CartBranchItem branch) async {
    await _showEditItemNoteAndToppingDialog(branch.cartIndex, syncIndices: branch.cartIndices);
  }

  Future<void> _removeItem(int index, {bool kitchenGatePassed = false}) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';
    final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

    if (!kitchenGatePassed && !await _ensureCanCancelKitchenItem(item)) return;
    if (!mounted) return;

    // Phần đã lưu trên bàn → bắt buộc chọn lý do.
    final saved = _savedPortion(item, item.quantity);
    if (!_ensureCanDeleteSaved(saved)) return;
    String? reason;
    if (saved > 0) {
      reason = await showDeleteItemReasonDialog(
        context,
        itemName: item.name,
        quantity: item.quantity,
        amount: item.itemTotal,
        tableName: widget.table.name,
        sentToKitchen: item.isSentKitchen,
        isLastItem: _cart.length == 1,
      );
      if (reason == null || !mounted) return;
    }
    if (index >= _cart.length || _cart[index] != item) return;

    if (item.isSentKitchen) {
      // Log suspicious action
      await _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: staffUser,
        userFullName: staffName,
        userRole: staffRole,
        action: 'CANCEL_KITCHEN_ITEM',
        targetType: 'TABLE',
        targetId: widget.table.name,
        details: 'Hủy món đã gửi bếp: ${item.name} x${item.quantity} tại ${widget.table.name}${reason != null ? " — Lý do: $reason" : ""}',
        isSuspicious: true,
      ));
    } else if (saved <= 0) {
      await _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: staffUser,
        userFullName: staffName,
        userRole: staffRole,
        action: 'CANCEL_ITEM',
        targetType: 'TABLE',
        targetId: widget.table.name,
        details: 'Hủy/bỏ món khỏi bàn ${widget.table.name}: ${item.name} x${item.quantity}',
        isSuspicious: false,
      ));
    }

    if (saved > 0) {
      _recordDeletion(item, removeQty: item.quantity, savedQty: saved, reason: reason!);
    } else {
      widget.table.addActionLog(OrderActionLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        staffUsername: staffUser,
        staffFullName: staffName,
        action: 'CANCEL_ITEM',
        details: '$staffName hủy món ${item.name} (x${item.quantity})',
      ));
    }

    setState(() {
      _cart.removeAt(index);
    });

    // Nếu giỏ hàng đã bị xóa hết món -> Chuyển bàn về trạng thái TRỐNG hoàn toàn!
    if (_cart.isEmpty) {
      _recalculateDiscounts();
      if (widget.table.deletedItems.isNotEmpty) {
        // Có món đã lưu bị xóa → ghi HĐ ĐÃ HỦY (giữ deletedItems cho báo cáo) rồi dọn bàn.
        widget.table.currentOrderJson = '';
        try {
          await _fb.cancelActiveBill(
            widget.table,
            reason: 'Xóa hết món${reason != null ? " — $reason" : ""}',
            staffUsername: staffUser,
            staffFullName: staffName,
            staffRole: staffRole,
          );
        } catch (_) {
          widget.table.clearTable();
          await _fb.saveTable(widget.table).catchError((_) {});
        }
      } else {
        widget.table.clearTable();
        await _fb.saveTable(widget.table).catchError((_) {});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xóa hết món trong bàn ${widget.table.name}. Bàn đã chuyển về trạng thái TRỐNG.'),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
    await _fb.saveTable(widget.table).catchError((_) {});
    _recalculateDiscounts();
  }

  // ==================== CANCEL ENTIRE BILL ====================
  Future<void> _showCancelBillDialog() async {
    if (!await _ensureShiftOpen() || !mounted) return;
    if (_cart.isEmpty) {
      widget.table.clearTable();
      await _fb.saveTable(widget.table);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final hasKitchen = _cart.any((i) => i.isSentKitchen);
    if (hasKitchen && !_auth.can(AppPermissions.cancelBill) && !_auth.can(AppPermissions.cancelKitchenItem) && !_auth.can(AppPermissions.deleteItem)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Bạn không có quyền hủy hóa đơn đã gửi bếp! Vui lòng liên hệ Quản Lý.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final reasonCtrl = TextEditingController(text: 'Khách đổi ý/không đợi được');
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';
    final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final quickReasons = [
            'Khách đổi ý/không đợi được',
            'Nhập nhầm bàn',
            'Khách về gấp',
            'Khách chuyển bàn khác',
            'Sự cố món/bếp hết hàng',
          ];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.cancel_outlined, color: context.tc.danger, size: 24),
                const SizedBox(width: 8),
                Text('Hủy Hóa Đơn Bàn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.bg(const Color(0xFFFFF0F1)),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.tc.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(widget.table.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15, color: context.tc.primaryDark)),
                            Text(widget.table.zone, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Mã HĐ: ${widget.table.currentBillId ?? "Chưa có"}${widget.table.currentOrderCode != null ? " • Đơn: ${widget.table.currentOrderCode}" : ""}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.primary)),
                        Text('Số món: ${_cart.length} món ($_cartCount phần) • Tổng: ${FormatUtils.vnd(_finalTotal)}', style: GoogleFonts.beVietnamPro(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Lý do hủy hóa đơn *:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickReasons.map((r) {
                      final isSelected = reasonCtrl.text == r;
                      return ChoiceChip(
                        label: Text(r, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : context.tc.textPrimary)),
                        selected: isSelected,
                        selectedColor: context.tc.primary,
                        backgroundColor: context.tc.cardElevated,
                        onSelected: (val) {
                          if (val) {
                            setDlgState(() => reasonCtrl.text = r);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nhập chi tiết lý do hủy đơn...',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ Sau khi xác nhận, toàn bộ món sẽ bị hủy và bàn sẽ trở về trạng thái TRỐNG.',
                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.ink(Colors.red.shade700), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bỏ qua'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger),
                icon: const Icon(Icons.delete_forever, size: 16, color: Colors.white),
                label: const Text('Xác nhận Hủy Đơn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final reason = reasonCtrl.text.trim();
      setState(() => _isLoading = true);
      try {
        await _fb.cancelActiveBill(
          widget.table,
          reason: reason,
          staffUsername: staffUser,
          staffFullName: staffName,
          staffRole: staffRole,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã hủy hóa đơn bàn ${widget.table.name} thành công. Bàn đã chuyển về trạng thái TRỐNG!'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi hủy hóa đơn: $e'), backgroundColor: AppColors.danger),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  /// Tự thêm món được tặng/giảm vào đơn khi đơn đã đủ điều kiện nhưng món thưởng chưa có.
  /// Một món thưởng → thêm luôn; nhiều món → hỏi chọn. Trả true khi đã thêm.
  Future<bool> _addRewardItems(CampaignModel c) async {
    if (_products.isEmpty) {
      try {
        final prods = await _fb.getProducts(storeCode: _fb.currentStoreCode);
        if (prods.isNotEmpty && mounted) {
          setState(() => _products = prods);
        }
      } catch (_) {}
    }
    final plan = CartCampaignPricing.rewardPlan(c, cart: _cart, products: _products);
    if (plan == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chương trình chưa cấu hình món được tặng/giảm hoặc món đã hết.')));
      }
      return false;
    }
    ProductModel? chosen = plan.candidates.length == 1 ? plan.candidates.first : null;
    if (chosen == null && mounted) {
      chosen = await showDialog<ProductModel>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text('Chọn món được tặng/giảm (${plan.units} phần)', style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold)),
          children: [
            for (final p in plan.candidates)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, p),
                child: Text('${p.name} • ${FormatUtils.vnd(p.price)}', style: GoogleFonts.beVietnamPro(fontSize: 14)),
              ),
          ],
        ),
      );
    }
    final picked = chosen;
    if (picked == null) return false;
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
    setState(() {
      _cart.add(OrderItemModel(
        productId: picked.id,
        name: picked.name,
        price: picked.price,
        quantity: plan.units,
        orderedBy: staffUser,
        orderedByName: staffName,
        orderedAt: DateTime.now().millisecondsSinceEpoch,
        isSentKitchen: false,
      ));
    });
    widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
    await _fb.saveTable(widget.table).catchError((_) {});
    return true;
  }

  /// Mở màn hình chọn món giảm giá Combo (chỉ hiển thị món/nhóm món được chọn giảm giá,
  /// giới hạn số lượng món được chọn theo số lượng món điều kiện (nước) trong giỏ hàng).
  Future<bool> _pickComboRewardItems(CampaignModel c) async {
    if (_products.isEmpty) {
      try {
        final prods = await _fb.getProducts(storeCode: _fb.currentStoreCode);
        if (prods.isNotEmpty && mounted) {
          setState(() => _products = prods);
        }
      } catch (_) {}
    }
    final combo = CartCampaignPricing.getComboInfo(c, cart: _cart, products: _products);
    if (combo == null) {
      return _addRewardItems(c);
    }

    if (combo.buyUnits <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đơn chưa có món nước nào đủ điều kiện của "${c.name}". Vui lòng chọn nước trước.'),
            backgroundColor: AppColors.accent,
          ),
        );
      }
      return false;
    }

    if (combo.candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chương trình chưa cấu hình món giảm giá hoặc các món đã hết hàng.')),
        );
      }
      return false;
    }

    final maxToSelect = combo.remainingRewardUnits > 0 ? combo.remainingRewardUnits : combo.maxRewardAllowed;
    if (maxToSelect <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Đơn đã đủ số món giảm giá (${combo.rewardUnitsInCart} món) theo ${combo.buyUnits} món nước.')),
        );
      }
      return true;
    }

    final chosen = await showModalBottomSheet<Map<ProductModel, int>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ComboRewardPickerSheet(
        campaign: c,
        maxAllowedUnits: maxToSelect,
        waterCount: combo.buyUnits,
        candidateProducts: combo.candidates,
        discountPerUnit: combo.discountPerUnit,
        benefitDescription: describeCampaignBenefit(c),
      ),
    );

    if (chosen == null || chosen.isEmpty) return false;

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân viên';
    setState(() {
      for (final entry in chosen.entries) {
        final p = entry.key;
        final qty = entry.value;
        if (qty <= 0) continue;
        _cart.add(OrderItemModel(
          productId: p.id,
          name: p.name,
          price: p.price,
          quantity: qty,
          orderedBy: staffUser,
          orderedByName: staffName,
          orderedAt: DateTime.now().millisecondsSinceEpoch,
          isSentKitchen: false,
        ));
      }
    });
    widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
    await _fb.saveTable(widget.table).catchError((_) {});
    return true;
  }

  /// Pricing Engine cho 1 chương trình trên giỏ hàng hiện tại
  PriceQuoteModel _quoteCampaign(CampaignModel c) {
    final isApplied = _appliedDiscounts.any((d) => d.campaignId == c.campaignId);
    return CartCampaignPricing.quote(
      c,
      cart: _cart,
      products: _products,
      branchId: _fb.currentStoreCode,
      guestCount: _guestCount,
      customerBirthday: _selectedCustomer?.birthday,
      nowMs: widget.table.openedAt,
      ignoreSchedule: isApplied,
    );
  }

  /// Đơn đang dùng chương trình KM khóa tích điểm?
  bool get _pointsBlockedByPromo => _appliedDiscounts.any((d) {
        final c = d.campaignId == null ? null : _campaignById[d.campaignId];
        return c != null && c.blockPoints;
      });

  /// Tự áp dụng các KM "chỉ đúng ngày sinh nhật" khi đơn đã gắn khách có ngày sinh trùng hôm nay.
  void _autoApplyBirthdayCampaigns() {
    final bday = _selectedCustomer?.birthday ?? '';
    if (bday.trim().isEmpty) return;
    final added = <String>[];
    for (final c in _campaigns) {
      if (!c.birthdayOnly || c.hasCodes || !c.isEligibleAt(DateTime.now().millisecondsSinceEpoch)) continue;
      if (_appliedDiscounts.any((d) => d.campaignId == c.campaignId)) continue;
      final q = _quoteCampaign(c);
      final amt = q.totalPromotionDiscount;
      if (amt <= 0) continue;
      final allowStack = _storeInfo?.allowStackPromotions ?? true;
      final check = CartCampaignPricing.checkStacking(
        currentDiscounts: _appliedDiscounts,
        incoming: c,
        campaignsById: _campaignById,
        allowStackPromotions: allowStack,
      );
      if (!check.canStack) continue;
      if (!allowStack) _appliedDiscounts.clear();
      final comboCnt = q.rewardBenefits.where((b) => b.campaignId == c.campaignId).fold<int>(0, (s, b) => s + b.quantity);
      _appliedDiscounts.add(CartCampaignPricing.discount(c, amt, comboCount: comboCnt > 0 ? comboCnt : null));
      added.add(c.name);
    }
    if (added.isNotEmpty) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sinh nhật khách: đã tự áp dụng ${added.join(", ")}'),
        backgroundColor: AppColors.success,
      ));
    }
  }

  /// Hồ sơ khách khôi phục từ bàn có thể thiếu ngày sinh → tra lại theo SĐT rồi tính lại KM sinh nhật.
  Future<void> _ensureCustomerBirthday() async {
    final c = _selectedCustomer;
    if (c == null || c.birthday.trim().isNotEmpty || c.phone.isEmpty) return;
    try {
      final full = await _fb.lookupCustomer(c.phone);
      if (!mounted || !identical(_selectedCustomer, c) || full == null || full.birthday.trim().isEmpty) return;
      setState(() => c.birthday = full.birthday);
    } catch (_) {}
  }

  /// Tự áp dụng các chương trình khuyến mãi tự động (autoApply: true, không có mã, không bắt buộc ghi chú)
  void _autoApplyEligibleCampaigns() {
    _autoApplyBirthdayCampaigns();

    final now = DateTime.now().millisecondsSinceEpoch;
    final allowStack = _storeInfo?.allowStackPromotions ?? true;
    final newlyApplied = <String>[];

    for (final c in _campaigns) {
      if (!c.autoApply || c.hasCodes || c.requireStaffNote || c.birthdayOnly) continue;
      if (!c.isEligibleAt(now)) continue;
      if (_appliedDiscounts.any((d) => d.campaignId == c.campaignId)) continue;

      final q = _quoteCampaign(c);
      final amt = q.totalPromotionDiscount;
      if (amt <= 0) continue;

      final comboCnt = q.rewardBenefits.where((b) => b.campaignId == c.campaignId).fold<int>(0, (s, b) => s + b.quantity);
      final check = CartCampaignPricing.checkStacking(
        currentDiscounts: _appliedDiscounts,
        incoming: c,
        campaignsById: _campaignById,
        allowStackPromotions: allowStack,
      );
      if (!check.canStack) {
        if (!allowStack && _appliedDiscounts.isNotEmpty) {
          final currentMax = _appliedDiscounts.fold<int>(0, (max, d) => d.amount > max ? d.amount : max);
          if (amt > currentMax) {
            _appliedDiscounts.clear();
            _appliedDiscounts.add(CartCampaignPricing.discount(c, amt, comboCount: comboCnt > 0 ? comboCnt : null));
            newlyApplied.add(c.name);
          }
        }
        continue;
      }
      _appliedDiscounts.add(CartCampaignPricing.discount(c, amt, comboCount: comboCnt > 0 ? comboCnt : null));
      newlyApplied.add(c.name);
    }

    if (newlyApplied.isNotEmpty && mounted) {
      setState(() {});
    }
  }

  void _syncTableDiscounts() {
    widget.table.discountsJson = _appliedDiscounts.isEmpty
        ? null
        : jsonEncode(_appliedDiscounts.map((e) => e.toMap()).toList());
  }

  void _recalculateDiscounts() {
    final List<BillDiscountModel> valid = [];
    final List<String> dropped = [];
    for (final d in _appliedDiscounts) {
      if (d.campaignId != null && _campaignById.containsKey(d.campaignId)) {
        // Chương trình KM mới: tính lại bằng Pricing Engine (bỏ qua khung giờ nếu đơn đã áp dụng trước đó)
        final r = CartCampaignPricing.recalculate(
          [d],
          _campaignById,
          cart: _cart,
          products: _products,
          branchId: _fb.currentStoreCode,
          guestCount: _guestCount,
          customerBirthday: _selectedCustomer?.birthday,
          orderTimestampMs: widget.table.openedAt,
          isExistingOrder: true,
        );
        valid.addAll(r.discounts);
        dropped.addAll(r.dropped);
      } else if (d.promoId != null) {
        final p = _allPromotions.where((pr) => pr.id == d.promoId).firstOrNull;
        if (p != null) {
          if (p.isValid(_subTotal)) {
            final amt = p.calculateDiscount(_subTotal, _cart);
            valid.add(BillDiscountModel(
              promoId: p.id,
              promoCode: d.promoCode ?? p.code,
              description: p.name,
              amount: amt,
              staffNote: d.staffNote,
            ));
          } else {
            dropped.add(d.description);
          }
        } else {
          valid.add(d);
        }
      } else {
        valid.add(d);
      }
    }
    setState(() => _appliedDiscounts = valid);
    _syncTableDiscounts();
    if (widget.table.currentOrderJson.isNotEmpty) {
      _fb.saveTable(widget.table).catchError((_) {});
    }
    if (dropped.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã gỡ khuyến mãi không còn đủ điều kiện: ${dropped.join(", ")}')),
      );
    }
    _autoApplyEligibleCampaigns();
  }

  // ==================== SEND TO KITCHEN ====================
  Future<void> _sendToKitchen() async {
    if (!await _ensureShiftOpen() || !mounted) return;
    if (_cart.isEmpty) return;

    final unsentItems = _cart.where((i) => !i.isSentKitchen).toList();
    if (unsentItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tất cả món đã được gửi bếp trước đó rồi!')),
      );
      return;
    }

    final updatedCart = _cart.map((i) => i.copyWith(isSentKitchen: true)).toList();
    setState(() => _cart = updatedCart);

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';

    final kitchenOrder = KitchenOrderModel(
      tableName: widget.table.name,
      orderCode: widget.table.currentOrderCode,
      billCode: widget.table.currentBillId,
      itemsJson: jsonEncode(unsentItems.map((e) => e.toMap()).toList()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      orderedBy: staffUser,
      orderedByName: staffName,
    );

    // Update table status and action log
    final t = widget.table;
    t.inUse = true;
    t.openedAt ??= DateTime.now().millisecondsSinceEpoch;
    t.currentOrderJson = jsonEncode(updatedCart.map((e) => e.toMap()).toList());
    t.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUser,
      staffFullName: staffName,
      action: 'SEND_KITCHEN',
      details: '$staffName gửi bếp ${unsentItems.length} món mới: ${unsentItems.map((e) => "${e.name} (x${e.quantity})").join(", ")}',
    ));

    // Execute network operations with fast failover
    await Future.wait([
      _fb.sendKitchenOrder(kitchenOrder).catchError((_) {}),
      _fb.saveTable(t).catchError((_) {}),
    ]);

    _fb.logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: _auth.currentUser?.username ?? 'staff',
      userFullName: _auth.currentUser?.fullName ?? 'Nhân Viên',
      userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
      action: 'SEND_KITCHEN',
      targetType: 'TABLE',
      targetId: widget.table.name,
      details: 'Gửi bếp bàn ${widget.table.name}: ${unsentItems.length} món mới',
    ));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã gửi ${unsentItems.length} món đến Bếp thành công! 🍽️'),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
      context.go('/tables');
    }
  }

  // ==================== SPLIT BILL DIALOG ====================
  Future<void> _showSplitBillDialog() async {
    if (!_auth.can(AppPermissions.mergeSplitTable)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền tách hóa đơn!'), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đơn hàng đang trống, không có món để tách!')),
      );
      return;
    }

    List<TableModel> allTables = [];
    try {
      allTables = await _fb.tablesStream().first.timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!mounted) return;

    final emptyTables = allTables
        .where((t) => !t.inUse && !t.isReserved && t.firebaseKey != widget.table.firebaseKey && !t.isAutoSplit)
        .toList();
    final inUseTables = allTables
        .where((t) => t.inUse && t.firebaseKey != widget.table.firebaseKey)
        .toList();

    final activeNamesInZone = <String>{
      widget.table.name,
      ...allTables
          .where((t) =>
              t.zone.trim().toLowerCase() == widget.table.zone.trim().toLowerCase() &&
              (t.inUse || t.isReserved || t.isActivelyOrdering()))
          .map((t) => t.name),
    };
    final nextSplitName = TableModel.nextSplitTableName(widget.table.baseName, activeNamesInZone);
    const String newSplitTableKey = '__NEW_SPLIT_TABLE__';

    // Theo dõi số lượng tách theo từng dòng (index) thay vì productId (tránh trùng các dòng khác topping/note)
    final Map<int, int> splitQty = {
      for (int i = 0; i < _cart.length; i++) i: 0,
    };

    // 3 chế độ xử lý phần món được tách:
    // - 'PAY_NOW': Thanh toán trước ngay phần món tách (chốt HĐ PAID ngay, cộng vào doanh thu & xuất hóa đơn)
    // - 'TRANSFER': Chuyển sang bàn trống khác (hoặc tạo bàn phụ mới trên sơ đồ bàn)
    // - 'MERGE': Ghép phần món tách vào bàn đang có khách khác
    String splitAction = 'PAY_NOW';
    String splitPayMethod = 'CASH';
    String selectedTransferKey = newSplitTableKey;
    String? selectedMergeKey = inUseTables.isNotEmpty ? inUseTables.first.firebaseKey : null;
    bool isSubmitting = false;

    String itemOptionSummary(OrderItemModel item) {
      final parts = <String>[
        if (item.selectedSize.trim().isNotEmpty) 'Size ${item.selectedSize}',
        if (item.selectedSugar.trim().isNotEmpty) item.selectedSugar,
        if (item.selectedIce.trim().isNotEmpty) item.selectedIce,
        if (item.selectedToppings.isNotEmpty) '+${item.selectedToppings.join(", ")}',
        if (item.note.trim().isNotEmpty) '"${item.note.trim()}"',
      ];
      return parts.join(' • ');
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          int totalSplitParts = 0;
          int totalSplitAmount = 0;
          for (int i = 0; i < _cart.length; i++) {
            final q = splitQty[i] ?? 0;
            if (q > 0) {
              totalSplitParts += q;
              final (taken, _) = _cart[i].splitQuantity(q);
              if (taken != null) {
                totalSplitAmount += taken.itemTotal;
              }
            }
          }

          final bool canSubmit = totalSplitParts > 0 &&
              !isSubmitting &&
              (splitAction != 'MERGE' || selectedMergeKey != null);

          String confirmLabel;
          if (splitAction == 'PAY_NOW') {
            confirmLabel = totalSplitParts > 0
                ? 'Thanh Toán & Xuất HĐ (${FormatUtils.vnd(totalSplitAmount)})'
                : 'Thanh Toán & Xuất HĐ';
          } else if (splitAction == 'TRANSFER') {
            final targetLabel = selectedTransferKey == newSplitTableKey
                ? nextSplitName
                : (emptyTables.where((t) => t.firebaseKey == selectedTransferKey).firstOrNull?.name ?? 'Bàn mới');
            confirmLabel = 'Chuyển Sang $targetLabel';
          } else {
            final targetLabel =
                inUseTables.where((t) => t.firebaseKey == selectedMergeKey).firstOrNull?.name ?? 'Bàn Khác';
            confirmLabel = 'Ghép Vào $targetLabel';
          }

          final splitQrUrl = (splitAction == 'PAY_NOW' && splitPayMethod == 'TRANSFER_QR' && totalSplitAmount > 0)
              ? VietQrGenerator.generateImageUrl(
                  bankId: _storeInfo?.bankId ?? 'MB',
                  bankAccount: _storeInfo?.bankAccount ?? '0987654321',
                  accountName: _storeInfo?.accountName ?? 'CHU QUAN FNB',
                  amount: totalSplitAmount,
                  orderInfo: VietQrGenerator.buildOrderInfo(
                    storeCode: _storeInfo?.storeCode ?? 'TRAM01',
                    tableName: widget.table.name,
                    suffix: 'TACH',
                  ),
                )
              : '';

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
            contentPadding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
            title: Row(
              children: [
                Icon(Icons.call_split, color: context.tc.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tách Đơn / Tách Món • ${widget.table.name}',
                    style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Đóng',
                  onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                ),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '1. Chọn số lượng món cần tách:',
                            style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () {
                            setDlgState(() {
                              final allSelected = _cart.asMap().entries.every((e) => (splitQty[e.key] ?? 0) == e.value.quantity);
                              for (int i = 0; i < _cart.length; i++) {
                                splitQty[i] = allSelected ? 0 : _cart[i].quantity;
                              }
                            });
                          },
                          child: Text(
                            _cart.asMap().entries.every((e) => (splitQty[e.key] ?? 0) == e.value.quantity)
                                ? 'Bỏ chọn hết'
                                : 'Chọn tất cả',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 230),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.tc.border),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _cart.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: context.tc.borderLight),
                        itemBuilder: (_, idx) {
                          final item = _cart[idx];
                          final curr = splitQty[idx] ?? 0;
                          final opts = itemOptionSummary(item);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        style: GoogleFonts.beVietnamPro(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: curr > 0 ? context.tc.primary : context.tc.textPrimary,
                                        ),
                                      ),
                                      if (opts.isNotEmpty)
                                        Text(
                                          opts,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                        ),
                                      Text(
                                        '${FormatUtils.vnd(item.unitPrice)} • Có: ${item.quantity} | Tách: $curr',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 11.5,
                                          fontWeight: curr > 0 ? FontWeight.w700 : FontWeight.w500,
                                          color: curr > 0 ? context.tc.primary : context.tc.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                                      onPressed: curr > 0
                                          ? () => setDlgState(() => splitQty[idx] = curr - 1)
                                          : null,
                                    ),
                                    SizedBox(
                                      width: 24,
                                      child: Text(
                                        '$curr',
                                        textAlign: TextAlign.center,
                                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(
                                        Icons.add_circle_outline,
                                        size: 22,
                                        color: curr < item.quantity ? context.tc.primary : null,
                                      ),
                                      onPressed: curr < item.quantity
                                          ? () => setDlgState(() => splitQty[idx] = curr + 1)
                                          : null,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.tc.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Đã chọn tách: $totalSplitParts phần',
                            style: GoogleFonts.beVietnamPro(fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            FormatUtils.vnd(totalSplitAmount),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.tc.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '2. Chọn cách xử lý phần món tách ra:',
                      style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    // Lựa chọn 1: Thanh toán trước
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setDlgState(() => splitAction = 'PAY_NOW'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: splitAction == 'PAY_NOW' ? context.tc.primary : context.tc.border,
                            width: splitAction == 'PAY_NOW' ? 1.8 : 1,
                          ),
                          color: splitAction == 'PAY_NOW' ? context.tc.primary.withValues(alpha: 0.06) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  splitAction == 'PAY_NOW' ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: splitAction == 'PAY_NOW' ? context.tc.primary : context.tc.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Thanh toán trước phần món này',
                                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      Text(
                                        'Chốt hóa đơn ĐÃ THANH TOÁN ngay, tính vào doanh thu & xuất bill',
                                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (splitAction == 'PAY_NOW') ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: splitPayMethod == 'CASH'
                                            ? context.tc.primary.withValues(alpha: 0.14)
                                            : context.tc.card,
                                        side: BorderSide(
                                          color: splitPayMethod == 'CASH' ? context.tc.primary : context.tc.border,
                                          width: splitPayMethod == 'CASH' ? 1.6 : 1,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      onPressed: () => setDlgState(() => splitPayMethod = 'CASH'),
                                      icon: Icon(
                                        Icons.payments_outlined,
                                        size: 16,
                                        color: splitPayMethod == 'CASH' ? context.tc.primary : context.tc.textSecondary,
                                      ),
                                      label: Text(
                                        'Tiền mặt',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          fontWeight: splitPayMethod == 'CASH' ? FontWeight.w700 : FontWeight.w600,
                                          color: splitPayMethod == 'CASH' ? context.tc.primary : context.tc.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: splitPayMethod == 'TRANSFER_QR'
                                            ? context.tc.primary.withValues(alpha: 0.14)
                                            : context.tc.card,
                                        side: BorderSide(
                                          color: splitPayMethod == 'TRANSFER_QR' ? context.tc.primary : context.tc.border,
                                          width: splitPayMethod == 'TRANSFER_QR' ? 1.6 : 1,
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                      ),
                                      onPressed: () => setDlgState(() => splitPayMethod = 'TRANSFER_QR'),
                                      icon: Icon(
                                        Icons.qr_code_2_outlined,
                                        size: 16,
                                        color: splitPayMethod == 'TRANSFER_QR'
                                            ? context.tc.primary
                                            : context.tc.textSecondary,
                                      ),
                                      label: Text(
                                        'Chuyển khoản QR',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          fontWeight: splitPayMethod == 'TRANSFER_QR' ? FontWeight.w700 : FontWeight.w600,
                                          color: splitPayMethod == 'TRANSFER_QR'
                                              ? context.tc.primary
                                              : context.tc.textPrimary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (splitPayMethod == 'TRANSFER_QR' && totalSplitAmount > 0) ...[
                                const SizedBox(height: 8),
                                Center(
                                  child: VietQrImage(
                                    url: splitQrUrl,
                                    height: 190,
                                    amount: totalSplitAmount,
                                    bankInfo:
                                        '${_storeInfo?.bankId} • ${_storeInfo?.bankAccount} • ${_storeInfo?.accountName}',
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Lựa chọn 2: Chuyển sang bàn trống khác / Tạo bàn tách mới
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setDlgState(() => splitAction = 'TRANSFER'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: splitAction == 'TRANSFER' ? context.tc.primary : context.tc.border,
                            width: splitAction == 'TRANSFER' ? 1.8 : 1,
                          ),
                          color: splitAction == 'TRANSFER' ? context.tc.primary.withValues(alpha: 0.06) : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  splitAction == 'TRANSFER' ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: splitAction == 'TRANSFER' ? context.tc.primary : context.tc.textSecondary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Chuyển sang bàn khác / Tạo bàn tách mới',
                                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13),
                                      ),
                                      Text(
                                        'Giữ thành đơn độc lập trên bàn mới hoặc bàn trống khác',
                                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (splitAction == 'TRANSFER') ...[
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                initialValue: selectedTransferKey,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Chọn bàn chuyển đến',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: newSplitTableKey,
                                    child: Text(
                                      '➕ Tạo bàn tách mới: $nextSplitName (${widget.table.zone})',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                                    ),
                                  ),
                                  ...emptyTables.map(
                                    (t) => DropdownMenuItem(
                                      value: t.firebaseKey,
                                      child: Text(
                                        '🪑 ${t.name} (${t.zone} • Bàn trống)',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setDlgState(() => selectedTransferKey = val);
                                  }
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Lựa chọn 3: Ghép vào bàn đang có khách
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: inUseTables.isNotEmpty ? () => setDlgState(() => splitAction = 'MERGE') : null,
                      child: Opacity(
                        opacity: inUseTables.isNotEmpty ? 1.0 : 0.55,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: splitAction == 'MERGE' ? context.tc.primary : context.tc.border,
                              width: splitAction == 'MERGE' ? 1.8 : 1,
                            ),
                            color: splitAction == 'MERGE' ? context.tc.primary.withValues(alpha: 0.06) : null,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    splitAction == 'MERGE' ? Icons.radio_button_checked : Icons.radio_button_off,
                                    color: splitAction == 'MERGE' ? context.tc.primary : context.tc.textSecondary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Ghép vào bàn đang có khách khác',
                                          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, fontSize: 13),
                                        ),
                                        Text(
                                          inUseTables.isNotEmpty
                                              ? 'Cộng dồn các món đã chọn vào hóa đơn của bàn khác'
                                              : 'Hiện không có bàn nào khác đang có khách để ghép',
                                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (splitAction == 'MERGE' && inUseTables.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                DropdownButtonFormField<String>(
                                  initialValue: selectedMergeKey,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Chọn bàn có khách muốn ghép vào',
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  items: inUseTables
                                      .map(
                                        (t) => DropdownMenuItem(
                                          value: t.firebaseKey,
                                          child: Text(
                                            '🔗 ${t.name} (${t.zone} • ${t.currentItems.length} món • ${FormatUtils.vnd(t.currentTotal)})',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setDlgState(() => selectedMergeKey = val);
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton.icon(
                style: dialogActionStyle(background: context.tc.primary),
                icon: Icon(
                  splitAction == 'PAY_NOW'
                      ? Icons.payments_outlined
                      : (splitAction == 'MERGE' ? Icons.call_merge : Icons.swap_horiz),
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  confirmLabel,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: !canSubmit
                    ? null
                    : () async {
                        setDlgState(() => isSubmitting = true);
                        final List<OrderItemModel> splitItems = [];
                        final List<OrderItemModel> remainingItems = [];

                        for (int i = 0; i < _cart.length; i++) {
                          final sQty = splitQty[i] ?? 0;
                          final (taken, rest) = _cart[i].splitQuantity(sQty);
                          if (taken != null) splitItems.add(taken);
                          if (rest != null) remainingItems.add(rest);
                        }

                        if (splitItems.isEmpty) {
                          setDlgState(() => isSubmitting = false);
                          return;
                        }

                        final staffName = _auth.currentUser?.fullName ?? 'Thu Ngân';
                        final staffUser = _auth.currentUser?.username ?? 'staff';
                        final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

                        try {
                          if (splitAction == 'PAY_NOW') {
                            if (!await _ensureShiftOpen()) {
                              if (ctx.mounted) setDlgState(() => isSubmitting = false);
                              return;
                            }
                            String? currentShiftId = _fb.activeShiftCache?.id;
                            if (currentShiftId == null) {
                              try {
                                final shift = await _fb.getCurrentOpenShift();
                                currentShiftId = shift?.id;
                              } catch (_) {}
                            }

                            final res = await _fb.paySplitItemsNow(
                              sourceTable: widget.table,
                              splitItems: splitItems,
                              remainingItems: remainingItems,
                              paymentMethod: splitPayMethod,
                              shiftId: currentShiftId,
                              staffUid: _auth.currentUid,
                              staffUsername: staffUser,
                              staffFullName: staffName,
                              staffRole: staffRole,
                              pointEarnRate: _storeInfo?.pointEarnRate,
                              pointRedeemRate: _storeInfo?.pointRedeemRate,
                            );

                            _fireBackgroundPaymentTasks(
                              res.paidBill,
                              splitPayMethod,
                              shouldPrint: _autoPrintBill,
                            );

                            if (mounted) {
                              setState(() {
                                _cart = remainingItems;
                              });
                              _recalculateDiscounts();
                            }

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (!mounted) return;

                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '🎉 Đã thanh toán trước $totalSplitParts phần (${FormatUtils.vnd(totalSplitAmount)}) • Mã HĐ: ${res.paidBill.billCode}!${_autoPrintBill ? " (Đang in bill)" : ""}',
                                ),
                                backgroundColor: AppColors.success,
                                duration: const Duration(seconds: 3),
                              ),
                            );

                            if (remainingItems.isEmpty) {
                              if (widget.returnToParentOnPay && Navigator.of(this.context).canPop()) {
                                Navigator.of(this.context).pop(true);
                              } else {
                                this.context.go('/tables');
                              }
                            }
                            return;
                          }

                          TableModel targetTable;
                          bool mergeIntoTarget = false;
                          if (splitAction == 'TRANSFER' && selectedTransferKey == newSplitTableKey) {
                            targetTable = TableModel(
                              name: nextSplitName,
                              zone: widget.table.zone,
                              capacity: widget.table.capacity,
                              isSplitTable: true,
                            );
                          } else if (splitAction == 'TRANSFER') {
                            targetTable = emptyTables.firstWhere(
                              (t) => t.firebaseKey == selectedTransferKey,
                              orElse: () => TableModel(
                                name: nextSplitName,
                                zone: widget.table.zone,
                                capacity: widget.table.capacity,
                                isSplitTable: true,
                              ),
                            );
                          } else {
                            targetTable = inUseTables.firstWhere((t) => t.firebaseKey == selectedMergeKey);
                            mergeIntoTarget = true;
                          }

                          final planned = await _fb.splitTableItems(
                            sourceTable: widget.table,
                            splitItems: splitItems,
                            remainingItems: remainingItems,
                            targetTable: targetTable,
                            mergeIntoTarget: mergeIntoTarget,
                            staffUsername: staffUser,
                            staffName: staffName,
                            staffRole: staffRole,
                          );

                          if (mounted) {
                            setState(() {
                              _cart = remainingItems;
                            });
                            _recalculateDiscounts();
                          }

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!mounted) return;

                          final actionVerb = mergeIntoTarget ? 'tách & ghép' : 'tách & chuyển';
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Đã $actionVerb $totalSplitParts phần (${FormatUtils.vnd(totalSplitAmount)}) sang bàn ${planned.updatedTarget.name}!',
                              ),
                              backgroundColor: AppColors.success,
                            ),
                          );
                          if (remainingItems.isEmpty) {
                            this.context.go('/tables');
                          }
                        } catch (e) {
                          if (ctx.mounted) {
                            setDlgState(() => isSubmitting = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Lỗi khi tách đơn: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== MERGE TABLE DIALOG ====================
  Future<void> _showMergeTableDialog() async {
    if (!_auth.can(AppPermissions.mergeSplitTable)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền ghép bàn!'), backgroundColor: AppColors.danger),
      );
      return;
    }

    final allTables = await _fb.tablesStream().first;
    if (!mounted) return;
    final otherInUseTables = allTables.where((t) => t.inUse && t.name != widget.table.name).toList();

    if (otherInUseTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có bàn nào khác đang hoạt động để ghép!')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ghép Bàn Vào ${widget.table.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: otherInUseTables.length,
            itemBuilder: (_, i) {
              final t = otherInUseTables[i];
              return ListTile(
                leading: Icon(Icons.table_restaurant, color: context.tc.primary),
                title: Text(t.name),
                subtitle: Text('${t.zone} • ${t.currentItems.length} món'),
                onTap: () async {
                  await _fb.mergeTables(t, widget.table);
                  final refreshed = await _fb.tablesStream().first;
                  final currentT = refreshed.where((x) => x.name == widget.table.name).firstOrNull;
                  if (currentT != null && mounted) {
                    setState(() {
                      _cart = List.from(currentT.currentItems);
                    });
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
        ],
      ),
    );
  }

  /// Tra lại số dư điểm dùng chung của khách đã gắn với bàn. Lỗi → giữ tên/SĐT, điểm "chưa biết".
  Future<void> _refreshCustomerPoints() async {
    final c = _selectedCustomer;
    if (c == null) return;
    final store = _fb.currentStoreCode;
    var m = await LoyaltyService().lookupMember(storeCode: store, customerId: c.id);
    if (!m.found && c.phone.isNotEmpty) m = await LoyaltyService().lookupMember(storeCode: store, phone: c.phone);
    if (!mounted || !identical(_selectedCustomer, c)) return;
    final ok = TableCustomerLogic.applyMember(c, found: m.found, points: m.points, totalPoints: m.totalPoints);
    setState(() => _customerPointsUnknown = !ok);
  }

  /// Chọn/bỏ khách: cập nhật màn hình và LƯU NGAY vào bàn (thoát vào lại không mất).
  Future<void> _setCustomer(KmtCustomerModel? c) async {
    setState(() {
      _selectedCustomer = c;
      _customerPointsUnknown = false;
      _pointsUsed = 0;
    });
    await _ensureCustomerBirthday();
    if (!mounted) return;
    _recalculateDiscounts();
    _autoApplyBirthdayCampaigns();
    TableCustomerLogic.writeToTable(widget.table, c);
    try {
      await _fb.saveTable(widget.table);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không lưu được khách vào bàn: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ==================== KIOTVIET CRM CUSTOMER DIALOGS ====================
  Future<void> _showCustomerLookupDialog() async {
    final tiers = _storeInfo?.loyaltyTiers ?? LoyaltyTier.defaults;
    final store = _fb.currentStoreCode;
    final picked = await showModalBottomSheet<KmtCustomerModel>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CustomerPickerSheet(
        tiers: tiers,
        showFullPhone: _auth.can(AppPermissions.viewCustomers) || _auth.can(AppPermissions.manageCustomers),
        loadCandidates: _fb.getBranchCandidates,
        lookupByPhone: (phone) async {
          final c = await _fb.lookupCustomer(phone);
          final m = await LoyaltyService().lookupMember(storeCode: store, phone: phone);
          if (c == null && !m.found) return null;
          return CustomerCandidate(
            id: c?.id ?? '',
            name: c?.fullName ?? m.name,
            phone: c?.phone ?? m.phone,
            points: m.found ? m.points : (c?.currentPoints ?? 0),
            totalPoints: m.found ? m.totalPoints : (c?.totalPoints ?? 0),
            gender: c?.gender ?? 'Khác',
            birthday: c?.birthday ?? '',
          );
        },
        createCustomer: (name, phone, {gender = 'Khác', birthday = ''}) async {
          final c = KmtCustomerModel(
            id: 'CUST_${DateTime.now().millisecondsSinceEpoch}',
            fullName: name,
            phone: phone,
            gender: gender,
            birthday: birthday,
            currentPoints: 0,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
          await _fb.saveCustomer(c); // 0 điểm; nếu SĐT đã có điểm chung, máy chủ gắn vào bản ghi đó
          return c;
        },
        updateCustomer: (updated) async {
          await _fb.saveCustomer(updated);
          if (_selectedCustomer?.id == updated.id) {
            setState(() => _selectedCustomer = updated);
            TableCustomerLogic.writeToTable(widget.table, updated);
            await _fb.saveTable(widget.table);
            _recalculateDiscounts();
            _autoApplyEligibleCampaigns();
          }
        },
      ),
    );
    if (picked == null || !mounted) return;
    if (picked.id.isEmpty) {
      // Khách chỉ có ở chi nhánh khác: tạo hồ sơ tại chi nhánh này (điểm lấy từ bản ghi dùng chung)
      final c = KmtCustomerModel(
        id: 'CUST_${DateTime.now().millisecondsSinceEpoch}',
        fullName: picked.fullName,
        phone: picked.phone,
        gender: picked.gender,
        birthday: picked.birthday,
        currentPoints: 0,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await _fb.saveCustomer(c);
      await _setCustomer(KmtCustomerModel(
        id: c.id,
        fullName: c.fullName,
        phone: c.phone,
        gender: c.gender,
        birthday: c.birthday,
        currentPoints: picked.currentPoints,
        totalPoints: picked.totalPoints,
        createdAt: c.createdAt,
      ));
      return;
    }
    // Điểm DÙNG CHUNG toàn chuỗi (gồm điểm tích ở chi nhánh khác) lấy từ máy chủ
    var m = await LoyaltyService().lookupMember(storeCode: store, customerId: picked.id);
    if (!m.found && picked.phone.isNotEmpty) m = await LoyaltyService().lookupMember(storeCode: store, phone: picked.phone);
    if (m.found) {
      picked.currentPoints = m.points;
      if (m.totalPoints > picked.totalPoints) picked.totalPoints = m.totalPoints;
    }
    if (!mounted) return;
    await _setCustomer(picked);
  }

  static DateTime? _parseBirthday(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(t)) {
      return DateTime.tryParse(t);
    }
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(t)) {
      final parts = t.split('/');
      final day = int.tryParse(parts[0]);
      final month = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day);
      }
    }
    return DateTime.tryParse(t);
  }

  Future<void> _showEditCustomerDialog(KmtCustomerModel customer) async {
    final nameCtrl = TextEditingController(text: customer.fullName);
    final phoneCtrl = TextEditingController(text: customer.phone);
    String gender = ['Nam', 'Nữ', 'Khác'].contains(customer.gender) ? customer.gender : 'Khác';
    DateTime? birthday = _parseBirthday(customer.birthday);
    final bdayCtrl = TextEditingController(
      text: birthday != null ? DateFormat('dd/MM/yyyy').format(birthday) : '',
    );
    String? formError;
    bool isSaving = false;

    final tiers = _storeInfo?.loyaltyTiers ?? LoyaltyTier.defaults;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_outlined, color: context.tc.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chỉnh Sửa Khách Hàng',
                  style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (formError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formError!,
                              style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: context.tc.cardElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.tc.borderLight),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mã: ${customer.code.isNotEmpty ? customer.code : customer.id}',
                            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.textSecondary)),
                        Text('${customer.currentPoints} pt (${customer.tierName(tiers)})',
                            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.ink(Colors.blue.shade800))),
                      ],
                    ),
                  ),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên *',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (formError != null) setDialogState(() => formError = null);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Số điện thoại *',
                      prefixIcon: Icon(Icons.phone_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) {
                      if (formError != null) setDialogState(() => formError = null);
                    },
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Giới tính',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'Nam', label: Text('Nam'), icon: Icon(Icons.male, size: 16)),
                        ButtonSegment(value: 'Nữ', label: Text('Nữ'), icon: Icon(Icons.female, size: 16)),
                        ButtonSegment(value: 'Khác', label: Text('Khác'), icon: Icon(Icons.person_outline, size: 16)),
                      ],
                      selected: {gender},
                      onSelectionChanged: (set) => setDialogState(() => gender = set.first),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: bdayCtrl,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ngày sinh',
                      hintText: 'Chọn ngày sinh (dd/MM/yyyy)',
                      prefixIcon: const Icon(Icons.cake_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: birthday != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                setDialogState(() {
                                  birthday = null;
                                  bdayCtrl.clear();
                                });
                              },
                            )
                          : const Icon(Icons.calendar_today, size: 18),
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final initial = birthday ?? DateTime(2000, 1, 1);
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: initial.isAfter(now) ? now : initial,
                        firstDate: DateTime(1920),
                        lastDate: now,
                        helpText: 'CHỌN NGÀY SINH KHÁCH HÀNG',
                      );
                      if (picked != null) {
                        setDialogState(() {
                          birthday = picked;
                          bdayCtrl.text = DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary),
              onPressed: isSaving
                  ? null
                  : () {
                      final name = nameCtrl.text.trim().toUpperCase();
                      final phone = phoneCtrl.text.trim();
                      final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');

                      if (name.isEmpty) {
                        setDialogState(() => formError = 'Vui lòng nhập họ và tên khách hàng');
                        return;
                      }
                      if (digits.length < 9) {
                        setDialogState(() => formError = 'Số điện thoại phải có ít nhất 9 chữ số');
                        return;
                      }
                      setDialogState(() => isSaving = true);
                      Navigator.pop(ctx, true);
                    },
              child: const Text('Lưu thay đổi'),
            ),
          ],
        ),
      ),
    );

    if (ok != true || !mounted) return;
    final name = nameCtrl.text.trim().toUpperCase();
    final phone = phoneCtrl.text.trim();
    final bdayStr = birthday != null ? DateFormat('yyyy-MM-dd').format(birthday!) : '';

    final updated = customer.copyWith(
      name: name,
      phone: phone,
      gender: gender,
      birthday: bdayStr,
    );

    try {
      await _fb.saveCustomer(updated);
      if (!mounted) return;
      setState(() => _selectedCustomer = updated);
      TableCustomerLogic.writeToTable(widget.table, updated);
      await _fb.saveTable(widget.table);
      if (!mounted) return;
      _recalculateDiscounts();
      _autoApplyEligibleCampaigns();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã cập nhật thông tin khách hàng "${updated.fullName}"')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi cập nhật khách hàng: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  // ==================== ITEM DISCOUNT & MANAGER APPROVAL ====================
  /// Trả về (được phép, lần duyệt). Nhân viên có quyền DISCOUNT_ITEM → (true, null).
  /// Không có quyền → nhờ Quản lý duyệt bằng PIN, xác minh PHÍA MÁY CHỦ (verifyManagerPin).
  Future<(bool, ManagerApproval?)> _requestManagerDiscountApproval(OrderItemModel item) async {
    if (_auth.can(AppPermissions.discountItem)) return (true, null);
    final approval = await showManagerApprovalDialog(
      context,
      action: ManagerApprovalAction.discountItem,
      contextText: 'Giảm giá "${item.name}" tại ${widget.table.name}',
    );
    return (approval != null, approval);
  }

  Future<void> _showItemDiscountDialog(int index) async {
    final (approved, approval) = await _requestManagerDiscountApproval(_cart[index]);
    if (!approved || !mounted) return;

    final item = _cart[index];
    final lineGross = item.lineGross;
    // Giảm giá áp cho TỪNG PHẦN được chọn: % hoặc số tiền mỗi phần × số phần được giảm.
    String discountMode = item.discountPercent > 0 ? 'PERCENT' : 'AMOUNT';
    // Mặc định giảm tất cả các phần; dòng đã có giảm giá → giữ số phần đã chọn.
    int discountedQty = item.hasDiscount && item.discountedQuantity > 0 ? item.discountedQuantity : item.quantity;
    final valCtrl = TextEditingController(
      text: item.discountPercent > 0
          ? '${item.discountPercent}'
          : item.discountUnitAmount > 0
              ? '${item.discountUnitAmount}'
              // Dữ liệu cũ (số tiền cố định cả dòng): quy đổi gần đúng ra đ/phần
              : (item.discountMode == 'FIXED' && item.quantity > 0
                  ? '${(item.lineDiscountTotal / item.quantity).round()}'
                  : '10'),
    );
    final reasonCtrl = TextEditingController(text: item.discountReason);

    final reasonPresets = [
      'Khách quen / VIP',
      'Nhân viên quán',
      'Món ra chậm',
      'Món lỗi / Đổi món',
      'Chủ quán duyệt',
      'Khuyến mại riêng',
    ];

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final inputNum = int.tryParse(valCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final calcDiscount = OrderItemModel.computeLineDiscount(
            unitPrice: item.unitPrice,
            quantity: item.quantity,
            discountedQuantity: discountedQty,
            percent: discountMode == 'PERCENT' ? inputNum.clamp(0, 100) : 0,
            unitAmount: discountMode == 'AMOUNT' ? inputNum : 0,
          );
          final calcAfter = lineGross - calcDiscount;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: context.bg(Colors.orange.shade100), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.local_offer, color: context.ink(Colors.orange.shade900), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Giảm Giá Món', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(item.name, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: context.tc.cardElevated, borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tiền gốc (${item.quantity} phần):', style: GoogleFonts.beVietnamPro(fontSize: 12)),
                        Text(FormatUtils.vnd(lineGross), style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Mode Selector: % vs VND
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Giảm theo %')),
                          selected: discountMode == 'PERCENT',
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                discountMode = 'PERCENT';
                                if (valCtrl.text.isEmpty || (int.tryParse(valCtrl.text) ?? 0) > 100) {
                                  valCtrl.text = '10';
                                }
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('Giảm số tiền (đ)')),
                          selected: discountMode == 'AMOUNT',
                          onSelected: (sel) {
                            if (sel) {
                              setDlgState(() {
                                discountMode = 'AMOUNT';
                                if (valCtrl.text.isEmpty) valCtrl.text = '5000';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: discountMode == 'PERCENT' ? 'Tỷ lệ giảm mỗi phần (%)' : 'Số tiền giảm mỗi phần (VND)',
                      suffixText: discountMode == 'PERCENT' ? '%' : 'đ',
                    ),
                    onChanged: (_) => setDlgState(() {}),
                  ),
                  const SizedBox(height: 8),
                  // Quick Preset Chips
                  Wrap(
                    spacing: 6,
                    children: discountMode == 'PERCENT'
                        ? [5, 10, 15, 20, 50, 100].map((p) => ActionChip(
                            label: Text('$p%'),
                            onPressed: () {
                              valCtrl.text = '$p';
                              setDlgState(() {});
                            },
                          )).toList()
                        : [5000, 10000, 20000, 50000].map((a) => ActionChip(
                            label: Text(FormatUtils.vnd(a)),
                            onPressed: () {
                              valCtrl.text = '$a';
                              setDlgState(() {});
                            },
                          )).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Chọn số phần được giảm (VD: 5 ly, chỉ giảm 2 ly)
                  Row(
                    children: [
                      Expanded(
                        child: Text('Số phần được giảm:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                      IconButton(
                        tooltip: 'Bớt 1 phần',
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: discountedQty > 1 ? () => setDlgState(() => discountedQty -= 1) : null,
                      ),
                      Text('$discountedQty / ${item.quantity}', style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold)),
                      IconButton(
                        tooltip: 'Thêm 1 phần',
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: discountedQty < item.quantity ? () => setDlgState(() => discountedQty += 1) : null,
                      ),
                    ],
                  ),
                  if (item.quantity > 1)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: discountedQty == item.quantity ? null : () => setDlgState(() => discountedQty = item.quantity),
                        child: const Text('Giảm tất cả các phần'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text('Lý do giảm giá:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: reasonPresets.map((r) => ChoiceChip(
                      label: Text(r, style: const TextStyle(fontSize: 11)),
                      selected: reasonCtrl.text == r,
                      onSelected: (sel) {
                        reasonCtrl.text = sel ? r : '';
                        setDlgState(() {});
                      },
                    )).toList(),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nhập lý do chi tiết (nếu có)...',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Calculation Preview
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: context.bg(Colors.orange.shade50), borderRadius: BorderRadius.circular(10), border: Border.all(color: context.line(Colors.orange.shade200))),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                'Số tiền giảm (${discountMode == 'PERCENT' ? '${inputNum.clamp(0, 100)}%' : FormatUtils.vnd(inputNum)} × $discountedQty/${item.quantity} món):',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.ink(Colors.orange.shade900)),
                              ),
                            ),
                            Text('-${FormatUtils.vnd(calcDiscount)}', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: context.ink(Colors.red.shade700))),
                          ],
                        ),
                        const Divider(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Thành tiền sau giảm:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(FormatUtils.vnd(calcAfter), style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: context.ink(Colors.green.shade800))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (item.hasDiscount)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _cart[index] = _cart[index].withoutLineDiscount();
                      _recalculateDiscounts();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Xóa Giảm Giá', style: TextStyle(color: context.ink(Colors.red.shade700))),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () {
                  final input = int.tryParse(valCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  // Lần duyệt PIN chỉ có hiệu lực 5 phút (máy chủ cấp)
                  if (approval != null && !approval.isValidFor(ManagerApprovalAction.discountItem)) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Lần duyệt PIN đã hết hạn. Vui lòng nhờ Quản lý duyệt lại.'), backgroundColor: AppColors.danger),
                    );
                    return;
                  }
                  setState(() {
                    _cart[index] = _cart[index].withLineDiscount(
                      percent: discountMode == 'PERCENT' ? input.clamp(0, 100) : 0,
                      unitAmount: discountMode == 'AMOUNT' ? input : 0,
                      discountedQuantity: discountedQty,
                      reason: reasonCtrl.text.trim(),
                      approvedBy: approval?.approverUid ?? '',
                      approvedByName: approval?.approverName ?? '',
                      approvalId: approval?.approvalId ?? '',
                      approvedAt: approval?.approvedAt,
                    );
                    _recalculateDiscounts();
                  });
                  Navigator.pop(ctx);
                  final applied = _cart[index];
                  if (approval != null && applied.hasDiscount) {
                    _fb.logAction(AuditLogModel(
                      timestamp: DateTime.now().millisecondsSinceEpoch,
                      username: _auth.currentUser?.username ?? '',
                      userFullName: _auth.currentUser?.fullName ?? 'Nhân viên',
                      userRole: _auth.currentUser?.roleId ?? 'UNKNOWN',
                      action: 'DISCOUNT_ITEM',
                      targetType: 'TABLE',
                      targetId: widget.table.name,
                      details: 'Giảm giá "${applied.name}" tại ${widget.table.name}: '
                          '${applied.discountDescription(FormatUtils.vnd)} (-${FormatUtils.vnd(applied.lineDiscountTotal)})'
                          '${ManagerPinLogic.approvalSuffix(approval)}',
                      afterState: {
                        'approvedBy': approval.approverUid,
                        'approvedByName': approval.approverName,
                        'approvalId': approval.approvalId,
                      },
                    ));
                  }
                },
                child: const Text('Áp Dụng'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== EDIT ITEM NOTE & TOPPING DIALOG ====================
  Future<void> _showEditItemNoteAndToppingDialog(int index, {List<int>? syncIndices}) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];

    // Find original product if possible
    ProductModel? originalProduct;
    for (final p in _products) {
      if (p.id == item.productId ||
          (p.code.isNotEmpty && p.code.toLowerCase() == item.name.toLowerCase()) ||
          p.name.toLowerCase() == item.name.toLowerCase()) {
        originalProduct = p;
        break;
      }
    }

    final hasSizes = (originalProduct != null && originalProduct.sizes.isNotEmpty);
    String selectedSize = item.selectedSize.isNotEmpty
        ? item.selectedSize
        : (hasSizes ? (originalProduct.sizes.containsKey('M') ? 'M' : originalProduct.sizes.keys.first) : '');
    int sizeExtra = hasSizes ? (originalProduct.sizes[selectedSize] ?? item.sizeExtraPrice) : item.sizeExtraPrice;

    String selectedSugar = item.selectedSugar.isNotEmpty ? item.selectedSugar : '100% đường';
    String selectedIce = item.selectedIce.isNotEmpty ? item.selectedIce : '100% đá';
    final List<String> selectedToppings = List.from(item.selectedToppings);
    final noteCtrl = TextEditingController(text: item.note);

    // Resolve category and toppings
    CategoryModel? matchedCategory;
    if (originalProduct != null) {
      for (final c in _categories) {
        if (c.name.trim().toLowerCase() == originalProduct.category.trim().toLowerCase()) {
          matchedCategory = c;
          break;
        }
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

    final resolved = resolveItemOptions(
      productNoteGroupIds: originalProduct?.noteGroupIds,
      productToppingGroupIds: originalProduct?.toppingGroupIds,
      categoryNoteGroupIds: matchedCategory?.noteGroupIds,
      categoryToppingGroupIds: matchedCategory?.toppingGroupIds,
      catalog: _catalog,
    );
    final catalogMode = !resolved.legacy; // đã cấu hình danh mục: chỉ hiện nhóm được gắn
    final Map<String, ProductModel?> toppingItemMap = {};
    final List<String> availableToppingNames = [];
    final List<String> catalogExtras = []; // topping đã chọn trước đó nhưng không còn trong danh mục

    if (catalogMode) {
      resolved.toppingPrices.forEach((n, p) {
        toppingItemMap[n] = ProductModel(name: n, price: p, unit: 'phần', category: 'Topping', isTopping: true);
        availableToppingNames.add(n);
      });
      final inCatalogSum = item.selectedToppings.where(toppingItemMap.containsKey).fold<int>(0, (a, n) => a + (toppingItemMap[n]?.price ?? 0));
      catalogExtras.addAll(item.selectedToppings.where((n) => !toppingItemMap.containsKey(n)));
      final extraTotal = item.toppingPrice - inCatalogSum;
      final extraEach = catalogExtras.isEmpty || extraTotal <= 0 ? 0 : extraTotal ~/ catalogExtras.length;
      for (final n in catalogExtras) {
        toppingItemMap[n] = ProductModel(name: n, price: extraEach, unit: 'phần', category: 'Topping');
      }
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
        if (!availableToppingNames.contains(match.name)) availableToppingNames.add(match.name);
      }
    } else if (originalProduct != null && originalProduct.allowedToppings.isNotEmpty) {
      for (final topName in originalProduct.allowedToppings) {
        final match = _products.firstWhere(
          (p) => p.name.toLowerCase() == topName.toLowerCase(),
          orElse: () => defaultFnbToppings.firstWhere(
            (p) => p.name.toLowerCase() == topName.toLowerCase(),
            orElse: () => ProductModel(name: topName, price: 5000, unit: 'phần', category: 'Topping', isTopping: true),
          ),
        );
        toppingItemMap[match.name] = match;
        if (!availableToppingNames.contains(match.name)) availableToppingNames.add(match.name);
      }
    } else {
      for (final p in _products) {
        if (p.isTopping || p.category.toLowerCase().contains('topping')) {
          toppingItemMap[p.name] = p;
          if (!availableToppingNames.contains(p.name)) availableToppingNames.add(p.name);
        }
      }
      for (final top in defaultFnbToppings) {
        if (!availableToppingNames.contains(top.name)) {
          toppingItemMap[top.name] = top;
          availableToppingNames.add(top.name);
        }
      }
    }

    // Ensure previously selected toppings in item are preserved in mapping
    for (final top in (catalogMode ? const <String>[] : item.selectedToppings)) {
      if (!availableToppingNames.contains(top)) {
        availableToppingNames.insert(0, top);
        toppingItemMap[top] = ProductModel(name: top, price: 5000, unit: 'phần', category: 'Topping');
      }
    }

    final isDrinkOrTea = (originalProduct != null && (
        originalProduct.category.toLowerCase().contains('trà') ||
        originalProduct.category.toLowerCase().contains('tea') ||
        originalProduct.category.toLowerCase().contains('cà phê') ||
        originalProduct.category.toLowerCase().contains('cafe') ||
        originalProduct.category.toLowerCase().contains('coffee') ||
        originalProduct.category.toLowerCase().contains('nước') ||
        originalProduct.category.toLowerCase().contains('uống') ||
        originalProduct.category.toLowerCase().contains('sinh tố') ||
        originalProduct.category.toLowerCase().contains('đá xay') ||
        originalProduct.category.toLowerCase().contains('sữa') ||
        originalProduct.category.toLowerCase().contains('matcha') ||
        originalProduct.hasIceSugarOptions ||
        originalProduct.sizes.isNotEmpty)) ||
        item.selectedSugar.isNotEmpty ||
        item.selectedIce.isNotEmpty ||
        item.selectedToppings.isNotEmpty;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int calcToppingPrice = 0;
          for (final topName in selectedToppings) {
            calcToppingPrice += toppingItemMap[topName]?.price ?? (catalogMode ? 0 : 5000);
          }
          final int unitPrice = item.price + sizeExtra + calcToppingPrice;
          final int totalPrice = unitPrice * item.quantity;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.88,
              ),
              decoration: BoxDecoration(
                color: context.tc.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. PINNED HEADER (Drag handle, Name, Price, Close)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(color: context.tc.border, borderRadius: BorderRadius.circular(2)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Chỉnh sửa: ${item.name}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Đơn giá gốc: ${FormatUtils.vnd(item.price)} • Số lượng: x${item.quantity}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              FormatUtils.vnd(unitPrice),
                              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: context.tc.primary),
                            ),
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
                        const Divider(height: 20),
                      ],
                    ),
                  ),

                  // 2. SCROLLABLE OPTIONS BODY
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                  // 1. SIZE SELECTION (if original product has sizes)
                  if (hasSizes) ...[
                    Text('Chọn kích cỡ (Size):', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: originalProduct!.sizes.entries.map((entry) {
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
                  if (isDrinkOrTea) ...[
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
                  if (catalogMode && (resolved.toppingGroups.isNotEmpty || catalogExtras.any(selectedToppings.contains))) ...[
                    ToppingGroupsSection(
                      groups: resolved.toppingGroups,
                      selected: selectedToppings,
                      extras: catalogExtras,
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
                  if (!catalogMode && availableToppingNames.isNotEmpty) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Topping thêm:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                        if (selectedToppings.isNotEmpty)
                          TextButton(
                            onPressed: () => setModalState(() => selectedToppings.clear()),
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                            child: Text('Bỏ chọn hết', style: TextStyle(fontSize: 11, color: context.tc.danger)),
                          ),
                      ],
                    ),
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

                  // 4. NOTE & NOTE PRESETS
                  Text('Ghi chú món:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    decoration: InputDecoration(
                      labelText: 'Ghi chú cho bếp / pha chế',
                      hintText: 'VD: ít ngọt, pha đậm vị, mang về...',
                      prefixIcon: Icon(Icons.edit_note, color: context.tc.primary),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: noteCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setModalState(() => noteCtrl.clear()),
                            )
                          : null,
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final presets = catalogMode
                        ? resolved.noteChips
                        : (_backendNotePresets.isNotEmpty
                            ? _backendNotePresets
                            : const ['Ít ngọt', 'Nhiều đá', 'Không đá', 'Ít đá', 'Để riêng đá', 'Mang về', 'Ít đường', 'Uống nóng']);
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
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),

                  // 3. PINNED BOTTOM ACTION BAR
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    decoration: BoxDecoration(
                      color: context.tc.card,
                      border: Border(top: BorderSide(color: context.tc.borderLight)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 8,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      top: false,
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.tc.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            setState(() {
                              final targetIndices = (syncIndices != null && syncIndices.isNotEmpty) ? syncIndices : [index];
                              for (final idx in targetIndices) {
                                if (idx < _cart.length) {
                                  _cart[idx] = _cart[idx].copyWith(
                                    note: noteCtrl.text.trim(),
                                    selectedToppings: selectedToppings,
                                    toppingPrice: calcToppingPrice,
                                    selectedSize: selectedSize,
                                    sizeExtraPrice: sizeExtra,
                                    selectedSugar: isDrinkOrTea ? selectedSugar : '',
                                    selectedIce: isDrinkOrTea ? selectedIce : '',
                                  );
                                }
                              }
                            });

                            widget.table.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
                            await _fb.saveTable(widget.table).catchError((_) {});
                            _recalculateDiscounts();

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã cập nhật ghi chú & tùy chọn món thành công! ✨'),
                                  backgroundColor: AppColors.success,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                          child: Text(
                            'Lưu thay đổi • ${FormatUtils.vnd(totalPrice)}',
                            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showUsePointsDialog() async {
    if (_selectedCustomer == null) return;
    if (!_auth.can(AppPermissions.redeemPoints)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền đổi điểm tích lũy (REDEEM_POINTS).'), backgroundColor: AppColors.danger),
      );
      return;
    }
    // Điểm DÙNG CHUNG toàn chuỗi: số dư thật nằm ở máy chủ (gộp mọi chi nhánh); không tra được → dùng bản sao tại chi nhánh
    final member = await LoyaltyService().lookupMember(storeCode: _fb.currentStoreCode, customerId: _selectedCustomer!.id);
    if (!mounted) return;
    final totalAvailable = member.found ? member.points : _selectedCustomer!.currentPoints;
    if (totalAvailable <= 0) return;
    final availableAmount = _subTotal - _itemDiscountTotal - _voucherDiscountTotal;
    final maxPointsPossible = availableAmount > 0 ? (availableAmount ~/ _pointRedeemRate) : 0;
    final maxUsable = totalAvailable < maxPointsPossible ? totalAvailable : maxPointsPossible;

    final pointsCtrl = TextEditingController(text: '$_pointsUsed');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dùng Điểm Tích Lũy', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách: ${_selectedCustomer!.fullName} (Có: $totalAvailable điểm dùng chung toàn chuỗi)', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Quy đổi: 1 điểm = ${FormatUtils.vnd(_pointRedeemRate)} trừ vào hóa đơn', style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: pointsCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Số điểm muốn dùng (Tối đa: $maxUsable)',
                suffixText: 'điểm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _pointsUsed = 0);
              Navigator.pop(ctx);
            },
            child: const Text('Không dùng điểm'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(pointsCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              if (val > maxUsable) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Chỉ được dùng tối đa $maxUsable điểm cho đơn này!')),
                );
                return;
              }
              setState(() => _pointsUsed = val);
              Navigator.pop(ctx);
            },
            child: const Text('Xác Nhận Dùng Điểm'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptStaffNote(BuildContext context) async {
    final noteController = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (noteCtx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit_note, color: context.tc.primary),
            const SizedBox(width: 8),
            const Text('Ghi chú áp dụng voucher'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chương trình này bắt buộc nhân viên nhập lý do / ghi chú trước khi áp dụng:'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              autofocus: true,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Lý do / Ghi chú của nhân viên *',
                hintText: 'VD: Khách thân thiết, voucher bù món hỏng...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(noteCtx, null),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.tc.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final t = noteController.text.trim();
              if (t.isEmpty) {
                ScaffoldMessenger.of(noteCtx).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập lý do ghi chú!')),
                );
                return;
              }
              Navigator.pop(noteCtx, t);
            },
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  // ==================== PROMOTIONS & DISCOUNT DIALOG ====================
  Future<void> _showDiscountDialog() async {
    // Tải lại CTKM mỗi lần mở để thấy ngay chương trình vừa tạo / sửa trên Web
    await _loadStoreAndPromotions();
    if (!mounted) return;
    final voucherCtrl = TextEditingController();
    final manualValueCtrl = TextEditingController();
    String manualType = 'PERCENT';
    VoucherCheckResult? voucherResult;
    // Chọn CTKM / nhập giảm giá chỉ có hiệu lực khi bấm "Xác nhận"; đóng hộp thoại bằng cách khác → hoàn lại
    final originalDiscounts = List<BillDiscountModel>.from(_appliedDiscounts);
    bool confirmed = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final allowStack = _storeInfo?.allowStackPromotions ?? true;
          final nowMs = DateTime.now().millisecondsSinceEpoch;

          return AlertDialog(
            title: Text('Áp Dụng Khuyến Mãi / Voucher', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Voucher Input
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: voucherCtrl,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'Nhập mã Voucher',
                              prefixIcon: Icon(Icons.confirmation_number_outlined),
                              hintText: 'VD: CHAOBAN20',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
                          onPressed: () async {
                            final code = normalizeVoucherCode(voucherCtrl.text);
                            if (code.isEmpty) return;

                            // 1. Khuyến mãi cũ (PromotionModel) có mã
                            final promo = _allPromotions.where((p) => p.code.toUpperCase() == code && p.isActive).firstOrNull;
                            if (promo != null) {
                              if (!promo.isValid(_subTotal)) {
                                setDlgState(() => voucherResult = VoucherCheckResult(VoucherCheckStatus.notApplicable,
                                    'Mã hợp lệ nhưng đơn chưa đạt điều kiện tối thiểu ${FormatUtils.vnd(promo.minBillAmount)}'));
                                return;
                              }
                              String? staffNote;
                              if (promo.requireStaffNote) {
                                if (!context.mounted) return;
                                staffNote = await _promptStaffNote(context);
                                if (staffNote == null || staffNote.trim().isEmpty) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Bắt buộc phải nhập ghi chú nhân viên để áp dụng mã này!')),
                                    );
                                  }
                                  return;
                                }
                              }
                              final amt = promo.calculateDiscount(_subTotal, _cart);
                              setDlgState(() {
                                if (!allowStack) _appliedDiscounts.clear();
                                _appliedDiscounts.removeWhere((d) => d.promoCode == code || d.promoId == promo.id);
                                _appliedDiscounts.add(BillDiscountModel(
                                  promoId: promo.id,
                                  promoCode: code,
                                  description: promo.name,
                                  amount: amt,
                                  staffNote: staffNote,
                                ));
                                voucherResult = VoucherCheckResult(VoucherCheckStatus.valid, 'Mã hợp lệ - ${promo.name}', discount: amt);
                              });
                              voucherCtrl.clear();
                              return;
                            }

                            if (_appliedDiscounts.any((d) => d.voucherCode == code || d.promoCode == code)) {
                              setDlgState(() => voucherResult =
                                  const VoucherCheckResult(VoucherCheckStatus.notApplicable, 'Mã này đã được áp dụng cho đơn hiện tại'));
                              return;
                            }

                            // 2. Mã voucher của Chương trình khuyến mãi (vouchers/{campaignId}/{voucherId})
                            VoucherModel? voucher;
                            CampaignModel? campaign;
                            try {
                              voucher = await CampaignService().lookupVoucherByCode(code).timeout(const Duration(seconds: 6));
                              if (voucher != null) {
                                campaign = await CampaignService().getCampaign(voucher.campaignId).timeout(const Duration(seconds: 6)) ??
                                    _campaignById[voucher.campaignId];
                              }
                            } catch (e) {
                              debugPrint('Error looking up voucher: $e');
                              setDlgState(() => voucherResult = const VoucherCheckResult(
                                  VoucherCheckStatus.notFound, 'Không kiểm tra được mã (mất kết nối?). Vui lòng thử lại.'));
                              return;
                            }
                            if (campaign != null) _campaignById[campaign.campaignId] = campaign;

                            // 2b. Nếu không tìm thấy mã voucher cá thể, kiểm tra xem có khớp với mã chương trình (programCode) không
                            if (campaign == null) {
                              final cleanCode = code.replaceAll(RegExp(r'[^A-Z0-9]'), '');
                              campaign = _campaigns.where((c) {
                                if (c.programCode.toUpperCase() == code) return true;
                                final cleanProg = c.programCode.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
                                return cleanProg.isNotEmpty && cleanProg == cleanCode;
                              }).firstOrNull;
                            }
                            if (campaign != null) _campaignById[campaign.campaignId] = campaign;

                            final result = evaluateVoucher(
                              code: code,
                              voucher: voucher,
                              campaign: campaign,
                              nowMs: DateTime.now().millisecondsSinceEpoch,
                              branchId: _fb.currentStoreCode,
                              quote: campaign != null ? _quoteCampaign(campaign) : null,
                            );
                            var currentResult = result;
                            if ((!currentResult.isValid || currentResult.discount <= 0) && campaign != null) {
                              final combo = CartCampaignPricing.getComboInfo(campaign, cart: _cart, products: _products);
                              if (combo != null && combo.buyUnits > 0 && combo.remainingRewardUnits > 0) {
                                final added = await _pickComboRewardItems(campaign);
                                if (added) {
                                  final newQuote = _quoteCampaign(campaign);
                                  currentResult = evaluateVoucher(
                                    code: code,
                                    voucher: voucher,
                                    campaign: campaign,
                                    nowMs: DateTime.now().millisecondsSinceEpoch,
                                    branchId: _fb.currentStoreCode,
                                    quote: newQuote,
                                  );
                                }
                              }
                            }
                            setDlgState(() => voucherResult = currentResult);
                            if (!currentResult.isValid || campaign == null || currentResult.discount <= 0) return;

                            // Bắt buộc nhân viên nhập ghi chú nếu requireStaffNote = true
                            String? staffNote;
                            if (campaign.requireStaffNote) {
                              if (!context.mounted) return;
                              staffNote = await _promptStaffNote(context);
                              if (staffNote == null || staffNote.trim().isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Bắt buộc phải nhập ghi chú nhân viên để áp dụng mã này!')),
                                  );
                                }
                                return;
                              }
                            }

                            final applied = campaign;
                            final stackCheck = CartCampaignPricing.checkStacking(
                              currentDiscounts: _appliedDiscounts,
                              incoming: applied,
                              campaignsById: _campaignById,
                              allowStackPromotions: allowStack,
                            );
                            if (!stackCheck.canStack) {
                              if (stackCheck.conflictingExclusiveCampaign != null) {
                                if (!context.mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Xung Đột Khuyến Mãi'),
                                    content: Text(
                                      'Đơn hàng đang áp dụng "${stackCheck.conflictingExclusiveCampaign!.name}" (áp dụng độc quyền, không cộng dồn).\n\n'
                                      'Bạn có muốn gỡ "${stackCheck.conflictingExclusiveCampaign!.name}" để áp dụng mã "${applied.name}" không?'
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Đổi sang mã mới', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                _appliedDiscounts.removeWhere((d) => d.campaignId == stackCheck.conflictingExclusiveCampaign!.campaignId);
                              } else if (stackCheck.requiresClearingExisting && _appliedDiscounts.isNotEmpty) {
                                if (!context.mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Áp Dụng Độc Quyền'),
                                    content: Text(
                                      'Chương trình "${applied.name}" áp dụng độc quyền (không cho phép cộng dồn với CTKM khác).\n\n'
                                      'Áp dụng mã này sẽ gỡ các khuyến mãi hiện có trên đơn:\n'
                                      '${_appliedDiscounts.map((d) => "• ${d.description}").join("\n")}\n\n'
                                      'Bạn có muốn tiếp tục?'
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Đồng ý gỡ & áp dụng', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                _appliedDiscounts.clear();
                              } else if (stackCheck.reason != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stackCheck.reason!), backgroundColor: AppColors.danger));
                                }
                                return;
                              }
                            }

                            final quote = _quoteCampaign(applied);
                            final comboCnt = quote.rewardBenefits
                                .where((b) => b.campaignId == applied.campaignId)
                                .fold<int>(0, (s, b) => s + b.quantity);

                            setDlgState(() {
                              final added = CartCampaignPricing.addWithStacking(
                                currentDiscounts: _appliedDiscounts,
                                incomingDiscount: CartCampaignPricing.discount(
                                  applied,
                                  currentResult.discount,
                                  voucherCode: code,
                                  staffNote: staffNote,
                                  comboCount: comboCnt > 0 ? comboCnt : null,
                                ),
                                incomingCampaign: applied,
                                campaignsById: _campaignById,
                                allowStackPromotions: allowStack,
                              );
                              _appliedDiscounts = added.discounts;
                            });
                            voucherCtrl.clear();
                          },
                          child: const Text('Áp Dụng'),
                        ),
                      ],
                    ),
                    if (voucherResult != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (voucherResult!.isValid ? AppColors.success : AppColors.danger).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: voucherResult!.isValid ? AppColors.success : AppColors.danger),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(voucherResult!.isValid ? Icons.check_circle : Icons.error_outline,
                                size: 18, color: voucherResult!.isValid ? AppColors.success : AppColors.danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                voucherResult!.isValid && voucherResult!.discount > 0
                                    ? '${voucherResult!.message} (-${FormatUtils.vnd(voucherResult!.discount)})'
                                    : voucherResult!.message,
                                style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Available list of promos
                    Text('Chương trình khuyến mãi khả dụng:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    if (!_allPromotions.any((p) => p.isActive && p.code.isEmpty) &&
                        !_campaigns.any((c) => !c.hasCodes))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'Chưa có chương trình khuyến mãi nào đang chạy cho chi nhánh này (hoặc ngoài khung ngày/giờ áp dụng). '
                          'Chương trình có phát hành mã thì nhập mã Voucher ở trên.',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                        ),
                      ),
                    ..._allPromotions.where((p) => p.isActive && p.code.isEmpty).map((p) {
                      final isSelected = _appliedDiscounts.any((d) => d.promoId == p.id);
                      final isValid = p.isValid(_subTotal);
                      return CheckboxListTile(
                        value: isSelected,
                        enabled: isValid || isSelected,
                        title: Text(p.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                          '${p.typeDisplay} • ${p.type == "PERCENT_BILL" ? "${p.value}%" : FormatUtils.vnd(p.value)} ${p.minBillAmount > 0 ? " (Đơn từ ${FormatUtils.vnd(p.minBillAmount)})" : ""}',
                          style: GoogleFonts.beVietnamPro(fontSize: 11),
                        ),
                        onChanged: (val) async {
                          if (val == true) {
                            String? staffNote;
                            if (p.requireStaffNote) {
                              staffNote = await _promptStaffNote(context);
                              if (staffNote == null || staffNote.trim().isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Bắt buộc phải nhập ghi chú nhân viên để áp dụng CTKM này!')),
                                  );
                                }
                                return;
                              }
                            }
                            setDlgState(() {
                              if (!allowStack) _appliedDiscounts.clear();
                              final amt = p.calculateDiscount(_subTotal, _cart);
                              _appliedDiscounts.add(BillDiscountModel(
                                promoId: p.id,
                                promoCode: p.code,
                                description: p.name,
                                amount: amt,
                                staffNote: staffNote,
                              ));
                            });
                          } else {
                            setDlgState(() {
                              _appliedDiscounts.removeWhere((d) => d.promoId == p.id);
                            });
                          }
                        },
                      );
                    }),
                    // Chương trình KM mới (không phát hành mã) - tính bằng Pricing Engine
                    ..._campaigns.where((c) => !c.hasCodes).map((c) {
                      final isSelected = _appliedDiscounts.any((d) => d.campaignId == c.campaignId);
                      // Ngoài khung ngày/giờ áp dụng: vẫn HIỆN trong danh sách (mờ) kèm lý do để nhân viên biết vì sao chưa dùng được
                      final inSchedule = c.isEligibleAt(nowMs);
                      final q = _quoteCampaign(c);
                      final amt = q.totalPromotionDiscount;
                      final reason = CartCampaignPricing.reason(q, c);
                      final combo = CartCampaignPricing.getComboInfo(c, cart: _cart, products: _products);
                      final isCombo = combo != null;
                      final hasWater = isCombo && combo.buyUnits > 0;
                      final needsCakes = isCombo && hasWater && combo.remainingRewardUnits > 0;
                      final canAutoAdd = !isCombo && amt <= 0 && CartCampaignPricing.needsRewardItems(q, c);

                      String sub = '${c.typeDisplay} • ${describeCampaignBenefit(c)}';
                      if (!c.isStackable) {
                        sub += ' • 🔒 Độc quyền';
                      } else if (c.effectiveMaxCampaignsPerOrder < 999) {
                        sub += ' • Tối đa ${c.effectiveMaxCampaignsPerOrder} CTKM/đơn';
                      }
                      if (isCombo) {
                        if (!hasWater) {
                          sub += ' • Chưa có nước trong đơn (chọn nước trước)${CartCampaignPricing.comboMissHint(c, cart: _cart, products: _products)}';
                        } else if (needsCakes) {
                          sub += ' • Đơn có ${combo.buyUnits} nước → Bấm để chọn tối đa ${combo.remainingRewardUnits} món giảm giá';
                        } else {
                          sub += ' • Đã đủ ${combo.maxRewardAllowed} combo → -${FormatUtils.vnd(amt)}';
                        }
                      } else {
                        if (amt > 0) {
                          sub += ' → -${FormatUtils.vnd(amt)}';
                        } else if (canAutoAdd) {
                          sub += ' • Đơn đủ điều kiện — bấm để tự thêm món được tặng/giảm';
                        } else if (reason != null) {
                          sub += ' • $reason';
                        }
                      }

                      if (!inSchedule) {
                        sub = '${c.typeDisplay} • ⏰ Ngoài thời gian áp dụng (${c.schedule.summary()})';
                      }

                      return CheckboxListTile(
                        value: isSelected,
                        enabled: !inSchedule ? isSelected : (isCombo ? hasWater : (amt > 0 || isSelected || canAutoAdd)),
                        title: Text(c.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(sub, style: GoogleFonts.beVietnamPro(fontSize: 11)),
                        secondary: (isCombo && hasWater && isSelected && combo.remainingRewardUnits > 0)
                            ? TextButton.icon(
                                icon: const Icon(Icons.add_circle_outline, size: 16),
                                label: Text('Thêm ${combo.remainingRewardUnits} món', style: GoogleFonts.beVietnamPro(fontSize: 11)),
                                onPressed: () async {
                                  final added = await _pickComboRewardItems(c);
                                  if (added) {
                                    final newQ = _quoteCampaign(c);
                                    final newAmt = newQ.totalPromotionDiscount;
                                    final comboCnt = newQ.rewardBenefits
                                        .where((b) => b.campaignId == c.campaignId)
                                        .fold<int>(0, (s, b) => s + b.quantity);
                                    setDlgState(() {
                                      _appliedDiscounts.removeWhere((d) => d.campaignId == c.campaignId);
                                      _appliedDiscounts.add(CartCampaignPricing.discount(
                                        c,
                                        newAmt,
                                        comboCount: comboCnt > 0 ? comboCnt : null,
                                      ));
                                    });
                                  }
                                },
                              )
                            : null,
                        onChanged: (val) async {
                          if (val == true) {
                            final stackCheck = CartCampaignPricing.checkStacking(
                              currentDiscounts: _appliedDiscounts,
                              incoming: c,
                              campaignsById: _campaignById,
                              allowStackPromotions: allowStack,
                            );
                            if (!stackCheck.canStack) {
                              if (stackCheck.conflictingExclusiveCampaign != null) {
                                if (!context.mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Xung Đột Khuyến Mãi'),
                                    content: Text(
                                      'Đơn hàng đang áp dụng "${stackCheck.conflictingExclusiveCampaign!.name}" (áp dụng độc quyền, không cộng dồn).\n\n'
                                      'Bạn có muốn gỡ "${stackCheck.conflictingExclusiveCampaign!.name}" để áp dụng "${c.name}" không?'
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Đổi sang KM mới', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                _appliedDiscounts.removeWhere((d) => d.campaignId == stackCheck.conflictingExclusiveCampaign!.campaignId);
                              } else if (stackCheck.requiresClearingExisting && _appliedDiscounts.isNotEmpty) {
                                if (!context.mounted) return;
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Áp Dụng Độc Quyền'),
                                    content: Text(
                                      'Chương trình "${c.name}" được cài đặt áp dụng độc quyền (không cho phép cộng dồn với CTKM khác).\n\n'
                                      'Áp dụng chương trình này sẽ gỡ các khuyến mãi hiện có trên đơn:\n'
                                      '${_appliedDiscounts.map((d) => "• ${d.description}").join("\n")}\n\n'
                                      'Bạn có muốn tiếp tục?'
                                    ),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Đồng ý gỡ & áp dụng', style: TextStyle(color: Colors.white)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm != true) return;
                                _appliedDiscounts.clear();
                              } else if (stackCheck.reason != null) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(stackCheck.reason!), backgroundColor: AppColors.danger));
                                }
                                return;
                              }
                            }

                            if (isCombo) {
                              if (!hasWater) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Vui lòng chọn món nước vào đơn trước khi áp dụng combo này.')),
                                  );
                                }
                                return;
                              }
                              if (needsCakes) {
                                final added = await _pickComboRewardItems(c);
                                if (!added) return;
                              }
                            } else if (canAutoAdd) {
                              final added = await _addRewardItems(c);
                              if (!added) return;
                            }

                            final newQ = _quoteCampaign(c);
                            final applyAmt = newQ.totalPromotionDiscount;
                            if (applyAmt <= 0) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Chưa tính được ưu đãi cho chương trình này.')),
                                );
                              }
                              setDlgState(() {});
                              return;
                            }

                            if (!context.mounted) return;
                            String? staffNote;
                            if (c.requireStaffNote) {
                              staffNote = await _promptStaffNote(context);
                              if (staffNote == null || staffNote.trim().isEmpty) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Bắt buộc phải nhập ghi chú nhân viên để áp dụng CTKM này!')),
                                  );
                                }
                                return;
                              }
                            }

                            final comboCnt = newQ.rewardBenefits
                                .where((b) => b.campaignId == c.campaignId)
                                .fold<int>(0, (s, b) => s + b.quantity);

                            setDlgState(() {
                              final added = CartCampaignPricing.addWithStacking(
                                currentDiscounts: _appliedDiscounts,
                                incomingDiscount: CartCampaignPricing.discount(
                                  c,
                                  applyAmt,
                                  staffNote: staffNote,
                                  comboCount: comboCnt > 0 ? comboCnt : null,
                                ),
                                incomingCampaign: c,
                                campaignsById: _campaignById,
                                allowStackPromotions: allowStack,
                              );
                              _appliedDiscounts = added.discounts;
                            });
                          } else {
                            setDlgState(() {
                              _appliedDiscounts.removeWhere((d) => d.campaignId == c.campaignId);
                            });
                          }
                        },
                      );
                    }),

                    // Manual Discount
                    if (_auth.can(AppPermissions.manualDiscount)) ...[
                      const Divider(height: 24),
                      Text('Giảm giá thủ công:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: manualValueCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: manualType == 'PERCENT' ? 'Giảm %' : 'Giảm số tiền VND',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: manualType,
                            items: const [
                              DropdownMenuItem(value: 'PERCENT', child: Text('% Bill')),
                              DropdownMenuItem(value: 'FIXED', child: Text('VND')),
                            ],
                            onChanged: (v) => setDlgState(() => manualType = v!),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(96, AppSpacing.minTapTarget),
                  backgroundColor: context.tc.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  // Giảm giá thủ công (nếu có nhập) được áp dụng cùng lúc với các CTKM đã chọn
                  final manualText = manualValueCtrl.text.trim();
                  if (manualText.isNotEmpty && _auth.can(AppPermissions.manualDiscount)) {
                    final val = int.tryParse(manualText.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                    if (val <= 0 || (manualType == 'PERCENT' && val > 100)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(manualType == 'PERCENT' ? 'Giảm % phải từ 1 đến 100' : 'Số tiền giảm không hợp lệ')),
                      );
                      return;
                    }
                    final raw = manualType == 'PERCENT' ? (_subTotal * val / 100).round() : val;
                    final amt = raw > _subTotal ? _subTotal : raw;
                    if (!allowStack) _appliedDiscounts.clear();
                    _appliedDiscounts.add(BillDiscountModel(
                      description: 'Giảm giá thủ công (${manualType == "PERCENT" ? "$val%" : FormatUtils.vnd(val)})',
                      amount: amt,
                    ));
                  }
                  confirmed = true;
                  Navigator.pop(ctx);
                },
                child: const Text('Xác nhận'),
              ),
            ],
          );
        },
      ),
    );
    if (!confirmed) {
      _appliedDiscounts
        ..clear()
        ..addAll(originalDiscounts);
    } else {
      _syncTableDiscounts();
      if (widget.table.currentOrderJson.isNotEmpty) {
        _fb.saveTable(widget.table).catchError((_) {});
      }
    }
    if (mounted) setState(() {});
  }

  // ==================== PAYMENT BOTTOM SHEET ====================
  Future<void> _showPaymentSheet() async {
    if (!await _ensureShiftOpen() || !mounted) return;

    String paymentMethod = 'CASH'; // 'CASH', 'TRANSFER_QR', 'SPLIT'
    final cashGivenCtrl = TextEditingController(text: '$_finalTotal');
    final cashSplitCtrl = TextEditingController(text: '${(_finalTotal ~/ 2)}');
    int changeAmount = 0;
    bool isProcessingPayment = false;
    String? paymentError; // Lỗi hiển thị ngay trong sheet

    final sheetOpenedTime = DateTime.now().millisecondsSinceEpoch;
    StreamSubscription<DatabaseEvent>? paymentSubscription;
    String? handledPaymentEventId;
    String? activeListeningMethod;
    int? activeListeningAmount;

    Future<void> executeCheckout(
      BuildContext ctx,
      void Function(void Function()) setSheetState, {
      int? overrideCashAmount,
      int? overrideQrAmount,
      String? matchedNote,
    }) async {
      if (isProcessingPayment) return;
      setSheetState(() {
        isProcessingPayment = true;
        paymentError = null;
      });
      if (!await _ensureShiftOpen()) {
        setSheetState(() => isProcessingPayment = false);
        return;
      }

      try {
        List<PaymentSplitModel>? splits;
        if (paymentMethod == 'SPLIT') {
          splits = [
            PaymentSplitModel(method: 'CASH', amount: overrideCashAmount ?? 0),
            PaymentSplitModel(method: 'TRANSFER_QR', amount: overrideQrAmount ?? 0),
          ];
        }

        final bill = await _buildCurrentBillAsync(
          status: 'PAID',
          method: paymentMethod,
          splits: splits,
        );

        // Đổi điểm (chặn nếu thiếu điểm) + tích điểm được xử lý trong closeAndPayBill (transaction, idempotent)
        await _fb.closeAndPayBill(
          bill,
          widget.table,
          pointEarnRate: _storeInfo?.pointEarnRate,
          pointRedeemRate: _storeInfo?.pointRedeemRate,
        );

        if (ctx.mounted) Navigator.pop(ctx);
        if (mounted) {
          final successMsg = matchedNote != null
              ? '⚡ $matchedNote! Đã tự động chốt đơn (${bill.billCode}) & bàn ${widget.table.name}! 🎉${_autoPrintBill ? " (Đang in bill)" : ""}'
              : 'Thanh toán thành công ${widget.table.name}: ${FormatUtils.vnd(bill.finalAmount)}! 🎉${_autoPrintBill ? " (Đang in bill)" : " (Không in bill)"}';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(successMsg),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 3),
            ),
          );
          if (widget.returnToParentOnPay && Navigator.of(context).canPop()) {
            Navigator.of(context).pop(true);
          } else {
            context.go('/tables');
          }
        }

        _fireBackgroundPaymentTasks(bill, paymentMethod, shouldPrint: _autoPrintBill);
      } catch (e) {
        if (ctx.mounted) {
          setSheetState(() {
            isProcessingPayment = false;
            paymentError = 'Lỗi thanh toán: $e';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi thanh toán: $e'), backgroundColor: AppColors.danger),
            );
          }
        }
      }
    }

    try {
      await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      // Tablet: không kéo giãn bảng thanh toán hết chiều ngang
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final cashGiven = int.tryParse(cashGivenCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? _finalTotal;
          changeAmount = cashGiven >= _finalTotal ? cashGiven - _finalTotal : 0;

          // Split calculations
          final parsedSplitCash = int.tryParse(cashSplitCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
          final splitCashAmount = parsedSplitCash.clamp(0, _finalTotal);
          final splitQrAmount = _finalTotal - splitCashAmount;
          final cashGivenForSplit = int.tryParse(cashGivenCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? splitCashAmount;
          final splitChangeAmount = cashGivenForSplit >= splitCashAmount ? cashGivenForSplit - splitCashAmount : 0;

          final effectiveQrAmount = paymentMethod == 'SPLIT' ? splitQrAmount : _finalTotal;
          final orderInfoText = VietQrGenerator.buildOrderInfo(
            storeCode: _storeInfo?.storeCode ?? 'TRAM01',
            tableName: widget.table.name,
          );
          final qrUrl = VietQrGenerator.generateImageUrl(
            bankId: _storeInfo?.bankId ?? 'MB',
            bankAccount: _storeInfo?.bankAccount ?? '0987654321',
            accountName: _storeInfo?.accountName ?? 'CHU QUAN FNB',
            amount: effectiveQrAmount,
            orderInfo: orderInfoText,
          );

          // Auto QR Check Listener Management
          void updatePaymentListener() {
            final currentTargetAmount = effectiveQrAmount;
            if (activeListeningMethod == paymentMethod && activeListeningAmount == currentTargetAmount) {
              return;
            }
            activeListeningMethod = paymentMethod;
            activeListeningAmount = currentTargetAmount;
            paymentSubscription?.cancel();
            paymentSubscription = null;

            if ((paymentMethod == 'TRANSFER_QR' || paymentMethod == 'SPLIT') && currentTargetAmount > 0) {
              paymentSubscription = _fb.listenPaymentEvents(sinceTimestamp: sheetOpenedTime - 15000).listen((event) async {
                if (!ctx.mounted || isProcessingPayment) return;
                final val = event.snapshot.value;
                if (val is! Map) return;

                final eventId = val['eventId']?.toString() ?? event.snapshot.key ?? '';
                final status = val['status']?.toString() ?? 'UNPROCESSED';
                if (status == 'PROCESSED' || handledPaymentEventId == eventId) return;

                final amount = (val['amount'] as num?)?.toInt() ?? 0;
                if (amount <= 0 || amount != currentTargetAmount) return;

                final content = (val['content']?.toString() ?? '').toLowerCase();
                final rawText = (val['rawText']?.toString() ?? '').toLowerCase();
                final bankName = val['bankName']?.toString() ?? 'Ngân hàng';

                final tableAscii = VietQrGenerator.toAscii(widget.table.name).toLowerCase();
                final tableNameClean = tableAscii.replaceAll(RegExp(r'[^a-z0-9]'), '');
                final contentClean = VietQrGenerator.toAscii(content).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                final rawClean = VietQrGenerator.toAscii(rawText).toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                final storeClean = VietQrGenerator.toAscii(_storeInfo?.storeCode ?? 'tram').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

                // Trích xuất số/chữ của bàn (VD: "bàn 1" -> "1", "bàn a1" -> "a1")
                final tableNumMatch = RegExp(r'[a-z]*\d+').stringMatch(tableNameClean);
                final tableNum = tableNumMatch ?? tableNameClean;

                // Khớp bàn nếu trong content hoặc rawText chứa tên bàn (VD: "ban1", "1", "bana1", "a1") hoặc mã chi nhánh ("tram01")
                final textHasTable = tableNameClean.isNotEmpty &&
                    (contentClean.contains(tableNameClean) ||
                     rawClean.contains(tableNameClean) ||
                     (tableNum.isNotEmpty && (contentClean.contains(tableNum) || rawClean.contains(tableNum))));
                final textHasStore = storeClean.isNotEmpty && (contentClean.contains(storeClean) || rawClean.contains(storeClean));
                final isRecentEvent = (val['timestamp'] as num? ?? 0) >= sheetOpenedTime - 30000;

                final isMatched = (textHasTable && textHasStore) || textHasTable || (textHasStore && isRecentEvent) || isRecentEvent;

                if (isMatched) {
                  handledPaymentEventId = eventId;
                  await _fb.markPaymentEventProcessed(eventId);
                  if (!ctx.mounted) return;
                  await executeCheckout(
                    ctx,
                    setSheetState,
                    overrideCashAmount: splitCashAmount,
                    overrideQrAmount: splitQrAmount,
                    matchedNote: 'Trạm Bot phát hiện tiền vào ${FormatUtils.vnd(amount)} từ $bankName',
                  );
                }
              });
            }
          }

          updatePaymentListener();

          final cashShortBy = cashGiven < _finalTotal ? _finalTotal - cashGiven : 0;
          final splitShortBy = cashGivenForSplit < splitCashAmount ? splitCashAmount - cashGivenForSplit : 0;
          final moneyInputStyle = GoogleFonts.beVietnamPro(fontSize: 22, fontWeight: FontWeight.w800, color: context.tc.textPrimary);

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(width: 40, height: 4, decoration: BoxDecoration(color: context.tc.border, borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 12),
                    PaymentTotalHeader(
                      tableName: widget.table.name,
                      total: _finalTotal,
                      customerLine: _selectedCustomer != null
                          ? 'Khách hàng: ${_selectedCustomer!.fullName} (${_selectedCustomer!.phone})'
                          : null,
                      onClose: () => Navigator.pop(ctx),
                    ),
                    if (_selectedCustomer != null) ...[
                      const SizedBox(height: 8),
                      LoyaltyEarnPreview(
                        pointsUnknown: _customerPointsUnknown,
                        pointsBlocked: _pointsBlockedByPromo,
                        customer: _selectedCustomer!,
                        pointsUsed: _pointsUsed,
                        earnPoints: _earnPreview,
                        earnRate: _earnRate,
                        redeemRate: _pointRedeemRate,
                        tiers: _storeInfo?.loyaltyTiers ?? LoyaltyTier.defaults,
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Payment Method Tabs (CASH, VIETQR, SPLIT)
                    PaymentMethodSelector(
                      selected: paymentMethod,
                      onChanged: (m) => setSheetState(() {
                        paymentMethod = m;
                        if (m == 'SPLIT' && (cashSplitCtrl.text.isEmpty || cashSplitCtrl.text == '0')) {
                          cashSplitCtrl.text = '${(_finalTotal ~/ 2)}';
                        }
                      }),
                    ),
                    const SizedBox(height: 16),

                    // CASH CALCULATOR
                    if (paymentMethod == 'CASH') ...[
                      TextField(
                        controller: cashGivenCtrl,
                        keyboardType: TextInputType.number,
                        style: moneyInputStyle,
                        decoration: const InputDecoration(
                          labelText: 'Khách đưa (VND)',
                          suffixText: 'đ',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                        onTap: () => cashGivenCtrl.selection = TextSelection(baseOffset: 0, extentOffset: cashGivenCtrl.text.length),
                        onChanged: (v) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 10),
                      QuickCashAmounts(
                        amountDue: _finalTotal,
                        onPick: (v) => setSheetState(() => cashGivenCtrl.text = '$v'),
                      ),
                      const SizedBox(height: 12),
                      ChangeDueRow(change: changeAmount, shortBy: cashShortBy),
                    ],

                    // VIETQR DISPLAY
                    if (paymentMethod == 'TRANSFER_QR') ...[
                      Center(
                        child: Column(
                          children: [
                            VietQrImage(
                              url: qrUrl,
                              height: 280,
                              amount: _finalTotal,
                              bankInfo: '${_storeInfo?.bankId} • ${_storeInfo?.bankAccount} • ${_storeInfo?.accountName}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_storeInfo?.bankId} • ${_storeInfo?.bankAccount} • ${_storeInfo?.accountName}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: context.tc.textPrimary),
                            ),
                            const SizedBox(height: 10),
                            const PaymentBotWatchingBox(),
                          ],
                        ),
                      ),
                    ],

                    // SPLIT PAYMENT DISPLAY (TIỀN MẶT + VIETQR)
                    if (paymentMethod == 'SPLIT') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.tc.infoLight,
                          borderRadius: AppRadius.brMd,
                          border: Border.all(color: context.tc.info.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Phân bổ thanh toán hỗn hợp', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: context.tc.info)),
                            const SizedBox(height: 10),
                            TextField(
                              controller: cashSplitCtrl,
                              keyboardType: TextInputType.number,
                              style: moneyInputStyle.copyWith(fontSize: 18),
                              decoration: const InputDecoration(
                                labelText: '1. Phần tiền mặt (VND)',
                                suffixText: 'đ',
                                prefixIcon: Icon(Icons.payments_outlined),
                              ),
                              onChanged: (v) => setSheetState(() {}),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    onPressed: () {
                                      cashSplitCtrl.text = '${(_finalTotal ~/ 2)}';
                                      setSheetState(() {});
                                    },
                                    child: const Text('50% tiền mặt', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                                    onPressed: () {
                                      cashSplitCtrl.text = '$_finalTotal';
                                      setSheetState(() {});
                                    },
                                    child: const Text('100% tiền mặt', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(color: context.tc.card, borderRadius: AppRadius.brSm),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text('2. Phần chuyển khoản QR:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600)),
                                  ),
                                  Text(
                                    FormatUtils.vnd(splitQrAmount),
                                    style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, color: context.tc.info),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (splitQrAmount > 0) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: Column(
                            children: [
                              VietQrImage(
                                url: qrUrl,
                                height: 230,
                                amount: splitQrAmount,
                                bankInfo: '${_storeInfo?.bankId} • ${_storeInfo?.bankAccount} • ${_storeInfo?.accountName}',
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Quét mã để chuyển khoản đúng ${FormatUtils.vnd(splitQrAmount)}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.tc.info),
                              ),
                              const SizedBox(height: 8),
                              const PaymentBotWatchingBox(),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: cashGivenCtrl,
                        keyboardType: TextInputType.number,
                        style: moneyInputStyle.copyWith(fontSize: 18),
                        decoration: InputDecoration(
                          labelText: 'Khách đưa tiền mặt (VND)',
                          hintText: '$splitCashAmount',
                          suffixText: 'đ',
                        ),
                        onChanged: (v) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 8),
                      ChangeDueRow(change: splitChangeAmount, shortBy: splitShortBy),
                    ],

                    const SizedBox(height: 16),

                    // Lỗi thanh toán hiển thị ngay trong sheet (SnackBar nằm sau sheet nên dễ bị che)
                    if (paymentError != null) ...[
                      PaymentErrorBox(
                        message: paymentError!,
                        onClose: () => setSheetState(() => paymentError = null),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Bật/tắt in hóa đơn khi thanh toán
                    AutoPrintToggleTile(
                      value: _autoPrintBill,
                      onChanged: (val) {
                        setSheetState(() => _autoPrintBill = val);
                        setState(() => _autoPrintBill = val);
                        _saveAutoPrintSetting(val);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Action Buttons: Đóng & In tạm tính & Thanh toán
                    Row(
                      children: [
                        IconButton.outlined(
                          icon: const Icon(Icons.close),
                          tooltip: 'Đóng',
                          style: IconButton.styleFrom(
                            minimumSize: const Size(48, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 56), padding: const EdgeInsets.symmetric(horizontal: 8)),
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Tạm tính', maxLines: 1, overflow: TextOverflow.ellipsis),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Đang gửi lệnh in tạm tính...'), duration: Duration(seconds: 1)),
                              );
                              _buildCurrentBillAsync(status: 'OPEN', method: paymentMethod).then((bill) {
                                _markTablePrePrinted();
                                ReceiptPrinter.printBill(
                                  store: _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm'),
                                  bill: bill,
                                  isPrePrint: true,
                                ).catchError((_) => false);
                              }).catchError((_) {});
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 3,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: context.tc.success,
                              minimumSize: const Size(0, 56),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: isProcessingPayment
                                ? null
                                : () => executeCheckout(
                                      ctx,
                                      setSheetState,
                                      overrideCashAmount: splitCashAmount,
                                      overrideQrAmount: splitQrAmount,
                                    ),
                            child: isProcessingPayment
                                ? const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                      SizedBox(width: 8),
                                      Flexible(child: Text('Đang xử lý...', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          paymentMethod == 'TRANSFER_QR'
                                              ? 'XÁC NHẬN ĐÃ NHẬN TIỀN'
                                              : 'XÁC NHẬN THU TIỀN',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    } finally {
      paymentSubscription?.cancel();
    }
  }

  void _fireBackgroundPaymentTasks(BillModel bill, String paymentMethod, {bool shouldPrint = true}) {
    // 1. KiotViet Cash Shift Sync (Doanh thu ca két)
    // QUY TẮC CỐT LÕI: Chỉ cộng phần TIỀN MẶT trong paymentSplits vào tiền két ca, không cộng tiền chuyển khoản!
    if (bill.shiftId != null) {
      int cashPortion = 0;
      int qrPortion = 0;
      int cardPortion = 0;

      if (bill.paymentSplits != null && bill.paymentSplits!.isNotEmpty) {
        for (final sp in bill.paymentSplits!) {
          final m = sp.method.toUpperCase();
          if (m == 'CASH') {
            cashPortion += sp.amount;
          } else if (m == 'TRANSFER_QR') {
            qrPortion += sp.amount;
          } else if (m == 'CARD') {
            cardPortion += sp.amount;
          } else {
            cashPortion += sp.amount;
          }
        }
      } else {
        cashPortion = paymentMethod == 'CASH' ? bill.finalAmount : 0;
        qrPortion = paymentMethod == 'TRANSFER_QR' ? bill.finalAmount : 0;
        cardPortion = paymentMethod == 'CARD' ? bill.finalAmount : 0;
      }

      _fb.recordCashShiftSale(
        shiftId: bill.shiftId,
        cashAmount: cashPortion,
        qrAmount: qrPortion,
        cardAmount: cardPortion,
      ).catchError((_) {});
    }

    // 2. Tích/đổi điểm khách: đã xử lý trong closeAndPayBill (transaction, idempotent theo hóa đơn)

    // 3. In hóa đơn ra máy in nhiệt (LAN hoặc Bluetooth)
    if (shouldPrint) {
      final store = _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm');
      ReceiptPrinter.printBill(
        store: store,
        bill: bill,
        isPrePrint: false,
      ).catchError((_) => false);
    }

    // 4. Nhật ký kiểm toán hệ thống
    _fb.logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: _auth.currentUser?.username ?? 'staff',
      userFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
      userRole: _auth.currentUser?.roleId ?? 'ROLE_STAFF',
      action: 'CREATE_BILL',
      targetType: 'BILL',
      targetId: bill.billCode,
      details: 'Thanh toán hoàn tất bàn ${widget.table.name}: ${FormatUtils.vnd(bill.finalAmount)} ($paymentMethod)${shouldPrint ? "" : " [Không in bill]"}',
    )).catchError((_) {});
  }

  Future<bool> _ensureShiftOpen() async {
    CashShiftModel? shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
    if (shift == null || !shift.isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Chức năng order & thanh toán đang bị khóa! Vui lòng khai báo tiền két đầu ca.'),
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

  /// Món trong giỏ đã bị báo hết hàng (theo danh sách món realtime). Chỉ cảnh báo, không xóa khỏi đơn.
  bool _isCartItemSoldOut(OrderItemModel item) {
    for (final p in _products) {
      if (p.name == item.name && (item.productId == 0 || p.id == item.productId || p.id == 0)) {
        return !isProductAvailable(p);
      }
    }
    return false;
  }

  Future<void> _goToAddItems() async {
    if (!await _ensureShiftOpen() || !mounted) return;

    final res = await context.push('/order-list', extra: {
      'table': widget.table,
      'isAddingMore': true,
    });
    if (!mounted) return;
    if (res is List<OrderItemModel>) {
      setState(() {
        _cart = List.from(res);
      });
      _recalculateDiscounts();
    } else {
      final refreshed = await _fb.tablesStream().first;
      final currentT = refreshed.where((x) => x.name == widget.table.name).firstOrNull;
      if (currentT != null && mounted) {
        setState(() {
          _cart = List.from(currentT.currentItems);
        });
        _recalculateDiscounts();
      }
    }
  }

  Future<void> _updateGuestCount(int newCount) async {
    if (newCount < 1) return;
    setState(() {
      _guestCount = newCount;
      widget.table.guestCount = newCount;
    });
    try {
      await _fb.saveTable(widget.table);
    } catch (_) {}
  }

  void _showEditGuestCountDialog() {
    final ctrl = TextEditingController(text: '$_guestCount');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: context.tc.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.people_alt, color: context.tc.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Số Lượng Khách', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bàn ${widget.table.name} • ${widget.table.zone}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(fontSize: 26, fontWeight: FontWeight.bold, color: context.tc.primary),
              decoration: InputDecoration(
                hintText: 'Nhập số khách',
                suffixText: 'khách',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1, 2, 4, 6, 8, 10, 15].map((count) {
                return ActionChip(
                  backgroundColor: context.tc.primaryLight.withValues(alpha: 0.4),
                  label: Text('$count khách', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  onPressed: () {
                    ctrl.text = '$count';
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary),
            onPressed: () {
              final val = int.tryParse(ctrl.text.trim());
              if (val != null && val > 0) {
                _updateGuestCount(val);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Cập Nhật'),
          ),
        ],
      ),
    );
  }

  Future<BillModel> _buildCurrentBillAsync({
    required String status,
    required String method,
    List<PaymentSplitModel>? splits,
  }) async {
    // Find active cash shift reliably from cache or query
    String? currentShiftId = _fb.activeShiftCache?.id;
    if (currentShiftId == null) {
      try {
        final shift = await _fb.getCurrentOpenShift();
        currentShiftId = shift?.id;
      } catch (_) {}
    }

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Thu Ngân';

    final logs = List<OrderActionLogModel>.from(widget.table.actionLogs);
    if (status == 'PAID') {
      String methodDisplay = "Tiền mặt";
      if (method == "TRANSFER_QR") methodDisplay = "VietQR";
      if (method == "SPLIT") methodDisplay = "Hỗn hợp (Tiền mặt + QR)";
      logs.add(OrderActionLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        staffUsername: staffUser,
        staffFullName: staffName,
        action: 'PAY_BILL',
        details: '$staffName thanh toán hóa đơn: ${FormatUtils.vnd(_finalTotal)} ($methodDisplay)',
      ));
    }

    widget.table.guestCount = _guestCount;

    final billCode = (widget.table.currentBillId != null && widget.table.currentBillId!.startsWith('HD-'))
        ? widget.table.currentBillId!
        : FormatUtils.billCode();
    final orderCode = widget.table.currentOrderCode ?? FormatUtils.orderCode();

    return BillModel(
      id: 'BILL_${DateTime.now().millisecondsSinceEpoch}',
      billCode: billCode,
      orderCode: orderCode,
      tableName: widget.table.name,
      zone: widget.table.zone,
      createdAt: widget.table.openedAt ?? DateTime.now().millisecondsSinceEpoch,
      closedAt: DateTime.now().millisecondsSinceEpoch,
      status: status,
      staffUid: _auth.currentUid,
      staffUsername: staffUser,
      staffFullName: staffName,
      items: _cart,
      subTotal: _subTotal,
      discounts: _appliedDiscounts,
      totalDiscount: _totalDiscount,
      pointsUsed: _pointsUsed,
      pointsDiscount: _pointsDiscount,
      vatRate: _vatRate,
      vatAmount: _vatAmount,
      finalAmount: _finalTotal,
      paymentMethod: method,
      paymentSplits: splits,
      notes: _billNotes,
      customerId: _selectedCustomer?.id,
      customerName: _selectedCustomer?.fullName,
      customerPhone: _selectedCustomer?.phone,
      shiftId: currentShiftId,
      actionLogs: logs,
      deletedItems: widget.table.deletedItems,
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        _syncTableDiscounts();
        if (widget.table.currentOrderJson.isNotEmpty) {
          _fb.saveTable(widget.table).catchError((_) {});
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bàn ${widget.table.name} (${widget.table.zone})',
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.table.currentBillId != null && widget.table.currentBillId!.isNotEmpty)
              Text(
                'Mã HĐ: ${widget.table.currentBillId}',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _autoPrintBill ? Icons.print : Icons.print_disabled_outlined,
              color: _autoPrintBill ? Colors.white : Colors.white60,
              size: 22,
            ),
            tooltip: _autoPrintBill ? 'In bill khi thanh toán: ĐANG BẬT' : 'In bill khi thanh toán: ĐANG TẮT',
            onPressed: () {
              final newVal = !_autoPrintBill;
              setState(() => _autoPrintBill = newVal);
              _saveAutoPrintSetting(newVal);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(newVal ? '🖨️ Đã BẬT tự động in bill khi thanh toán' : '🚫 Đã TẮT in bill khi thanh toán (chỉ chốt đơn, không in giấy)'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: newVal ? AppColors.success : AppColors.warningInk,
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Thao tác bàn',
            onSelected: (val) {
              if (val == 'SPLIT') _showSplitBillDialog();
              if (val == 'MERGE') _showMergeTableDialog();
              if (val == 'CANCEL') _showCancelBillDialog();
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: 'SPLIT',
                child: Row(
                  children: [
                    Icon(Icons.call_split, size: 20, color: context.tc.primary),
                    const SizedBox(width: 10),
                    const Text('Tách hóa đơn'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'MERGE',
                child: Row(
                  children: [
                    Icon(Icons.merge_type, size: 20, color: context.tc.primary),
                    const SizedBox(width: 10),
                    const Text('Ghép bàn'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'CANCEL',
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, size: 20, color: context.tc.danger),
                    const SizedBox(width: 10),
                    Text('Hủy hóa đơn bàn', style: TextStyle(color: context.tc.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingState(message: 'Đang tải đơn hàng...')
          : LayoutBuilder(
              builder: (context, constraints) {
                // Tablet ngang (≥ 900dp): danh sách món bên trái, tổng tiền & nút thao tác cố định bên phải
                final wide = constraints.maxWidth >= 900;
                final unsentCount = _cart.where((i) => !i.isSentKitchen).fold(0, (sum, i) => sum + i.quantity);

                final summary = CartSummaryPanel(
                  sidePanel: wide,
                  subTotal: _subTotal,
                  itemDiscountTotal: _itemDiscountTotal,
                  appliedDiscounts: _appliedDiscounts,
                  pointsUsed: _pointsUsed,
                  pointsDiscount: _pointsDiscount,
                  vatRate: _vatRate,
                  vatAmount: _vatAmount,
                  finalTotal: _finalTotal,
                  unsentCount: unsentCount,
                  cartEmpty: _cart.isEmpty,
                  onDiscount: _showDiscountDialog,
                  onPrePrint: _cart.isEmpty ? null : _printPreBill,
                  onCancel: _showCancelBillDialog,
                  onSendKitchen: _sendToKitchen,
                  onPay: _showPaymentSheet,
                );

                final customerBar = CartCustomerBar(
                  pointsBlocked: _pointsBlockedByPromo,
                  customer: _selectedCustomer,
                  onEdit: _selectedCustomer == null ? null : () => _showEditCustomerDialog(_selectedCustomer!),
                  pointsUsed: _pointsUsed,
                  earnPoints: _earnPreview,
                  earnRate: _earnRate,
                  redeemRate: _pointRedeemRate,
                  tiers: _storeInfo?.loyaltyTiers ?? LoyaltyTier.defaults,
                  onConfigureRate: _auth.can(AppPermissions.manageCustomers) ? _openLoyaltyConfig : null,
                  onLookup: _showCustomerLookupDialog,
                  onUsePoints: _showUsePointsDialog,
                  pointsUnknown: _customerPointsUnknown,
                  onRetryPoints: _refreshCustomerPoints,
                  onClear: () => _setCustomer(null),
                );

                final linePromoDiscounts = CartCampaignPricing.computeLinePromotionDiscounts(
                  cart: _cart,
                  appliedDiscounts: _appliedDiscounts,
                  campaignsById: _campaignById,
                  products: _products,
                  branchId: _fb.currentStoreCode,
                  customerBirthday: _selectedCustomer?.birthday,
                  guestCount: _guestCount,
                  orderTimestampMs: widget.table.openedAt,
                  isExistingOrder: true,
                );

                final groups = buildCartProductGroups(
                  cart: _cart,
                  linePromoDiscounts: linePromoDiscounts,
                  isSoldOutFn: _isCartItemSoldOut,
                );

                final cartList = _cart.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: 'Chưa có món nào trong order',
                        subtitle: 'Bấm "Thêm món" để chọn món cho bàn này.',
                        action: SizedBox(
                          width: 220,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Thêm món vào đơn'),
                            onPressed: _goToAddItems,
                          ),
                        ),
                      )
                    : _treeViewMode
                        ? ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 76),
                            itemCount: groups.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) => CartTreeGroupCard(
                              group: groups[index],
                              onRemove: _confirmRemoveItem,
                              onEditNote: _showEditItemNoteAndToppingDialog,
                              onDiscount: _showItemDiscountDialog,
                              onIncrement: _incrementItem,
                              onDecrement: _decrementItem,
                              onRemoveGroup: _confirmRemoveGroup,
                              onRemoveBranch: _confirmRemoveBranch,
                              onIncrementBranch: _incrementBranch,
                              onDecrementBranch: _decrementBranch,
                              onEditNoteBranch: _showEditBranchNoteAndToppingDialog,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 76),
                            itemCount: _cart.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) => CartItemCard(
                              item: _cart[index],
                              onRemove: () => _confirmRemoveItem(index),
                              onEditNote: () => _showEditItemNoteAndToppingDialog(index),
                              onDiscount: () => _showItemDiscountDialog(index),
                              onIncrement: () => _incrementItem(index),
                              onDecrement: () => _decrementItem(index),
                              soldOut: _isCartItemSoldOut(_cart[index]),
                              promoDiscounts: linePromoDiscounts[index] ?? const [],
                            ),
                          );

                final leftColumn = Column(
                  children: [
                    CartHeaderBar(
                      tableName: widget.table.name,
                      zone: widget.table.zone,
                      guestCount: _guestCount,
                      onEditGuests: _showEditGuestCountDialog,
                      onDecrementGuests: _guestCount > 1 ? () => _updateGuestCount(_guestCount - 1) : null,
                      onIncrementGuests: () => _updateGuestCount(_guestCount + 1),
                      treeViewMode: _treeViewMode,
                      onToggleTreeViewMode: _cart.isNotEmpty ? (v) => _setTreeViewMode(v) : null,
                      totalQty: _cart.fold(0, (s, i) => s + i.quantity),
                      uniqueProductsCount: groups.length,
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(child: cartList),
                          // Nút thêm món (+) khối tròn nổi ngay trên phần khách hàng
                          Positioned(
                            right: 16,
                            bottom: 12,
                            child: Tooltip(
                              message: 'Thêm món',
                              child: Material(
                                color: context.tc.primary,
                                shape: const CircleBorder(),
                                elevation: 5,
                                shadowColor: Colors.black45,
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: _goToAddItems,
                                  child: Container(
                                    width: 52,
                                    height: 52,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.add,
                                      color: Colors.white,
                                      size: 28,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!wide) customerBar,
                    if (!wide) summary,
                  ],
                );

                return Column(
                  children: [
                    if (!_isShiftOpen)
                      InfoBanner(
                        solid: true,
                        tone: BannerTone.warning,
                        icon: Icons.lock,
                        title: 'Đang khóa order & thanh toán do chưa nhập két đầu ca.',
                        actionLabel: 'Mở két ngay',
                        actionIcon: Icons.point_of_sale,
                        onAction: () => CashShiftDialog.show(context),
                      ),
                    Expanded(
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: leftColumn),
                                SizedBox(
                                  width: 400,
                                  child: ColoredBox(
                                    color: context.tc.card,
                                    child: Column(
                                      children: [
                                        customerBar,
                                        const Spacer(),
                                        summary,
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : leftColumn,
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }

  /// Sau khi gửi lệnh in tạm tính: lưu giỏ hiện tại + đánh dấu bàn "Chờ thanh toán"
  /// (`prePrintedAt`/`prePrintedBy`). Mọi thay đổi món sau đó sẽ tự xóa cờ này.
  Future<void> _markTablePrePrinted() async {
    if (_cart.isEmpty) return;
    final t = widget.table;
    t.inUse = true;
    t.openedAt ??= DateTime.now().millisecondsSinceEpoch;
    t.currentOrderJson = jsonEncode(_cart.map((e) => e.toMap()).toList());
    t.markPrePrinted(by: _auth.currentUser?.username);
    await _fb.saveTable(t).catchError((_) {});
  }

  /// In phiếu tạm tính (giữ nguyên luồng cũ: gửi lệnh in LAN, bỏ qua lỗi máy in).
  void _printPreBill() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đang gửi lệnh in tạm tính...'), duration: Duration(seconds: 1)),
    );
    _buildCurrentBillAsync(status: 'PRE_PRINT', method: 'PRE_PRINT').then((bill) {
      _markTablePrePrinted();
      ReceiptPrinter.printBill(
        store: _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm'),
        bill: bill,
        isPrePrint: true,
      ).catchError((_) => false);
    }).catchError((_) {});
  }
}
