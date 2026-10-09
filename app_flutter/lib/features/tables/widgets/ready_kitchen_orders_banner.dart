// lib/features/tables/widgets/ready_kitchen_orders_banner.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';

/// Banner / Floating Notification Card nổi bật thông báo món bếp đã nấu xong.
class ReadyKitchenOrdersBanner extends StatelessWidget {
  final List<KitchenOrderModel> orders;
  final Future<void> Function(KitchenOrderModel order) onPickUp;
  final VoidCallback onViewAll;

  const ReadyKitchenOrdersBanner({
    super.key,
    required this.orders,
    required this.onPickUp,
    required this.onViewAll,
  });

  String _formatTimeAgo(int timestamp) {
    if (timestamp <= 0) return '';
    final diff = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    if (diff.inMinutes < 1) return 'vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    return FormatUtils.timeOnly(timestamp);
  }

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) return const SizedBox.shrink();

    final isSingle = orders.length == 1;
    final latestOrder = orders.first;
    final latestTableName = latestOrder.tableName.toUpperCase();
    final staffName = latestOrder.orderedByName?.trim().isNotEmpty == true
        ? latestOrder.orderedByName!
        : 'Chủ Quán / Nhân viên';
    final doneTime = latestOrder.doneAt ?? latestOrder.timestamp;
    final timeAgoStr = _formatTimeAgo(doneTime);

    return Material(
      color: Colors.transparent,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          // Phối màu xanh lá & vàng cam nổi bật
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF8E7), Color(0xFFF0FDF4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF2E7D32),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onViewAll,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Chuông thông báo hiệu ứng nổi bật
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE65100), Color(0xFF2E7D32)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE65100).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),

                // Nội dung thông báo
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Tiêu đề: [BÀN A1] ĐÃ XONG MÓN!
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              isSingle
                                  ? '[$latestTableName] ĐÃ XONG MÓN!'
                                  : '[$latestTableName] & ${orders.length - 1} BÀN KHÁC ĐÃ XONG!',
                              style: GoogleFonts.beVietnamPro(
                                color: const Color(0xFF1B5E20),
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (timeAgoStr.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFA5D6A7)),
                              ),
                              child: Text(
                                timeAgoStr,
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Nội dung: Mời [Chủ Quán / Nhân viên] vào lấy món!
                      Text(
                        isSingle
                            ? 'Mời $staffName vào lấy món mang cho khách! (${latestOrder.items.length} món)'
                            : 'Có ${orders.length} đơn bếp đã xong chờ mang ra bàn. Chạm để xem!',
                        style: GoogleFonts.beVietnamPro(
                          color: const Color(0xFFBF360C),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Nút hành động
                if (isSingle)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      minimumSize: const Size(0, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 1,
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      'Đã lấy món',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => onPickUp(latestOrder),
                  )
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2E7D32),
                          side: const BorderSide(color: Color(0xFF2E7D32)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: onViewAll,
                        child: Text(
                          'Xem (${orders.length})',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          minimumSize: const Size(0, 36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 1,
                        ),
                        onPressed: () => onPickUp(latestOrder),
                        child: Text(
                          'Lấy [$latestTableName]',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Mở bottom sheet hiển thị toàn bộ danh sách các món đang chờ lấy
  static Future<void> showReadyOrdersModal({
    required BuildContext context,
    required Future<void> Function(KitchenOrderModel order) onPickUp,
    Future<void> Function(List<KitchenOrderModel> orders)? onPickUpAll,
  }) {
    final fb = FirebaseService();

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StreamBuilder<List<KitchenOrderModel>>(
            stream: fb.readyToServeKitchenOrdersStream(),
            builder: (context, snapshot) {
              final readyOrders = snapshot.data ?? [];

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle kéo bottom sheet
                  Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 6),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFA5D6A7)),
                          ),
                          child: const Icon(
                            Icons.restaurant,
                            color: Color(0xFF2E7D32),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Món Đã Nấu Xong • Sẵn Sàng Phục Vụ',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: TramColors.textPrimary,
                                ),
                              ),
                              Text(
                                readyOrders.isEmpty
                                    ? 'Không có đơn nào đang chờ'
                                    : 'Có ${readyOrders.length} đơn đang chờ mang ra bàn cho khách',
                                style: GoogleFonts.beVietnamPro(
                                  fontSize: 12,
                                  color: TramColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (readyOrders.length > 1 && onPickUpAll != null) ...[
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF2E7D32),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            icon: const Icon(Icons.done_all, size: 16),
                            label: Text(
                              'Lấy tất cả',
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            onPressed: () async {
                              await onPickUpAll(readyOrders);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                          ),
                          const SizedBox(width: 4),
                        ],
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: 'Đóng',
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // Danh sách đơn
                  Expanded(
                    child: readyOrders.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 56,
                                    color: Colors.green.shade400,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Đã lấy hết tất cả món!',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: TramColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Không còn đơn bếp nào đang chờ phục vụ.',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      color: TramColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: readyOrders.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final order = readyOrders[index];
                              final doneTime = order.doneAt ?? order.timestamp;
                              final timeStr = FormatUtils.timeOnly(doneTime);
                              final staff = order.orderedByName?.trim().isNotEmpty == true
                                  ? order.orderedByName!
                                  : 'Chủ Quán / Nhân viên';

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey.shade200),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header thẻ đơn
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FBF9),
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF2E7D32),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'BÀN ${order.tableName.toUpperCase()}',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          if (timeStr.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text(
                                              'Xong lúc $timeStr',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 12,
                                                color: TramColors.textSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          const Spacer(),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF2E7D32),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              minimumSize: const Size(0, 32),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              elevation: 0,
                                            ),
                                            icon: const Icon(Icons.check, size: 14),
                                            label: Text(
                                              'Đã lấy món',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            onPressed: () => onPickUp(order),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Thông tin người gửi món
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Nhân viên gửi: ',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11.5,
                                              color: TramColors.textSecondary,
                                            ),
                                          ),
                                          Text(
                                            staff,
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w600,
                                              color: TramColors.textPrimary,
                                            ),
                                          ),
                                          if (order.orderCode != null || order.billCode != null) ...[
                                            const Spacer(),
                                            Text(
                                              order.orderCode ?? order.billCode ?? '',
                                              style: GoogleFonts.beVietnamPro(
                                                fontSize: 11,
                                                color: TramColors.textHint,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    if (order.note != null && order.note!.trim().isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                                        child: Text(
                                          'Ghi chú: ${order.note}',
                                          style: GoogleFonts.beVietnamPro(
                                            fontSize: 11.5,
                                            fontStyle: FontStyle.italic,
                                            color: const Color(0xFFD97706),
                                          ),
                                        ),
                                      ),

                                    const Divider(height: 8),

                                    // Danh sách món
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: order.items.map((item) {
                                          final options = <String>[];
                                          if (item.selectedSize != null) options.add('Size ${item.selectedSize}');
                                          if (item.selectedSugar != null) options.add(item.selectedSugar!);
                                          if (item.selectedIce != null) options.add(item.selectedIce!);
                                          if (item.selectedToppings.isNotEmpty) {
                                            options.add(item.selectedToppings.join(', '));
                                          }
                                          if (item.note != null && item.note!.trim().isNotEmpty) {
                                            options.add('Ghi chú: ${item.note}');
                                          }

                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2.5),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '• ',
                                                  style: GoogleFonts.beVietnamPro(
                                                    color: const Color(0xFF2E7D32),
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: RichText(
                                                    text: TextSpan(
                                                      children: [
                                                        TextSpan(
                                                          text: item.name,
                                                          style: GoogleFonts.beVietnamPro(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w600,
                                                            color: TramColors.textPrimary,
                                                          ),
                                                        ),
                                                        TextSpan(
                                                          text: '  x${item.quantity}',
                                                          style: GoogleFonts.beVietnamPro(
                                                            fontSize: 13,
                                                            fontWeight: FontWeight.w800,
                                                            color: const Color(0xFFBF360C),
                                                          ),
                                                        ),
                                                        if (options.isNotEmpty)
                                                          TextSpan(
                                                            text: ' (${options.join(" • ")})',
                                                            style: GoogleFonts.beVietnamPro(
                                                              fontSize: 11.5,
                                                              color: TramColors.textSecondary,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
