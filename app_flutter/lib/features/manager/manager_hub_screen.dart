// lib/features/manager/manager_hub_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'tabs/overview_tab.dart';
import 'tabs/revenue_tab.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/bills_tab.dart';
import 'tabs/audit_tab.dart';
import '../reports/reports_hub_screen.dart';
import '../crm/customer_management_screen.dart';

class ManagerHubScreen extends StatefulWidget {
  final int initialTab;

  const ManagerHubScreen({super.key, this.initialTab = 0});

  @override
  State<ManagerHubScreen> createState() => _ManagerHubScreenState();
}

class _ManagerHubScreenState extends State<ManagerHubScreen> {
  final _auth = AuthService();
  final _fb = FirebaseService();
  late int _currentIndex;
  // Danh sách chi nhánh nạp từ Firebase; khởi tạo bằng chi nhánh đang đăng nhập
  List<StoreInfoModel> _stores = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    final current = _auth.currentStoreInfo;
    if (current != null) _stores = [current];
    _loadStores();
  }

  @override
  void didUpdateWidget(ManagerHubScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      setState(() => _currentIndex = widget.initialTab);
    }
  }

  Future<void> _loadStores() async {
    try {
      final list = await _fb.getAllStores();
      if (mounted && list.isNotEmpty) {
        setState(() => _stores = list);
      }
    } catch (_) {}
    _fb.storesStream().listen((list) {
      if (mounted && list.isNotEmpty) setState(() => _stores = list);
    });
  }

  void _showStoreSwitcherDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.storefront, color: TramColors.brandPrimary),
            const SizedBox(width: 8),
            Text(
              'Chọn Chi Nhánh',
              style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: _stores.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _stores.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = _stores[index];
                    final isCurrent = s.storeCode == _auth.currentStoreCode;
                    return ListTile(
                      leading: Icon(
                        isCurrent ? Icons.check_circle : Icons.store,
                        color: isCurrent ? TramColors.brandPrimary : Colors.grey,
                      ),
                      title: Text(
                        s.storeName,
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? TramColors.brandPrimary : TramColors.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Mã CH: ${s.storeCode} ${s.address.isNotEmpty ? "• ${s.address}" : ""}',
                        style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.textSecondary),
                      ),
                      onTap: () async {
                        final sName = s.storeName;
                        final sCode = s.storeCode;
                        final sm = ScaffoldMessenger.of(context);
                        Navigator.pop(ctx);
                        if (!isCurrent) {
                          await _auth.switchStore(sCode);
                          if (!mounted) return;
                          sm.showSnackBar(
                            SnackBar(
                              content: Text('Đã chuyển sang chi nhánh: $sName ($sCode)'),
                              backgroundColor: TramColors.success,
                            ),
                          );
                          setState(() {});
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _auth,
      builder: (context, _) {
        final currentStore = _auth.currentStoreInfo;
        final storeName = currentStore?.storeName ?? 'POS Trạm';
        final storeCode = _auth.currentStoreCode;
        final roleName = _auth.isOwner ? 'CHỦ QUÁN' : 'QUẢN LÝ';

        return Scaffold(
          backgroundColor: TramColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: TramColors.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
            elevation: 0.5,
            scrolledUnderElevation: 0,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            title: InkWell(
              onTap: _auth.canAccessManagerHub ? _showStoreSwitcherDialog : null,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: TramColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_auth.canAccessManagerHub) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 20, color: TramColors.brandPrimary),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: _auth.isOwner ? Colors.black : TramColors.accent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          roleName,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'CH: $storeCode • ${_auth.currentUser?.fullName ?? ""}',
                        style: GoogleFonts.beVietnamPro(fontSize: 10, color: TramColors.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              // Nút nhỏ chuyển sang chế độ Bán Hàng (Full POS nghiệp vụ nhân viên)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: TramColors.brandPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                    minimumSize: const Size(0, 30),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.point_of_sale, size: 13),
                  label: Text(
                    'Bán Hàng',
                    style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    context.go('/tables');
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.assessment_outlined, color: TramColors.brandPrimary, size: 20),
                tooltip: 'Trung tâm Báo cáo',
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: TramColors.textPrimary, size: 20),
                tooltip: 'Làm mới',
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() {}),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: TramColors.textPrimary, size: 20),
                tooltip: 'Tuỳ chọn',
                onSelected: (val) async {
                  if (val == 'REPORTS') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportsHubScreen()),
                    );
                  } else if (val == 'CUSTOMERS') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomerManagementScreen()),
                    );
                  } else if (val == 'STORE') {
                    _showStoreSwitcherDialog();
                  } else if (val == 'LOGOUT') {
                    await _auth.logout();
                    if (mounted) context.go('/login');
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'REPORTS',
                    child: Row(
                      children: [
                        Icon(Icons.assessment_outlined, size: 18, color: TramColors.brandPrimary),
                        SizedBox(width: 8),
                        Text('Trung tâm Báo cáo (12 BC)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'CUSTOMERS',
                    child: Row(
                      children: [
                        Icon(Icons.people_outline, size: 18, color: TramColors.brandPrimary),
                        SizedBox(width: 8),
                        Text('Khách hàng & Tích điểm KMT'),
                      ],
                    ),
                  ),
                  if (_auth.canAccessManagerHub)
                    const PopupMenuItem(
                      value: 'STORE',
                      child: Row(
                        children: [
                          Icon(Icons.storefront, size: 18, color: TramColors.brandPrimary),
                          SizedBox(width: 8),
                          Text('Đổi chi nhánh'),
                        ],
                      ),
                    ),
                  const PopupMenuItem(
                    value: 'LOGOUT',
                    child: Row(
                      children: [
                        Icon(Icons.logout, size: 18, color: TramColors.danger),
                        SizedBox(width: 8),
                        Text('Đăng xuất', style: TextStyle(color: TramColors.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            key: ValueKey('hub_body_${_auth.currentStoreCode}'),
            index: _currentIndex,
            children: [
              OverviewTab(
                key: ValueKey('overview_${_auth.currentStoreCode}'),
                onGoToPOS: () => context.go('/tables'),
                onGoToRevenue: () => setState(() => _currentIndex = 1),
                onGoToAnalytics: () => setState(() => _currentIndex = 2),
                onGoToBills: () => setState(() => _currentIndex = 3),
                onGoToAudit: () => setState(() => _currentIndex = 4),
              ),
              RevenueTab(key: ValueKey('revenue_${_auth.currentStoreCode}')),
              AnalyticsTab(key: ValueKey('analytics_${_auth.currentStoreCode}')),
              BillsTab(key: ValueKey('bills_${_auth.currentStoreCode}')),
              AuditTab(key: ValueKey('audit_${_auth.currentStoreCode}')),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: TramColors.borderLight, width: 1)),
              boxShadow: const [
                BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, -2)),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: TramColors.brandPrimary,
              unselectedItemColor: TramColors.textSecondary,
              selectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold),
              unselectedLabelStyle: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.normal),
              elevation: 0,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Tổng quan',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.monetization_on_outlined),
                  activeIcon: Icon(Icons.monetization_on),
                  label: 'Doanh thu',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.bar_chart_outlined),
                  activeIcon: Icon(Icons.bar_chart),
                  label: 'Phân tích',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.receipt_long_outlined),
                  activeIcon: Icon(Icons.receipt_long),
                  label: 'Hóa đơn',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.shield_outlined),
                  activeIcon: Icon(Icons.shield),
                  label: 'Giám sát',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
