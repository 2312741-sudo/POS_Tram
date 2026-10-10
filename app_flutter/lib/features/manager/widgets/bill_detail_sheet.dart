// lib/features/manager/widgets/bill_detail_sheet.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/permissions/app_permissions.dart';
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

    final tableStr = bill.tableName.trim().isNotEmpty
        ? 'Bàn: ${bill.tableName}${bill.zone.trim().isNotEmpty ? " (${bill.zone})" : ""}'
        : 'Mang về';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: context.tc.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              bill.billCode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.beVietnamPro(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: context.tc.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusBadge(context, bill.status),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$tableStr • $closedTime',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.beVietnamPro(
                          fontSize: 12,
                          color: context.tc.textSecondary,
                        ),
                      ),
                    ],
                  ),
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
                    color: context.tc.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.tc.borderLight),
                  ),
                  child: Column(
                    children: [
                      _infoRow(context, 'Thu ngân thanh toán:', bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername),
                      const SizedBox(height: 6),
                      _infoRow(context, 'Nhân viên nhận order:', bill.orderStaffSummary),
                      const SizedBox(height: 6),
                      _infoRow(context, 'Giờ mở bàn:', createdTime),
                      const SizedBox(height: 6),
                      _infoRow(context, 'Giờ thanh toán:', closedTime),
                      const SizedBox(height: 6),
                      _infoRow(context, 'Hình thức thanh toán:', _paymentMethodText(bill.paymentMethod)),
                      if (bill.customerName != null && bill.customerName!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow(context, 'Khách hàng:', '${bill.customerName} (${bill.customerPhone ?? ""})'),
                      ],
                      if (bill.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _infoRow(context, 'Ghi chú hóa đơn:', bill.notes),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Danh sách món ăn chi tiết
                Row(
                  children: [
                    Icon(Icons.restaurant_menu, size: 20, color: context.tc.primary),
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
                    color: context.tc.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.tc.borderLight),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0; i < bill.items.length; i++) ...[
                        _buildItemRow(context, bill.items[i], i + 1),
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
                    color: context.tc.cardElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: context.tc.borderLight),
                  ),
                  child: Column(
                    children: [
                      _calcRow(context, 'Tiền hàng (Tạm tính):', FormatUtils.vnd(bill.subTotal)),
                      if (bill.itemDiscountTotal > 0) ...[
                        const SizedBox(height: 8),
                        _calcRow(context,
                          'Giảm giá món:',
                          '- ${FormatUtils.vnd(bill.itemDiscountTotal)}',
                          valueColor: context.tc.danger,
                        ),
                      ],
                      if (bill.orderLevelDiscount > 0) ...[
                        const SizedBox(height: 8),
                        _calcRow(context,
                          'Giảm giá đơn / Voucher:',
                          '- ${FormatUtils.vnd(bill.orderLevelDiscount)}',
                          valueColor: context.tc.danger,
                        ),
                      ],
                      if (bill.vatAmount > 0) ...[
                        const SizedBox(height: 8),
                        _calcRow(context, 
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
                              color: context.tc.textPrimary,
                            ),
                          ),
                          Text(
                            FormatUtils.vnd(bill.finalAmount),
                            style: GoogleFonts.beVietnamPro(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: context.tc.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Món đã xóa khỏi đơn (có lý do)
                if (bill.deletedItems.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.remove_shopping_cart_outlined, size: 20, color: context.tc.danger),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Món đã xóa (${bill.deletedItemsCount} món • ${FormatUtils.vnd(bill.deletedItemsAmount)})',
                          style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...bill.deletedItems.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${e.quantity} x ${e.name} — ${e.reason}\n${e.staffFullName.isNotEmpty ? e.staffFullName : e.staffUsername} • ${FormatUtils.dateTime(e.timestamp)}${e.sentToKitchen ? " • Đã gửi bếp" : ""}',
                                style: GoogleFonts.beVietnamPro(fontSize: 12),
                              ),
                            ),
                            Text('-${FormatUtils.vnd(e.amount)}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold, color: context.tc.danger)),
                          ],
                        ),
                      )),
                  const SizedBox(height: 20),
                ],

                // Action Logs (Nhật ký thao tác trên đơn)
                if (bill.actionLogs.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.history_toggle_off, size: 20, color: context.tc.info),
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
                      color: context.tc.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.tc.borderLight),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0; i < bill.actionLogs.length; i++) ...[
                          _buildActionLogRow(context, bill.actionLogs[i]),
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
              color: context.tc.card,
              border: Border(top: BorderSide(color: context.tc.borderLight)),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: bill.status == 'CANCELLED' ? 'Xóa vĩnh viễn' : 'Hủy hóa đơn',
                  style: IconButton.styleFrom(
                    backgroundColor: context.bg(Colors.red.shade50),
                    foregroundColor: context.tc.danger,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: Icon(bill.status == 'CANCELLED' ? Icons.delete_forever : Icons.cancel_outlined),
                  onPressed: () => _confirmCancelOrDeleteBill(context, bill, auth, fb),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(color: context.tc.primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(Icons.file_download_outlined, color: context.tc.primary),
                    label: Text(
                      'Xuất / Chia Sẻ',
                      style: GoogleFonts.beVietnamPro(
                        fontWeight: FontWeight.bold,
                        color: context.tc.primary,
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
                      backgroundColor: context.tc.primary,
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
                            backgroundColor: AppColors.success,
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

  Widget _buildItemRow(BuildContext context, OrderItemModel item, int index) {
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
                  color: context.tc.textSecondary,
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
                        color: context.tc.textPrimary,
                      ),
                    ),
                    if (item.optionsSummary.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          item.optionsSummary,
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: context.tc.textSecondary,
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
                            color: context.tc.warning,
                          ),
                        ),
                      ),
                    if (item.hasDiscount)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${item.discountDescription(FormatUtils.vnd)}: -${FormatUtils.vnd(item.lineDiscountTotal)}'
                          '${item.discountReason.isNotEmpty ? ' (${item.discountReason})' : ''}',
                          style: GoogleFonts.beVietnamPro(
                            fontSize: 11,
                            color: context.tc.danger,
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
                            color: context.tc.info,
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
                      color: context.tc.primary,
                    ),
                  ),
                  Text(
                    '${item.quantity} x ${FormatUtils.vndWithoutUnit(item.price)}',
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 11,
                      color: context.tc.textSecondary,
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

  Widget _buildActionLogRow(BuildContext context, OrderActionLogModel log) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 5, right: 8),
          decoration: BoxDecoration(
            color: context.tc.info,
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
                      color: context.tc.textPrimary,
                    ),
                  ),
                  Text(
                    FormatUtils.dateTime(log.timestamp),
                    style: GoogleFonts.beVietnamPro(
                      fontSize: 10,
                      color: context.tc.textSecondary,
                    ),
                  ),
                ],
              ),
              Text(
                '${log.action}: ${log.details}',
                style: GoogleFonts.beVietnamPro(
                  fontSize: 11,
                  color: context.tc.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary)),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600, color: context.tc.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _calcRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary)),
        Text(
          value,
          style: GoogleFonts.beVietnamPro(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: valueColor ?? context.tc.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(BuildContext context, String status) {
    Color bg;
    Color text;
    String label;
    if (status == 'PAID') {
      bg = context.tc.successLight;
      text = context.tc.success;
      label = 'Hoàn thành';
    } else if (status == 'CANCELLED') {
      bg = context.tc.dangerLight;
      text = context.tc.danger;
      label = 'Đã hủy';
    } else {
      bg = context.tc.warningLight;
      text = context.tc.warning;
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

  Future<void> _confirmCancelOrDeleteBill(
    BuildContext context,
    BillModel bill,
    AuthService auth,
    FirebaseService fb,
  ) async {
    if (!auth.can(AppPermissions.cancelBill)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn không có quyền hủy hoặc xóa hóa đơn!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final reasonCtrl = TextEditingController();
    final quickReasons = [
      'Khách đổi ý hủy món',
      'Nhập nhầm bàn / nhầm món',
      'Thu ngân tính nhầm tiền',
      'Hóa đơn thử nghiệm / test',
      'Khách không đủ tiền thanh toán',
    ];
    String selectedReason = quickReasons.first;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: context.bg(Colors.red.shade50), shape: BoxShape.circle),
                child: Icon(Icons.warning_amber_rounded, color: context.tc.danger, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bill.status == 'CANCELLED' ? 'Xóa Hóa Đơn Khỏi Hệ Thống' : 'Hủy / Xóa Hóa Đơn',
                  style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.tc.cardElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.tc.borderLight),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Mã HĐ: ${bill.billCode}', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13, color: context.tc.primaryDark)),
                          Text(bill.status == 'CANCELLED' ? 'ĐÃ HỦY' : 'ĐÃ THANH TOÁN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: bill.status == 'CANCELLED' ? context.tc.danger : context.tc.success)),
                        ],
                      ),
                      if (bill.orderCode != null && bill.orderCode!.isNotEmpty)
                        Text('Mã đặt món: ${bill.orderCode}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: Colors.blueGrey)),
                      const SizedBox(height: 4),
                      Text('Bàn: ${bill.tableName} (${bill.zone}) • Tổng tiền: ${FormatUtils.vnd(bill.finalAmount)}', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.w600)),
                      Text('Thu ngân: ${bill.staffFullName} • ${FormatUtils.timeOnly(bill.closedAt ?? bill.createdAt)}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text('Lý do hủy / xóa *:', style: GoogleFonts.beVietnamPro(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: quickReasons.map((r) {
                    final isSel = selectedReason == r;
                    return ChoiceChip(
                      label: Text(r, style: TextStyle(fontSize: 11, color: isSel ? Colors.white : context.tc.textPrimary)),
                      selected: isSel,
                      selectedColor: context.tc.danger,
                      backgroundColor: context.tc.cardElevated,
                      onSelected: (val) {
                        if (val) {
                          setDlgState(() {
                            selectedReason = r;
                            reasonCtrl.text = r;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    hintText: 'Nhập chi tiết lý do...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
            if (bill.status != 'CANCELLED')
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.tc.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Hủy hóa đơn'),
                onPressed: () async {
                  final reason = reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : selectedReason;
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Close detail sheet
                  await fb.cancelPaidBill(
                    bill: bill,
                    reason: reason,
                    staffUsername: auth.currentUser?.username ?? 'staff',
                    staffFullName: auth.currentUser?.fullName ?? 'Thu Ngân',
                    staffRole: auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã hủy hóa đơn ${bill.billCode}!'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                },
              ),
            // Tùy chọn Xóa vĩnh viễn (Chủ quán hoặc quản lý có quyền)
            if (auth.isRootOwner || auth.isOwner || auth.can(AppPermissions.cancelBill))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.ink(Colors.red.shade800),
                  side: BorderSide(color: context.line(Colors.red.shade300)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.delete_forever, size: 16),
                label: const Text('Xóa hẳn khỏi máy'),
                onPressed: () async {
                  final reason = reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : selectedReason;
                  Navigator.pop(ctx);
                  Navigator.pop(context); // Close detail sheet
                  await fb.deleteBill(
                    bill: bill,
                    reason: reason,
                    staffUsername: auth.currentUser?.username ?? 'staff',
                    staffFullName: auth.currentUser?.fullName ?? 'Thu Ngân',
                    staffRole: auth.currentUser?.roleId ?? 'ROLE_STAFF',
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã xóa vĩnh viễn hóa đơn ${bill.billCode}!'),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}
