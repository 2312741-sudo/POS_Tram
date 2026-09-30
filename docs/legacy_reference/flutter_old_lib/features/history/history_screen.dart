// lib/features/history/history_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();
  late TabController _tabCtrl;
  int _periodIndex = 0; // 0=today, 1=week, 2=month, 3=year
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _auth.isManager ? 2 : 1, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  bool _matchesPeriod(OrderHistoryModel order) {
    final dt = order.dateTime;
    final now = _selectedDate;
    switch (_periodIndex) {
      case 0: return dt.year == now.year && dt.month == now.month && dt.day == now.day;
      case 1:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekEnd = weekStart.add(const Duration(days: 6));
        return dt.isAfter(weekStart.subtract(const Duration(days: 1))) && dt.isBefore(weekEnd.add(const Duration(days: 1)));
      case 2: return dt.year == now.year && dt.month == now.month;
      case 3: return dt.year == now.year;
      default: return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Lịch sử đơn hàng', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700,
        )),
        bottom: _auth.isManager
          ? TabBar(controller: _tabCtrl, tabs: const [
              Tab(text: 'Lịch sử'),
              Tab(text: 'Báo cáo'),
            ])
          : null,
      ),
      body: _auth.isManager
        ? TabBarView(controller: _tabCtrl, children: [
            _buildHistoryTab(),
            _buildReportTab(),
          ])
        : _buildHistoryTab(),
    );
  }

  Widget _buildPeriodFilter() {
    final labels = ['Hôm nay', 'Tuần', 'Tháng', 'Năm'];
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final sel = _periodIndex == i;
          return GestureDetector(
            onTap: () => setState(() { _periodIndex = i; _selectedDate = DateTime.now(); }),
            child: AnimatedContainer(
              duration: 200.ms,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? AppColors.primary : AppColors.border),
              ),
              child: Text(labels[i], style: GoogleFonts.beVietnamPro(
                color: sel ? Colors.white : AppColors.textSecondary,
                fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              )),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<List<OrderHistoryModel>>(
      stream: _fb.historyStream(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final filtered = all.where(_matchesPeriod).toList();
        
        return Column(
          children: [
            _buildPeriodFilter(),
            Expanded(
              child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.history_outlined,
                    title: 'Không có lịch sử',
                    subtitle: 'Chưa có đơn hàng nào trong khoảng thời gian này',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 12),
                    itemBuilder: (_, i) => _HistoryItem(
                      order: filtered[i],
                      canDelete: _auth.isManager,
                      onDelete: () => _deleteOrder(filtered[i]),
                    ).animate(delay: (i * 30).ms).fadeIn(duration: 200.ms),
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReportTab() {
    return StreamBuilder<List<OrderHistoryModel>>(
      stream: _fb.historyStream(),
      builder: (context, snap) {
        final all = snap.data ?? [];
        final filtered = all.where(_matchesPeriod).toList();
        
        final totalRevenue = filtered.fold<int>(0, (s, o) => s + o.totalAmount);
        final cashRevenue = filtered.where((o) => o.paymentMethod == 'Tiền mặt').fold<int>(0, (s, o) => s + o.totalAmount);
        final transferRevenue = filtered.where((o) => o.paymentMethod != 'Tiền mặt').fold<int>(0, (s, o) => s + o.totalAmount);
        final avgOrder = filtered.isEmpty ? 0 : totalRevenue ~/ filtered.length;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildPeriodFilter(),
              const SizedBox(height: 16),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  StatCard(title: 'Tổng doanh thu', value: FormatUtils.currency(totalRevenue),
                    icon: Icons.attach_money, color: AppColors.success),
                  StatCard(title: 'Số hóa đơn', value: '${filtered.length} đơn',
                    icon: Icons.receipt_outlined, color: AppColors.primary),
                  StatCard(title: 'Tiền mặt', value: FormatUtils.currency(cashRevenue),
                    icon: Icons.money, color: AppColors.warning),
                  StatCard(title: 'Chuyển khoản', value: FormatUtils.currency(transferRevenue),
                    icon: Icons.qr_code_2, color: AppColors.info),
                  StatCard(title: 'Trung bình/đơn', value: FormatUtils.currency(avgOrder),
                    icon: Icons.bar_chart, color: AppColors.secondary),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteOrder(OrderHistoryModel order) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa hóa đơn',
      message: 'Xóa hóa đơn ${order.orderCode}? Không thể hoàn tác!',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true && order.firebaseKey != null) {
      await _fb.deleteHistory(order.firebaseKey!);
      await _fb.logAction(AuditLogModel(
        action: 'DELETE_HISTORY',
        username: _auth.currentUser?.username ?? '',
        userRole: _auth.currentUser?.role ?? '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Xóa hóa đơn ${order.orderCode} - ${FormatUtils.currency(order.totalAmount)}',
        targetId: order.orderCode,
      ));
    }
  }
}

class _HistoryItem extends StatelessWidget {
  final OrderHistoryModel order;
  final bool canDelete;
  final VoidCallback onDelete;

  const _HistoryItem({required this.order, required this.canDelete, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_outlined, color: AppColors.success, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(order.orderCode, style: GoogleFonts.beVietnamPro(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13,
                      )),
                      const SizedBox(width: 8),
                      _PaymentBadge(method: order.paymentMethod),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Bàn ${order.tableName} • ${FormatUtils.dateTime(order.timestamp)}',
                    style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(FormatUtils.currency(order.totalAmount), style: GoogleFonts.beVietnamPro(
                  color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15,
                )),
                if (canDelete)
                  GestureDetector(
                    onTap: onDelete,
                    child: const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 16),
            Text('Chi tiết đơn ${order.orderCode}', style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16,
            )),
            const SizedBox(height: 12),
            ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(child: Text('${item.name} x${item.quantity}',
                    style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary))),
                  Text(FormatUtils.currency(item.total),
                    style: GoogleFonts.beVietnamPro(color: AppColors.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            )),
            const Divider(color: AppColors.border),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tổng cộng', style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                Text(FormatUtils.currency(order.totalAmount), style: GoogleFonts.beVietnamPro(
                  color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 18,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    if (method == 'Tiền mặt') { color = AppColors.warning; icon = Icons.money; }
    else if (method == 'Chuyển khoản') { color = AppColors.info; icon = Icons.qr_code_2; }
    else { color = AppColors.success; icon = Icons.sync_alt; }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 2),
          Text(method.length > 8 ? 'K.Hợp' : method,
            style: GoogleFonts.beVietnamPro(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
