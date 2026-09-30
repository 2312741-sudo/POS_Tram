// lib/features/orders/order_cart_screen.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class OrderCartScreen extends StatefulWidget {
  final TableModel table;
  final List<ProductModel> initialProducts;

  const OrderCartScreen({super.key, required this.table, this.initialProducts = const []});

  @override
  State<OrderCartScreen> createState() => _OrderCartScreenState();
}

class _OrderCartScreenState extends State<OrderCartScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  late List<ProductModel> _cart;
  bool _kitchenSent = false; // Anti-cheat: once sent to kitchen, prices locked

  // Settings
  String _kitchenPrinterIp = AppConstants.defaultPrinterIp;
  String _billPrinterIp = AppConstants.defaultPrinterIp;
  String _bankId = AppConstants.defaultBankId;
  String _bankAccount = AppConstants.defaultBankAccount;
  String _accountName = AppConstants.defaultAccountName;
  String _managerPin = AppConstants.defaultManagerPin;

  @override
  void initState() {
    super.initState();
    _cart = List.from(widget.initialProducts);
    _kitchenSent = widget.table.inUse;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _kitchenPrinterIp = prefs.getString(AppConstants.prefKitchenPrinterIp) ?? AppConstants.defaultPrinterIp;
      _billPrinterIp = prefs.getString(AppConstants.prefBillPrinterIp) ?? AppConstants.defaultPrinterIp;
      _bankId = prefs.getString(AppConstants.prefBankId) ?? AppConstants.defaultBankId;
      _bankAccount = prefs.getString(AppConstants.prefBankAccount) ?? AppConstants.defaultBankAccount;
      _accountName = prefs.getString(AppConstants.prefAccountName) ?? AppConstants.defaultAccountName;
      _managerPin = prefs.getString(AppConstants.prefManagerPin) ?? AppConstants.defaultManagerPin;
    });
  }

  int get _total => _cart.fold(0, (s, p) => s + p.total);

  void _removeItem(int index) {
    setState(() => _cart.removeAt(index));
  }

  void _incrementItem(int index) {
    setState(() {
      _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity + 1);
    });
  }

  void _decrementItem(int index) {
    if (_cart[index].quantity <= 1) {
      _removeItem(index);
    } else {
      setState(() {
        _cart[index] = _cart[index].copyWith(quantity: _cart[index].quantity - 1);
      });
    }
  }

  Future<void> _sendToKitchen() async {
    if (_cart.isEmpty) return;
    
    final itemsJson = jsonEncode(_cart.map((p) => p.toMap()).toList());
    final kitchenOrder = KitchenOrderModel(
      tableName: widget.table.name,
      itemsJson: itemsJson,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    
    // Save to Firebase
    await _fb.sendKitchenOrder(kitchenOrder);
    
    // Update table status
    final table = widget.table;
    table.inUse = true;
    table.currentOrderJson = itemsJson;
    await _fb.saveTable(table);
    
    // Audit log
    await _fb.logAction(AuditLogModel(
      action: AppConstants.actionSendKitchen,
      username: _auth.currentUser?.username ?? '',
      userRole: _auth.currentUser?.role ?? '',
      timestamp: DateTime.now().millisecondsSinceEpoch,
      details: 'Gửi bếp bàn ${widget.table.name}, ${_cart.length} món',
    ));

    setState(() => _kitchenSent = true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Đã gửi bếp thành công! 🍽️',
          style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      context.go('/tables');
    }
  }

  Future<void> _showPaymentDialog() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaymentSheet(
        total: _total,
        tableName: widget.table.name,
        bankId: _bankId,
        bankAccount: _bankAccount,
        accountName: _accountName,
        managerPin: _managerPin,
        onConfirm: (method) async {
          // Save to Firebase history
          final history = OrderHistoryModel(
            orderCode: FormatUtils.orderCode(),
            tableName: widget.table.name,
            totalAmount: _total,
            itemsJson: jsonEncode(_cart.map((p) => p.toMap()).toList()),
            paymentMethod: method,
            timestamp: DateTime.now().millisecondsSinceEpoch,
            staffUsername: _auth.currentUser?.username,
          );
          
          await _fb.saveHistory(history);
          
          // Clear table
          final table = widget.table;
          table.inUse = false;
          table.currentOrderJson = '';
          await _fb.saveTable(table);
          
          // Audit log
          await _fb.logAction(AuditLogModel(
            action: AppConstants.actionPayment,
            username: _auth.currentUser?.username ?? '',
            userRole: _auth.currentUser?.role ?? '',
            timestamp: DateTime.now().millisecondsSinceEpoch,
            details: 'Thanh toán bàn ${widget.table.name}: ${FormatUtils.currency(_total)} ($method)',
            targetId: history.orderCode,
          ));

          if (mounted) context.go('/tables');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCartList()),
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: AppColors.surface,
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.card, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.arrow_back_ios_new, size: 14, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Đơn bàn ${widget.table.name}', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700,
                )),
                Text('${widget.table.zone} • ${_cart.length} loại món',
                  style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.push('/order-list', extra: widget.table),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, color: AppColors.primary, size: 16),
                  const SizedBox(width: 4),
                  Text('Thêm món', style: GoogleFonts.beVietnamPro(
                    color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shopping_cart_outlined, color: AppColors.textHint, size: 64),
            const SizedBox(height: 16),
            Text('Giỏ hàng trống', style: GoogleFonts.beVietnamPro(
              color: AppColors.textHint, fontSize: 16,
            )),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => context.push('/order-list', extra: widget.table),
              icon: const Icon(Icons.add),
              label: const Text('Chọn món'),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _cart.length,
      separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 1),
      itemBuilder: (_, i) => _CartItem(
        product: _cart[i],
        locked: _kitchenSent,
        onIncrement: () => _incrementItem(i),
        onDecrement: () => _decrementItem(i),
        onRemove: () => _removeItem(i),
      ).animate(delay: (i * 30).ms).fadeIn(duration: 200.ms),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tổng cộng', style: GoogleFonts.beVietnamPro(
                color: AppColors.textSecondary, fontSize: 14,
              )),
              Text(FormatUtils.currency(_total), style: GoogleFonts.beVietnamPro(
                color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w700,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _cart.isEmpty ? null : _sendToKitchen,
                  icon: const Icon(Icons.kitchen_outlined),
                  label: const Text('Gửi bếp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _cart.isEmpty ? null : _showPaymentDialog,
                  icon: const Icon(Icons.payment),
                  label: const Text('Thanh toán'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==================== CART ITEM ====================
class _CartItem extends StatelessWidget {
  final ProductModel product;
  final bool locked;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;

  const _CartItem({
    required this.product,
    required this.locked,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(product.name),
      direction: locked ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.danger.withOpacity(0.15),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      onDismissed: (_) => onRemove(),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: GoogleFonts.beVietnamPro(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14,
                  )),
                  const SizedBox(height: 4),
                  Text(FormatUtils.currency(product.price), style: GoogleFonts.beVietnamPro(
                    color: AppColors.textSecondary, fontSize: 13,
                  )),
                ],
              ),
            ),
            if (!locked) ...[
              Row(
                children: [
                  _CtrlBtn(icon: Icons.remove, onTap: onDecrement),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('${product.quantity}', style: GoogleFonts.beVietnamPro(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16,
                    )),
                  ),
                  _CtrlBtn(icon: Icons.add, onTap: onIncrement, isPrimary: true),
                ],
              ),
            ] else
              Text('x${product.quantity}', style: GoogleFonts.beVietnamPro(
                color: AppColors.textSecondary, fontSize: 15, fontWeight: FontWeight.w600,
              )),
            const SizedBox(width: 12),
            Text(FormatUtils.currency(product.total), style: GoogleFonts.beVietnamPro(
              color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14,
            )),
          ],
        ),
      ),
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;
  const _CtrlBtn({required this.icon, required this.onTap, this.isPrimary = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primary : AppColors.cardElevated,
          borderRadius: BorderRadius.circular(8),
          border: isPrimary ? null : Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: isPrimary ? Colors.white : AppColors.textPrimary, size: 16),
      ),
    );
  }
}

// ==================== PAYMENT SHEET ====================
class _PaymentSheet extends StatefulWidget {
  final int total;
  final String tableName;
  final String bankId, bankAccount, accountName, managerPin;
  final Future<void> Function(String method) onConfirm;

  const _PaymentSheet({
    required this.total,
    required this.tableName,
    required this.bankId,
    required this.bankAccount,
    required this.accountName,
    required this.managerPin,
    required this.onConfirm,
  });

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  int _method = 0; // 0=cash, 1=transfer, 2=mixed
  int _cashAmount = 0;
  bool _loading = false;
  final _cashCtrl = TextEditingController();

  String get _methodLabel {
    switch (_method) {
      case 1: return 'Chuyển khoản';
      case 2: return 'Tiền mặt + CK';
      default: return 'Tiền mặt';
    }
  }

  int get _transferAmount => _method == 2
    ? (widget.total - _cashAmount).clamp(0, widget.total)
    : widget.total;

  String get _qrUrl {
    final encodedName = Uri.encodeComponent(widget.accountName);
    final desc = Uri.encodeComponent('${widget.tableName} THANH TOAN');
    return 'https://img.vietqr.io/image/${widget.bankId}-${widget.bankAccount}-compact2.png'
        '?amount=$_transferAmount&addInfo=$desc&accountName=$encodedName';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              width: 40, height: 4, margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text('Thanh toán', style: GoogleFonts.beVietnamPro(
                        color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700,
                      )),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(FormatUtils.currency(widget.total), style: GoogleFonts.beVietnamPro(
                        color: AppColors.primary, fontSize: 32, fontWeight: FontWeight.w800,
                      )),
                    ),
                    const SizedBox(height: 24),

                    // Method selection
                    Text('Phương thức', style: GoogleFonts.beVietnamPro(
                      color: AppColors.textSecondary, fontSize: 13,
                    )),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _MethodBtn(label: 'Tiền mặt', icon: Icons.money, selected: _method == 0,
                          onTap: () => setState(() => _method = 0)),
                        const SizedBox(width: 8),
                        _MethodBtn(label: 'Chuyển KH', icon: Icons.qr_code_2, selected: _method == 1,
                          onTap: () => setState(() => _method = 1)),
                        const SizedBox(width: 8),
                        _MethodBtn(label: 'Kết hợp', icon: Icons.sync_alt, selected: _method == 2,
                          onTap: () => setState(() => _method = 2)),
                      ],
                    ),

                    if (_method == 2) ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _cashCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: const InputDecoration(
                          labelText: 'Tiền mặt (đ)',
                          prefixIcon: Icon(Icons.money, color: AppColors.textSecondary),
                        ),
                        onChanged: (v) => setState(() => _cashAmount = int.tryParse(v) ?? 0),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.card, borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Còn lại chuyển khoản:', style: GoogleFonts.beVietnamPro(
                              color: AppColors.textSecondary, fontSize: 13,
                            )),
                            Text(FormatUtils.currency(_transferAmount), style: GoogleFonts.beVietnamPro(
                              color: AppColors.primary, fontWeight: FontWeight.w700,
                            )),
                          ],
                        ),
                      ),
                    ],

                    if (_method > 0) ...[
                      const SizedBox(height: 20),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Image.network(
                            _qrUrl,
                            width: 220, height: 220,
                            loadingBuilder: (_, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const SizedBox(width: 220, height: 220,
                                child: Center(child: CircularProgressIndicator(color: AppColors.primary)));
                            },
                            errorBuilder: (_, __, ___) => const SizedBox(width: 220, height: 220,
                              child: Center(child: Text('Không tải được QR', textAlign: TextAlign.center))),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : () async {
                          setState(() => _loading = true);
                          Navigator.pop(context);
                          await widget.onConfirm(_methodLabel);
                        },
                        child: _loading
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : Text('Xác nhận thanh toán', style: GoogleFonts.beVietnamPro(
                              fontSize: 16, fontWeight: FontWeight.w700,
                            )),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MethodBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _MethodBtn({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: 200.ms,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary, size: 22),
              const SizedBox(height: 4),
              Text(label, style: GoogleFonts.beVietnamPro(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
              ), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
