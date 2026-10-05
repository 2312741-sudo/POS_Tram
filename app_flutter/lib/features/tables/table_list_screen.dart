// lib/features/tables/table_list_screen.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../cash_shift/cash_shift_dialog.dart';
import '../auth/change_password_dialog.dart';

class TableListScreen extends StatefulWidget {
  const TableListScreen({super.key});

  @override
  State<TableListScreen> createState() => _TableListScreenState();
}

class _TableListScreenState extends State<TableListScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();
  String _selectedZone = 'Tất cả';
  String _statusFilter = 'ALL'; // 'ALL', 'EMPTY', 'IN_USE', 'RESERVED'
  bool _hasCheckedShift = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialCashShift();
    });
  }

  Future<void> _checkInitialCashShift() async {
    if (_hasCheckedShift) return;
    _hasCheckedShift = true;
    final shift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
    if ((shift == null || !shift.isOpen) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Chức năng order đang bị khóa! Vui lòng khai báo tiền két đầu ca để bắt đầu.'),
          backgroundColor: TramColors.warningInk,
          duration: Duration(seconds: 4),
        ),
      );
      await CashShiftDialog.show(context);
    }
  }

  void _navigateTo(String path) {
    Navigator.of(context).pop();
    Future.microtask(() {
      if (mounted) context.push(path);
    });
  }

  void _showStoreSwitcherDialog() {
    final stores = [
      StoreInfoModel(
        storeCode: 'TRAM01',
        storeName: 'POS Trạm - Trụ sở 01 (Đà Lạt)',
        address: 'Số 123 Đường Ba Tháng Tư, Phường 3, TP. Đà Lạt',
      ),
      StoreInfoModel(
        storeCode: 'TRAM02',
        storeName: 'POS Trạm - Chi nhánh 02 (Sài Gòn)',
        address: 'Số 456 Nguyễn Thị Minh Khai, Quận 1, TP. Hồ Chí Minh',
      ),
    ];

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
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: stores.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final s = stores[index];
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
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu chức năng',
                onPressed: () => Scaffold.of(ctx).openDrawer(),
              ),
            ),
            title: InkWell(
              onTap: _auth.canAccessManagerHub ? _showStoreSwitcherDialog : null,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _auth.currentStoreInfo?.storeName ?? 'POS Trạm',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_auth.canAccessManagerHub) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 20, color: Colors.white70),
                      ],
                    ],
                  ),
                  Text(
                    'CH: ${_auth.currentStoreCode} • ${_auth.currentUser?.fullName ?? ""}',
                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.white70),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        actions: [
          // Ca Két Tiền KiotViet button
          StreamBuilder<List<CashShiftModel>>(
            stream: _fb.cashShiftsStream(),
            initialData: _fb.activeShiftCache != null ? [_fb.activeShiftCache!] : null,
            builder: (context, snapshot) {
              final shifts = snapshot.data ?? (_fb.activeShiftCache != null ? [_fb.activeShiftCache!] : <CashShiftModel>[]);
              final activeShift = shifts.where((s) => s.isOpen).firstOrNull ?? _fb.activeShiftCache;
              final isOpen = activeShift != null && activeShift.isOpen;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: InkWell(
                  onTap: () => CashShiftDialog.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isOpen ? Colors.green.shade800 : Colors.amber.shade900,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isOpen ? Icons.point_of_sale : Icons.lock_clock,
                          size: 15,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isOpen ? 'Ca mở' : 'Mở ca',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Đơn Online',
            onPressed: () => context.push('/online-orders'),
          ),
          if (_auth.canAccessManagerHub)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: TramColors.brandPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  minimumSize: const Size(0, 32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.analytics_outlined, size: 14),
                label: Text(
                  'Quản Trị',
                  style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => context.go('/manager-hub'),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.dashboard_outlined),
              tooltip: 'Tổng quan / Báo cáo',
              onPressed: () => context.push('/dashboard'),
            ),
        ],
      ),
      drawer: _buildDrawer(),
      body: StreamBuilder<List<TableModel>>(
        key: ValueKey('tables_stream_${_auth.currentStoreCode}'),
        stream: _fb.tablesStream(),
        initialData: _fb.defaultTables,
        builder: (context, snapshot) {
          final allTables = (snapshot.data != null && snapshot.data!.isNotEmpty)
              ? snapshot.data!
              : _fb.defaultTables;
          final zones = ['Tất cả', ...allTables.map((t) => t.zone).toSet()];
          if (!zones.contains(_selectedZone)) {
            _selectedZone = 'Tất cả';
          }

          final emptyCount = allTables.where((t) => !t.inUse && !t.isReserved).length;
          final inUseCount = allTables.where((t) => t.inUse).length;
          final reservedCount = allTables.where((t) => t.isReserved).length;

          // Filter by zone
          var list = _selectedZone == 'Tất cả'
              ? allTables
              : allTables.where((t) => t.zone == _selectedZone).toList();

          // Filter by status
          if (_statusFilter == 'EMPTY') {
            list = list.where((t) => !t.inUse && !t.isReserved).toList();
          } else if (_statusFilter == 'IN_USE') {
            list = list.where((t) => t.inUse).toList();
          } else if (_statusFilter == 'RESERVED') {
            list = list.where((t) => t.isReserved).toList();
          }

          return Column(
            children: [
              // Banner cảnh báo khóa order nếu chưa mở két
              StreamBuilder<List<CashShiftModel>>(
                stream: _fb.cashShiftsStream(),
                initialData: _fb.activeShiftCache != null ? [_fb.activeShiftCache!] : null,
                builder: (context, shiftSnap) {
                  if (shiftSnap.connectionState == ConnectionState.waiting && shiftSnap.data == null && _fb.activeShiftCache == null) {
                    return const SizedBox.shrink();
                  }
                  final shifts = shiftSnap.data ?? (_fb.activeShiftCache != null ? [_fb.activeShiftCache!] : <CashShiftModel>[]);
                  final activeShift = shifts.where((s) => s.isOpen).firstOrNull ?? _fb.activeShiftCache;
                  final isShiftOpen = activeShift != null && activeShift.isOpen;

                  if (isShiftOpen) return const SizedBox.shrink();

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock, color: Colors.white, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ĐANG KHÓA ORDER • CHƯA NHẬP KÉT TIỀN',
                                style: GoogleFonts.beVietnamPro(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Vui lòng khai báo số tiền mặt đầu ca để mở khóa nhận đơn.',
                                style: GoogleFonts.beVietnamPro(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.amber.shade900,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.point_of_sale, size: 14),
                          label: const Text('Mở Ca', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () => CashShiftDialog.show(context),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Zone filter chips
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.white,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: zones.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final z = zones[index];
                    final isSelected = z == _selectedZone;
                    return ChoiceChip(
                      label: Text(z),
                      selected: isSelected,
                      selectedColor: AppColors.primaryLight,
                      labelStyle: TextStyle(
                        color: isSelected ? AppColors.primaryDark : AppColors.textPrimary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedZone = z);
                      },
                    );
                  },
                ),
              ),

              // Summary status bar (interactive filter tabs)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: AppColors.cardElevated,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildStatusFilterChip('ALL', 'Tất cả (${allTables.length})', AppColors.textPrimary),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip('EMPTY', 'Trống ($emptyCount)', AppColors.tableEmptyBorder),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip('IN_USE', 'Có khách ($inUseCount)', AppColors.primary),
                      const SizedBox(width: 8),
                      _buildStatusFilterChip('RESERVED', 'Đặt trước ($reservedCount)', TramColors.tableReserved),
                    ],
                  ),
                ),
              ),

              // Tables Grid
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.table_restaurant_outlined, size: 64, color: AppColors.textHint),
                            const SizedBox(height: 12),
                            Text('Chưa có bàn nào phù hợp bộ lọc', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.05,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final table = list[index];
                          return _buildTableCard(table, allTables);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _auth.can(AppPermissions.openTable)
          ? FloatingActionButton.extended(
              onPressed: () => _showAddTableDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Thêm Bàn'),
            )
          : null,
        );
      },
    );
  }

  Widget _buildStatusFilterChip(String key, String label, Color dotColor) {
    final isSelected = _statusFilter == key;
    return InkWell(
      onTap: () => setState(() => _statusFilter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? dotColor.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? dotColor : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.beVietnamPro(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? dotColor : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableCard(TableModel table, List<TableModel> allTables) {
    final bool inUse = table.inUse;
    final bool isReserved = table.isReserved;
    final int itemsCount = table.currentItems.fold(0, (sum, i) => sum + i.quantity);
    final int totalAmount = table.currentItems.fold(0, (sum, i) => sum + i.itemTotal);

    // Color definitions based on state
    Color cardBg;
    Color borderColor;
    String statusText;
    Color statusColor;

    if (inUse) {
      cardBg = const Color(0xFFFFF0F1);
      borderColor = AppColors.primary;
      statusText = 'Có khách';
      statusColor = AppColors.primary;
    } else if (isReserved) {
      cardBg = const Color(0xFFFFFBEB);
      borderColor = TramColors.tableReserved;
      statusText = 'Đặt trước';
      statusColor = TramColors.tableReserved;
    } else {
      cardBg = Colors.white;
      borderColor = AppColors.border;
      statusText = 'Trống';
      statusColor = AppColors.success;
    }

    return InkWell(
      onTap: () async {
        if (isReserved) {
          _showReservationActionsDialog(table);
          return;
        }
        if (!_auth.can(AppPermissions.openTable) && !_auth.can(AppPermissions.viewMenu)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bạn không có quyền mở bàn hoặc chọn món!')),
          );
          return;
        }

        // 1. BUỘC KHÓA CHỨC NĂNG ORDER NẾU CHƯA NHẬP KÉT
        CashShiftModel? openShift = _fb.activeShiftCache;
        if (openShift == null || !openShift.isOpen) {
          openShift = await _fb.getCurrentOpenShift();
        }
        if (openShift == null || !openShift.isOpen) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⚠️ Chức năng order đang bị khóa! Vui lòng khai báo tiền két đầu ca để bắt đầu.'),
                backgroundColor: TramColors.warningInk,
                duration: Duration(seconds: 3),
              ),
            );
            final opened = await CashShiftDialog.show(context);
            if (opened != true) {
              return; // Chặn tuyệt đối không cho nhận đơn
            }
            final recheck = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
            if (recheck == null || !recheck.isOpen) {
              return;
            }
          } else {
            return;
          }
        }

        // 2. NẾU BÀN ĐANG CÓ KHÁCH (ĐANG SỬ DỤNG): VÀO THẲNG MÀN HÌNH ĐƠN HÀNG (ORDER CART)
        if (inUse) {
          context.push('/order-cart', extra: {
            'table': table,
            'products': table.currentItems,
          });
          return;
        }

        // 3. NẾU BÀN TRỐNG: VÀO THẲNG MÀN HÌNH CHỌN MÓN (XOÁ POPUP NHẬP SỐ KHÁCH)
        if (table.openedAt == null) {
          table.openedAt = DateTime.now().millisecondsSinceEpoch;
        }
        if (table.guestCount == null || table.guestCount! <= 0) {
          table.guestCount = 2; // Số khách mặc định, nhân viên có thể sửa trong màn hình đơn
        }
        table.ensureCodes();
        context.push('/order-list', extra: table);
      },
      onLongPress: () {
        if (inUse) {
          _showInUseTableActionsDialog(table, allTables);
        } else if (!isReserved) {
          _showReserveTableDialog(table);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: (inUse || isReserved) ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: inUse
                  ? AppColors.primary.withOpacity(0.12)
                  : (isReserved ? TramColors.tableReserved.withOpacity(0.12) : AppColors.shadow),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Header: Table name + Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: borderColor.withOpacity(0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.table_restaurant,
                          size: 15,
                          color: borderColor,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          table.name,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: inUse ? AppColors.primaryDark : AppColors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            // Middle info: Area & Details
            if (isReserved) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Khách: ${table.reservationCustomer ?? "Khách hẹn"}',
                      style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: TramColors.tableReserved),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${table.reservationPhone ?? ""} • ${table.reservationTime ?? ""}',
                      style: GoogleFonts.beVietnamPro(fontSize: 10, color: AppColors.textSecondary),
                    ),
                    if (table.reservationDeposit > 0)
                      Text(
                        'Cọc: ${FormatUtils.vnd(table.reservationDeposit)}',
                        style: GoogleFonts.beVietnamPro(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                      ),
                  ],
                ),
              ),
            ] else if (inUse) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((table.currentBillId != null && table.currentBillId!.isNotEmpty) ||
                        (table.currentOrderCode != null && table.currentOrderCode!.isNotEmpty)) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 3),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 0.5),
                        ),
                        child: Text(
                          table.currentBillId != null && table.currentBillId!.isNotEmpty
                              ? 'HĐ: ${table.currentBillId}'
                              : (table.currentOrderCode != null ? 'Đơn: ${table.currentOrderCode}' : ''),
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 9.0,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    Row(
                      children: [
                        Text(
                          'Khu vực: ${table.zone}',
                          style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary),
                        ),
                        if (table.guestCount != null && table.guestCount! > 0) ...[
                          const SizedBox(width: 4),
                          Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
                          const SizedBox(width: 4),
                          Text(
                            '👥 ${table.guestCount}k',
                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                        if (table.durationInUse != null) ...[
                          const SizedBox(width: 4),
                          Text('•', style: TextStyle(color: Colors.grey.shade400, fontSize: 10)),
                          const SizedBox(width: 4),
                          Text(
                            '⏱ ${table.durationInUse!.inMinutes}p',
                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'Khu vực: ${table.zone}',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            ],

            const Divider(height: 6),

            // Footer: Items total / Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (inUse)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$itemsCount món',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (totalAmount > 0)
                          Text(
                            FormatUtils.vnd(totalAmount),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                      ],
                    ),
                  )
                else if (isReserved)
                  Expanded(
                    child: Text(
                      'Chạm để xử lý',
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: TramColors.tableReserved, fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  Expanded(
                    child: Text(
                      'Giữ để đặt trước',
                      style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                    ),
                  ),

                // Table quick action popup menu
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 18),
                  padding: EdgeInsets.zero,
                  onSelected: (val) async {
                    if (val == 'TRANSFER' || val == 'MERGE') {
                      final openShift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
                      if (openShift == null || !openShift.isOpen) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('⚠️ Chức năng thao tác đơn đang bị khóa! Vui lòng khai báo tiền két đầu ca.'),
                              backgroundColor: TramColors.warningInk,
                            ),
                          );
                          final opened = await CashShiftDialog.show(context);
                          if (opened != true && (_fb.activeShiftCache == null || !_fb.activeShiftCache!.isOpen)) {
                            return;
                          }
                        } else {
                          return;
                        }
                      }
                    }

                    if (val == 'QR') {
                      context.push('/qr-code', extra: {'tableName': table.name, 'tableZone': table.zone});
                    } else if (val == 'RESERVE') {
                      _showReserveTableDialog(table);
                    } else if (val == 'TRANSFER') {
                      _showTransferTableDialog(table, allTables);
                    } else if (val == 'MERGE') {
                      _showMergeTableDialog(table, allTables);
                    } else if (val == 'CANCEL_BILL') {
                      _confirmCancelTableBill(table);
                    }
                  },
                  itemBuilder: (ctx) => [
                    if (!inUse && !isReserved)
                      const PopupMenuItem(
                        value: 'RESERVE',
                        child: Row(
                          children: [
                            Icon(Icons.bookmark_add_outlined, size: 18, color: TramColors.tableReserved),
                            SizedBox(width: 8),
                            Text('Đặt trước bàn này'),
                          ],
                        ),
                      ),
                    if (inUse) ...[
                      const PopupMenuItem(
                        value: 'TRANSFER',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Chuyển sang bàn khác'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'MERGE',
                        child: Row(
                          children: [
                            Icon(Icons.call_merge, size: 18, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Ghép vào bàn khác'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'CANCEL_BILL',
                        child: Row(
                          children: [
                            Icon(Icons.cancel_outlined, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Hủy hóa đơn', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    const PopupMenuItem(
                      value: 'QR',
                      child: Row(
                        children: [
                          Icon(Icons.qr_code, size: 18),
                          SizedBox(width: 8),
                          Text('Xem mã QR'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== KIOTVIET TABLE ACTIONS ====================

  void _showReservationActionsDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.event_seat, color: TramColors.tableReserved),
            const SizedBox(width: 8),
            Text('Thông Tin Đặt Bàn - ${table.name}', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách hàng: ${table.reservationCustomer ?? "Không có"}', style: GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Số điện thoại: ${table.reservationPhone ?? "Không có"}', style: GoogleFonts.beVietnamPro(fontSize: 13)),
            const SizedBox(height: 4),
            Text('Giờ hẹn đón: ${table.reservationTime ?? "Chưa rõ"}', style: GoogleFonts.beVietnamPro(fontSize: 13)),
            const SizedBox(height: 4),
            Text('Tiền đặt cọc: ${FormatUtils.vnd(table.reservationDeposit)}', style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.green.shade800, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await _fb.cancelReservation(table);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã hủy đặt trước bàn ${table.name}!')),
                );
              }
            },
            child: const Text('Hủy Đặt Bàn', style: TextStyle(color: AppColors.danger)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              // Buộc kiểm tra ca két trước khi nhận khách vào bàn gọi món
              CashShiftModel? openShift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
              if (openShift == null || !openShift.isOpen) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('⚠️ Chức năng order đang bị khóa! Vui lòng khai báo tiền két đầu ca để bắt đầu.'),
                      backgroundColor: TramColors.warningInk,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  final opened = await CashShiftDialog.show(context);
                  if (opened != true && (_fb.activeShiftCache == null || !_fb.activeShiftCache!.isOpen)) return;
                }
              }
              // Nhận khách vào bàn: Bỏ đặt trước, chuyển sang inUse và mở màn hình chọn món
              await _fb.cancelReservation(table);
              table.inUse = true;
              table.openedAt = DateTime.now().millisecondsSinceEpoch;
              await _fb.saveTable(table);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                context.push('/order-list', extra: table);
              }
            },
            child: const Text('Nhận Bàn & Gọi Món'),
          ),
        ],
      ),
    );
  }

  void _showReserveTableDialog(TableModel table) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final timeCtrl = TextEditingController(text: '19:00');
    final depositCtrl = TextEditingController(text: '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Đặt Trước ${table.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên khách hàng *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại *',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: timeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Giờ hẹn (VD: 18:30)',
                  prefixIcon: Icon(Icons.access_time),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: depositCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Tiền đặt cọc (VND)',
                  prefixIcon: Icon(Icons.attach_money),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: TramColors.tableReserved),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final phone = phoneCtrl.text.trim();
              if (name.isEmpty || phone.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập tên và SĐT khách!')),
                );
                return;
              }
              final deposit = int.tryParse(depositCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
              await _fb.reserveTable(
                table: table,
                customerName: name,
                phone: phone,
                time: timeCtrl.text.trim(),
                deposit: deposit,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã ghi nhận đặt trước cho bàn ${table.name}!')),
                );
              }
            },
            child: const Text('Xác Nhận Đặt Bàn'),
          ),
        ],
      ),
    );
  }

  void _showTransferTableDialog(TableModel sourceTable, List<TableModel> allTables) {
    final emptyTables = allTables.where((t) => !t.inUse && !t.isReserved && t.name != sourceTable.name).toList();
    if (emptyTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hiện không còn bàn trống nào để chuyển!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chuyển Bàn: ${sourceTable.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chọn bàn trống muốn chuyển đến:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: emptyTables.length,
                  itemBuilder: (_, i) {
                    final target = emptyTables[i];
                    return ListTile(
                      leading: const Icon(Icons.table_restaurant, color: AppColors.success),
                      title: Text(target.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                      subtitle: Text(target.zone),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () async {
                        await _fb.transferTable(sourceTable, target);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Đã chuyển toàn bộ món từ ${sourceTable.name} sang ${target.name}!')),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        ],
      ),
    );
  }

  void _showMergeTableDialog(TableModel sourceTable, List<TableModel> allTables) {
    final inUseTables = allTables.where((t) => t.inUse && t.name != sourceTable.name).toList();
    if (inUseTables.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có bàn đang có khách khác để ghép!')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ghép Bàn: ${sourceTable.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chọn bàn có khách muốn gộp chung hóa đơn:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: inUseTables.length,
                  itemBuilder: (_, i) {
                    final target = inUseTables[i];
                    return ListTile(
                      leading: const Icon(Icons.table_restaurant, color: AppColors.primary),
                      title: Text(target.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                      subtitle: Text('${target.zone} • ${target.currentItems.length} món'),
                      trailing: const Icon(Icons.call_merge, size: 16),
                      onTap: () async {
                        await _fb.mergeTables(sourceTable, target);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Đã gộp hóa đơn của ${sourceTable.name} vào ${target.name}!')),
                          );
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
        ],
      ),
    );
  }

  void _showInUseTableActionsDialog(TableModel table, List<TableModel> allTables) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final int itemCount = table.currentItems.fold(0, (sum, i) => sum + i.quantity);
        final int total = table.currentItems.fold(0, (sum, i) => sum + i.itemTotal);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.table_restaurant, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  table.name,
                                  style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    table.zone,
                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${table.currentBillId != null ? "HĐ: ${table.currentBillId} • " : ""}${table.currentOrderCode != null ? "Đơn: ${table.currentOrderCode} • " : ""}$itemCount món (${FormatUtils.vnd(total)})',
                              style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                ListTile(
                  leading: const Icon(Icons.shopping_cart_checkout, color: AppColors.primary),
                  title: Text('Xem giỏ hàng & Thanh toán', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Xem chi tiết các món, giảm giá, in tạm tính và thanh toán'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/order-cart', extra: table);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.add_shopping_cart, color: TramColors.brandPrimary),
                  title: Text('Gọi thêm món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Mở thực đơn chọn món thêm vào bàn này'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/order-list', extra: table);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.swap_horiz, color: Colors.blue),
                  title: Text('Chuyển sang bàn khác', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransferTableDialog(table, allTables);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call_merge, color: Colors.orange),
                  title: Text('Ghép vào bàn khác', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMergeTableDialog(table, allTables);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                  title: Text('Hủy hóa đơn (Trả bàn trống)', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: Colors.red)),
                  subtitle: const Text('Xóa toàn bộ món và đặt lại bàn về trạng thái trống', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmCancelTableBill(table);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmCancelTableBill(TableModel table) async {
    final openShift = _fb.activeShiftCache ?? await _fb.getCurrentOpenShift();
    if (openShift == null || !openShift.isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Chức năng hủy đơn bị khóa! Vui lòng mở ca trước.'),
            backgroundColor: TramColors.warningInk,
          ),
        );
      }
      return;
    }

    final hasKitchen = table.currentItems.any((i) => i.isSentKitchen);
    if (hasKitchen && !_auth.can(AppPermissions.cancelBill) && !_auth.can(AppPermissions.cancelKitchenItem)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Bạn không có quyền hủy hóa đơn đã gửi bếp! Vui lòng liên hệ Quản Lý.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    final reasonCtrl = TextEditingController(text: 'Khách đổi ý/không đợi được');
    final staffUser = _auth.currentUser?.username ?? 'staff';
    final staffName = _auth.currentUser?.fullName ?? 'Nhân Viên';
    final staffRole = _auth.currentUser?.roleId ?? 'ROLE_STAFF';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final quickReasons = [
            'Khách đổi ý/không đợi được',
            'Nhập nhầm bàn',
            'Khách về gấp',
            'Khách chuyển bàn khác',
            'Sự cố món/bếp hết hàng',
          ];

          final int itemsCount = table.currentItems.fold(0, (sum, i) => sum + i.quantity);
          final int totalAmount = table.currentItems.fold(0, (sum, i) => sum + i.itemTotal);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.cancel_outlined, color: AppColors.danger, size: 24),
                const SizedBox(width: 8),
                Text('Hủy Hóa Đơn Bàn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(table.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.primaryDark)),
                            Text(table.zone, style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (table.currentBillId != null)
                              Text('Mã HĐ: ${table.currentBillId}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                            if (table.currentOrderCode != null)
                              Text('Mã đơn: ${table.currentOrderCode}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey)),
                          ],
                        ),
                        Text('Số món: ${table.currentItems.length} món ($itemsCount phần) • Tổng: ${FormatUtils.vnd(totalAmount)}', style: GoogleFonts.beVietnamPro(fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Lý do hủy hóa đơn *:', style: GoogleFonts.beVietnamPro(fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickReasons.map((r) {
                      final isSelected = reasonCtrl.text == r;
                      return ChoiceChip(
                        label: Text(r, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : AppColors.textPrimary)),
                        selected: isSelected,
                        selectedColor: AppColors.primary,
                        backgroundColor: Colors.grey.shade100,
                        onSelected: (val) {
                          if (val) {
                            setDlgState(() => reasonCtrl.text = r);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: reasonCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Nhập chi tiết lý do hủy đơn...',
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '⚠️ Sau khi xác nhận, toàn bộ món sẽ bị hủy và bàn sẽ trở về trạng thái TRỐNG.',
                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.red.shade700, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Bỏ qua'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                icon: const Icon(Icons.delete_forever, size: 16, color: Colors.white),
                label: const Text('Xác nhận Hủy Đơn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) return;
                  Navigator.pop(ctx, true);
                },
              ),
            ],
          );
        },
      ),
    );

    if (confirmed == true) {
      final reason = reasonCtrl.text.trim();
      try {
        await _fb.cancelActiveBill(
          table,
          reason: reason,
          staffUsername: staffUser,
          staffFullName: staffName,
          staffRole: staffRole,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã hủy hóa đơn bàn ${table.name}. Bàn đã về trạng thái TRỐNG!'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi khi hủy hóa đơn: $e'), backgroundColor: AppColors.danger),
          );
        }
      }
    }
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            accountName: Text(_auth.currentUser?.fullName ?? 'Chủ Quán', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: Colors.white)),
            accountEmail: Text('Store: ${_auth.currentStoreCode} • ${_auth.currentUser?.roleId}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.white70)),
            currentAccountPicture: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/logo.jpg',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.restaurant, color: AppColors.primary, size: 28),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_auth.canAccessManagerHub)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7E2930), Color(0xFF53171C)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2)),
                ],
              ),
              child: ListTile(
                leading: const Icon(Icons.analytics_outlined, color: Colors.white),
                title: Text(
                  'CỔNG QUẢN LÝ & BÁO CÁO',
                  style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                subtitle: Text(
                  'Toàn bộ báo cáo doanh thu & giám sát như Web',
                  style: GoogleFonts.beVietnamPro(color: Colors.white70, fontSize: 11),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 14),
                onTap: () {
                  Navigator.pop(context);
                  context.go('/manager-hub');
                },
              ),
            ),
          if (_auth.canAccessManagerHub)
            ListTile(
              leading: const Icon(Icons.storefront, color: TramColors.brandPrimary),
              title: const Text('Đổi Chi Nhánh (Cửa Hàng)'),
              subtitle: Text('Hiện tại: ${_auth.currentStoreCode} • ${_auth.currentStoreInfo?.storeName ?? ""}'),
              onTap: () {
                Navigator.pop(context);
                _showStoreSwitcherDialog();
              },
            ),
          ListTile(
            leading: const Icon(Icons.table_restaurant),
            title: const Text('Sơ đồ bàn & Gọi món'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          // Quản lý ca & két tiền (KiotViet cash shift)
          ListTile(
            leading: const Icon(Icons.point_of_sale, color: TramColors.success),
            title: const Text('Quản Lý Ca & Két Tiền'),
            subtitle: const Text('Mở ca, thu chi phát sinh, kết ca'),
            onTap: () {
              Navigator.pop(context);
              CashShiftDialog.show(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long, color: TramColors.brandPrimary),
            title: const Text('Phiếu Bàn Giao Ca'),
            subtitle: const Text('Xem phiên giao két & chênh lệch'),
            onTap: () => _navigateTo('/cash-shifts'),
          ),
          ListTile(
            leading: const Icon(Icons.summarize_outlined, color: TramColors.info),
            title: const Text('Báo Cáo Cuối Ngày'),
            subtitle: const Text('Tổng hợp, Thu chi, Hàng hóa, Phòng bàn'),
            onTap: () => _navigateTo('/end-of-day-report'),
          ),
          ListTile(
            leading: const Icon(Icons.soup_kitchen),
            title: const Text('Màn hình Bếp / KDS'),
            onTap: () => _navigateTo('/kitchen'),
          ),
          ListTile(
            leading: const Icon(Icons.delivery_dining, color: TramColors.warning),
            title: const Text('Đơn Hàng Online (App/Web)'),
            onTap: () => _navigateTo('/online-orders'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('Lịch sử hóa đơn đã thanh toán'),
            onTap: () {
              Navigator.pop(context);
              if (_auth.canAccessManagerHub) {
                context.go('/manager-hub?tab=3');
              } else {
                context.push('/history');
              }
            },
          ),
          const Divider(),

          // Quản lý nghiệp vụ (Theo phân quyền)
          if (_auth.isRootOwner || _auth.can(AppPermissions.managePromotions))
            ListTile(
              leading: const Icon(Icons.discount_outlined, color: AppColors.accent),
              title: const Text('Khuyến Mãi & Voucher'),
              onTap: () => _navigateTo('/promotions'),
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewInventory))
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Kho hàng'),
              onTap: () {
                Navigator.pop(context);
                context.push('/inventory');
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewInventory))
            ListTile(
              leading: const Icon(Icons.assessment_outlined, color: AppColors.info),
              title: const Text('Báo cáo Kho hàng'),
              onTap: () {
                Navigator.pop(context);
                context.push('/inventory-report');
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.managePromotions))
            ListTile(
              leading: const Icon(Icons.insights_outlined, color: AppColors.accent),
              title: const Text('Hiệu suất Khuyến mãi'),
              onTap: () {
                Navigator.pop(context);
                context.push('/promotion-report');
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewAuditLogs))
            ListTile(
              leading: const Icon(Icons.security_outlined, color: AppColors.danger),
              title: const Text('Lịch Sử Thao Tác (Audit Log)'),
              onTap: () {
                Navigator.pop(context);
                if (_auth.canAccessManagerHub) {
                  context.go('/manager-hub?tab=4');
                } else {
                  context.push('/audit-logs');
                }
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.manageRolesPermissions))
            ListTile(
              leading: const Icon(Icons.grid_on_outlined, color: AppColors.primary),
              title: const Text('Ma Trận Phân Quyền Chi Tiết'),
              onTap: () => _navigateTo('/permissions-matrix'),
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.manageUsers))
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Tài Khoản Nhân Viên'),
              onTap: () => _navigateTo('/user-management'),
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewMenu))
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Quản Lý Thực Đơn'),
              onTap: () => _navigateTo('/menu-management'),
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewReports))
            ListTile(
              leading: const Icon(Icons.analytics_outlined),
              title: const Text('Báo Cáo Doanh Thu'),
              onTap: () {
                Navigator.pop(context);
                if (_auth.canAccessManagerHub) {
                  context.go('/manager-hub?tab=1');
                } else {
                  context.push('/dashboard');
                }
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewReports))
            ListTile(
              leading: const Icon(Icons.bar_chart, color: TramColors.brandPrimary),
              title: const Text('Trung Tâm Báo Cáo (12 Báo Cáo)'),
              subtitle: const Text('Doanh thu, Món ăn, Ca két, Lãi gộp, Xuất file'),
              onTap: () {
                Navigator.pop(context);
                context.push('/reports-hub');
              },
            ),

          ListTile(
            leading: const Icon(Icons.print, color: TramColors.brandPrimary),
            title: const Text('Cài Đặt Máy In (Bluetooth / LAN)'),
            subtitle: const Text('Kết nối máy in nhiệt, khổ giấy, in thử'),
            onTap: () {
              Navigator.pop(context);
              context.push('/printer-settings');
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_reset, color: TramColors.warning),
            title: const Text('Đổi Mật Khẩu'),
            onTap: () {
              Navigator.pop(context);
              ChangePasswordDialog.show(context);
            },
          ),

          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppColors.danger),
            title: const Text('Đăng Xuất', style: TextStyle(color: AppColors.danger)),
            onTap: () async {
              await _auth.logout();
              if (mounted) {
                context.go('/login');
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddTableDialog() {
    final nameCtrl = TextEditingController();
    String selectedZone = _selectedZone == 'Tất cả' ? 'Khu A' : _selectedZone;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm Bàn Mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên bàn (VD: A6, B6, Bàn 01)',
                prefixIcon: Icon(Icons.table_bar),
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<ZoneModel>>(
              stream: _fb.zonesStream(),
              initialData: _fb.defaultZones,
              builder: (context, snapshot) {
                final zones = (snapshot.data != null && snapshot.data!.isNotEmpty)
                    ? snapshot.data!
                    : _fb.defaultZones;
                final zoneNames = zones.map((z) => z.name).toList();
                if (!zoneNames.contains(selectedZone)) {
                  selectedZone = zoneNames.isNotEmpty ? zoneNames.first : 'Khu A';
                }
                return DropdownButtonFormField<String>(
                  value: selectedZone,
                  decoration: const InputDecoration(labelText: 'Khu vực'),
                  items: zones.map((z) => DropdownMenuItem(value: z.name, child: Text(z.name))).toList(),
                  onChanged: (val) {
                    if (val != null) selectedZone = val;
                  },
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final newTable = TableModel(name: name, zone: selectedZone);
                await _fb.saveTable(newTable);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
            child: const Text('Lưu Bàn'),
          ),
        ],
      ),
    );
  }
}
