// Dòng báo cáo hóa đơn dùng chung cho màn hình báo cáo & xuất Excel (thuần Dart).
//
// - Trạng thái: PAID → "Hoàn thành", CANCELLED → "Đã hủy".
// - "Giảm giá món" = tổng lineDiscountTotal của các dòng.
// - "Giảm giá đơn" = totalDiscount − giảm giá món (voucher/CTKM + đổi điểm).
import 'package:intl/intl.dart';

import '../../data/models/bill_model.dart';

class BillReportRows {
  static String statusLabel(String status) {
    switch (status) {
      case 'PAID':
        return 'Hoàn thành';
      case 'CANCELLED':
        return 'Đã hủy';
      case 'REFUNDED':
        return 'Đã hoàn tiền';
      case 'OPEN':
        return 'Đang mở';
      default:
        return status;
    }
  }

  /// Lọc theo trạng thái: 'ALL' (Hoàn thành + Đã hủy + Hoàn tiền), 'PAID', 'CANCELLED'.
  static List<BillModel> filterByStatus(List<BillModel> bills, String status) {
    if (status == 'ALL') return bills.where((b) => b.status != 'OPEN' && b.status != 'PRE_PRINT').toList();
    return bills.where((b) => b.status == status).toList();
  }

  static String _time(int ms) => DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

  static String voucherCodes(BillModel b) {
    final codes = <String>[];
    for (final d in b.discounts) {
      final c = d.toMap()['voucherCode']?.toString().trim() ?? '';
      if (c.isNotEmpty) codes.add(c);
    }
    return codes.join(', ');
  }

  static const List<String> summaryHeaders = [
    'Mã HĐ',
    'Thời gian',
    'Bàn',
    'Thu ngân',
    'Trạng thái',
    'Tiền hàng',
    'Giảm giá món',
    'Giảm giá đơn',
    'VAT',
    'Tổng thanh toán',
    'HTTT',
    'Mã voucher',
    'Số món xóa',
    'Tiền xóa món',
  ];

  static List<dynamic> summaryRow(BillModel b) => [
        b.billCode,
        _time(b.closedAt ?? b.createdAt),
        b.tableName,
        b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername,
        statusLabel(b.status),
        b.subTotal,
        b.itemDiscountTotal,
        b.orderLevelDiscount,
        b.vatAmount,
        b.finalAmount,
        b.paymentMethod,
        voucherCodes(b),
        b.deletedItemsCount,
        b.deletedItemsAmount,
      ];

  static const List<String> itemHeaders = [
    'Mã HĐ',
    'Trạng thái',
    'Bàn',
    'Tên món',
    'Tùy chọn',
    'Số lượng',
    'Đơn giá',
    'Thành tiền gộp',
    'Giảm giá món',
    'Thành tiền',
  ];

  static List<List<dynamic>> itemRows(BillModel b) => b.items
      .map((i) => <dynamic>[
            b.billCode,
            statusLabel(b.status),
            b.tableName,
            i.name,
            i.optionsSummary,
            i.quantity,
            i.unitPrice,
            i.lineGross,
            i.lineDiscountTotal,
            i.itemTotal,
          ])
      .toList();

  static const List<String> deletedHeaders = [
    'Mã HĐ',
    'Trạng thái',
    'Bàn',
    'Thời gian xóa',
    'Tên món',
    'Số lượng',
    'Đơn giá',
    'Giá trị xóa',
    'Lý do',
    'Nhân viên',
    'Đã gửi bếp',
  ];

  static List<List<dynamic>> deletedRows(BillModel b) => b.deletedItems
      .map((e) => <dynamic>[
            b.billCode,
            statusLabel(b.status),
            b.tableName,
            _time(e.timestamp),
            e.name,
            e.quantity,
            e.unitPrice,
            e.amount,
            e.reason,
            e.staffFullName.isNotEmpty ? e.staffFullName : e.staffUsername,
            e.sentToKitchen ? 'Có' : 'Không',
          ])
      .toList();
}
