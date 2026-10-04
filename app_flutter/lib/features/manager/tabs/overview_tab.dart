// lib/features/manager/tabs/overview_tab.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';
import '../../cash_shift/cash_shift_dialog.dart';

class OverviewTab extends StatefulWidget {
  final VoidCallback onGoToPOS;
  final VoidCallback onGoToRevenue;
  final VoidCallback onGoToAnalytics;
  final VoidCallback onGoToBills;
  final VoidCallback onGoToAudit;

  const OverviewTab({
    super.key,
    required this.onGoToPOS,
    required this.onGoToRevenue,
    required this.onGoToAnalytics,
    required this.onGoToBills,
    required this.onGoToAudit,
  });

  @override
  State<OverviewTab> createState() => _OverviewTabState();
}

class _OverviewTabState extends State<OverviewTab> {
  final _fb = FirebaseService();

  List<BillModel> _bills = [];
  List<TableModel> _tables = [];
  List<OnlineOrderModel> _onlineOrders = [];
  List<AuditLogModel> _auditLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _fb.billsStream().listen((b) {
      if (mounted) setState(() { _bills = b; _loading = false; });
    });
    _fb.tablesStream().listen((t) {
      if (mounted) setState(() => _tables = t);
    });
    _fb.onlineOrdersStream().listen((o) {
      if (mounted) setState(() => _onlineOrders = o);
    });
    _fb.auditLogsStream().listen((a) {
      if (mounted) setState(() => _auditLogs = a);
    });
  }

  List<BillModel> get _todayPaidBills {
    final now = DateTime.now();
    return _bills.where((b) {
      if (b.status != 'PAID') return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
  }

  int get _todayRevenue => _todayPaidBills.fold(0, (s, b) => s + b.finalAmount);
  int get _todayServingTotal => _tables.where((t) => t.inUse && !t.isMerged).fold<int>(0, (s, t) => s + t.currentTotal);
  int get _todayDiscounts => _todayPaidBills.fold(0, (s, b) => s + b.totalDiscount);
  int get _occupiedTables => _tables.where((t) => t.inUse).length;
  int get _pendingOnlineOrders => _onlineOrders.where((o) => o.isPending).length;

  int get _todaySuspiciousCount {
    final now = DateTime.now();
    return _auditLogs.where((l) {
      final dt = DateTime.fromMillisecondsSinceEpoch(l.timestamp);
      final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
      return isToday && l.isSuspicious;
    }).length;
  }

  // 7-day revenue trend data
  List<Map<String, dynamic>> get _sevenDayTrend {
    final now = DateTime.now();
    return List.generate(7, (i) {
      final targetDate = now.subtract(Duration(days: 6 - i));
      final dayBills = _bills.where((b) {
        if (b.status != 'PAID') return false;
        final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
        return dt.year == targetDate.year && dt.month == targetDate.month && dt.day == targetDate.day;
      });
      final revenue = dayBills.fold(0, (s, b) => s + b.finalAmount);
      return {
        'label': DateFormat('dd/MM').format(targetDate),
        'revenue': revenue,
      };
    });
  }

  Map<String, int> get _topProductsToday {
    final map = <String, int>{};
    for (final b in _todayPaidBills) {
      for (final item in b.items) {
        map[item.name] = (map[item.name] ?? 0) + item.quantity;
      }
    }
    final sorted = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted.take(5));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bills.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: TramColors.brandPrimary));
    }

    return RefreshIndicator(
      color: TramColors.brandPrimary,
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // 1. Alert Bar: Nếu có đơn online hoặc nghi vấn gian lận
          if (_pendingOnlineOrders > 0 || _todaySuspiciousCount > 0) ...[
            Row(
              children: [
                if (_pendingOnlineOrders > 0)
                  Expanded(
                    child: InkWell(
                      onTap: () => context.push('/online-orders'),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: TramColors.warningSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: TramColors.warning.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.delivery_dining, size: 20, color: TramColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_pendingOnlineOrders đơn online cần duyệt',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.warningInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_pendingOnlineOrders > 0 && _todaySuspiciousCount > 0) const SizedBox(width: 8),
                if (_todaySuspiciousCount > 0)
                  Expanded(
                    child: InkWell(
                      onTap: widget.onGoToAudit,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: TramColors.dangerSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: TramColors.danger.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined, size: 20, color: TramColors.danger),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '$_todaySuspiciousCount thao tác nghi vấn',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.danger),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // Ô DOANH THU ƯỚC TÍNH NGÀY = TỔNG DOANH THU + ĐƠN ĐANG PHỤC VỤ
          _buildKpiCard(
            title: 'Doanh thu ước tính ngày (Đã thu + Phục vụ)',
            value: FormatUtils.vnd(_todayRevenue + _todayServingTotal),
            subtitle: 'Đã thu: ${FormatUtils.vnd(_todayRevenue)} + Đang phục vụ: ${FormatUtils.vnd(_todayServingTotal)}',
            icon: Icons.trending_up,
            color: const Color(0xFF059669),
            onTap: widget.onGoToRevenue,
          ),
          const SizedBox(height: 12),

          // 3. Grid 4 Thẻ KPI Hôm Nay
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Doanh thu hôm nay',
                  value: FormatUtils.vnd(_todayRevenue),
                  subtitle: '${_todayPaidBills.length} đơn hoàn tất',
                  icon: Icons.monetization_on,
                  color: TramColors.brandPrimary,
                  onTap: widget.onGoToRevenue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'Số đơn bán ra',
                  value: '${_todayPaidBills.length} đơn',
                  subtitle: 'Xem danh sách',
                  icon: Icons.receipt_long,
                  color: TramColors.success,
                  onTap: widget.onGoToBills,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildKpiCard(
                  title: 'Bàn đang phục vụ',
                  value: '$_occupiedTables/${_tables.length} bàn',
                  subtitle: '${_tables.length - _occupiedTables} bàn còn trống',
                  icon: Icons.table_restaurant,
                  color: TramColors.warning,
                  onTap: widget.onGoToPOS,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildKpiCard(
                  title: 'Tổng giảm giá',
                  value: FormatUtils.vnd(_todayDiscounts),
                  subtitle: 'Voucher & điểm',
                  icon: Icons.discount,
                  color: TramColors.danger,
                  onTap: widget.onGoToAnalytics,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 4. Biểu Đồ Xu Hướng Doanh Thu 7 Ngày Qua
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TramColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trending_up, size: 20, color: TramColors.brandPrimary),
                        const SizedBox(width: 8),
                        Text(
                          'Xu Hướng 7 Ngày Qua',
                          style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: widget.onGoToRevenue,
                      child: Text(
                        'Chi tiết ›',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _buildTrendChart(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 5. Top 5 Món Bán Chạy Hôm Nay
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TramColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.local_fire_department, size: 20, color: TramColors.warning),
                        const SizedBox(width: 8),
                        Text(
                          'Top Món Bán Chạy Hôm Nay',
                          style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: widget.onGoToAnalytics,
                      child: Text(
                        'Top 10 ›',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_topProductsToday.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Hôm nay chưa có món nào được thanh toán',
                        style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
                      ),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < _topProductsToday.entries.length; i++) ...[
                        _buildTopItemRow(
                          rank: i + 1,
                          name: _topProductsToday.entries.elementAt(i).key,
                          count: _topProductsToday.entries.elementAt(i).value,
                          maxCount: _topProductsToday.values.first,
                        ),
                        if (i < _topProductsToday.length - 1) const Divider(height: 14),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 6. Phím Tắt Nghiệp Vụ Quản Lý
          Text(
            'Lối tắt nghiệp vụ',
            style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: TramColors.textSecondary),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionShortcut(
                  label: 'Két Tiền Ca',
                  icon: Icons.point_of_sale,
                  color: TramColors.success,
                  onTap: () => CashShiftDialog.show(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Voucher',
                  icon: Icons.discount_outlined,
                  color: TramColors.warning,
                  onTap: () => context.push('/promotions'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Nhân Viên',
                  icon: Icons.people_outline,
                  color: TramColors.info,
                  onTap: () => context.push('/user-management'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Thực Đơn',
                  icon: Icons.menu_book_outlined,
                  color: TramColors.brandPrimary,
                  onTap: () => context.push('/menu-management'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionShortcut(
                  label: 'Báo Cáo Cuối Ngày',
                  icon: Icons.summarize_outlined,
                  color: TramColors.brandPrimary,
                  onTap: () => context.push('/end-of-day-report'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Phiếu Giao Ca',
                  icon: Icons.receipt_long,
                  color: TramColors.success,
                  onTap: () => context.push('/cash-shifts'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Kho Hàng',
                  icon: Icons.inventory_2_outlined,
                  color: TramColors.accent,
                  onTap: () => context.push('/inventory'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionShortcut(
                  label: 'Giám Sát',
                  icon: Icons.shield_outlined,
                  color: TramColors.danger,
                  onTap: widget.onGoToAudit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TramColors.borderLight),
          boxShadow: const [
            BoxShadow(color: Color(0x06000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.w800, color: TramColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart() {
    final trend = _sevenDayTrend;
    final maxRevenue = trend.map((e) => (e['revenue'] as int).toDouble()).fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxRevenue > 0 ? maxRevenue * 1.25 : 1000000.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = trend[group.x.toInt()];
              return BarTooltipItem(
                '${item['label']}\n',
                GoogleFonts.beVietnamPro(color: Colors.white, fontSize: 11),
                children: [
                  TextSpan(
                    text: FormatUtils.vnd(rod.toY.toInt()),
                    style: GoogleFonts.beVietnamPro(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (val, meta) {
                if (val == 0) return const SizedBox.shrink();
                return Text(
                  val >= 1000000 ? '${(val / 1000000).toStringAsFixed(1)}M' : '${(val / 1000).toInt()}k',
                  style: GoogleFonts.beVietnamPro(fontSize: 9, color: TramColors.textSecondary),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < trend.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      trend[idx]['label'],
                      style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (value) => FlLine(
            color: TramColors.borderLight,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(trend.length, (i) {
          final rev = (trend[i]['revenue'] as int).toDouble();
          final isToday = i == trend.length - 1;
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: rev,
                color: isToday ? TramColors.brandPrimary : const Color(0xFFC76C74),
                width: 14,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTopItemRow({
    required int rank,
    required String name,
    required int count,
    required int maxCount,
  }) {
    Color badgeColor;
    if (rank == 1) {
      badgeColor = const Color(0xFFFFB800); // Gold
    } else if (rank == 2) {
      badgeColor = const Color(0xFF9E9E9E); // Silver
    } else if (rank == 3) {
      badgeColor = const Color(0xFFCD7F32); // Bronze
    } else {
      badgeColor = Colors.grey.shade400;
    }

    final ratio = maxCount > 0 ? (count / maxCount).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$rank',
            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: badgeColor),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: TramColors.textPrimary),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(rank == 1 ? TramColors.brandPrimary : TramColors.accent),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$count ly',
          style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
        ),
      ],
    );
  }

  Widget _buildActionShortcut({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TramColors.borderLight),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w600, color: TramColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
