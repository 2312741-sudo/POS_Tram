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

class KitchenScreen extends StatefulWidget {
  const KitchenScreen({super.key});

  @override
  State<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends State<KitchenScreen> {
  final _fb = FirebaseService();
  List<KitchenOrderModel> _orders = [];
  bool _loading = true;
  Timer? _timer;

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
    super.dispose();
  }

  void _setupStream() {
    _fb.kitchenOrdersStream().listen((orders) {
      final wasEmpty = _orders.isEmpty;
      final hadOrders = _orders.length;
      if (mounted) {
        setState(() { _orders = orders; _loading = false; });
        // Vibrate when new order arrives
        if (!wasEmpty && orders.length > hadOrders) {
          HapticFeedback.heavyImpact();
        }
      }
    });
  }

  Future<void> _markDone(KitchenOrderModel order) async {
    if (order.firebaseKey == null) return;
    await _fb.markKitchenOrderDone(order.firebaseKey!);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0D14),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.kitchenAccent))
                : _orders.isEmpty
                  ? _buildEmptyState()
                  : _buildOrderList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.kitchenCard,
        border: const Border(bottom: BorderSide(color: AppColors.border)),
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
                Text('${_orders.length} đơn đang chờ', style: GoogleFonts.beVietnamPro(
                  color: AppColors.kitchenAccent, fontSize: 13,
                )),
              ],
            ),
          ),
          if (_orders.isNotEmpty)
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.danger.withOpacity(0.5), blurRadius: 12)],
              ),
              child: Center(
                child: Text('${_orders.length}', style: GoogleFonts.beVietnamPro(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16,
                )),
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(begin: const Offset(0.95, 0.95), end: const Offset(1.05, 1.05), duration: 1.seconds),
          const SizedBox(width: 8),
          PopupMenuButton(
            icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
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
              color: AppColors.success.withOpacity(0.1),
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
            color: AppColors.textSecondary, fontSize: 14,
          )),
        ],
      ),
    );
  }

  Widget _buildOrderList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _KitchenOrderCard(
        order: _orders[i],
        onDone: () => _markDone(_orders[i]),
      ).animate(delay: (i * 50).ms).fadeIn(duration: 300.ms).slideX(begin: 0.1, end: 0),
    );
  }
}

class _KitchenOrderCard extends StatelessWidget {
  final KitchenOrderModel order;
  final VoidCallback onDone;

  const _KitchenOrderCard({required this.order, required this.onDone});

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
          color: AppColors.success.withOpacity(0.2),
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
              ? AppColors.danger.withOpacity(0.5)
              : AppColors.border,
            width: waiting.inMinutes >= 10 ? 2 : 1,
          ),
          boxShadow: waiting.inMinutes >= 10
            ? [BoxShadow(color: AppColors.danger.withOpacity(0.2), blurRadius: 16)]
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
                      color: timerColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: timerColor.withOpacity(0.3)),
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
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 12),

              // Items list
              ...items.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.cardElevated.withOpacity(0.5),
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
                            color: AppColors.kitchenAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.kitchenAccent.withOpacity(0.5)),
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
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.amber.withOpacity(0.3)),
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
