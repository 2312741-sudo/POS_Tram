// lib/features/kitchen/kitchen_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/delete_account_dialog.dart';
import 'sold_out_actions.dart';
import 'sold_out_sheet.dart';
import '../../core/domain/kitchen_sla.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  final _fb = FirebaseService();
  List<KitchenOrderModel> _orders = [];
  bool _loading = true;
  Object? _error;
  Timer? _timer;
  StreamSubscription<List<KitchenOrderModel>>? _sub;
  // Đơn vừa vuốt "Xong" – ẩn ngay để Dismissible không còn trong cây widget
  final Set<String> _pendingDone = {};
  // Đang xong một phần (key|nhóm) – chặn bấm đúp
  final Set<String> _pendingGroup = {};
  final Set<String> _pendingItem = {};

  Future<void> _markItemDone(KitchenOrderModel order, int itemIndex) async {
    final key = order.firebaseKey;
    if (key == null) return;
    final guard = '$key|item_$itemIndex';
    if (!_pendingItem.add(guard)) return;
    try {
      await _fb.markKitchenOrderItemDone(order, itemIndex);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật được món: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      _pendingItem.remove(guard);
    }
  }

  @override
  void initState() {
    super.initState();
    _setupStream();
    // Update timer every second for waiting time display
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _setupStream() {
    _sub?.cancel();
    _sub = _fb.kitchenOrdersStream().listen((orders) {
      final wasLoading = _loading;
      final hadOrders = _orders.length;
      if (mounted) {
        setState(() {
          _orders = orders;
          _loading = false;
          _error = null;
          _pendingDone.removeWhere((k) => !orders.any((o) => o.firebaseKey == k));
        });
        // Rung khi có đơn mới (kể cả đơn đầu tiên lúc bếp đang trống)
        if (!wasLoading && orders.length > hadOrders) {
          HapticFeedback.heavyImpact();
        }
      }
    }, onError: (Object e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    });
  }

  List<KitchenOrderModel> get _visibleOrders =>
      _orders.where((o) => o.firebaseKey == null || !_pendingDone.contains(o.firebaseKey)).toList();

  Future<void> _markDone(KitchenOrderModel order) async {
    final key = order.firebaseKey;
    if (key == null || _pendingDone.contains(key)) return; // chặn bấm đúp
    setState(() => _pendingDone.add(key));
    try {
      await _fb.markKitchenOrderDone(key);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      setState(() => _pendingDone.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật được đơn: $e'), backgroundColor: AppColors.danger),
      );
    }
  }

  Future<void> _markGroupDone(KitchenOrderModel order, String group) async {
    final key = order.firebaseKey;
    if (key == null) return;
    final guard = '$key|$group';
    if (!_pendingGroup.add(guard)) return;
    try {
      await _fb.markKitchenOrderGroupDone(order, group);
      HapticFeedback.mediumImpact();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không cập nhật được đơn: $e'), backgroundColor: AppColors.danger),
      );
    } finally {
      _pendingGroup.remove(guard);
    }
  }

  bool get _canCallStaff =>
      AuthService().can(AppPermissions.viewKitchen) || AuthService().can(AppPermissions.sendKitchen);

  Future<void> _callStaff() async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gọi nhân viên'),
        content: TextField(
          controller: note,
          maxLength: 120,
          decoration: const InputDecoration(hintText: 'Nội dung (không bắt buộc)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Gọi')),
        ],
      ),
    );
    final message = note.text;
    note.dispose();
    if (ok != true) return;
    try {
      await _fb.callStaff(message: message);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gọi nhân viên'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không gọi được nhân viên: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleOrders;
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
      backgroundColor: AppColors.kitchenBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.kitchenAccent))
                : _error != null
                  ? ErrorState(
                      title: 'Không tải được đơn bếp',
                      message: '$_error',
                      foreground: AppColors.darkTextPrimary,
                      onRetry: () {
                        setState(() { _loading = true; _error = null; });
                        _setupStream();
                      },
                    )
                  : visible.isEmpty
                    ? _buildEmptyState()
                    : _buildOrderList(visible),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 640;
        final isVeryNarrow = constraints.maxWidth < 420;

        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: isVeryNarrow ? 10 : 16,
            vertical: isVeryNarrow ? 10 : 14,
          ),
          decoration: const BoxDecoration(
            color: AppColors.kitchenCard,
            border: Border(bottom: BorderSide(color: AppColors.kitchenCardBorder)),
          ),
          child: Row(
            children: [
              // Tài khoản không phải Bếp (chủ / quản lý / nhân viên) vào xem màn bếp thì có nút quay về
              if (!AuthService().isKitchen)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    tooltip: 'Quay về',
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/tables');
                      }
                    },
                  ),
                ),
              Container(
                padding: EdgeInsets.all(isVeryNarrow ? 8 : 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.kitchenAccent, AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.kitchen, color: Colors.white, size: isVeryNarrow ? 20 : 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Màn bếp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        color: Colors.white,
                        fontSize: isVeryNarrow ? 16 : 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${_visibleOrders.length} đơn đang chờ',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.beVietnamPro(
                        color: AppColors.kitchenAccent,
                        fontSize: isVeryNarrow ? 11.5 : 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (_canCallStaff)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: isNarrow
                      ? InkWell(
                          onTap: _callStaff,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.shade700),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.campaign, color: Colors.amberAccent, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'Gọi NV',
                                  style: GoogleFonts.beVietnamPro(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: _callStaff,
                          icon: const Icon(Icons.campaign_outlined, size: 18),
                          label: const Text('Gọi nhân viên'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.kitchenCardBorder),
                          ),
                        ),
                ),
              if (canToggleAvailability())
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: isNarrow
                      ? InkWell(
                          onTap: () => SoldOutSheet.show(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.kitchenCardBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.no_meals_outlined, color: Colors.white70, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  'Hết món',
                                  style: GoogleFonts.beVietnamPro(
                                    color: Colors.white,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => SoldOutSheet.show(context),
                          icon: const Icon(Icons.no_meals_outlined, size: 18),
                          label: const Text('Hết món'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 38),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: AppColors.kitchenCardBorder),
                          ),
                        ),
                ),
              if (_visibleOrders.isNotEmpty)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.danger.withValues(alpha: 0.5), blurRadius: 10),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '${_visibleOrders.length}',
                      style: GoogleFonts.beVietnamPro(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1.seconds),
              const SizedBox(width: 4),
          PopupMenuButton(
            tooltip: 'Tùy chọn',
            icon: const Icon(Icons.more_vert, color: AppColors.darkTextSecondary),
            color: AppColors.surface,
            itemBuilder: (menuCtx) => [
              PopupMenuItem(
                onTap: () async {
                  await AuthService().logout();
                  if (!mounted) return;
                  context.go('/login');
                },
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Text('Đăng xuất', style: GoogleFonts.beVietnamPro(color: AppColors.danger)),
                  ],
                ),
              ),
              PopupMenuItem(
                onTap: () {
                  // onTap của PopupMenuItem chạy trước khi menu đóng hẳn; lùi một khung để dialog mở đúng
                  Future.microtask(() {
                    if (!mounted) return;
                    DeleteAccountDialog.start(context);
                  });
                },
                child: Row(
                  children: [
                    const Icon(Icons.no_accounts_outlined, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Text('Xóa tài khoản của tôi', style: GoogleFonts.beVietnamPro(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  },
);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 72),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 2.seconds),
          const SizedBox(height: 24),
          Text('Tất cả đơn đã xong! 🎉', style: GoogleFonts.beVietnamPro(
            color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 8),
          Text('Đang chờ đơn mới...', style: GoogleFonts.beVietnamPro(
            color: AppColors.darkTextSecondary, fontSize: 14,
          )),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<KitchenOrderModel> orders) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tablet/màn hình bếp lớn: chia nhiều cột để thấy được nhiều đơn cùng lúc
        final cols = (constraints.maxWidth / 380).floor().clamp(1, 4);
        Widget card(int i) => _KitchenOrderCard(
              key: ValueKey(orders[i].firebaseKey ?? '${orders[i].tableName}_${orders[i].timestamp}'),
              order: orders[i],
              onDone: () => _markDone(orders[i]),
              onGroupDone: (g) => _markGroupDone(orders[i], g),
              onItemDone: (idx) => _markItemDone(orders[i], idx),
            ).animate(delay: (i * 50).ms).fadeIn(duration: 300.ms).slideX(begin: 0.1, end: 0);

        if (cols == 1) {
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => card(i),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int c = 0; c < cols; c++) ...[
                if (c > 0) const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      for (int i = c; i < orders.length; i += cols) ...[
                        card(i),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _KitchenOrderCard extends StatelessWidget {
  final KitchenOrderModel order;
  final VoidCallback onDone;
  final void Function(String group) onGroupDone;
  final void Function(int itemIndex) onItemDone;

  const _KitchenOrderCard({
    super.key,
    required this.order,
    required this.onDone,
    required this.onGroupDone,
    required this.onItemDone,
  });

  Color _timerColor(Duration d) {
    if (d.inMinutes < 5) return AppColors.success;
    if (d.inMinutes < 10) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    final waiting = order.waitingTime;
    final timerColor = _timerColor(waiting);
    final items = order.items;
    final groups = order.itemGroups;
    // Có cả nước lẫn bánh → cho xong từng phần
    final canSplit = order.groupsPresent.length >= 2;

    final tName = order.tableName.trim();
    final tableDisplayName = tName.toLowerCase().startsWith('bàn') || tName.toLowerCase().contains('mang')
        ? tName
        : 'Bàn $tName';

    return Dismissible(
      key: Key(order.firebaseKey ?? order.tableName + order.timestamp.toString()),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 32),
            const SizedBox(height: 4),
            Text('Xong!', style: GoogleFonts.beVietnamPro(
              color: AppColors.success, fontWeight: FontWeight.w700,
            )),
          ],
        ),
      ),
      onDismissed: (_) => onDone(),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.kitchenCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: waiting.inMinutes >= 10
              ? AppColors.danger.withValues(alpha: 0.5)
              : AppColors.kitchenCardBorder,
            width: waiting.inMinutes >= 10 ? 2 : 1,
          ),
          boxShadow: waiting.inMinutes >= 10
            ? [BoxShadow(color: AppColors.danger.withValues(alpha: 0.2), blurRadius: 16)]
            : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.kitchenAccent, AppColors.primary],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tableDisplayName, style: GoogleFonts.beVietnamPro(
                      color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                    )),
                  ),
                  const Spacer(),
                  // Timer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: timerColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: timerColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, color: timerColor, size: 14),
                        const SizedBox(width: 4),
                        Text(FormatUtils.waitTime(waiting), style: GoogleFonts.beVietnamPro(
                          color: timerColor, fontWeight: FontWeight.w700, fontSize: 13,
                        )),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.kitchenCardBorder, height: 1),
              const SizedBox(height: 12),

              // Items list
              ...items.asMap().entries.map((entry) {
                final item = entry.value;
                final grp = entry.key < groups.length ? groups[entry.key] : null;
                return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  // Trước đây nền kem nhạt + chữ trắng => gần như không đọc được
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.kitchenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (canSplit && grp != null) ...[
                          Text(kitchenGroupLabel(grp), style: GoogleFonts.beVietnamPro(color: Colors.white54, fontSize: 11)),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            item.name,
                            style: GoogleFonts.beVietnamPro(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.kitchenAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.kitchenAccent.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            'x${item.quantity}',
                            style: GoogleFonts.beVietnamPro(
                              color: AppColors.kitchenAccent,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => onItemDone(entry.key),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.6)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check, size: 14, color: AppColors.success),
                                const SizedBox(width: 3),
                                Text(
                                  'Xong',
                                  style: GoogleFonts.beVietnamPro(
                                    color: AppColors.success,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (item.optionsSummary.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '⚙️ ${item.optionsSummary}',
                            style: GoogleFonts.beVietnamPro(
                              color: Colors.amber.shade200,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (item.note.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          '📝 Lưu ý: ${item.note}',
                          style: GoogleFonts.beVietnamPro(
                            color: Colors.orange.shade300,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ],
                    if (item.orderedByName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text(
                          '👤 Order bởi: ${item.orderedByName}',
                          style: GoogleFonts.beVietnamPro(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
              }),

              const SizedBox(height: 12),
              if (canSplit) ...[
                Row(
                  children: [
                    for (final g in [kKitchenGroupDrink, kKitchenGroupFood]) ...[
                      if (g != kKitchenGroupDrink) const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onGroupDone(g),
                          icon: Icon(g == kKitchenGroupDrink ? Icons.local_cafe_outlined : Icons.cake_outlined, size: 18),
                          label: Text('Xong ${kitchenGroupLabel(g).toLowerCase()}'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.success,
                            side: const BorderSide(color: AppColors.success),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
              ],
              // Done button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(canSplit ? 'Xong cả đơn' : 'Đã xong', style: GoogleFonts.beVietnamPro(
                    fontWeight: FontWeight.w700, fontSize: 15,
                  )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
