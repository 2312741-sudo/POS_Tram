// lib/features/online_orders/online_order_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class OnlineOrderScreen extends StatefulWidget {
  const OnlineOrderScreen({super.key});

  @override
  State<OnlineOrderScreen> createState() => _OnlineOrderScreenState();
}

class _OnlineOrderScreenState extends State<OnlineOrderScreen> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  List<OnlineOrderModel> _orders = [];
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _fb.onlineOrdersStream().listen((orders) {
      if (mounted) {
        final hadPending = _orders.where((o) => o.isPending).length;
        setState(() => _orders = orders);
        final hasPending = orders.where((o) => o.isPending).length;
        if (hasPending > hadPending) {
          HapticFeedback.heavyImpact();
        }
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<OnlineOrderModel> get _pending => _orders.where((o) => o.status == 'PENDING').toList();
  List<OnlineOrderModel> get _confirmed => _orders.where((o) => o.status == 'CONFIRMED').toList();
  List<OnlineOrderModel> get _cancelled => _orders.where((o) => o.status == 'CANCELLED').toList();

  Future<void> _updateStatus(OnlineOrderModel order, String status) async {
    if (order.firebaseKey == null) return;
    await _fb.updateOnlineOrderStatus(order.firebaseKey!, status);
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _pending.length;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Row(
          children: [
            Text('Đơn hàng online', style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
            if (pendingCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('$pendingCount', style: GoogleFonts.beVietnamPro(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ).animate(onPlay: (c) => c.repeat(reverse: true))
                .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1.seconds),
            ],
          ],
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: pendingCount > 0 ? 'Chờ ($pendingCount)' : 'Chờ'),
            Tab(text: 'Đã duyệt (${_confirmed.length})'),
            Tab(text: 'Đã hủy (${_cancelled.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildOrderList(_pending, showActions: true),
          _buildOrderList(_confirmed, showActions: false),
          _buildOrderList(_cancelled, showActions: false),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<OnlineOrderModel> orders, {required bool showActions}) {
    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.smartphone_outlined,
        title: 'Không có đơn nào',
        subtitle: 'Các đơn hàng online sẽ hiển thị ở đây',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _OnlineOrderCard(
        order: orders[i],
        showActions: showActions,
        onConfirm: () => _updateStatus(orders[i], 'CONFIRMED'),
        onCancel: () => _updateStatus(orders[i], 'CANCELLED'),
        onTap: () => context.push('/online-order-detail', extra: orders[i]),
      ).animate(delay: (i * 50).ms).fadeIn(duration: 250.ms),
    );
  }
}

class _OnlineOrderCard extends StatelessWidget {
  final OnlineOrderModel order;
  final bool showActions;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  const _OnlineOrderCard({
    required this.order,
    required this.showActions,
    required this.onConfirm,
    required this.onCancel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCallWaiter = order.isCallWaiter;
    final items = order.items;
    final total = items.fold<int>(0, (s, p) => s + p.itemTotal);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCallWaiter ? AppColors.warning.withAlpha(120) : AppColors.border,
            width: isCallWaiter ? 2 : 1,
          ),
          boxShadow: isCallWaiter ? [
            BoxShadow(color: AppColors.warning.withAlpha(50), blurRadius: 12),
          ] : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isCallWaiter ? AppColors.warning.withAlpha(30) : AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCallWaiter ? Icons.campaign_outlined : Icons.restaurant,
                          color: isCallWaiter ? AppColors.warning : AppColors.primary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isCallWaiter ? '🔔 Gọi nhân viên' : 'Đặt món',
                          style: GoogleFonts.beVietnamPro(
                            color: isCallWaiter ? AppColors.warning : AppColors.primary,
                            fontWeight: FontWeight.w700, fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text('Bàn ${order.tableName}', style: GoogleFonts.beVietnamPro(
                    color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(width: 8),
                  Text('• ${order.tableZone}', style: GoogleFonts.beVietnamPro(
                    color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              if (!isCallWaiter && items.isNotEmpty) ...[
                Text(
                  items.map((p) => '${p.name} x${p.quantity}').join(', '),
                  style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(FormatUtils.currency(total), style: GoogleFonts.beVietnamPro(
                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
              ] else if (isCallWaiter)
                Text('Khách đang chờ nhân viên phục vụ', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: 4),
              Text(FormatUtils.dateTime(order.timestamp), style: GoogleFonts.beVietnamPro(
                color: AppColors.textHint, fontSize: 11)),
              if (showActions) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text('Từ chối', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: onConfirm,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text('Xác nhận', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
