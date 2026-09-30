// lib/features/online_orders/online_order_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class OnlineOrderDetailScreen extends StatelessWidget {
  final OnlineOrderModel order;
  const OnlineOrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    final total = items.fold<int>(0, (s, p) => s + p.total);
    final isCallWaiter = order.isCallWaiter;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Chi tiết đơn online', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700,
        )),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Table info card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Bàn', style: GoogleFonts.beVietnamPro(
                            color: AppColors.textSecondary, fontSize: 12)),
                          Text(order.tableName, style: GoogleFonts.beVietnamPro(
                            color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 22)),
                          Text(order.tableZone, style: GoogleFonts.beVietnamPro(
                            color: AppColors.textSecondary, fontSize: 13)),
                        ],
                      ),
                      _StatusBadge(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: AppColors.textSecondary, size: 14),
                      const SizedBox(width: 6),
                      Text(FormatUtils.dateTime(order.timestamp), style: GoogleFonts.beVietnamPro(
                        color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                  if (order.type == 'CALL_WAITER') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withAlpha(25),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.warning.withAlpha(80)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.campaign, color: AppColors.warning, size: 20),
                          const SizedBox(width: 10),
                          Text('Khách gọi nhân viên phục vụ', style: GoogleFonts.beVietnamPro(
                            color: AppColors.warning, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (!isCallWaiter && items.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Các món đặt', style: GoogleFonts.beVietnamPro(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: items.asMap().entries.map((e) {
                    final item = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: e.key < items.length - 1
                          ? const Border(bottom: BorderSide(color: AppColors.border))
                          : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.name, style: GoogleFonts.beVietnamPro(
                            color: AppColors.textPrimary, fontWeight: FontWeight.w500))),
                          Text('x${item.quantity}', style: GoogleFonts.beVietnamPro(
                            color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(width: 16),
                          Text(FormatUtils.currency(item.total), style: GoogleFonts.beVietnamPro(
                            color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withAlpha(60)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tổng cộng', style: GoogleFonts.beVietnamPro(
                      color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(FormatUtils.currency(total), style: GoogleFonts.beVietnamPro(
                      color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 20)),
                  ],
                ),
              ),
            ],

            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ghi chú', style: GoogleFonts.beVietnamPro(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(order.notes!, style: GoogleFonts.beVietnamPro(
                  color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              ),
            ],

            if (order.isPending) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        if (order.firebaseKey != null) {
                          await FirebaseService().updateOnlineOrderStatus(order.firebaseKey!, 'CANCELLED');
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Từ chối', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (order.firebaseKey != null) {
                          await FirebaseService().updateOnlineOrderStatus(order.firebaseKey!, 'CONFIRMED');
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Xác nhận đơn', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'CONFIRMED': color = AppColors.success; label = 'Đã xác nhận'; break;
      case 'CANCELLED': color = AppColors.danger; label = 'Đã hủy'; break;
      default: color = AppColors.warning; label = 'Đang chờ';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(label, style: GoogleFonts.beVietnamPro(
        color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}
