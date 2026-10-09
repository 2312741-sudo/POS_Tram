// lib/features/orders/order_cart_screen.dart
import 'dart:convert';
import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/printer/receipt_printer.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/manager_pin_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/vietqr/vietqr_generator.dart';
import '../../data/models/app_models.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/firebase_service.dart';
import '../../data/services/campaign_service.dart';
import '../../core/domain/promotion_migration.dart';
import '../cash_shift/cash_shift_dialog.dart';
import 'widgets/cart_item_card.dart';
import 'widgets/cart_panels.dart';
import 'widgets/payment_widgets.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/manager_pin_dialogs.dart';

class OrderCartScreen extends StatefulWidget {
  final TableModel table;
  final List<OrderItemModel> initialProducts;

  const OrderCartScreen({super.key, required this.table, this.initialProducts = const []});

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
  bool _isLoading = false;
  bool _isShiftOpen = false;
  bool _autoPrintBill = true;

  // Products, Categories and Backend Note Presets for Toppings & Notes editing
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  List<String> _backendNotePresets = [];

  // KiotViet CRM Customer Loyalty
  KmtCustomerModel? _selectedCustomer;
  int _pointsUsed = 0;
  late int _guestCount;

  // Huỷ các listener Firebase khi rời màn hình (trước đây bị rò rỉ listener)
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _isShiftOpen = _fb.activeShiftCache != null && _fb.activeShiftCache!.isOpen;
    widget.table.ensureCodes();
    _cart = List.from(widget.initialProducts.isNotEmpty ? widget.initialProducts : widget.table.currentItems);
    _guestCount = widget.table.guestCount ?? 2;
    _storeInfo = _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _fb.currentStoreCode, storeName: 'POS Trạm');
    _loadStoreAndPromotions();
    _loadAutoPrintSetting();

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

    _subscriptions.add(_fb.cashShiftsStream().listen((shifts) {
      final openOne = shifts.where((s) => s.isOpen).firstOrNull;
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

  Future<void> _loadStoreAndPromotions() async {
    try {
      final info = await _fb.getStoreInfo();
      final promos = await _fb.getPromotions();

      try {
        final campaigns = await CampaignService().getCampaigns();
        final now = DateTime.now().millisecondsSinceEpoch;
        final storeCode = _fb.currentStoreCode;
        for (final c in campaigns) {
          if (!c.active) continue;
          if (!c.isEligibleAt(now)) continue;
          if (!c.isEligibleForBranch(storeCode)) continue;

          final legacy = PromotionMigration.toLegacy(c);
          if (!promos.any((p) => p.id == legacy.id)) {
            promos.add(legacy);
          }
        }
      } catch (e) {
        debugPrint('Error loading campaigns into cart: $e');
      }

      if (mounted) {
        setState(() {
          _storeInfo = info;
          _vatRate = (info.defaultVatRate == 8.0) ? 0.0 : info.defaultVatRate;
          _allPromotions = promos;
        });
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

  int get _cartCount => _cart.fold(0, (s, p) => s + p.quantity);

  // ==================== CART ACTIONS ====================
  Future<void> _incrementItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    setState(() {
      _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity + 1);
    });
    _recalculateDiscounts();
  }

  Future<void> _decrementItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    if (item.isSentKitchen && !_auth.can(AppPermissions.cancelKitchenItem)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền hủy món đã gửi bếp!'), backgroundColor: AppColors.danger),
      );
      return;
    }

    if (item.quantity <= 1) {
      await _removeItem(index);
    } else {
      setState(() {
        _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity - 1);
      });
      _recalculateDiscounts();
    }
  }

  Future<void> _confirmRemoveItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    final bool isKitchen = item.isSentKitchen;

    if (isKitchen && !_auth.can(AppPermissions.cancelKitchenItem)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Bạn không có quyền hủy món đã gửi bếp!'),
          backgroundColor: AppColors.danger,
        ),
      );
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
      await _removeItem(index);
    }
  }

  Future<void> _removeItem(int index) async {
    if (!await _ensureShiftOpen() || !mounted) return;
    final item = _cart[index];
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';
    final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

    if (item.isSentKitchen) {
      if (!_auth.can(AppPermissions.cancelKitchenItem)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn không có quyền hủy món đã gửi bếp!'), backgroundColor: AppColors.danger),
        );
        return;
      }

      // Log suspicious action
      await _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: staffUser,
        userFullName: staffName,
        userRole: staffRole,
        action: 'CANCEL_KITCHEN_ITEM',
        targetType: 'TABLE',
        targetId: widget.table.name,
        details: 'Hủy món đã gửi bếp: ${item.name} x${item.quantity} tại ${widget.table.name}',
        isSuspicious: true,
      ));
    } else {
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

    widget.table.addActionLog(OrderActionLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      staffUsername: staffUser,
      staffFullName: staffName,
      action: 'CANCEL_ITEM',
      details: '$staffName hủy món ${item.name} (x${item.quantity})',
    ));

    setState(() {
      _cart.removeAt(index);
    });

    // Nếu giỏ hàng đã bị xóa hết món -> Chuyển bàn về trạng thái TRỐNG hoàn toàn!
    if (_cart.isEmpty) {
      widget.table.clearTable();
      await _fb.saveTable(widget.table).catchError((_) {});
      _recalculateDiscounts();
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
    if (hasKitchen && !_auth.can(AppPermissions.cancelBill) && !_auth.can(AppPermissions.cancelKitchenItem)) {
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

  void _recalculateDiscounts() {
    final List<BillDiscountModel> valid = [];
    for (final d in _appliedDiscounts) {
      if (d.promoId != null) {
        final p = _allPromotions.where((pr) => pr.id == d.promoId).firstOrNull;
        if (p != null) {
          if (p.isValid(_subTotal)) {
            final amt = p.calculateDiscount(_subTotal, _cart);
            valid.add(BillDiscountModel(
              promoId: p.id,
              promoCode: d.promoCode ?? p.code,
              description: p.name,
              amount: amt,
            ));
          }
        } else {
          valid.add(d);
        }
      } else {
        valid.add(d);
      }
    }
    setState(() => _appliedDiscounts = valid);
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

    final Map<int, int> splitQty = {};
    for (final item in _cart) {
      splitQty[item.productId] = 0;
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: Text('Tách Hóa Đơn - ${widget.table.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Chọn số lượng món muốn tách sang hóa đơn mới:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
                  const SizedBox(height: 12),
                  ..._cart.map((item) {
                    final curr = splitQty[item.productId] ?? 0;
                    return ListTile(
                      dense: true,
                      title: Text(item.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                      subtitle: Text('Tổng có: ${item.quantity} | Tách: $curr'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: curr > 0 ? () => setDlgState(() => splitQty[item.productId] = curr - 1) : null,
                          ),
                          Text('$curr', style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: curr < item.quantity ? () => setDlgState(() => splitQty[item.productId] = curr + 1) : null,
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () async {
                  final List<OrderItemModel> splitItems = [];
                  final List<OrderItemModel> remainingItems = [];

                  for (final item in _cart) {
                    final sQty = splitQty[item.productId] ?? 0;
                    // Chia số phần được giảm & tổng giảm giữa 2 phần (không nhân đôi giảm giá)
                    final (taken, rest) = item.splitQuantity(sQty);
                    if (taken != null) splitItems.add(taken);
                    if (rest != null) remainingItems.add(rest);
                  }

                  if (splitItems.isEmpty) return;

                  final newBill = BillModel(
                    id: 'BILL_${DateTime.now().millisecondsSinceEpoch}',
                    billCode: FormatUtils.billCode(),
                    orderCode: FormatUtils.orderCode(),
                    tableName: '${widget.table.name} (Tách)',
                    zone: widget.table.zone,
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                    staffUsername: _auth.currentUser?.username ?? 'staff',
                    staffFullName: _auth.currentUser?.fullName ?? 'Thu Ngân',
                    items: splitItems,
                    subTotal: splitItems.fold(0, (s, i) => s + i.itemTotal),
                    finalAmount: splitItems.fold(0, (s, i) => s + i.itemTotal),
                    parentBillId: widget.table.name,
                  );
                  final splitSummary = splitItems.map((e) => '${e.quantity}x ${e.name}').join(', ');
                  final staffName = _auth.currentUser?.fullName ?? 'Thu Ngân';
                  final staffUser = _auth.currentUser?.username ?? 'staff';
                  final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

                  widget.table.addActionLog(OrderActionLogModel(
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                    staffUsername: staffUser,
                    staffFullName: staffName,
                    action: 'SPLIT_BILL',
                    details: '$staffName tách sang đơn mới ${newBill.billCode}: $splitSummary',
                  ));

                  await _fb.logAction(AuditLogModel(
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                    username: staffUser,
                    userFullName: staffName,
                    userRole: staffRole,
                    action: 'SPLIT_BILL',
                    targetType: 'TABLE',
                    targetId: widget.table.name,
                    details: 'Tách từ ${widget.table.name} sang đơn mới ${newBill.billCode} các món: $splitSummary',
                  ));

                  await _fb.saveBill(newBill);

                  if (remainingItems.isEmpty) {
                    widget.table.inUse = false;
                    widget.table.currentOrderJson = '';
                    widget.table.openedAt = null;
                    widget.table.guestCount = null;
                    widget.table.currentBillId = null;
                    widget.table.actionLogsJson = null;
                    await _fb.saveTable(widget.table);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Đã tách toàn bộ món sang hóa đơn ${newBill.billCode}! Bàn đã được dọn.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      this.context.go('/tables');
                    }
                  } else {
                    setState(() => _cart = remainingItems);
                    widget.table.currentOrderJson = jsonEncode(remainingItems.map((e) => e.toMap()).toList());
                    await _fb.saveTable(widget.table);
                    _recalculateDiscounts();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text('Đã tách thành công hóa đơn ${newBill.billCode}!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  }
                },
                child: const Text('Tách Hóa Đơn'),
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

  // ==================== KIOTVIET CRM CUSTOMER DIALOGS ====================
  void _showCustomerLookupDialog() {
    final phoneCtrl = TextEditingController();
    bool isSearching = false;
    KmtCustomerModel? foundCustomer;
    bool searched = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Khách Hàng Tích Điểm (KiotViet)', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: phoneCtrl,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Số điện thoại',
                            prefixIcon: Icon(Icons.phone),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
                        onPressed: isSearching
                            ? null
                            : () async {
                                final phone = phoneCtrl.text.trim();
                                if (phone.isEmpty) return;
                                setDlgState(() => isSearching = true);
                                final c = await _fb.lookupCustomer(phone);
                                setDlgState(() {
                                  foundCustomer = c;
                                  isSearching = false;
                                  searched = true;
                                });
                              },
                        child: isSearching
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Tìm'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (searched && foundCustomer != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.bg(Colors.green.shade50),
                        border: Border.all(color: context.line(Colors.green.shade200)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.verified, color: Colors.green, size: 20),
                              const SizedBox(width: 6),
                              Text(foundCustomer!.fullName, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('SĐT: ${foundCustomer!.phone}', style: GoogleFonts.beVietnamPro(fontSize: 12)),
                          Text('Điểm tích lũy: ${foundCustomer!.currentPoints} điểm', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: context.ink(Colors.green.shade900))),
                          Text('Xếp hạng: ${foundCustomer!.groupName}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
                        ],
                      ),
                    ),
                  ] else if (searched && foundCustomer == null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.bg(Colors.amber.shade50),
                        border: Border.all(color: context.line(Colors.amber.shade200)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const Text('Chưa có thông tin khách này trong hệ thống Trạm.'),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.person_add, size: 16),
                            label: const Text('Đăng Ký Khách Mới'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showRegisterCustomerDialog(phoneCtrl.text.trim());
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              if (foundCustomer != null)
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedCustomer = foundCustomer;
                      _pointsUsed = 0;
                    });
                    Navigator.pop(ctx);
                  },
                  child: const Text('Chọn Khách Này'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showRegisterCustomerDialog(String phone) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: phone);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Đăng Ký Thành Viên Trạm', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Họ và tên khách *', prefixIcon: Icon(Icons.person)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Số điện thoại *', prefixIcon: Icon(Icons.phone)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final p = phoneCtrl.text.trim();
              if (name.isEmpty || p.isEmpty) return;
              final newCust = KmtCustomerModel(
                id: 'CUST_${DateTime.now().millisecondsSinceEpoch}',
                fullName: name,
                phone: p,
                currentPoints: 0,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              );
              await _fb.saveCustomer(newCust);
              setState(() {
                _selectedCustomer = newCust;
                _pointsUsed = 0;
              });
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã tạo thành viên: $name!')),
                );
              }
            },
            child: const Text('Lưu & Chọn'),
          ),
        ],
      ),
    );
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
  Future<void> _showEditItemNoteAndToppingDialog(int index) async {
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

    final Map<String, ProductModel?> toppingItemMap = {};
    final List<String> availableToppingNames = [];

    if (matchedCategory != null && matchedCategory.allowedToppingIds.isNotEmpty) {
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
    for (final top in item.selectedToppings) {
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
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          int calcToppingPrice = 0;
          for (final topName in selectedToppings) {
            calcToppingPrice += toppingItemMap[topName]?.price ?? 5000;
          }
          final int unitPrice = item.price + sizeExtra + calcToppingPrice;
          final int totalPrice = unitPrice * item.quantity;

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                      Text(
                        FormatUtils.vnd(unitPrice),
                        style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold, color: context.tc.primary),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

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

                  // 3. TOPPINGS
                  if (availableToppingNames.isNotEmpty) ...[
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
                    final presets = _backendNotePresets.isNotEmpty
                        ? _backendNotePresets
                        : const ['Ít ngọt', 'Nhiều đá', 'Không đá', 'Ít đá', 'Để riêng đá', 'Mang về', 'Ít đường', 'Uống nóng'];
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

                  // 5. SAVE BUTTON
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.tc.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () async {
                        setState(() {
                          _cart[index] = _cart[index].copyWith(
                            note: noteCtrl.text.trim(),
                            selectedToppings: selectedToppings,
                            toppingPrice: calcToppingPrice,
                            selectedSize: selectedSize,
                            sizeExtraPrice: sizeExtra,
                            selectedSugar: isDrinkOrTea ? selectedSugar : '',
                            selectedIce: isDrinkOrTea ? selectedIce : '',
                          );
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
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showUsePointsDialog() {
    if (_selectedCustomer == null || _selectedCustomer!.currentPoints <= 0) return;
    final availableAmount = _subTotal - _itemDiscountTotal - _voucherDiscountTotal;
    final maxPointsPossible = availableAmount > 0 ? (availableAmount ~/ _pointRedeemRate) : 0;
    final maxUsable = _selectedCustomer!.currentPoints < maxPointsPossible
        ? _selectedCustomer!.currentPoints
        : maxPointsPossible;

    final pointsCtrl = TextEditingController(text: '$_pointsUsed');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dùng Điểm Tích Lũy', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách: ${_selectedCustomer!.fullName} (Có: ${_selectedCustomer!.currentPoints} điểm)', style: const TextStyle(fontWeight: FontWeight.w600)),
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
    final voucherCtrl = TextEditingController();
    final manualValueCtrl = TextEditingController();
    String manualType = 'PERCENT';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final allowStack = _storeInfo?.allowStackPromotions ?? true;

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
                            final code = voucherCtrl.text.trim().toUpperCase();
                            if (code.isEmpty) return;

                            PromotionModel? promo = _allPromotions.where((p) => p.code == code && p.isActive).firstOrNull;
                            CampaignModel? campaign;

                            if (promo == null) {
                              try {
                                final voucher = await CampaignService().lookupVoucherByCode(code);
                                if (voucher != null) {
                                  if (!voucher.isUsable) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Mã voucher này ${voucher.state == "REDEEMED" ? "đã được sử dụng" : "không khả dụng"}!')),
                                      );
                                    }
                                    return;
                                  }
                                  campaign = await CampaignService().getCampaign(voucher.campaignId);
                                  if (campaign != null && campaign.active) {
                                    // Kiểm tra thời gian & khung giờ
                                    if (!campaign.isEligibleAt(DateTime.now().millisecondsSinceEpoch)) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Khuyến mãi hiện không trong khung giờ hoặc ngày áp dụng!')),
                                        );
                                      }
                                      return;
                                    }
                                    // Kiểm tra chi nhánh
                                    if (!campaign.isEligibleForBranch(_fb.currentStoreCode)) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Khuyến mãi không áp dụng tại chi nhánh này!')),
                                        );
                                      }
                                      return;
                                    }
                                    promo = PromotionMigration.toLegacy(campaign).copyWith(
                                      code: code,
                                    );
                                  }
                                }
                              } catch (e) {
                                debugPrint('Error looking up voucher: $e');
                              }
                            }

                            if (promo == null) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Mã voucher không tồn tại hoặc đã hết hạn!')),
                                );
                              }
                              return;
                            }
                            if (!promo.isValid(_subTotal)) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Đơn hàng chưa đạt điều kiện tối thiểu ${FormatUtils.vnd(promo.minBillAmount)}!')),
                                );
                              }
                              return;
                            }

                            // Bắt buộc nhân viên nhập ghi chú nếu requireStaffNote = true
                            String? staffNote;
                            if (campaign?.requireStaffNote == true || promo.requireStaffNote == true) {
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
                              _appliedDiscounts.removeWhere((d) => d.promoCode == code || d.promoId == promo!.id);
                              _appliedDiscounts.add(BillDiscountModel(
                                promoId: promo!.id,
                                promoCode: code,
                                description: promo.name,
                                amount: amt,
                                staffNote: staffNote,
                              ));
                            });
                            voucherCtrl.clear();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Đã áp dụng mã $code: -${FormatUtils.vnd(amt)}')),
                              );
                            }
                          },
                          child: const Text('Áp Dụng'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Available list of promos
                    Text('Chương trình khuyến mãi khả dụng:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 8),
                    ..._allPromotions.where((p) => p.isActive).map((p) {
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

                    // Manual Discount
                    if (_auth.can(AppPermissions.manualDiscount)) ...[
                      const Divider(height: 24),
                      Text('Giảm giá thủ công (Bớt tiền):', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.accent)),
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
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget), backgroundColor: AppColors.accent),
                            onPressed: () {
                              final val = int.tryParse(manualValueCtrl.text.trim()) ?? 0;
                              if (val <= 0) return;
                              final amt = manualType == 'PERCENT' ? (_subTotal * val / 100).round() : val;
                              setDlgState(() {
                                if (!allowStack) _appliedDiscounts.clear();
                                _appliedDiscounts.add(BillDiscountModel(
                                  description: 'Bớt tiền thủ công (${manualType == "PERCENT" ? "$val%" : FormatUtils.vnd(val)})',
                                  amount: amt,
                                ));
                              });
                              manualValueCtrl.clear();
                            },
                            child: const Text('Bớt Tiền'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Xong')),
            ],
          );
        },
      ),
    );
    setState(() {});
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
          context.go('/tables');
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
          final qrUrl = VietQrGenerator.generateImageUrl(
            bankId: _storeInfo?.bankId ?? 'MB',
            bankAccount: _storeInfo?.bankAccount ?? '0987654321',
            accountName: _storeInfo?.accountName ?? 'CHU QUAN FNB',
            amount: effectiveQrAmount,
            orderInfo: '${_storeInfo?.storeCode ?? "TRAM"}_${widget.table.name}',
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
                final tableNameClean = widget.table.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
                final contentClean = content.replaceAll(RegExp(r'[^a-z0-9]'), '');
                final rawClean = rawText.replaceAll(RegExp(r'[^a-z0-9]'), '');
                final storeClean = (_storeInfo?.storeCode ?? 'tram').toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

                // Khớp bàn nếu trong content hoặc rawText chứa tên bàn (VD: "a1", "ban_a1") hoặc mã chi nhánh ("tram01")
                final textHasTable = tableNameClean.isNotEmpty && (contentClean.contains(tableNameClean) || rawClean.contains(tableNameClean));
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
                    ),
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
                            VietQrImage(url: qrUrl, height: 220),
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
                              VietQrImage(url: qrUrl, height: 180),
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

                    // Action Buttons: In tạm tính & Thanh toán
                    Row(
                      children: [
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
                                final bytes = ReceiptPrinter.buildBillReceiptBytes(
                                  store: _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm'),
                                  bill: bill,
                                  isPrePrint: true,
                                );
                                ReceiptPrinter.printViaLan(
                                  printerIp: _storeInfo?.billPrinterIp ?? '',
                                  data: bytes,
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
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle_outline, color: Colors.white, size: 22),
                                      SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          'XÁC NHẬN THU TIỀN',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
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

    // 3. In hóa đơn ra máy in nhiệt LAN (nếu bật in bill và có cấu hình IP máy in)
    if (shouldPrint) {
      final store = _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm');
      if (store.billPrinterIp.isNotEmpty) {
        try {
          final bytes = ReceiptPrinter.buildBillReceiptBytes(store: store, bill: bill, isPrePrint: false);
          ReceiptPrinter.printViaLan(
            printerIp: store.billPrinterIp,
            data: bytes,
          ).catchError((_) => false);
        } catch (_) {}
      }
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  customer: _selectedCustomer,
                  pointsUsed: _pointsUsed,
                  onLookup: _showCustomerLookupDialog,
                  onUsePoints: _showUsePointsDialog,
                  onClear: () => setState(() {
                    _selectedCustomer = null;
                    _pointsUsed = 0;
                  }),
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
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                        itemCount: _cart.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => CartItemCard(
                          item: _cart[index],
                          onRemove: () => _confirmRemoveItem(index),
                          onEditNote: () => _showEditItemNoteAndToppingDialog(index),
                          onDiscount: () => _showItemDiscountDialog(index),
                          onIncrement: () => _incrementItem(index),
                          onDecrement: () => _decrementItem(index),
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
                      onAddItems: _goToAddItems,
                    ),
                    Expanded(child: cartList),
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
      final bytes = ReceiptPrinter.buildBillReceiptBytes(
        store: _storeInfo ?? StoreInfoModel(storeCode: 'TRAM01', storeName: 'POS Trạm'),
        bill: bill,
        isPrePrint: true,
      );
      ReceiptPrinter.printViaLan(
        printerIp: _storeInfo?.billPrinterIp ?? '',
        data: bytes,
      ).catchError((_) => false);
    }).catchError((_) {});
  }
}
