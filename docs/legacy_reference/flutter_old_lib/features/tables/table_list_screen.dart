// lib/features/tables/table_list_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/common_widgets.dart';

class TableListScreen extends StatefulWidget {
  const TableListScreen({super.key});

  @override
  State<TableListScreen> createState() => _TableListScreenState();
}

class _TableListScreenState extends State<TableListScreen> with TickerProviderStateMixin {
  final _auth = AuthService();
  final _fb = FirebaseService();
  
  String _zoneFilter = '';
  int _statusFilter = 0; // 0=all, 1=occupied, 2=free
  List<ZoneModel> _zones = [];
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _statusFilter = _tabController.index);
      }
    });
    _loadZones();
    _setupNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadZones() {
    _fb.zonesStream().listen((zones) {
      if (mounted) setState(() => _zones = zones);
    });
  }

  void _setupNotifications() {
    // Kitchen done notifications
    _fb.kitchenOrdersRef.onChildChanged.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data is Map && data['isDone'] == true) {
        _showKitchenDoneAlert(data['tableName']?.toString() ?? '');
      }
    });

    // Online order notifications (for STAFF)
    if (_auth.isStaff) {
      _fb.onlineOrdersRef.onChildAdded.listen((event) {
        if (!mounted) return;
        final data = event.snapshot.value;
        if (data is Map) {
          final status = data['status']?.toString();
          final type = data['type']?.toString();
          if (status == 'PENDING') {
            final msg = type == 'CALL_WAITER'
              ? '🔔 Bàn ${data['tableName']} đang gọi nhân viên!'
              : '📦 Đơn mới từ bàn ${data['tableName']}';
            _showNotificationSnackbar(msg);
            HapticFeedback.heavyImpact();
          }
        }
      });
    }
  }

  void _showKitchenDoneAlert(String tableName) {
    HapticFeedback.vibrate();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: AppColors.success, size: 24),
            ),
            const SizedBox(width: 12),
            Text('Bếp báo xong món', style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700,
            )),
          ],
        ),
        content: Text(
          'Bếp đã hoàn thành đơn bàn: $tableName',
          style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  void _showNotificationSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    String selectedZone = _zones.isNotEmpty ? _zones.first.name : 'Khu A';
    
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text('Thêm bàn mới', style: GoogleFonts.beVietnamPro(
            color: AppColors.textPrimary, fontWeight: FontWeight.w700,
          )),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Tên bàn (VD: A1, B2)',
                  prefixIcon: Icon(Icons.table_restaurant, color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedZone,
                dropdownColor: AppColors.card,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Khu vực',
                  prefixIcon: Icon(Icons.location_on_outlined, color: AppColors.textSecondary),
                ),
                items: _zones.map((z) => DropdownMenuItem(value: z.name, child: Text(z.name))).toList(),
                onChanged: (v) => setSt(() => selectedZone = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isNotEmpty) {
                  await _fb.addTable(nameCtrl.text.trim(), selectedZone);
                  if (mounted) Navigator.pop(ctx);
                }
              },
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _buildDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildZoneFilter(),
            _buildStatusTabs(),
            Expanded(child: _buildTableGrid()),
          ],
        ),
      ),
      floatingActionButton: _auth.isManager
        ? FloatingActionButton.extended(
            onPressed: _showAddTableDialog,
            icon: const Icon(Icons.add),
            label: Text('Thêm bàn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
            backgroundColor: AppColors.primary,
          )
        : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(Icons.menu, color: AppColors.textPrimary, size: 20),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh sách bàn',
                  style: GoogleFonts.beVietnamPro(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _auth.currentUser?.fullName ?? '',
                  style: GoogleFonts.beVietnamPro(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (_auth.isManager)
            GestureDetector(
              onTap: () => context.push('/menu-management'),
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
                    const Icon(Icons.restaurant_menu, color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text('Thực đơn', style: GoogleFonts.beVietnamPro(
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

  Widget _buildZoneFilter() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildZoneChip('Tất cả', ''),
            ...(_zones.map((z) => _buildZoneChip(z.name, z.name))),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneChip(String label, String value) {
    final isSelected = _zoneFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _zoneFilter = value),
      child: AnimatedContainer(
        duration: 200.ms,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.beVietnamPro(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTabs() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(text: 'Tất cả'),
          Tab(text: 'Đang dùng'),
          Tab(text: 'Trống'),
        ],
      ),
    );
  }

  Widget _buildTableGrid() {
    return StreamBuilder<List<TableModel>>(
      stream: _fb.tablesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        
        final allTables = snapshot.data ?? [];
        final tables = allTables.where((t) {
          final matchZone = _zoneFilter.isEmpty || t.zone == _zoneFilter;
          final matchStatus = _statusFilter == 0 ||
            (_statusFilter == 1 && t.inUse) ||
            (_statusFilter == 2 && !t.inUse);
          return matchZone && matchStatus;
        }).toList();

        if (tables.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.table_restaurant_outlined, color: AppColors.textHint, size: 64),
                const SizedBox(height: 16),
                Text('Không có bàn', style: GoogleFonts.beVietnamPro(
                  color: AppColors.textHint, fontSize: 16,
                )),
              ],
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.1,
          ),
          itemCount: tables.length,
          itemBuilder: (ctx, i) => TableCard(
            table: tables[i],
            isManager: _auth.isManager,
            onTap: () {
              if (tables[i].inUse) {
                context.push('/order-cart', extra: {
                  'table': tables[i],
                  'products': tables[i].currentOrder,
                });
              } else {
                context.push('/order-list', extra: tables[i]);
              }
            },
            onQRTap: () => context.push('/qr-code', extra: {
              'tableName': tables[i].name,
              'tableZone': tables[i].zone,
            }),
            onDelete: _auth.isManager ? () => _confirmDeleteTable(tables[i]) : null,
          ).animate(delay: (i * 40).ms).fadeIn(duration: 300.ms).scale(
            begin: const Offset(0.9, 0.9),
            curve: Curves.easeOutBack,
          ),
        );
      },
    );
  }

  void _confirmDeleteTable(TableModel table) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Xóa bàn', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700,
        )),
        content: Text('Xóa bàn "${table.name}"? Hành động này không thể hoàn tác.',
          style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              await _fb.deleteTable(table);
              if (mounted) Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final user = _auth.currentUser;
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, Color(0xFFE55A28)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.2),
                    ),
                    child: Center(
                      child: Text(
                        user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : 'U',
                        style: GoogleFonts.beVietnamPro(
                          color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.fullName ?? '',
                          style: GoogleFonts.beVietnamPro(
                            color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          FormatUtils.roleLabel(user?.role ?? ''),
                          style: GoogleFonts.beVietnamPro(
                            color: Colors.white.withOpacity(0.8), fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Menu items
            if (_auth.isManager) ...[
              _drawerItem(Icons.dashboard_outlined, 'Dashboard', '/dashboard'),
              _drawerItem(Icons.history_outlined, 'Lịch sử đơn hàng', '/history'),
              _drawerItem(Icons.restaurant_menu_outlined, 'Quản lý thực đơn', '/menu-management'),
              _drawerItem(Icons.category_outlined, 'Quản lý danh mục', '/category-management'),
              _drawerItem(Icons.map_outlined, 'Quản lý khu vực', '/zone-management'),
              _drawerItem(Icons.people_outline, 'Quản lý nhân viên', '/user-management'),
              _drawerItem(Icons.smartphone_outlined, 'Đơn hàng online', '/online-orders'),
            ] else ...[
              _drawerItem(Icons.history_outlined, 'Lịch sử đơn hàng', '/history'),
              _drawerItem(Icons.smartphone_outlined, 'Đơn hàng online', '/online-orders'),
            ],

            const Spacer(),
            const Divider(color: AppColors.border),
            _drawerItem(Icons.logout_outlined, 'Đăng xuất', null, isLogout: true, isRed: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem(IconData icon, String label, String? route, {bool isLogout = false, bool isRed = false}) {
    return ListTile(
      leading: Icon(icon, color: isRed ? AppColors.danger : AppColors.textSecondary, size: 22),
      title: Text(label, style: GoogleFonts.beVietnamPro(
        color: isRed ? AppColors.danger : AppColors.textPrimary,
        fontWeight: FontWeight.w500,
        fontSize: 14,
      )),
      onTap: () async {
        Navigator.pop(context);
        if (isLogout) {
          await AuthService().logout();
          if (mounted) context.go('/login');
        } else if (route != null) {
          context.push(route);
        }
      },
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

// ==================== TABLE CARD WIDGET ====================
class TableCard extends StatelessWidget {
  final TableModel table;
  final bool isManager;
  final VoidCallback onTap;
  final VoidCallback onQRTap;
  final VoidCallback? onDelete;

  const TableCard({
    super.key,
    required this.table,
    required this.isManager,
    required this.onTap,
    required this.onQRTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: isManager ? () => _showContextMenu(context) : null,
      child: AnimatedContainer(
        duration: 300.ms,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: table.inUse
            ? LinearGradient(
                colors: [
                  AppColors.tableOccupied.withOpacity(0.2),
                  AppColors.tableOccupied.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
          color: table.inUse ? null : AppColors.card,
          border: Border.all(
            color: table.inUse ? AppColors.tableOccupied.withOpacity(0.5) : AppColors.border,
            width: table.inUse ? 1.5 : 1,
          ),
          boxShadow: table.inUse
            ? [BoxShadow(
                color: AppColors.tableOccupied.withOpacity(0.2),
                blurRadius: 12,
                offset: const Offset(0, 4),
              )]
            : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: table.inUse
                        ? AppColors.tableOccupied.withOpacity(0.15)
                        : AppColors.cardElevated,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.table_restaurant,
                      color: table.inUse ? AppColors.tableOccupied : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  // Status indicator with pulse animation
                  if (table.inUse)
                    _PulseIndicator(color: AppColors.tableOccupied)
                  else
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.tableFree,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),

              const Spacer(),

              Text(
                table.name,
                style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                table.zone,
                style: GoogleFonts.beVietnamPro(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),

              if (table.inUse && table.currentTotal > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.tableOccupied.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    FormatUtils.currency(table.currentTotal),
                    style: GoogleFonts.beVietnamPro(
                      color: AppColors.tableOccupied,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text('Bàn ${table.name}', style: GoogleFonts.beVietnamPro(
              color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700,
            )),
            const SizedBox(height: 16),
            _menuOption(context, Icons.qr_code_2, 'Xem mã QR bàn', onQRTap),
            if (onDelete != null)
              _menuOption(context, Icons.delete_outline, 'Xóa bàn này', onDelete!, isRed: true),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _menuOption(BuildContext ctx, IconData icon, String label, VoidCallback action, {bool isRed = false}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isRed ? AppColors.danger : AppColors.primary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isRed ? AppColors.danger : AppColors.primary, size: 20),
      ),
      title: Text(label, style: GoogleFonts.beVietnamPro(
        color: isRed ? AppColors.danger : AppColors.textPrimary,
        fontWeight: FontWeight.w500,
      )),
      onTap: () { Navigator.pop(ctx); action(); },
    );
  }
}

class _PulseIndicator extends StatefulWidget {
  final Color color;
  const _PulseIndicator({required this.color});

  @override
  State<_PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<_PulseIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: 1.5.seconds)..repeat(reverse: true);
    _anim = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color.withOpacity(_anim.value),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(
            color: widget.color.withOpacity(_anim.value * 0.5),
            blurRadius: 6,
            spreadRadius: 2,
          )],
        ),
      ),
    );
  }
}
