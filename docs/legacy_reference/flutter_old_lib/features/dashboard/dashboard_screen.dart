// lib/features/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _fb = FirebaseService();
  List<OrderHistoryModel> _history = [];
  List<TableModel> _tables = [];
  List<OnlineOrderModel> _onlineOrders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _fb.historyStream().listen((h) {
      if (mounted) setState(() { _history = h; _loading = false; });
    });
    _fb.tablesStream().listen((t) {
      if (mounted) setState(() => _tables = t);
    });
    _fb.onlineOrdersStream().listen((o) {
      if (mounted) setState(() => _onlineOrders = o);
    });
  }

  List<OrderHistoryModel> get _todayOrders {
    final now = DateTime.now();
    return _history.where((h) {
      final dt = h.dateTime;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
  }

  int get _todayRevenue => _todayOrders.fold(0, (s, o) => s + o.totalAmount);
  int get _occupiedTables => _tables.where((t) => t.inUse).length;
  int get _pendingOnline => _onlineOrders.where((o) => o.isPending).length;

  Map<String, int> get _topProducts {
    final map = <String, int>{};
    for (final order in _todayOrders) {
      for (final item in order.items) {
        map[item.name] = (map[item.name] ?? 0) + item.quantity;
      }
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(5));
  }

  // Anomaly detection: staff who cancelled many orders today
  // (Based on audit_logs in real implementation)
  List<String> get _anomalies {
    final anomalies = <String>[];
    if (_pendingOnline > 5) anomalies.add('Có $_pendingOnline đơn online đang chờ xử lý');
    if (_occupiedTables == _tables.length && _tables.isNotEmpty) anomalies.add('Tất cả bàn đang được sử dụng!');
    return anomalies;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Dashboard', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700,
        )),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: _loading
        ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
        : RefreshIndicator(
            onRefresh: () async => setState(() {}),
            color: AppColors.primary,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stat cards
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      StatCard(
                        title: 'Doanh thu hôm nay',
                        value: FormatUtils.currency(_todayRevenue),
                        icon: Icons.attach_money,
                        color: AppColors.success,
                        onTap: () => context.push('/history'),
                      ),
                      StatCard(
                        title: 'Hóa đơn hôm nay',
                        value: '${_todayOrders.length} đơn',
                        icon: Icons.receipt_outlined,
                        color: AppColors.primary,
                      ),
                      StatCard(
                        title: 'Bàn đang dùng',
                        value: '$_occupiedTables/${_tables.length}',
                        icon: Icons.table_restaurant,
                        color: AppColors.tableOccupied,
                        onTap: () => context.go('/tables'),
                      ),
                      StatCard(
                        title: 'Đơn online chờ',
                        value: _pendingOnline > 0 ? '$_pendingOnline đơn' : 'Không có',
                        icon: Icons.smartphone_outlined,
                        color: _pendingOnline > 0 ? AppColors.warning : AppColors.success,
                        onTap: () => context.push('/online-orders'),
                      ),
                    ].asMap().entries.map((e) =>
                      e.value.animate(delay: (e.key * 80).ms).fadeIn(duration: 300.ms)
                        .slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic)
                    ).toList(),
                  ),

                  // Anomaly Alerts
                  if (_anomalies.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: '⚠️ Cảnh báo',
                      subtitle: 'Hoạt động cần chú ý',
                    ),
                    const SizedBox(height: 12),
                    ..._anomalies.map((alert) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.danger.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 20),
                          const SizedBox(width: 10),
                          Expanded(child: Text(alert, style: GoogleFonts.beVietnamPro(
                            color: AppColors.danger, fontSize: 13,
                          ))),
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms)),
                  ],

                  // Top products today
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: '🏆 Top món bán chạy hôm nay',
                    action: TextButton(
                      onPressed: () => context.push('/history'),
                      child: Text('Xem tất cả', style: GoogleFonts.beVietnamPro(
                        color: AppColors.primary, fontSize: 13,
                      )),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_topProducts.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Center(
                        child: Text('Chưa có đơn hàng hôm nay', style: GoogleFonts.beVietnamPro(
                          color: AppColors.textHint,
                        )),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: _topProducts.entries.toList().asMap().entries.map((e) {
                          final rank = e.key + 1;
                          final product = e.value;
                          final maxQty = _topProducts.values.first;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              border: e.key < _topProducts.length - 1
                                ? const Border(bottom: BorderSide(color: AppColors.border))
                                : null,
                            ),
                            child: Row(
                              children: [
                                // Rank badge
                                Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: rank <= 3
                                      ? [AppColors.kitchenAccent, AppColors.textSecondary, const Color(0xFFCD7F32)][rank - 1].withOpacity(0.2)
                                      : AppColors.cardElevated,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text('$rank', style: GoogleFonts.beVietnamPro(
                                    color: rank <= 3
                                      ? [AppColors.kitchenAccent, AppColors.textSecondary, const Color(0xFFCD7F32)][rank - 1]
                                      : AppColors.textSecondary,
                                    fontWeight: FontWeight.w700, fontSize: 12,
                                  ))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(product.key, style: GoogleFonts.beVietnamPro(
                                        color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14,
                                      )),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: product.value / maxQty,
                                        backgroundColor: AppColors.cardElevated,
                                        color: AppColors.primary,
                                        borderRadius: BorderRadius.circular(4),
                                        minHeight: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text('${product.value} phần', style: GoogleFonts.beVietnamPro(
                                  color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14,
                                )),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ).animate().fadeIn(duration: 400.ms, delay: 200.ms),

                  // Live occupied tables
                  const SizedBox(height: 20),
                  SectionHeader(
                    title: '🪑 Bàn đang phục vụ',
                    action: TextButton(
                      onPressed: () => context.go('/tables'),
                      child: Text('Xem tất cả', style: GoogleFonts.beVietnamPro(
                        color: AppColors.primary, fontSize: 13,
                      )),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _tables.where((t) => t.inUse).map((t) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.tableOccupied.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.tableOccupied.withOpacity(0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.table_restaurant, color: AppColors.tableOccupied, size: 14),
                          const SizedBox(width: 6),
                          Text(t.name, style: GoogleFonts.beVietnamPro(
                            color: AppColors.tableOccupied, fontWeight: FontWeight.w600, fontSize: 13,
                          )),
                          if (t.currentTotal > 0) ...[
                            const SizedBox(width: 6),
                            Text('• ${FormatUtils.currency(t.currentTotal)}', style: GoogleFonts.beVietnamPro(
                              color: AppColors.textSecondary, fontSize: 11,
                            )),
                          ],
                        ],
                      ),
                    )).toList(),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
    );
  }
}
