// lib/features/kitchen/kitchen_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.kitchenCard,
        border: const Border(bottom: BorderSide(color: AppColors.kitchenCardBorder)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.kitchenAccent, AppColors.primary],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.kitchen, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Màn bếp', style: GoogleFonts.beVietnamPro(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                )),
                Text('${_visibleOrders.length} đơn đang chờ', style: GoogleFonts.beVietnamPro(
                  color: AppColors.kitchenAccent, fontSize: 13,
                )),
              ],
            ),
          ),
          if (_visibleOrders.isNotEmpty)
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.danger.withValues(alpha: 0.5), blurRadius: 12)],
              ),
              child: Center(
                child: Text('${_visibleOrders.length}', style: GoogleFonts.beVietnamPro(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                )),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1.seconds),
          const SizedBox(width: 8),
          PopupMenuButton(
            tooltip: 'Tùy chọn',
            icon: const Icon(Icons.more_vert, color: AppColors.darkTextSecondary),
            color: AppColors.surface,
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () async {
                  await AuthService().logout();
                  if (mounted) context.go('/login');
                },
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: AppColors.danger, size: 18),
                    const SizedBox(width: 8),
                    Text('Đăng xuất', style: GoogleFonts.beVietnamPro(color: AppColors.danger)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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

  const _KitchenOrderCard({super.key, required this.order, required this.onDone});

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
              ...items.map((item) => Container(
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
              )),

              const SizedBox(height: 12),
              // Done button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onDone,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('Đã xong', style: GoogleFonts.beVietnamPro(
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
