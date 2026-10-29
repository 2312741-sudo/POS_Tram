// lib/features/online_orders/online_order_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class OnlineOrderDetailScreen extends StatelessWidget {
  final OnlineOrderModel order;
  const OnlineOrderDetailScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final items = order.items;
    final total = items.fold<int>(0, (s, p) => s + p.itemTotal);
    final isCallWaiter = order.isCallWaiter;

    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        title: Text('Chi tiết đơn online', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontWeight: FontWeight.w700,
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
                color: context.tc.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.tc.border),
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
                            color: context.tc.textSecondary, fontSize: 12)),
                          Text(order.tableName, style: GoogleFonts.beVietnamPro(
                            color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 22)),
                          Text(order.tableZone, style: GoogleFonts.beVietnamPro(
                            color: context.tc.textSecondary, fontSize: 13)),
                        ],
                      ),
                      _StatusBadge(status: order.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: context.tc.border),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(LucideIcons.clock, color: context.tc.textSecondary, size: 14),
                      const SizedBox(width: 6),
                      Text(FormatUtils.dateTime(order.timestamp), style: GoogleFonts.beVietnamPro(
                        color: context.tc.textSecondary, fontSize: 13)),
                    ],
                  ),
                  if (order.type == 'CALL_WAITER') ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.tc.warningLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.tc.warning.withAlpha(100)),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.megaphone, color: context.tc.warningInk, size: 20),
                          const SizedBox(width: 10),
                          Text(
                            'Khách gọi nhân viên phục vụ',
                            style: GoogleFonts.beVietnamPro(
                              color: context.tc.warningInk,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: context.tc.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.tc.border),
                ),
                child: Column(
                  children: items.asMap().entries.map((e) {
                    final item = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        border: e.key < items.length - 1
                          ? Border(bottom: BorderSide(color: context.tc.border))
                          : null,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.name, style: GoogleFonts.beVietnamPro(
                            color: context.tc.textPrimary, fontWeight: FontWeight.w500))),
                          Text('x${item.quantity}', style: GoogleFonts.beVietnamPro(
                            color: context.tc.textSecondary, fontSize: 13)),
                          const SizedBox(width: 16),
                          Text(FormatUtils.vnd(item.itemTotal), style: GoogleFonts.beVietnamPro(
                            color: context.tc.primary, fontWeight: FontWeight.w700)),
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
                  color: context.tc.primary.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.tc.primary.withAlpha(60)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tổng cộng', style: GoogleFonts.beVietnamPro(
                      color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(FormatUtils.currency(total), style: GoogleFonts.beVietnamPro(
                      color: context.tc.primary, fontWeight: FontWeight.w800, fontSize: 20)),
                  ],
                ),
              ),
            ],

            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Ghi chú', style: GoogleFonts.beVietnamPro(
                color: context.tc.textPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.tc.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.tc.border),
                ),
                child: Text(order.notes!, style: GoogleFonts.beVietnamPro(
                  color: context.tc.textSecondary, fontStyle: FontStyle.italic)),
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
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: context.tc.danger,
                              content: Row(
                                children: [
                                  const Icon(LucideIcons.circleX, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      order.isCallWaiter
                                          ? 'Đã hủy yêu cầu gọi phục vụ tại bàn ${order.tableName}'
                                          : 'Đã từ chối đơn hàng online tại bàn ${order.tableName}',
                                      style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.tc.danger,
                        side: BorderSide(color: context.tc.danger),
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
                        final fb = FirebaseService();
                        final user = AuthService().currentUser;
                        bool success = false;
                        if (order.isCallWaiter) {
                          if (order.firebaseKey != null) {
                            await fb.updateOnlineOrderStatus(order.firebaseKey!, 'CONFIRMED');
                            success = true;
                          }
                        } else {
                          success = await fb.confirmOnlineOrderAndAddToTable(
                            order,
                            staffUsername: user?.username,
                            staffFullName: user?.fullName,
                          );
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: success ? context.tc.success : context.tc.danger,
                              content: Row(
                                children: [
                                  Icon(
                                    success ? LucideIcons.circleCheck : LucideIcons.circleAlert,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      success
                                          ? (order.isCallWaiter
                                              ? 'Đã tiếp nhận yêu cầu gọi phục vụ tại bàn ${order.tableName}!'
                                              : 'Đã duyệt đơn và thêm món vào bàn ${order.tableName}!')
                                          : 'Lỗi duyệt đơn, vui lòng kiểm tra lại bàn',
                                      style: GoogleFonts.beVietnamPro(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: context.tc.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        order.isCallWaiter ? 'Tiếp nhận yêu cầu' : 'Xác nhận đơn',
                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
                      ),
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
    Color textColor;
    Color bgColor;
    Color borderColor;
    String label;
    switch (status) {
      case 'CONFIRMED':
        textColor = context.tc.success;
        bgColor = context.tc.successLight;
        borderColor = context.tc.success.withAlpha(80);
        label = 'Đã xác nhận';
        break;
      case 'CANCELLED':
        textColor = context.tc.danger;
        bgColor = context.tc.dangerLight;
        borderColor = context.tc.danger.withAlpha(80);
        label = 'Đã hủy';
        break;
      default:
        textColor = context.tc.warningInk;
        bgColor = context.tc.warningLight;
        borderColor = context.tc.warning.withAlpha(120);
        label = 'Đang chờ';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }
}
