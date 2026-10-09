// lib/features/tables/table_list_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../widgets/common_widgets.dart';
import '../../widgets/theme_mode_selector.dart';
import 'widgets/table_card.dart';
import 'widgets/ready_kitchen_orders_banner.dart';

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

  // Giữ nguyên stream giữa các lần build (trước đây mỗi lần setState lại
  // tạo stream mới => huỷ/đăng ký lại listener Firebase và nháy loading).
  String? _tablesStreamStore;
  Stream<List<TableModel>>? _tablesStream;

  // Lắng nghe các món bếp đã nấu xong sẵn sàng phục vụ
  String? _readyOrdersStore;
  StreamSubscription<List<KitchenOrderModel>>? _readyOrdersSub;
  List<KitchenOrderModel> _readyOrders = [];
  final Set<String> _knownReadyOrderKeys = {};
  bool _isFirstReadyEmit = true;

  Stream<List<TableModel>> _tablesStreamFor(String storeCode) {
    if (_tablesStream == null || _tablesStreamStore != storeCode) {
      _tablesStreamStore = storeCode;
      _tablesStream = _fb.tablesStream();
    }
    return _tablesStream!;
  }

  void _setupReadyOrdersListener(String storeCode) {
    if (_readyOrdersStore == storeCode && _readyOrdersSub != null) return;
    _readyOrdersStore = storeCode;
    _readyOrdersSub?.cancel();
    _knownReadyOrderKeys.clear();
    _isFirstReadyEmit = true;

    _readyOrdersSub = _fb.readyToServeKitchenOrdersStream().listen((orders) {
      if (!mounted) return;
      final newOrders = orders
          .where((o) => o.firebaseKey != null && !_knownReadyOrderKeys.contains(o.firebaseKey!))
          .toList();

      if (!_isFirstReadyEmit && newOrders.isNotEmpty) {
        // Phát âm thanh cảnh báo & rung máy cho nhân viên phục vụ
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
      _isFirstReadyEmit = false;
      for (final o in orders) {
        if (o.firebaseKey != null) {
          _knownReadyOrderKeys.add(o.firebaseKey!);
        }
      }

      setState(() {
        _readyOrders = orders;
      });
    }, onError: (err) {
      debugPrint('[TableListScreen] readyToServeKitchenOrdersStream error: $err');
    });
  }

  Future<void> _handlePickUpKitchenOrder(KitchenOrderModel order) async {
    final key = order.firebaseKey;
    if (key == null) return;
    try {
      final staff = _auth.currentUser?.fullName ?? _auth.currentUser?.username ?? 'Nhân viên';
      await _fb.markKitchenOrderPickedUp(key, pickedUpBy: staff);
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã xác nhận lấy món cho bàn ${order.tableName}'),
            backgroundColor: TramColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi cập nhật nhận món: $e'),
            backgroundColor: TramColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _handlePickUpAllKitchenOrders(List<KitchenOrderModel> orders) async {
    final staff = _auth.currentUser?.fullName ?? _auth.currentUser?.username ?? 'Nhân viên';
    for (final order in orders) {
      if (order.firebaseKey != null) {
        await _fb.markKitchenOrderPickedUp(order.firebaseKey!, pickedUpBy: staff);
      }
    }
    HapticFeedback.mediumImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xác nhận lấy tất cả ${orders.length} đơn món'),
          backgroundColor: TramColors.success,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showReadyOrdersSheet(BuildContext context) {
    ReadyKitchenOrdersBanner.showReadyOrdersModal(
      context: context,
      onPickUp: _handlePickUpKitchenOrder,
      onPickUpAll: _handlePickUpAllKitchenOrders,
    );
  }

  @override
  void dispose() {
    _readyOrdersSub?.cancel();
    super.dispose();
  }

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

  Future<void> _showStoreSwitcherDialog() async {
    // Lấy danh sách chi nhánh thực tế từ Firebase (không hardcode)
    List<StoreInfoModel> stores = [];
    try {
      stores = await _fb.getAllStores();
    } catch (_) {}
    final current = _auth.currentStoreInfo;
    if (stores.isEmpty && current != null) stores = [current];
    if (!mounted) return;
    if (stores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tải được danh sách chi nhánh. Vui lòng thử lại.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.storefront, color: context.tc.primary),
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
                  color: isCurrent ? context.tc.primary : context.tc.textHint,
                ),
                title: Text(
                  s.storeName,
                  style: GoogleFonts.beVietnamPro(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent ? context.tc.primary : context.tc.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Mã CH: ${s.storeCode} ${s.address.isNotEmpty ? "• ${s.address}" : ""}',
                  style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
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
        _setupReadyOrdersListener(_auth.currentStoreCode);
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
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                child: InkWell(
                  onTap: () => CashShiftDialog.show(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isOpen ? TramColors.success : TramColors.warningInk,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white38),
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
          if (_readyOrders.isNotEmpty)
            IconButton(
              icon: Badge.count(
                count: _readyOrders.length,
                backgroundColor: TramColors.danger,
                child: const Icon(Icons.notifications_active, color: Colors.amberAccent),
              ),
              tooltip: '${_readyOrders.length} đơn bếp đã xong chờ lấy',
              onPressed: () => _showReadyOrdersSheet(context),
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
                  backgroundColor: context.isDarkMode ? context.tc.primary : Colors.white,
                  foregroundColor: context.isDarkMode ? Colors.white : TramColors.brandPrimary,
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
        stream: _tablesStreamFor(_auth.currentStoreCode),
        builder: (context, snapshot) {
          // Không hiển thị bàn giả khi lỗi (VD: không có quyền) - báo lỗi cho nhân viên
          if (snapshot.hasError) {
            return ErrorState(
              title: 'Không tải được danh sách bàn',
              message: '${snapshot.error}',
              onRetry: () => setState(() => _tablesStream = null),
            );
          }
          if (!snapshot.hasData) {
            return const LoadingState(message: 'Đang tải sơ đồ bàn...');
          }
          final allTables = snapshot.data!;
          final zones = ['Tất cả', ...allTables.map((t) => t.zone).toSet()];
          if (!zones.contains(_selectedZone)) {
            _selectedZone = 'Tất cả';
          }

          final emptyCount = allTables.where((t) => !t.inUse && !t.isReserved).length;
          final inUseCount = allTables.where((t) => t.inUse && !t.isAwaitingPayment).length;
          final awaitingCount = allTables.where((t) => t.isAwaitingPayment).length;
          final reservedCount = allTables.where((t) => t.isReserved).length;

          // Filter by zone
          var list = _selectedZone == 'Tất cả'
              ? allTables
              : allTables.where((t) => t.zone == _selectedZone).toList();

          // Filter by status
          if (_statusFilter == 'EMPTY') {
            list = list.where((t) => !t.inUse && !t.isReserved).toList();
          } else if (_statusFilter == 'IN_USE') {
            list = list.where((t) => t.inUse && !t.isAwaitingPayment).toList();
          } else if (_statusFilter == 'AWAITING') {
            list = list.where((t) => t.isAwaitingPayment).toList();
          } else if (_statusFilter == 'RESERVED') {
            list = list.where((t) => t.isReserved).toList();
          }

          return Column(
            children: [
              // Banner cảnh báo khóa order nếu chưa mở két
              StreamBuilder<List<CashShiftModel>>(
                stream: _fb.cashShiftsStream(), // repo đã cache stream theo chi nhánh
                initialData: _fb.activeShiftCache != null ? [_fb.activeShiftCache!] : null,
                builder: (context, shiftSnap) {
                  if (shiftSnap.connectionState == ConnectionState.waiting && shiftSnap.data == null && _fb.activeShiftCache == null) {
                    return const SizedBox.shrink();
                  }
                  final shifts = shiftSnap.data ?? (_fb.activeShiftCache != null ? [_fb.activeShiftCache!] : <CashShiftModel>[]);
                  final activeShift = shifts.where((s) => s.isOpen).firstOrNull ?? _fb.activeShiftCache;
                  final isShiftOpen = activeShift != null && activeShift.isOpen;

                  if (isShiftOpen) return const SizedBox.shrink();

                  return InfoBanner(
                    solid: true,
                    tone: BannerTone.warning,
                    icon: Icons.lock,
                    title: 'ĐANG KHÓA ORDER • CHƯA NHẬP KÉT TIỀN',
                    message: 'Vui lòng khai báo số tiền mặt đầu ca để mở khóa nhận đơn.',
                    actionLabel: 'Mở ca',
                    actionIcon: Icons.point_of_sale,
                    onAction: () => CashShiftDialog.show(context),
                  );
                },
              ),

              // Banner / Floating Card thông báo món bếp đã xong sẵn sàng phục vụ
              if (_readyOrders.isNotEmpty)
                ReadyKitchenOrdersBanner(
                  orders: _readyOrders,
                  onPickUp: _handlePickUpKitchenOrder,
                  onViewAll: () => _showReadyOrdersSheet(context),
                ),

              // Zone filter chips
              Container(
                height: 56,
                color: context.tc.card,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  itemCount: zones.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final z = zones[index];
                    final isSelected = z == _selectedZone;
                    return ChoiceChip(
                      label: Text(z),
                      selected: isSelected,
                      showCheckmark: false,
                      selectedColor: context.tc.primary,
                      side: BorderSide(color: isSelected ? context.tc.primary : context.tc.border),
                      labelStyle: GoogleFonts.beVietnamPro(
                        fontSize: 14,
                        color: isSelected ? Colors.white : context.tc.textPrimary,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                      onSelected: (val) {
                        if (val) setState(() => _selectedZone = z);
                      },
                    );
                  },
                ),
              ),

              // Thanh lọc trạng thái kiêm chú thích màu bàn
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.tc.cardElevated,
                  border: Border(bottom: BorderSide(color: context.tc.borderLight)),
                ),
                child: TableStatusFilterBar(
                  selected: _statusFilter,
                  total: allTables.length,
                  emptyCount: emptyCount,
                  inUseCount: inUseCount,
                  awaitingCount: awaitingCount,
                  reservedCount: reservedCount,
                  onSelected: (key) => setState(() => _statusFilter = key),
                ),
              ),

              // Tables Grid – số cột tự co giãn theo chiều rộng (điện thoại 2 cột, tablet 4-6 cột)
              Expanded(
                child: list.isEmpty
                    ? EmptyState(
                        icon: Icons.table_restaurant_outlined,
                        title: allTables.isEmpty ? 'Chưa có bàn nào' : 'Không có bàn phù hợp bộ lọc',
                        subtitle: allTables.isEmpty
                            ? 'Bấm "Thêm Bàn" để tạo sơ đồ bàn cho chi nhánh.'
                            : 'Thử chọn khu vực hoặc trạng thái khác.',
                        action: (allTables.isNotEmpty && (_statusFilter != 'ALL' || _selectedZone != 'Tất cả'))
                            ? OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(minimumSize: const Size(180, 44)),
                                onPressed: () => setState(() {
                                  _statusFilter = 'ALL';
                                  _selectedZone = 'Tất cả';
                                }),
                                icon: const Icon(Icons.filter_alt_off_outlined),
                                label: const Text('Bỏ lọc'),
                              )
                            : null,
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 230,
                          mainAxisExtent: 156,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final table = list[index];
                          return TableCard(
                            table: table,
                            onTap: () => _onTableTap(table),
                            onLongPress: () {
                              if (table.inUse) {
                                _showInUseTableActionsDialog(table, allTables);
                              } else if (!table.isReserved) {
                                _showReserveTableDialog(table);
                              }
                            },
                            onMenuSelected: (val) => _onTableMenuSelected(val, table, allTables),
                          );
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
              icon: const Icon(Icons.add, color: Colors.white),
              label: Text('Thêm Bàn', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
              backgroundColor: context.tc.primary,
              foregroundColor: Colors.white,
            )
          : null,
        );
      },
    );
  }

  Future<void> _onTableTap(TableModel table) async {
    final bool inUse = table.inUse;
    final bool isReserved = table.isReserved;
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
    if (!mounted) return;

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
  }

  Future<void> _onTableMenuSelected(String val, TableModel table, List<TableModel> allTables) async {
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
    if (!mounted) return;

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
  }

  // ==================== KIOTVIET TABLE ACTIONS ====================

  void _showReservationActionsDialog(TableModel table) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.event_seat, color: context.tc.warning),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Thông Tin Đặt Bàn - ${table.name}', style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
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
            Text('Tiền đặt cọc: ${FormatUtils.vnd(table.reservationDeposit)}', style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.success, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await _fb.cancelReservation(table);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi hủy đặt bàn: $e'), backgroundColor: AppColors.danger),
                  );
                }
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã hủy đặt trước bàn ${table.name}!')),
                );
              }
            },
            child: Text('Hủy Đặt Bàn', style: TextStyle(color: context.tc.danger)),
          ),
          ElevatedButton(
            style: dialogActionStyle(background: context.tc.primary),
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
              try {
                await _fb.cancelReservation(table);
                table.inUse = true;
                table.openedAt = DateTime.now().millisecondsSinceEpoch;
                await _fb.saveTable(table);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi nhận bàn: $e'), backgroundColor: AppColors.danger),
                  );
                }
                return;
              }
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
        title: Text('Đặt trước ${table.name}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
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
            style: dialogActionStyle(background: TramColors.warningInk),
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
              try {
                await _fb.reserveTable(
                  table: table,
                  customerName: name,
                  phone: phone,
                  time: timeCtrl.text.trim(),
                  deposit: deposit,
                );
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Lỗi đặt bàn: $e'), backgroundColor: AppColors.danger),
                  );
                }
                return;
              }
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
              Text('Chọn bàn trống muốn chuyển đến:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: emptyTables.length,
                  itemBuilder: (_, i) {
                    final target = emptyTables[i];
                    return ListTile(
                      leading: Icon(Icons.table_restaurant, color: context.tc.success),
                      title: Text(target.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                      subtitle: Text(target.zone),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () async {
                        try {
                          await _fb.transferTable(sourceTable, target);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Lỗi chuyển bàn: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                          return;
                        }
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
              Text('Chọn bàn có khách muốn gộp chung hóa đơn:', style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: inUseTables.length,
                  itemBuilder: (_, i) {
                    final target = inUseTables[i];
                    return ListTile(
                      leading: Icon(Icons.table_restaurant, color: context.tc.primary),
                      title: Text(target.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                      subtitle: Text('${target.zone} • ${target.currentItems.length} món'),
                      trailing: const Icon(Icons.call_merge, size: 16),
                      onTap: () async {
                        try {
                          await _fb.mergeTables(sourceTable, target);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Lỗi gộp bàn: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                          return;
                        }
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
                          color: context.tc.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.table_restaurant, color: context.tc.primary, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    table.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: context.tc.primaryLight,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    table.zone,
                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.primaryDark, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${table.currentBillId != null ? "HĐ: ${table.currentBillId} • " : ""}${table.currentOrderCode != null ? "Đơn: ${table.currentOrderCode} • " : ""}$itemCount món (${FormatUtils.vnd(total)})',
                              style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                ListTile(
                  leading: Icon(Icons.shopping_cart_checkout, color: context.tc.primary),
                  title: Text('Xem giỏ hàng & Thanh toán', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Xem chi tiết các món, giảm giá, in tạm tính và thanh toán'),
                  onTap: () {
                    Navigator.pop(ctx);
                    // Router '/order-cart' yêu cầu extra dạng Map (truyền thẳng TableModel sẽ crash)
                    context.push('/order-cart', extra: {
                      'table': table,
                      'products': table.currentItems,
                    });
                  },
                ),
                ListTile(
                  leading: Icon(Icons.add_shopping_cart, color: context.tc.primary),
                  title: Text('Gọi thêm món', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Mở thực đơn chọn món thêm vào bàn này'),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push('/order-list', extra: table);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.swap_horiz, color: context.ink(TramColors.managerAccent)),
                  title: Text('Chuyển sang bàn khác', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransferTableDialog(table, allTables);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.call_merge, color: context.tc.warning),
                  title: Text('Ghép vào bàn khác', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showMergeTableDialog(table, allTables);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: Icon(Icons.cancel_outlined, color: context.tc.danger),
                  title: Text('Hủy hóa đơn (Trả bàn trống)', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, color: context.tc.danger)),
                  subtitle: Text('Xóa toàn bộ món và đặt lại bàn về trạng thái trống', style: TextStyle(color: context.tc.danger.withValues(alpha: 0.85))),
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

    if (!mounted) return;
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
                Icon(Icons.cancel_outlined, color: context.tc.danger, size: 24),
                const SizedBox(width: 8),
                Flexible(child: Text('Hủy Hóa Đơn Bàn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16))),
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
                      color: TableStatusStyle.resolve(context, TableVisualStatus.inUse).background,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.tc.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(table.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15, color: context.tc.primaryDark)),
                            ),
                            const SizedBox(width: 8),
                            Text(table.zone, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          children: [
                            if (table.currentBillId != null)
                              Text('Mã HĐ: ${table.currentBillId}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.isDarkMode ? context.tc.primaryDark : context.tc.primary)),
                            if (table.currentOrderCode != null)
                              Text('Mã đơn: ${table.currentOrderCode}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.ink(Colors.blueGrey))),
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
                        label: Text(r, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : context.tc.textPrimary)),
                        selected: isSelected,
                        selectedColor: context.tc.primary,
                        showCheckmark: false,
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
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.danger, fontStyle: FontStyle.italic),
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
                style: dialogActionStyle(background: context.tc.danger),
                icon: const Icon(Icons.delete_forever, size: 18, color: Colors.white),
                label: const Text('Xác nhận Hủy Đơn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (reasonCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng chọn hoặc nhập lý do hủy đơn.')),
                    );
                    return;
                  }
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
            accountEmail: Text('Chi nhánh: ${_auth.currentStoreCode} • ${FormatUtils.roleLabel(_auth.currentUser?.roleId ?? '')}', style: GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.white70)),
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
                gradient: AppColors.primaryGradient,
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
              leading: Icon(Icons.storefront, color: context.tc.primary),
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
            leading: Icon(Icons.point_of_sale, color: context.tc.success),
            title: const Text('Quản Lý Ca & Két Tiền'),
            subtitle: const Text('Mở ca, thu chi phát sinh, kết ca'),
            onTap: () {
              Navigator.pop(context);
              CashShiftDialog.show(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.receipt_long, color: context.tc.primary),
            title: const Text('Phiếu Bàn Giao Ca'),
            subtitle: const Text('Xem phiên giao két & chênh lệch'),
            onTap: () => _navigateTo('/cash-shifts'),
          ),
          ListTile(
            leading: Icon(Icons.summarize_outlined, color: context.tc.info),
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
            leading: Icon(Icons.delivery_dining, color: context.tc.warning),
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
              leading: Icon(Icons.discount_outlined, color: context.ink(AppColors.accent)),
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
              leading: Icon(Icons.assessment_outlined, color: context.tc.info),
              title: const Text('Báo cáo Kho hàng'),
              onTap: () {
                Navigator.pop(context);
                context.push('/inventory-report');
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.managePromotions))
            ListTile(
              leading: Icon(Icons.insights_outlined, color: context.ink(AppColors.accent)),
              title: const Text('Hiệu suất Khuyến mãi'),
              onTap: () {
                Navigator.pop(context);
                context.push('/promotion-report');
              },
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.viewAuditLogs))
            ListTile(
              leading: Icon(Icons.security_outlined, color: context.tc.danger),
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
              leading: Icon(Icons.grid_on_outlined, color: context.tc.primary),
              title: const Text('Ma Trận Phân Quyền Chi Tiết'),
              onTap: () => _navigateTo('/permissions-matrix'),
            ),
          if (_auth.isRootOwner || _auth.can(AppPermissions.manageUsers))
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Nhân viên và phân quyền'),
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
              leading: Icon(Icons.bar_chart, color: context.tc.primary),
              title: const Text('Trung Tâm Báo Cáo (12 Báo Cáo)'),
              subtitle: const Text('Doanh thu, Món ăn, Ca két, Lãi gộp, Xuất file'),
              onTap: () {
                Navigator.pop(context);
                context.push('/reports-hub');
              },
            ),

          ListTile(
            leading: Icon(Icons.settings_outlined, color: context.tc.primary),
            title: const Text('Cài Đặt (Máy In & Giao Diện)'),
            subtitle: const Text('Máy in Bluetooth / LAN, khổ giấy, in thử • Sáng / Tối'),
            onTap: () {
              Navigator.pop(context);
              context.push('/printer-settings');
            },
          ),
          ListTile(
            leading: Icon(Icons.palette_outlined, color: context.tc.primary),
            title: const Text('Giao Diện (Sáng / Tối)'),
            subtitle: const Text('Chọn Sáng, Tối hoặc Theo hệ thống'),
            onTap: () {
              Navigator.pop(context);
              showThemeModeDialog(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.lock_reset, color: context.tc.warning),
            title: const Text('Đổi Mật Khẩu'),
            onTap: () {
              Navigator.pop(context);
              ChangePasswordDialog.show(context);
            },
          ),

          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: context.tc.danger),
            title: Text('Đăng Xuất', style: TextStyle(color: context.tc.danger)),
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
                  initialValue: selectedZone,
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
            style: dialogActionStyle(),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isNotEmpty) {
                final newTable = TableModel(name: name, zone: selectedZone);
                try {
                  await _fb.saveTable(newTable);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Lỗi lưu bàn: $e'), backgroundColor: AppColors.danger),
                    );
                  }
                  return;
                }
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
