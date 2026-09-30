// lib/features/manager/widgets/bill_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/printer/receipt_printer.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format_utils.dart';
import '../../../data/models/app_models.dart';
import '../../../data/services/firebase_service.dart';

class BillDetailSheet extends StatelessWidget {
  final BillModel bill;

  const BillDetailSheet({super.key, required this.bill});

  static Future<void> show(BuildContext context, BillModel bill) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BillDetailSheet(bill: bill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService();
    final fb = FirebaseService();
    final createdTime = FormatUtils.dateTime(bill.createdAt);
    final closedTime = bill.closedAt != null ? FormatUtils.dateTime(bill.closedAt!) : 'Chưa đóng';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          bill.billCode,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: TramColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(bill.status),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bàn: ${bill.tableName} (${bill.zone}) • $closedTime',
                      style: GoogleFonts.beVietnamPro(
                        fontSize: 12,
                        color: TramColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Info Grid Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: TramColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TramColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      _infoRow('Thu ngân thanh toán:', bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername),
                      const SizedBox(height: 6),
                      _infoRow('Nhân viên nhận order:', bill.orderStaffSummary),
                      const SizedBox(height: 6),
                      _infoRow('Giờ mở bàn:', createdTime),
                      const SizedBox(height: 6),
                      _infoRow('Giờ thanh toán:', closedTime),
                      const SizedBox(height: 6),
                      _infoRow('Hình thức thanh toán:', _paymentMethodText(bill.paymentMethod)),
                      if (bill.customerName != null && bill.customerName!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow('Khách hàng:', '${bill.customerName} (${bill.customerPhone ?? ""})'),
                      ],
                      if (bill.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow('Ghi chú hóa đơn:', bill.notes),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Danh sách món ăn chi tiết
                Row(
                  children: [
                    const Icon(Icons.restaurant_menu, size: 20, color: TramColors.brandPrimary),
                    const SizedBox(width: 8),
                    Text(
                      'Danh sách món ăn (${bill.items.length} món)',
                      style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: TramColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < bill.items.length; i++) ...[
                        _buildItemRow(bill.items[i], i + 1),
                        if (i < bill.items.length - 1) const Divider(height: 1, indent: 14, endIndent: 14),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Financial Breakdown (Bảng tính tiền)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBF8F2),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: TramColors.borderLight),
                  ),
                  child: Column(
                    children: [
                      _calcRow('Tiền hàng (Tạm tính):', FormatUtils.vnd(bill.subTotal)),
                      if (bill.totalDiscount > 0) ...[
                        const SizedBox(height: 8),
                        _calcRow(
                          'Giảm giá / Voucher:',
                          '- ${FormatUtils.vnd(bill.totalDiscount)}',
                          valueColor: TramColors.danger,
                        ),
                      ],
                      if (bill.vatAmount > 0) ...[
                        const SizedBox(height: 8),
                        _calcRow(
                          'Thuế VAT (${bill.vatRate}%):',
                          '+ ${FormatUtils.vnd(bill.vatAmount)}',
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TỔNG THANH TOÁN:',
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: TramColors.textPrimary,
                            ),
                          ),
                          Text(
                            FormatUtils.vnd(bill.finalAmount),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: TramColors.brandPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Action Logs (Nhật ký thao tác trên đơn)
                if (bill.actionLogs.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.history_toggle_off, size: 20, color: TramColors.info),
                      const SizedBox(width: 8),
                      Text(
                        'Lịch sử thao tác đơn (${bill.actionLogs.length})',
                        style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: TramColors.borderLight),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < bill.actionLogs.length; i++) ...[
                          _buildActionLogRow(bill.actionLogs[i]),
                          if (i < bill.actionLogs.length - 1)
                            const Divider(height: 12, indent: 8, endIndent: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),

          // Bottom Action Buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: TramColors.borderLight)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: TramColors.brandPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.file_download_outlined, color: TramColors.brandPrimary),
                    label: Text(
                      'Xuất / Chia Sẻ',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.bold,
                        color: TramColors.brandPrimary,
                      ),
                    ),
                    onPressed: () async {
                      final storeName = auth.currentStoreInfo?.storeName ?? 'TramFnB';
                      final path = await fb.exportReportExcel(
                        storeName: storeName,
                        reportType: 'HoaDon_${bill.billCode}',
                        bills: [bill],
                      );
                      if (path != null) {
                        await Share.shareXFiles([XFile(path)], text: 'Hóa đơn ${bill.billCode} - $storeName');
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: TramColors.brandPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.print, color: Colors.white),
                    label: Text(
                      'In Lại Bill',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    onPressed: () async {
                      final storeInfo = auth.currentStoreInfo ??
                          StoreInfoModel(storeCode: auth.currentStoreCode, storeName: 'POS Trạm');
                      await ReceiptPrinter.printBill(store: storeInfo, bill: bill);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã gửi lệnh in hóa đơn sang máy in!'),
                            backgroundColor: TramColors.success,
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemRow(OrderItemModel item, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$index.',
                style: GoogleFonts.beVietnamPro(
                  fontWeight: FontWeight.bold,
                  color: TramColors.textSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.name}${item.selectedSize.isNotEmpty ? " (Size ${item.selectedSize})" : ""}',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: TramColors.textPrimary,
                      ),
                    ),
                    if (item.optionsSummary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.optionsSummary,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: TramColors.textSecondary,
                          ),
                        ),
                      ),
                    if (item.note.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Ghi chú: ${item.note}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: TramColors.warning,
                          ),
                        ),
                      ),
                    if (item.orderedByName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Phục vụ: ${item.orderedByName}${item.orderedAt != null ? " • ${FormatUtils.timeOnly(item.orderedAt!)}" : ""}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: TramColors.info,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    FormatUtils.vnd(item.itemTotal),
                    style: GoogleFonts.beVietnamPro(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: TramColors.brandPrimary,
                    ),
                  ),
                  Text(
                    '${item.quantity} x ${FormatUtils.vndWithoutUnit(item.price)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: TramColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionLogRow(OrderActionLogModel log) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5, right: 8),
          decoration: const BoxDecoration(
            color: TramColors.info,
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    log.staffFullName.isNotEmpty ? log.staffFullName : log.staffUsername,
                    style: GoogleFonts.beVietnamPro(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: TramColors.textPrimary,
                    ),
                  ),
                  Text(
                    FormatUtils.dateTime(log.timestamp),
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      color: TramColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                '${log.action}: ${log.details}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: TramColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.beVietnamPro(fontSize: 12, color: TramColors.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: TramColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _calcRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.beVietnamPro(fontSize: 13, color: TramColors.textSecondary)),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? TramColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg;
    Color text;
    String label;
    if (status == 'PAID') {
      bg = TramColors.successSurface;
      text = TramColors.success;
      label = 'Đã thanh toán';
    } else if (status == 'CANCELLED') {
      bg = TramColors.dangerSurface;
      text = TramColors.danger;
      label = 'Đã hủy';
    } else {
      bg = TramColors.warningSurface;
      text = TramColors.warning;
      label = 'Đang phục vụ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.beVietnamPro(fontSize: 11, fontWeight: FontWeight.bold, color: text),
      ),
    );
  }

  String _paymentMethodText(String method) {
    final m = method.toLowerCase();
    if (m.contains('cash') || m.contains('tiền mặt')) return '💵 Tiền mặt';
    if (m.contains('transfer') || m.contains('chuyển') || m.contains('qr')) return '🏦 Chuyển khoản (VietQR)';
    if (m.contains('card') || m.contains('thẻ')) return '💳 Thẻ ngân hàng';
    return method;
  }
}
