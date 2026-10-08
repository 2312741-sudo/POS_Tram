// lib/features/manager/tabs/revenue_tab.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';
import '../widgets/bill_detail_sheet.dart';

enum RevenueTabType { day, week, month, year }

class RevenueTab extends StatefulWidget {
  const RevenueTab({super.key});

  @override
  State<RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<RevenueTab> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<BillModel> _bills = [];
  List<TableModel> _tables = [];
  bool _loading = true;

  RevenueTabType _tab = RevenueTabType.day;
  int _offset = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _fb.billsStream().listen((b) {
      if (mounted) {
        setState(() {
          _bills = b;
          _loading = false;
        });
      }
    });

    _fb.tablesStream().listen((t) {
      if (mounted) {
        setState(() {
          _tables = t;
        });
      }
    }, onError: (Object e) => debugPrint('Lỗi tải danh sách bàn: $e'));
  }

  // Active serving tables
  List<TableModel> get _servingTables => _tables.where((t) => t.inUse && !t.isMerged).toList();
  int get _servingCount => _servingTables.length;
  int get _servingTotal => _servingTables.fold<int>(0, (s, t) => s + t.currentTotal);

  // Takeaway metrics
  List<BillModel> get _takeawayBills => _filteredBills.where((b) {
    final t = b.tableName.toLowerCase();
    final z = b.zone.toLowerCase();
    return t.contains('mang về') || t.contains('mang ve') || z.contains('mang về') || z.contains('mang ve');
  }).toList();
  int get _takeawayCount => _takeawayBills.length;
  int get _takeawayRevenue => _takeawayBills.fold(0, (s, b) => s + b.finalAmount);

  // Range calculation matching web logic
  DateTime get _now => DateTime.now();

  Map<String, dynamic> get _currentRange {
    final now = _now;
    if (_tab == RevenueTabType.day) {
      final target = DateTime(now.year, now.month, now.day).subtract(Duration(days: _offset));
      final start = DateTime(target.year, target.month, target.day, 0, 0, 0);
      final end = DateTime(target.year, target.month, target.day, 23, 59, 59, 999);
      final label = DateFormat('dd/MM/yyyy').format(target);
      return {'start': start, 'end': end, 'label': _offset == 0 ? 'Hôm nay ($label)' : label};
    } else if (_tab == RevenueTabType.week) {
      // Week starts on Monday
      final currentWeekday = now.weekday; // 1 = Mon, 7 = Sun
      final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: currentWeekday - 1));
      final targetMonday = monday.subtract(Duration(days: 7 * _offset));
      final targetSunday = targetMonday.add(const Duration(days: 6));
      final start = DateTime(targetMonday.year, targetMonday.month, targetMonday.day, 0, 0, 0);
      final end = DateTime(targetSunday.year, targetSunday.month, targetSunday.day, 23, 59, 59, 999);
      final label = '${DateFormat('dd/MM').format(targetMonday)} - ${DateFormat('dd/MM/yyyy').format(targetSunday)}';
      return {'start': start, 'end': end, 'label': _offset == 0 ? 'Tuần này ($label)' : label};
    } else if (_tab == RevenueTabType.month) {
      int targetMonth = now.month - _offset;
      int targetYear = now.year;
      while (targetMonth <= 0) {
        targetMonth += 12;
        targetYear -= 1;
      }
      final start = DateTime(targetYear, targetMonth, 1, 0, 0, 0);
      final daysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
      final end = DateTime(targetYear, targetMonth, daysInMonth, 23, 59, 59, 999);
      final label = 'Tháng $targetMonth/$targetYear';
      return {'start': start, 'end': end, 'label': _offset == 0 ? 'Tháng này ($label)' : label};
    } else {
      final targetYear = now.year - _offset;
      final start = DateTime(targetYear, 1, 1, 0, 0, 0);
      final end = DateTime(targetYear, 12, 31, 23, 59, 59, 999);
      final label = 'Năm $targetYear';
      return {'start': start, 'end': end, 'label': _offset == 0 ? 'Năm nay ($label)' : label};
    }
  }

  List<BillModel> get _filteredBills {
    final range = _currentRange;
    final startMs = (range['start'] as DateTime).millisecondsSinceEpoch;
    final endMs = (range['end'] as DateTime).millisecondsSinceEpoch;

    return _bills.where((b) {
      if (b.status != 'PAID') return false;
      final ts = b.closedAt ?? b.createdAt;
      return ts >= startMs && ts <= endMs;
    }).toList();
  }

  int get _totalRevenue => _filteredBills.fold(0, (s, b) => s + b.finalAmount);
  int get _cashRevenue => _filteredBills
      .where((b) => b.paymentMethod.toLowerCase().contains('cash') || b.paymentMethod.toLowerCase().contains('tiền mặt'))
      .fold(0, (s, b) => s + b.finalAmount);
  int get _transferRevenue => _filteredBills
      .where((b) => b.paymentMethod.toLowerCase().contains('transfer') || b.paymentMethod.toLowerCase().contains('chuyển') || b.paymentMethod.toLowerCase().contains('qr'))
      .fold(0, (s, b) => s + b.finalAmount);
  int get _avgPerOrder => _filteredBills.isNotEmpty ? (_totalRevenue / _filteredBills.length).round() : 0;

  // Chart data builder
  List<Map<String, dynamic>> get _chartData {
    final bills = _filteredBills;
    final range = _currentRange;

    if (_tab == RevenueTabType.day) {
      // 24 hours
      return List.generate(24, (h) {
        final rev = bills.where((b) {
          final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
          return dt.hour == h;
        }).fold(0, (s, b) => s + b.finalAmount);
        return {'label': '${h}h', 'revenue': rev};
      });
    } else if (_tab == RevenueTabType.week) {
      // 7 days of week (Mon to Sun)
      final days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      return List.generate(7, (i) {
        final weekday = i + 1; // 1 = Mon, 7 = Sun
        final rev = bills.where((b) {
          final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
          return dt.weekday == weekday;
        }).fold(0, (s, b) => s + b.finalAmount);
        return {'label': days[i], 'revenue': rev};
      });
    } else if (_tab == RevenueTabType.month) {
      // Days in month
      final start = range['start'] as DateTime;
      final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
      return List.generate(daysInMonth, (i) {
        final day = i + 1;
        final rev = bills.where((b) {
          final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
          return dt.day == day;
        }).fold(0, (s, b) => s + b.finalAmount);
        return {'label': '$day', 'revenue': rev};
      });
    } else {
      // 12 months
      final months = ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'T10', 'T11', 'T12'];
      return List.generate(12, (i) {
        final month = i + 1;
        final rev = bills.where((b) {
          final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
          return dt.month == month;
        }).fold(0, (s, b) => s + b.finalAmount);
        return {'label': months[i], 'revenue': rev};
      });
    }
  }

  void _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _now.subtract(Duration(days: _offset)),
      firstDate: DateTime(2022),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      final daysDiff = DateTime(_now.year, _now.month, _now.day).difference(DateTime(picked.year, picked.month, picked.day)).inDays;
      setState(() {
        _tab = RevenueTabType.day;
        _offset = daysDiff >= 0 ? daysDiff : 0;
      });
    }
  }

  Future<void> _exportExcel() async {
    if (_filteredBills.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có dữ liệu hóa đơn nào trong khoảng thời gian này!')),
      );
      return;
    }
    final storeName = _auth.currentStoreInfo?.storeName ?? 'TramFnB';
    final tabName = _tab.name.toUpperCase();
    final path = await _fb.exportReportExcel(
      storeName: storeName,
      reportType: 'DoanhThu_$tabName',
      bills: _filteredBills,
    );
    if (path != null) {
      await Share.shareXFiles([XFile(path)], text: 'Báo cáo doanh thu $tabName - $storeName');
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xuất báo cáo thất bại!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _bills.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: TramColors.brandPrimary));
    }

    final range = _currentRange;
    final chartData = _chartData;
    final filtered = _filteredBills;

    return RefreshIndicator(
      color: TramColors.brandPrimary,
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. Header & Export Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Báo Cáo Doanh Thu 💰',
                    style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold, color: TramColors.textPrimary),
                  ),
                  Text(
                    'Phân tích & đối soát tài chính theo kỳ',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: TramColors.brandPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text('Xuất Excel', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _exportExcel,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Tab Period Selector (Ngày / Tuần / Tháng / Năm)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _buildPeriodTab('Ngày', RevenueTabType.day),
                _buildPeriodTab('Tuần', RevenueTabType.week),
                _buildPeriodTab('Tháng', RevenueTabType.month),
                _buildPeriodTab('Năm', RevenueTabType.year),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Quick Filter Chips (Hôm nay, Hôm qua, Tháng này, Tháng trước)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildQuickFilterChip('Hôm nay', () {
                  setState(() {
                    _tab = RevenueTabType.day;
                    _offset = 0;
                  });
                }, _tab == RevenueTabType.day && _offset == 0),
                const SizedBox(width: 8),
                _buildQuickFilterChip('Hôm qua', () {
                  setState(() {
                    _tab = RevenueTabType.day;
                    _offset = 1;
                  });
                }, _tab == RevenueTabType.day && _offset == 1),
                const SizedBox(width: 8),
                _buildQuickFilterChip('Tháng này', () {
                  setState(() {
                    _tab = RevenueTabType.month;
                    _offset = 0;
                  });
                }, _tab == RevenueTabType.month && _offset == 0),
                const SizedBox(width: 8),
                _buildQuickFilterChip('Tháng trước', () {
                  setState(() {
                    _tab = RevenueTabType.month;
                    _offset = 1;
                  });
                }, _tab == RevenueTabType.month && _offset == 1),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Navigation Controls (Trước / Sau / DatePicker)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: TramColors.borderLight),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Kỳ trước',
                  onPressed: () => setState(() => _offset++),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickCustomDate,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_month, size: 16, color: TramColors.brandPrimary),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              range['label'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: TramColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Kỳ sau',
                  onPressed: _offset > 0 ? () => setState(() => _offset--) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Grid Thẻ Thống Kê
          if (_tab == RevenueTabType.day) ...[
            _buildSummaryCard(
              title: 'Doanh thu ước tính ngày',
              value: FormatUtils.vnd(_totalRevenue + _servingTotal),
              subtitle: 'Công thức: Đã thu (${FormatUtils.vnd(_totalRevenue)}) + Phục vụ (${FormatUtils.vnd(_servingTotal)})',
              icon: Icons.trending_up,
              color: const Color(0xFF059669),
              fullWidth: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Tổng doanh thu',
                    value: FormatUtils.vnd(_totalRevenue),
                    subtitle: '${filtered.length} hóa đơn đã thu',
                    icon: Icons.monetization_on,
                    color: TramColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Đang phục vụ',
                    value: FormatUtils.vnd(_servingTotal),
                    subtitle: '$_servingCount bàn đang dùng',
                    icon: Icons.table_restaurant_outlined,
                    color: const Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Mang về',
                    value: FormatUtils.vnd(_takeawayRevenue),
                    subtitle: '$_takeawayCount hóa đơn mang về',
                    icon: Icons.shopping_bag_outlined,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Tiền mặt',
                    value: FormatUtils.vnd(_cashRevenue),
                    subtitle: 'Doanh thu tiền mặt',
                    icon: Icons.payments_outlined,
                    color: TramColors.success,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Chuyển khoản (QR)',
                    value: FormatUtils.vnd(_transferRevenue),
                    subtitle: 'Chuyển khoản / VietQR',
                    icon: Icons.qr_code_2,
                    color: TramColors.info,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'TB / Đơn',
                    value: FormatUtils.vnd(_avgPerOrder),
                    subtitle: 'Giá trị TB mỗi hóa đơn',
                    icon: Icons.analytics_outlined,
                    color: TramColors.warning,
                  ),
                ),
              ],
            ),
            if (_servingCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDBEAFE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.table_restaurant, color: Color(0xFF2563EB), size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Đang phục vụ $_servingCount bàn (Chưa thanh toán)',
                                style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold, color: const Color(0xFF1E3A8A)),
                              ),
                              Text(
                                'Tổng tạm tính: ${FormatUtils.vnd(_servingTotal)}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: const Color(0xFF2563EB)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _servingTables.map((st) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF93C5FD)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF22C55E),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${st.name} (${st.zone}): ',
                                style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF1E40AF)),
                              ),
                              Text(
                                FormatUtils.vnd(st.currentTotal),
                                style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF1D4ED8)),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Tổng doanh thu',
                    value: FormatUtils.vnd(_totalRevenue),
                    subtitle: '${filtered.length} đơn hoàn tất',
                    icon: Icons.monetization_on,
                    color: TramColors.brandPrimary,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Mang về',
                    value: FormatUtils.vnd(_takeawayRevenue),
                    subtitle: '$_takeawayCount hóa đơn mang về',
                    icon: Icons.shopping_bag_outlined,
                    color: const Color(0xFF8B5CF6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Tiền mặt',
                    value: FormatUtils.vnd(_cashRevenue),
                    subtitle: 'Doanh thu tiền mặt',
                    icon: Icons.payments_outlined,
                    color: TramColors.success,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Chuyển khoản (QR)',
                    value: FormatUtils.vnd(_transferRevenue),
                    subtitle: 'Chuyển khoản / VietQR',
                    icon: Icons.qr_code_2,
                    color: TramColors.info,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSummaryCard(
              title: 'Giá trị trung bình mỗi đơn (TB/Đơn)',
              value: FormatUtils.vnd(_avgPerOrder),
              subtitle: 'Doanh thu bình quân mỗi hóa đơn',
              icon: Icons.analytics_outlined,
              color: TramColors.warning,
              fullWidth: true,
            ),
          ],
          const SizedBox(height: 24),

          // 5. Biểu Đồ Cột Doanh Thu Tương Tác
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
                    Text(
                      'Biểu đồ doanh thu',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      range['label'],
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 220,
                  child: _buildBarChart(chartData),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 6. Chi Tiết Danh Sách Hóa Đơn Trong Kỳ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Danh sách hóa đơn (${filtered.length})',
                style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              Text(
                'Chạm để xem chi tiết món',
                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),

          if (filtered.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TramColors.borderLight),
              ),
              child: Column(
                children: [
                  const Icon(Icons.receipt_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(
                    'Không có hóa đơn nào trong khoảng thời gian này',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final bill = filtered[index];
                final time = FormatUtils.dateTime(bill.closedAt ?? bill.createdAt);
                final isCash = bill.paymentMethod.toLowerCase().contains('cash') || bill.paymentMethod.toLowerCase().contains('tiền mặt');

                return InkWell(
                  onTap: () => BillDetailSheet.show(context, bill),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TramColors.borderLight),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (isCash ? TramColors.success : TramColors.info).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isCash ? Icons.payments_outlined : Icons.qr_code_2,
                            color: isCash ? TramColors.success : TramColors.info,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    bill.billCode,
                                    style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        bill.tableName.isNotEmpty ? bill.tableName : 'Mang về',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.bold, color: TramColors.brandPrimary),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '$time • Thu ngân: ${bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername}',
                                style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              FormatUtils.vnd(bill.finalAmount),
                              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: TramColors.brandPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${bill.items.length} món',
                              style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildPeriodTab(String label, RevenueTabType type) {
    final isSelected = _tab == type;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          _tab = type;
          _offset = 0;
        }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? const [BoxShadow(color: Color(0x0A000000), blurRadius: 4, offset: Offset(0, 2))]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.beVietnamPro(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? TramColors.brandPrimary : TramColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
    bool fullWidth = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TramColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold, color: TramColors.textPrimary),
                ),
                Text(
                  title,
                  style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.w600, color: TramColors.textSecondary),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: GoogleFonts.beVietnamPro(fontSize: 10, color: Colors.grey.shade500),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();
    final maxRevenue = data.map((e) => (e['revenue'] as int).toDouble()).fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxRevenue > 0 ? maxRevenue * 1.25 : 100000.0;

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final item = data[group.x.toInt()];
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
              reservedSize: 42,
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
                if (idx >= 0 && idx < data.length) {
                  // For 24 hours, show every 4 hours to avoid crowding
                  if (_tab == RevenueTabType.day && idx % 3 != 0) {
                    return const SizedBox.shrink();
                  }
                  // For month (up to 31 days), show every 5 days
                  if (_tab == RevenueTabType.month && idx % 5 != 0 && idx != data.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data[idx]['label'],
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
        barGroups: List.generate(data.length, (i) {
          final rev = (data[i]['revenue'] as int).toDouble();
          return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: rev,
                color: TramColors.brandPrimary,
                width: _tab == RevenueTabType.month ? 6 : (_tab == RevenueTabType.day ? 8 : 16),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildQuickFilterChip(String label, VoidCallback onTap, bool active) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? TramColors.brandPrimary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? TramColors.brandPrimary : TramColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            fontSize: 12,
            fontWeight: active ? FontWeight.bold : FontWeight.w500,
            color: active ? Colors.white : TramColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
