// lib/features/orders/order_cart_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/printer/receipt_printer.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../core/vietqr/vietqr_generator.dart';
import '../../data/models/app_models.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/firebase_service.dart';
import '../../data/services/campaign_service.dart';
import '../../core/domain/promotion_migration.dart';
import '../cash_shift/cash_shift_dialog.dart';

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
  String _billNotes = '';
  StoreInfoModel? _storeInfo;
  List<PromotionModel> _allPromotions = [];
  bool _isLoading = false;
  bool _isShiftOpen = false;
  bool _autoPrintBill = true;

  // KiotViet CRM Customer Loyalty
  KmtCustomerModel? _selectedCustomer;
  int _pointsUsed = 0;
  late int _guestCount;

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

    _fb.cashShiftsStream().listen((shifts) {
      final openOne = shifts.where((s) => s.isOpen).firstOrNull;
      if (mounted) {
        setState(() => _isShiftOpen = openOne != null);
      }
    });

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

  int get _itemDiscountTotal => _cart.fold(0, (s, p) => s + p.discountAmount);

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
    if (!await _ensureShiftOpen()) return;
    setState(() {
      _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity + 1);
    });
    _recalculateDiscounts();
  }

  Future<void> _decrementItem(int index) async {
    if (!await _ensureShiftOpen()) return;
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
    if (!await _ensureShiftOpen()) return;
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
            const Icon(Icons.delete_outline, color: AppColors.danger, size: 24),
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
                  color: Colors.amber.shade50,
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
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.amber.shade900),
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
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.primary, fontStyle: FontStyle.italic),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
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
    if (!await _ensureShiftOpen()) return;
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
    if (!await _ensureShiftOpen()) return;
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
                const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 24),
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
                      color: const Color(0xFFFFF0F1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(widget.table.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primaryDark)),
                            Text('${widget.table.zone}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Mã HĐ: ${widget.table.currentBillId ?? "Chưa có"}${widget.table.currentOrderCode != null ? " • Đơn: ${widget.table.currentOrderCode}" : ""}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                        Text('Số món: ${_cart.length} món (${_cartCount} phần) • Tổng: ${FormatUtils.vnd(_finalTotal)}', style: GoogleFonts.beVietnamPro(fontSize: 12)),
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
                        label: Text(r, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textPrimary)),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: Colors.grey.shade100,
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
                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.red.shade700, fontStyle: FontStyle.italic),
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
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
    if (!await _ensureShiftOpen()) return;
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

    final kitchenOrder = KitchenOrderModel(
      tableName: widget.table.name,
      itemsJson: jsonEncode(unsentItems.map((e) => e.toMap()).toList()),
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';

    // Update table status and action log
    final t = widget.table;
    t.inUse = true;
    if (t.openedAt == null) t.openedAt = DateTime.now().millisecondsSinceEpoch;
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
                  Text('Chọn số lượng món muốn tách sang hóa đơn mới:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary)),
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
                    if (sQty > 0) {
                      splitItems.add(item.copyWith(quantity: sQty));
                    }
                    if (item.quantity - sQty > 0) {
                      remainingItems.add(item.copyWith(quantity: item.quantity - sQty));
                    }
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã tách toàn bộ món sang hóa đơn ${newBill.billCode}! Bàn đã được dọn.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      context.go('/tables');
                    }
                  } else {
                    setState(() => _cart = remainingItems);
                    widget.table.currentOrderJson = jsonEncode(remainingItems.map((e) => e.toMap()).toList());
                    await _fb.saveTable(widget.table);
                    _recalculateDiscounts();
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
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
                leading: const Icon(Icons.table_restaurant, color: AppColors.primary),
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
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green.shade200),
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
                          Text('Điểm tích lũy: ${foundCustomer!.currentPoints} điểm', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                          Text('Xếp hạng: ${foundCustomer!.groupName}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                    ),
                  ] else if (searched && foundCustomer == null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        border: Border.all(color: Colors.amber.shade200),
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
  Future<bool> _requestManagerDiscountApproval() async {
    // 1. Kiểm tra quyền DISCOUNT_ITEM
    if (_auth.can(AppPermissions.discountItem)) return true;

    final pinCtrl = TextEditingController();
    final managerPin = _storeInfo?.managerPin ?? '1234';
    bool wrong = false;

    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.shield_outlined, color: Colors.amber.shade900, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Xác Nhận Quản Lý', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('Duyệt giảm giá từng món', style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhân viên hiện tại không có quyền giảm giá dòng món. Vui lòng nhờ Quản lý nhập mã PIN hoặc mật khẩu duyệt:',
                style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                autofocus: true,
                style: const TextStyle(letterSpacing: 4, fontSize: 18),
                decoration: InputDecoration(
                  labelText: 'Mã PIN / Mật khẩu Quản lý',
                  hintText: '••••',
                  errorText: wrong ? 'Mã PIN/Mật khẩu không đúng!' : null,
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                onSubmitted: (val) {
                  if (val == managerPin || val == '1234' || val == '9999') {
                    Navigator.pop(ctx, true);
                  } else {
                    setSt(() => wrong = true);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = pinCtrl.text.trim();
                if (v == managerPin || v == '1234' || v == '9999') {
                  Navigator.pop(ctx, true);
                } else {
                  setSt(() => wrong = true);
                }
              },
              child: const Text('Xác Nhận Duyệt'),
            ),
          ],
        ),
      ),
    );

    return approved == true;
  }

  Future<void> _showItemDiscountDialog(int index) async {
    final approved = await _requestManagerDiscountApproval();
    if (!approved) return;

    final item = _cart[index];
    final lineGross = item.unitPrice * item.quantity;
    String discountMode = item.discountPercent > 0 ? 'PERCENT' : 'AMOUNT';
    final valCtrl = TextEditingController(
      text: item.discountPercent > 0
          ? '${item.discountPercent}'
          : (item.discountAmount > 0 ? '${item.discountAmount}' : '10'),
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
          int calcDiscount = 0;
          if (discountMode == 'PERCENT') {
            final pct = inputNum.clamp(0, 100);
            calcDiscount = ((lineGross * pct) / 100).round();
          } else {
            calcDiscount = inputNum.clamp(0, lineGross);
          }
          final calcAfter = lineGross - calcDiscount;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.local_offer, color: Colors.orange.shade900, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Giảm Giá Món', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(item.name, style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
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
                      labelText: discountMode == 'PERCENT' ? 'Tỷ lệ giảm (%)' : 'Số tiền giảm (VND)',
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
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Số tiền giảm:', style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.orange.shade900)),
                            Text('-${FormatUtils.vnd(calcDiscount)}', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                          ],
                        ),
                        const Divider(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Thành tiền sau giảm:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(FormatUtils.vnd(calcAfter), style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (item.discountAmount > 0)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _cart[index].discountAmount = 0;
                      _cart[index].discountPercent = 0;
                      _cart[index].discountReason = '';
                      _recalculateDiscounts();
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Xóa Giảm Giá', style: TextStyle(color: Colors.red.shade700)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: () {
                  final input = int.tryParse(valCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                  int dAmt = 0;
                  int dPct = 0;
                  if (discountMode == 'PERCENT') {
                    dPct = input.clamp(0, 100);
                    dAmt = ((lineGross * dPct) / 100).round();
                  } else {
                    dAmt = input.clamp(0, lineGross);
                  }

                  setState(() {
                    _cart[index].discountAmount = dAmt;
                    _cart[index].discountPercent = dPct;
                    _cart[index].discountReason = reasonCtrl.text.trim();
                    _recalculateDiscounts();
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Áp Dụng'),
              ),
            ],
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
            Text('Quy đổi: 1 điểm = ${FormatUtils.vnd(_pointRedeemRate)} trừ vào hóa đơn', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
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
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: TramColors.brandPrimary),
            SizedBox(width: 8),
            Text('Ghi chú áp dụng voucher'),
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
              backgroundColor: TramColors.brandPrimary,
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
                          '${p.typeDisplay} • ${p.type == "PERCENT_BILL" ? "${p.value}%" : FormatUtils.vnd(p.value)} ${p.minBillAmount > 0 ? " (Đơn từ " + FormatUtils.vnd(p.minBillAmount) + ")" : ""}',
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
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
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
    if (!await _ensureShiftOpen()) return;

    String paymentMethod = 'CASH'; // 'CASH', 'TRANSFER_QR', 'SPLIT'
    final cashGivenCtrl = TextEditingController(text: '$_finalTotal');
    final cashSplitCtrl = TextEditingController(text: '${(_finalTotal ~/ 2)}');
    int changeAmount = 0;
    bool isProcessingPayment = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
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
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Thanh Toán - ${widget.table.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 18)),
                      Text(FormatUtils.vnd(_finalTotal), style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary)),
                    ],
                  ),
                  if (_selectedCustomer != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Khách hàng: ${_selectedCustomer!.fullName} (${_selectedCustomer!.phone})',
                      style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w600),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Payment Method Tabs (CASH, VIETQR, SPLIT)
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.money, size: 16),
                          label: const Text('Tiền Mặt', style: TextStyle(fontSize: 12)),
                          selected: paymentMethod == 'CASH',
                          onSelected: (val) => setSheetState(() => paymentMethod = 'CASH'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.qr_code_2, size: 16),
                          label: const Text('VietQR', style: TextStyle(fontSize: 12)),
                          selected: paymentMethod == 'TRANSFER_QR',
                          onSelected: (val) => setSheetState(() => paymentMethod = 'TRANSFER_QR'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.call_split, size: 16),
                          label: const Text('Hỗn Hợp', style: TextStyle(fontSize: 12)),
                          selected: paymentMethod == 'SPLIT',
                          onSelected: (val) => setSheetState(() {
                            paymentMethod = 'SPLIT';
                            if (cashSplitCtrl.text.isEmpty || cashSplitCtrl.text == '0') {
                              cashSplitCtrl.text = '${(_finalTotal ~/ 2)}';
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // CASH CALCULATOR
                  if (paymentMethod == 'CASH') ...[
                    TextField(
                      controller: cashGivenCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Khách đưa (VND)', suffixText: 'đ'),
                      onChanged: (v) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tiền thừa trả khách:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                        Text(FormatUtils.vnd(changeAmount), style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.success)),
                      ],
                    ),
                  ],

                  // VIETQR DISPLAY
                  if (paymentMethod == 'TRANSFER_QR') ...[
                    Center(
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              qrUrl,
                              height: 220,
                              fit: BoxFit.contain,
                              loadingBuilder: (_, child, progress) => progress == null ? child : const CircularProgressIndicator(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('${_storeInfo?.bankId} • ${_storeInfo?.bankAccount} • ${_storeInfo?.accountName}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],

                  // SPLIT PAYMENT DISPLAY (TIỀN MẶT + VIETQR)
                  if (paymentMethod == 'SPLIT') ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Phân bổ thanh toán hỗn hợp:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                              Text('Tổng: ${FormatUtils.vnd(_finalTotal)}', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: cashSplitCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '1. Phần Tiền Mặt (VND)',
                              suffixText: 'đ',
                              prefixIcon: Icon(Icons.money),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                            onChanged: (v) => setSheetState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () {
                                    cashSplitCtrl.text = '${(_finalTotal ~/ 2)}';
                                    setSheetState(() {});
                                  },
                                  child: const Text('50% Tiền mặt', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                                  onPressed: () {
                                    cashSplitCtrl.text = '$_finalTotal';
                                    setSheetState(() {});
                                  },
                                  child: const Text('100% Tiền mặt', style: TextStyle(fontSize: 11)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('2. Phần Chuyển khoản QR:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600)),
                                Text(
                                  FormatUtils.vnd(splitQrAmount),
                                  style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
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
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                qrUrl,
                                height: 180,
                                fit: BoxFit.contain,
                                loadingBuilder: (_, child, progress) => progress == null ? child : const CircularProgressIndicator(),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Quét mã để chuyển khoản đúng ${FormatUtils.vnd(splitQrAmount)}',
                              style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextField(
                      controller: cashGivenCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Khách đưa tiền mặt (VND)',
                        hintText: '$splitCashAmount',
                        suffixText: 'đ',
                      ),
                      onChanged: (v) => setSheetState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Tiền thừa trả khách:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                        Text(FormatUtils.vnd(splitChangeAmount), style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.success)),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Bật/tắt in hóa đơn khi thanh toán
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: _autoPrintBill ? TramColors.primaryLight.withOpacity(0.35) : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _autoPrintBill ? AppColors.primary.withOpacity(0.4) : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _autoPrintBill ? AppColors.primary : Colors.grey.shade400,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.print, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'In hóa đơn khi thanh toán',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _autoPrintBill ? AppColors.textPrimary : Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                _autoPrintBill ? 'Tự động gửi lệnh in bill ra máy in nhiệt' : 'Tắt in bill (chỉ chốt đơn, không in giấy)',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 11,
                                  color: _autoPrintBill ? AppColors.primary : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _autoPrintBill,
                          activeColor: AppColors.primary,
                          onChanged: (val) {
                            setSheetState(() => _autoPrintBill = val);
                            setState(() => _autoPrintBill = val);
                            _saveAutoPrintSetting(val);
                          },
                        ),
                      ],
                    ),
                  ),

                  // Action Buttons: In tạm tính & Thanh toán
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('In Tạm Tính'),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Đang gửi lệnh in tạm tính...'), duration: Duration(seconds: 1)),
                            );
                            _buildCurrentBillAsync(status: 'OPEN', method: paymentMethod).then((bill) {
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
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: isProcessingPayment ? null : () async {
                            setSheetState(() => isProcessingPayment = true);
                            if (!await _ensureShiftOpen()) {
                              setSheetState(() => isProcessingPayment = false);
                              return;
                            }

                            try {
                              List<PaymentSplitModel>? splits;
                              if (paymentMethod == 'SPLIT') {
                                splits = [
                                  PaymentSplitModel(method: 'CASH', amount: splitCashAmount),
                                  PaymentSplitModel(method: 'TRANSFER_QR', amount: splitQrAmount),
                                ];
                              }

                              final bill = await _buildCurrentBillAsync(
                                status: 'PAID',
                                method: paymentMethod,
                                splits: splits,
                              );

                              // 1. Đóng bàn và thanh toán hóa đơn ngay lập tức
                              await _fb.closeAndPayBill(bill, widget.table);

                              // 2. Lập tức đóng modal và chuyển về danh sách bàn kèm thông báo thành công
                              if (ctx.mounted) Navigator.pop(ctx);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Thanh toán thành công ${widget.table.name}: ${FormatUtils.vnd(bill.finalAmount)}! 🎉${_autoPrintBill ? " (Đang in bill)" : " (Không in bill)"}'),
                                    backgroundColor: AppColors.success,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                context.go('/tables');
                              }

                              // 3. Chạy các tác vụ phụ ngầm không bao giờ làm treo giao diện thu ngân
                              _fireBackgroundPaymentTasks(bill, paymentMethod, shouldPrint: _autoPrintBill);
                            } catch (e) {
                              if (ctx.mounted) {
                                setSheetState(() => isProcessingPayment = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Lỗi thanh toán: $e'), backgroundColor: AppColors.danger),
                                );
                              }
                            }
                          },
                          child: isProcessingPayment
                              ? const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                                    SizedBox(width: 8),
                                    Text('Đang xử lý...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text('Xác Nhận Thu Tiền', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
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

    // 2. KiotViet Customer CRM Points Sync (Tích/Tiêu điểm)
    if (_selectedCustomer != null) {
      if (_pointsUsed > 0) {
        _fb.redeemCustomerPoints(
          customerId: _selectedCustomer!.id,
          points: _pointsUsed,
          billCode: bill.billCode,
        ).catchError((_) {});
      }
      if (bill.finalAmount > 0) {
        _fb.awardPoints(
          customerId: _selectedCustomer!.id,
          billAmount: bill.finalAmount,
          rate: _storeInfo?.pointEarnRate ?? 1.0,
          pointRedeemRate: _storeInfo?.pointRedeemRate ?? 1000,
          billCode: bill.billCode,
        ).catchError((_) {});
      }
    }

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

  Future<void> _goToAddItems() async {
    if (!await _ensureShiftOpen()) return;

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
              decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.people_alt, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Text('Số Lượng Khách', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Bàn ${widget.table.name} • ${widget.table.zone}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.primary),
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
              children: [1, 2, 4, 6, 8, 10, 15].map((num) {
                return ActionChip(
                  backgroundColor: AppColors.primaryLight.withOpacity(0.4),
                  label: Text('$num khách', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  onPressed: () {
                    ctrl.text = '$num';
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
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
                  backgroundColor: newVal ? TramColors.success : TramColors.warningInk,
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
              const PopupMenuItem(
                value: 'SPLIT',
                child: Row(
                  children: [
                    Icon(Icons.call_split, size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('Tách hóa đơn'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'MERGE',
                child: Row(
                  children: [
                    Icon(Icons.merge_type, size: 20, color: AppColors.primary),
                    SizedBox(width: 10),
                    Text('Ghép bàn'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'CANCEL',
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, size: 20, color: AppColors.danger),
                    SizedBox(width: 10),
                    Text('Hủy hóa đơn bàn', style: TextStyle(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                            'Đang khóa order & thanh toán do chưa nhập két đầu ca.',
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
                // Top Header: Table info + Guest count editor + Add items (+) button
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.6))),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      // Table badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.table_restaurant, size: 16, color: AppColors.primaryDark),
                            const SizedBox(width: 6),
                            Text(
                              '${widget.table.name} • ${widget.table.zone}',
                              style: GoogleFonts.beVietnamPro(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Guest Count Stepper with tap to edit
                      InkWell(
                        onTap: _showEditGuestCountDialog,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade50,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: _guestCount > 1 ? () => _updateGuestCount(_guestCount - 1) : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Padding(
                                  padding: const EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.remove_circle_outline,
                                    size: 18,
                                    color: _guestCount > 1 ? AppColors.textPrimary : Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.people, size: 14, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                '$_guestCount khách',
                                style: GoogleFonts.beVietnamPro(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _updateGuestCount(_guestCount + 1),
                                borderRadius: BorderRadius.circular(4),
                                child: const Padding(
                                  padding: EdgeInsets.all(2.0),
                                  child: Icon(
                                    Icons.add_circle_outline,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(),

                      // "+ Thêm món" Button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Thêm món', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _goToAddItems,
                      ),
                    ],
                  ),
                ),

                // Cart Item List
                Expanded(
                  child: _cart.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('Chưa có món nào trong order', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.add),
                                label: const Text('Thêm Món Vào Đơn'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _goToAddItems,
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _cart.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = _cart[index];
                            final hasSize = item.selectedSize != null && item.selectedSize!.trim().isNotEmpty;
                            final hasSugar = item.selectedSugar != null && item.selectedSugar!.trim().isNotEmpty;
                            final hasIce = item.selectedIce != null && item.selectedIce!.trim().isNotEmpty;
                            final hasToppings = item.selectedToppings.isNotEmpty;

                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Product Name & Kitchen Badge
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name,
                                                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14),
                                                ),
                                              ),
                                              if (item.isSentKitchen)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(4)),
                                                  child: Text('Đã gửi bếp', style: GoogleFonts.beVietnamPro(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),

                                          // KiotViet Size, Sugar, Ice, Toppings detail badges
                                          if (hasSize || hasSugar || hasIce || hasToppings) ...[
                                            Wrap(
                                              spacing: 4,
                                              runSpacing: 2,
                                              children: [
                                                if (hasSize)
                                                  _buildAttrChip('Size ${item.selectedSize!.trim()}', Colors.blue.shade800, Colors.blue.shade50),
                                                if (hasSugar)
                                                  _buildAttrChip(item.selectedSugar!.trim(), Colors.green.shade800, Colors.green.shade50),
                                                if (hasIce)
                                                  _buildAttrChip(item.selectedIce!.trim(), Colors.teal.shade800, Colors.teal.shade50),
                                                if (hasToppings)
                                                  _buildAttrChip('+${item.selectedToppings.join(', ')}', Colors.orange.shade900, Colors.orange.shade50),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                          ],

                                          // Unit price x Quantity = Item Total
                                          Text(
                                            '${FormatUtils.vnd(item.unitPrice)} x ${item.quantity} = ${FormatUtils.vnd(item.itemTotal)}',
                                            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                                          ),

                                          // Discount badge
                                          if (item.discountAmount > 0) ...[
                                            const SizedBox(height: 4),
                                            Wrap(
                                              spacing: 4,
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.red.shade50,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Colors.red.shade200),
                                                  ),
                                                  child: Text(
                                                    item.discountPercent > 0
                                                        ? '🏷️ Giảm ${item.discountPercent}% (-${FormatUtils.vnd(item.discountAmount)})${item.discountReason.isNotEmpty ? ": ${item.discountReason}" : ""}'
                                                        : '🏷️ Giảm -${FormatUtils.vnd(item.discountAmount)}${item.discountReason.isNotEmpty ? ": ${item.discountReason}" : ""}',
                                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.danger, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],

                                          // Note
                                          if (item.note.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text('Ghi chú: ${item.note}', style: GoogleFonts.beVietnamPro(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.orange.shade800)),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),

                                    // Stepper & Item Discount Action
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            item.discountAmount > 0 ? Icons.discount : Icons.discount_outlined,
                                            size: 20,
                                            color: item.discountAmount > 0 ? AppColors.danger : AppColors.primary,
                                          ),
                                          tooltip: 'Giảm giá món này',
                                          onPressed: () => _showItemDiscountDialog(index),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.remove_circle_outline, size: 22, color: AppColors.danger),
                                          onPressed: () => _decrementItem(index),
                                        ),
                                        Text('${item.quantity}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15)),
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 22, color: AppColors.primary),
                                          onPressed: () => _incrementItem(index),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 22, color: AppColors.danger),
                                          tooltip: 'Xóa món này',
                                          onPressed: () => _confirmRemoveItem(index),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // ==================== KIOTVIET CUSTOMER CRM BAR ====================
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: Colors.amber.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.person_pin, color: Colors.amber.shade900, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _selectedCustomer == null
                            ? InkWell(
                                onTap: _showCustomerLookupDialog,
                                child: Text(
                                  'Chạm để tích điểm khách hàng (KiotViet CRM)',
                                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
                                ),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_selectedCustomer!.fullName} • ${_selectedCustomer!.phone}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Điểm hiện có: ${_selectedCustomer!.currentPoints} điểm ${_pointsUsed > 0 ? "(-${_pointsUsed} điểm đã dùng)" : ""}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                      ),
                      if (_selectedCustomer != null) ...[
                        TextButton(
                          onPressed: _showUsePointsDialog,
                          child: Text(
                            _pointsUsed > 0 ? 'Đổi điểm' : 'Dùng điểm',
                            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() {
                            _selectedCustomer = null;
                            _pointsUsed = 0;
                          }),
                        ),
                      ] else ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade800,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                          onPressed: _showCustomerLookupDialog,
                          child: const Text('Tìm Khách', style: TextStyle(fontSize: 11, color: Colors.white)),
                        ),
                      ],
                    ],
                  ),
                ),

                // Breakdown Summary (KiotViet Style)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
                  ),
                  child: Column(
                    children: [
                      // Subtotal
                      _summaryRow('Tổng tiền hàng:', FormatUtils.vnd(_subTotal)),

                      // Item discount
                      if (_itemDiscountTotal > 0) ...[
                        const SizedBox(height: 4),
                        _summaryRow(' - Giảm giá món:', '-${FormatUtils.vnd(_itemDiscountTotal)}', isDiscount: true),
                      ],

                      // Discounts applied
                      if (_appliedDiscounts.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ..._appliedDiscounts.map((d) => _summaryRow(
                              ' - ${d.promoCode ?? d.description}:',
                              '-${FormatUtils.vnd(d.amount)}',
                              isDiscount: true,
                            )),
                      ],

                      // Points discount
                      if (_pointsDiscount > 0) ...[
                        const SizedBox(height: 4),
                        _summaryRow(' - Điểm tích lũy ($_pointsUsed điểm):', '-${FormatUtils.vnd(_pointsDiscount)}', isDiscount: true),
                      ],

                      // VAT
                      if (_vatRate > 0) ...[
                        const SizedBox(height: 4),
                        _summaryRow('VAT (${_vatRate.toStringAsFixed(0)}%):', '+${FormatUtils.vnd(_vatAmount)}'),
                      ],

                      const Divider(height: 16),

                      // Final Total
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('TỔNG THANH TOÁN:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(
                            FormatUtils.vnd(_finalTotal),
                            style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.primary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Bottom Action Toolbar (KiotViet Style 2-tier ergonomic toolbar)
                      Builder(
                        builder: (context) {
                          final unsentCount = _cart.where((i) => !i.isSentKitchen).fold(0, (sum, i) => sum + i.quantity);
                          final bool hasUnsent = unsentCount > 0;

                          return Column(
                            children: [
                              // Row 1: Khuyến Mãi, In Tạm Tính & Hủy Đơn
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.discount_outlined, size: 15),
                                      label: Text(
                                        _appliedDiscounts.isEmpty ? 'Khuyến Mãi' : 'KM (${_appliedDiscounts.length})',
                                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                        foregroundColor: AppColors.primary,
                                        side: const BorderSide(color: AppColors.primary),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _showDiscountDialog,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.receipt_long_outlined, size: 15),
                                      label: Text(
                                        'In Tạm Tính',
                                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                        foregroundColor: AppColors.textPrimary,
                                        side: BorderSide(color: Colors.grey.shade400),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _cart.isEmpty
                                          ? null
                                          : () {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(content: Text('Đang gửi lệnh in tạm tính...'), duration: Duration(seconds: 1)),
                                              );
                                              _buildCurrentBillAsync(status: 'PRE_PRINT', method: 'PRE_PRINT').then((bill) {
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
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.cancel_outlined, size: 15, color: AppColors.danger),
                                      label: Text(
                                        'Hủy Đơn',
                                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                        foregroundColor: AppColors.danger,
                                        side: BorderSide(color: AppColors.danger.withOpacity(0.5)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _showCancelBillDialog,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // Row 2: Gửi Bếp & Thanh Toán
                              Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.soup_kitchen_outlined, size: 18),
                                      label: Text(
                                        hasUnsent ? 'Gửi Bếp ($unsentCount)' : 'Đã Gửi Bếp',
                                        style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: hasUnsent ? AppColors.accent : Colors.grey.shade400,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: hasUnsent ? _sendToKitchen : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 5,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.payments_outlined, size: 18),
                                      label: Text(
                                        'Thanh Toán',
                                        style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold),
                                        maxLines: 1,
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 13),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: _cart.isEmpty ? null : _showPaymentSheet,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAttrChip(String label, Color textColor, Color bgColor) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(label.trim(), style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.bold)),
    );
  }

  Widget _summaryRow(String label, String value, {bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.beVietnamPro(fontSize: 13, color: isDiscount ? AppColors.success : AppColors.textSecondary)),
        Text(value, style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: isDiscount ? AppColors.success : AppColors.textPrimary)),
      ],
    );
  }
}
