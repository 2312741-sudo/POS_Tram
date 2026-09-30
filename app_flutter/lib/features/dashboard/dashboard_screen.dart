// lib/features/dashboard/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
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
  final _auth = AuthService();

  List<BillModel> _bills = [];
  List<TableModel> _tables = [];
  List<OnlineOrderModel> _onlineOrders = [];
  bool _loading = false;

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
  }

  List<BillModel> get _todayPaidBills {
    final now = DateTime.now();
    return _bills.where((b) {
      if (b.status != 'PAID') return false;
      final dt = DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt);
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
  }

  int get _todayRevenue => _todayPaidBills.fold(0, (s, o) => s + o.finalAmount);
  int get _todayDiscounts => _todayPaidBills.fold(0, (s, o) => s + o.totalDiscount);
  int get _occupiedTables => _tables.where((t) => t.inUse).length;
  int get _pendingOnline => _onlineOrders.where((o) => o.isPending).length;

  Map<String, int> get _topProducts {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Báo Cáo Tổng Quan Hôm Nay', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Xuất Báo Cáo Excel (Trạm)',
            onPressed: () async {
              final storeName = _auth.currentStoreInfo?.storeName ?? 'TramFnB';
              final path = await _fb.exportReportExcel(
                storeName: storeName,
                reportType: 'DoanhThu',
                bills: _todayPaidBills,
              );
              if (mounted) {
                if (path != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã xuất file Excel: $path'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Không có dữ liệu hoặc xuất thất bại!')),
                  );
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Store Info Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.storefront, size: 32, color: AppColors.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _auth.currentStoreInfo?.storeName ?? 'POS Trạm',
                                style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryDark),
                              ),
                              Text(
                                'Mã CH: ${_auth.currentStoreCode} • Ngày: ${FormatUtils.dateOnly(DateTime.now().millisecondsSinceEpoch)}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Stat Cards Grid
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      StatCard(
                        title: 'Doanh thu hôm nay',
                        value: FormatUtils.vnd(_todayRevenue),
                        icon: Icons.monetization_on,
                        color: AppColors.success,
                      ),
                      StatCard(
                        title: 'Số đơn đã bán',
                        value: '${_todayPaidBills.length} đơn',
                        icon: Icons.receipt_long,
                        color: AppColors.primary,
                      ),
                      StatCard(
                        title: 'Bàn đang phục vụ',
                        value: '$_occupiedTables/${_tables.length} bàn',
                        icon: Icons.table_restaurant,
                        color: AppColors.warning,
                      ),
                      StatCard(
                        title: 'Tổng khuyến mãi đã giảm',
                        value: FormatUtils.vnd(_todayDiscounts),
                        icon: Icons.discount,
                        color: AppColors.danger,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Top Selling Items
                  Text('Top 5 món bán chạy nhất:', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 12),
                  if (_topProducts.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Center(child: Text('Chưa có dữ liệu bán hàng hôm nay', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary))),
                      ),
                    )
                  else
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: _topProducts.entries.map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: AppColors.primaryLight, shape: BoxShape.circle),
                                    child: const Icon(Icons.local_fire_department, size: 16, color: AppColors.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Text(e.key, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 13))),
                                  Text('${e.value} phần', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: AppColors.primary)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  // Navigation Shortcuts
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.history),
                          label: const Text('Xem Lịch Sử Hóa Đơn'),
                          onPressed: () => context.push('/history'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.security),
                          label: const Text('Xem Audit Log'),
                          onPressed: () => context.push('/audit-logs'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }
}
