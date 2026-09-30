// lib/features/manager/tabs/analytics_tab.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';

class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  final _fb = FirebaseService();
  List<BillModel> _bills = [];
  bool _loading = true;
  int _touchedPieIndex = -1;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  void _loadBills() {
    _fb.billsStream().listen((b) {
      if (mounted) {
        setState(() {
          _bills = b.where((e) => e.status == 'PAID').toList();
          _loading = false;
        });
      }
    });
  }

  // 1. Payment Breakdown
  Map<String, dynamic> get _paymentData {
    int cash = 0;
    int cashAmount = 0;
    int transfer = 0;
    int transferAmount = 0;
    int other = 0;
    int otherAmount = 0;

    for (final b in _bills) {
      final m = b.paymentMethod.toLowerCase();
      if (m.contains('cash') || m.contains('tiền mặt')) {
        cash++;
        cashAmount += b.finalAmount;
      } else if (m.contains('transfer') || m.contains('chuyển') || m.contains('qr')) {
        transfer++;
        transferAmount += b.finalAmount;
      } else {
        other++;
        otherAmount += b.finalAmount;
      }
    }

    final total = _bills.length;
    return {
      'cash': {'count': cash, 'amount': cashAmount, 'pct': total > 0 ? (cash / total * 100).toStringAsFixed(1) : '0'},
      'transfer': {'count': transfer, 'amount': transferAmount, 'pct': total > 0 ? (transfer / total * 100).toStringAsFixed(1) : '0'},
      'other': {'count': other, 'amount': otherAmount, 'pct': total > 0 ? (other / total * 100).toStringAsFixed(1) : '0'},
      'total': total,
    };
  }

  // 2. Hourly revenue across all data
  List<Map<String, dynamic>> get _hourlyData {
    return List.generate(24, (h) {
      final rev = _bills.where((b) {
        final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
        return dt.hour == h;
      }).fold(0, (s, b) => s + b.finalAmount);
      return {'hour': '${h}h', 'revenue': rev};
    });
  }

  // 3. Top 10 Best Selling Items
  List<Map<String, dynamic>> get _top10Products {
    final Map<String, Map<String, dynamic>> map = {};
    for (final b in _bills) {
      for (final item in b.items) {
        final key = item.name;
        if (!map.containsKey(key)) {
          map[key] = {'name': item.name, 'qty': 0, 'revenue': 0};
        }
        map[key]!['qty'] = (map[key]!['qty'] as int) + item.quantity;
        map[key]!['revenue'] = (map[key]!['revenue'] as int) + item.itemTotal;
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => (b['qty'] as int).compareTo(a['qty'] as int));
    return list.take(10).toList();
  }

  // 4. Revenue by Zone
  List<Map<String, dynamic>> get _zoneData {
    final Map<String, int> map = {};
    for (final b in _bills) {
      final zone = b.zone.isNotEmpty ? b.zone : 'Khu vực chung';
      map[zone] = (map[zone] ?? 0) + b.finalAmount;
    }
    final list = map.entries.map((e) => {'zone': e.key, 'revenue': e.value}).toList();
    list.sort((a, b) => (b['revenue'] as int).compareTo(a['revenue'] as int));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bills.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: TramColors.brandPrimary));
    }

    final pData = _paymentData;
    final top10 = _top10Products;
    final zones = _zoneData;
    final hourly = _hourlyData;

    return RefreshIndicator(
      color: TramColors.brandPrimary,
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phân Tích Chuyên Sâu 📈',
                style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold, color: TramColors.textPrimary),
              ),
              Text(
                'Tổng hợp ${_bills.length} đơn hàng đã thanh toán',
                style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. Tỷ Lệ Phương Thức Thanh Toán (PieChart)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TramColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.pie_chart, size: 20, color: TramColors.brandPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'Tỷ Lệ Phương Thức Thanh Toán',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_bills.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Chưa có dữ liệu thanh toán', style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary)),
                    ),
                  )
                else
                  Column(
                    children: [
                      SizedBox(
                        height: 170,
                        child: PieChart(
                          PieChartData(
                            pieTouchData: PieTouchData(
                              touchCallback: (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions ||
                                      pieTouchResponse == null ||
                                      pieTouchResponse.touchedSection == null) {
                                    _touchedPieIndex = -1;
                                    return;
                                  }
                                  _touchedPieIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                });
                              },
                            ),
                            sectionsSpace: 3,
                            centerSpaceRadius: 36,
                            sections: _buildPieSections(pData),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildPaymentLegendItem(
                        label: 'Tiền mặt',
                        count: pData['cash']['count'],
                        amount: pData['cash']['amount'],
                        pct: pData['cash']['pct'],
                        color: TramColors.success,
                      ),
                      const Divider(height: 14),
                      _buildPaymentLegendItem(
                        label: 'Chuyển khoản (VietQR)',
                        count: pData['transfer']['count'],
                        amount: pData['transfer']['amount'],
                        pct: pData['transfer']['pct'],
                        color: TramColors.info,
                      ),
                      if (pData['other']['count'] > 0) ...[
                        const Divider(height: 14),
                        _buildPaymentLegendItem(
                          label: 'Khác / Thẻ',
                          count: pData['other']['count'],
                          amount: pData['other']['amount'],
                          pct: pData['other']['pct'],
                          color: TramColors.warning,
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Doanh Thu Theo 24 Khung Giờ (Peak Hours)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TramColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
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
                        const Icon(Icons.access_time_filled, size: 20, color: TramColors.warning),
                        const SizedBox(width: 8),
                        Text(
                          'Khung Giờ Cao Điểm (0h - 23h)',
                          style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Phân bổ doanh thu theo từng giờ để bố trí nhân lực',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: _buildHourlyChart(hourly),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3. Top 10 Món Bán Chạy Nhất
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TramColors.borderLight),
              boxShadow: const [
                BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.emoji_events, size: 20, color: Color(0xFFFFB800)),
                    const SizedBox(width: 8),
                    Text(
                      'Top 10 Món Bán Chạy Nhất',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (top10.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('Chưa có dữ liệu món bán', style: GoogleFonts.beVietnamPro(color: TramColors.textSecondary)),
                    ),
                  )
                else
                  Column(
                    children: [
                      for (int i = 0; i < top10.length; i++) ...[
                        _buildTopItemCard(
                          rank: i + 1,
                          name: top10[i]['name'],
                          qty: top10[i]['qty'],
                          revenue: top10[i]['revenue'],
                          maxQty: top10[0]['qty'],
                        ),
                        if (i < top10.length - 1) const Divider(height: 16),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Doanh Thu Theo Khu Vực
          if (zones.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: TramColors.borderLight),
                boxShadow: const [
                  BoxShadow(color: Color(0x06000000), blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place, size: 20, color: TramColors.info),
                      const SizedBox(width: 8),
                      Text(
                        'Doanh Thu Theo Khu Vực / Tầng',
                        style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Column(
                    children: [
                      for (int i = 0; i < zones.length; i++) ...[
                        _buildZoneRow(
                          zone: zones[i]['zone'],
                          revenue: zones[i]['revenue'],
                          totalRevenue: _bills.fold(0, (s, b) => s + b.finalAmount),
                        ),
                        if (i < zones.length - 1) const Divider(height: 14),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections(Map<String, dynamic> data) {
    final sections = <PieChartSectionData>[];
    final cashCount = (data['cash']['count'] as int).toDouble();
    final transferCount = (data['transfer']['count'] as int).toDouble();
    final otherCount = (data['other']['count'] as int).toDouble();

    if (cashCount > 0) {
      final isTouched = _touchedPieIndex == sections.length;
      sections.add(
        PieChartSectionData(
          color: TramColors.success,
          value: cashCount,
          title: '${data['cash']['pct']}%',
          radius: isTouched ? 55 : 48,
          titleStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    if (transferCount > 0) {
      final isTouched = _touchedPieIndex == sections.length;
      sections.add(
        PieChartSectionData(
          color: TramColors.info,
          value: transferCount,
          title: '${data['transfer']['pct']}%',
          radius: isTouched ? 55 : 48,
          titleStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    if (otherCount > 0) {
      final isTouched = _touchedPieIndex == sections.length;
      sections.add(
        PieChartSectionData(
          color: TramColors.warning,
          value: otherCount,
          title: '${data['other']['pct']}%',
          radius: isTouched ? 55 : 48,
          titleStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      );
    }

    return sections;
  }

  Widget _buildPaymentLegendItem({
    required String label,
    required int count,
    required int amount,
    required String pct,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: TramColors.textPrimary),
              ),
              Text(
                '$count đơn ($pct%)',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          FormatUtils.vnd(amount),
          style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildHourlyChart(List<Map<String, dynamic>> data) {
    final maxRev = data.map((e) => (e['revenue'] as int).toDouble()).fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxRev > 0 ? maxRev * 1.25 : 100000.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = data[group.x.toInt()];
              return BarTooltipItem(
                'Khung ${item['hour']}\n',
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
              reservedSize: 36,
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
                // Show every 3 hours (0h, 3h, 6h, 9h, 12h, 15h, 18h, 21h)
                if (idx % 3 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    data[idx]['hour'],
                    style: GoogleFonts.beVietnamPro(fontSize: 9, color: TramColors.textSecondary),
                  ),
                );
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
        barGroups: List.generate(data.length, (i) {
          final rev = (data[i]['revenue'] as int).toDouble();
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: rev,
                color: TramColors.warning,
                width: 7,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTopItemCard({
    required int rank,
    required String name,
    required int qty,
    required int revenue,
    required int maxQty,
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

    final ratio = maxQty > 0 ? (qty / maxQty).clamp(0.0, 1.0) : 0.0;

    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: badgeColor, width: 1.5),
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
                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: TramColors.textPrimary),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 5,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation<Color>(rank <= 3 ? TramColors.brandPrimary : TramColors.accent),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Doanh thu: ${FormatUtils.vnd(revenue)}',
                style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '$qty ly',
          style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
        ),
      ],
    );
  }

  Widget _buildZoneRow({
    required String zone,
    required int revenue,
    required int totalRevenue,
  }) {
    final pct = totalRevenue > 0 ? (revenue / totalRevenue * 100).toStringAsFixed(1) : '0';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.table_bar_outlined, size: 18, color: TramColors.brandPrimary),
            const SizedBox(width: 8),
            Text(
              zone,
              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.w600, color: TramColors.textPrimary),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              FormatUtils.vnd(revenue),
              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
            ),
            Text(
              '$pct% doanh số',
              style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
            ),
          ],
        ),
      ],
    );
  }
}
