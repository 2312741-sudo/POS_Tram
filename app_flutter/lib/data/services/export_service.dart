import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_models.dart';

class ExportService {
  static String sanitizeFileName(String input) {
    const vietMap = {
      'à': 'a', 'á': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ằ': 'a', 'ắ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ầ': 'a', 'ấ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'è': 'e', 'é': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ề': 'e', 'ế': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'ì': 'i', 'í': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ò': 'o', 'ó': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ồ': 'o', 'ố': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ờ': 'o', 'ớ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ù': 'u', 'ú': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ừ': 'u', 'ứ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ỳ': 'y', 'ý': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd', 'Đ': 'D'
    };
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      buffer.write(vietMap[input[i]] ?? input[i]);
    }
    return buffer.toString()
        .replaceAll(RegExp(r'[^a-zA-Z0-9\s_\-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<String?> exportReportExcel({
    required String reportType,
    required String storeName,
    List<String>? headers,
    List<List<dynamic>>? rows,
    List<BillModel>? bills,
  }) async {
    try {
      final actualHeaders = headers ?? ['Mã HĐ', 'Bàn', 'Khu vực', 'Thu ngân', 'Thời gian', 'Tiền hàng', 'Giảm giá', 'Điểm dùng', 'VAT', 'Tổng tiền', 'HTTT', 'Khách hàng', 'SĐT'];
      final actualRows = rows ?? (bills?.map((b) => [
        b.billCode,
        b.tableName,
        b.zone,
        b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername,
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt)),
        b.subTotal,
        b.totalDiscount,
        b.pointsDiscount,
        b.vatAmount,
        b.finalAmount,
        b.paymentMethod,
        b.customerName ?? '',
        b.customerPhone ?? '',
      ]).toList() ?? []);

      final excel = Excel.createExcel();
      final sheet = excel['TongQuan'];
      excel.setDefaultSheet('TongQuan');

      // Title Row
      sheet.appendRow([TextCellValue('BÁO CÁO $reportType - ${storeName.toUpperCase()}')]);
      final nowStr = DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.now());
      sheet.appendRow([TextCellValue('Thời gian xuất: $nowStr')]);
      sheet.appendRow([]);

      // Headers Row
      sheet.appendRow(actualHeaders.map((h) => TextCellValue(h)).toList());

      // Data Rows
      for (final row in actualRows) {
        sheet.appendRow(row.map((cell) {
          if (cell is num) {
            return DoubleCellValue(cell.toDouble());
          }
          return TextCellValue(cell.toString());
        }).toList());
      }

      // Xuất Sheet 2: Chi tiết món & người nhận order nếu có bills
      if (bills != null && bills.isNotEmpty) {
        final itemSheet = excel['ChiTietMon'];
        itemSheet.appendRow([
          TextCellValue('Mã HĐ'),
          TextCellValue('Bàn'),
          TextCellValue('Tên món'),
          TextCellValue('Tùy chọn (Size/Đường/Đá/Topping)'),
          TextCellValue('Ghi chú'),
          TextCellValue('Số lượng'),
          TextCellValue('Đơn giá (VNĐ)'),
          TextCellValue('Thành tiền (VNĐ)'),
          TextCellValue('Người nhận order món'),
          TextCellValue('Người thanh toán'),
          TextCellValue('Thời gian gọi món'),
        ]);

        for (final b in bills) {
          for (final item in b.items) {
            final orderTime = item.orderedAt != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(item.orderedAt!))
                : DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt));
            itemSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(item.name),
              TextCellValue(item.optionsSummary),
              TextCellValue(item.note),
              DoubleCellValue(item.quantity.toDouble()),
              DoubleCellValue(item.unitPrice.toDouble()),
              DoubleCellValue(item.itemTotal.toDouble()),
              TextCellValue(item.orderedByName.isNotEmpty ? item.orderedByName : b.orderStaffSummary),
              TextCellValue(b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername),
              TextCellValue(orderTime),
            ]);
          }
        }

        // Xuất Sheet 3: Lịch sử thao tác từng đơn hàng
        final logSheet = excel['LichSuThaoTac'];
        logSheet.appendRow([
          TextCellValue('Mã HĐ'),
          TextCellValue('Bàn'),
          TextCellValue('Thời gian'),
          TextCellValue('Nhân viên thao tác'),
          TextCellValue('Hành động'),
          TextCellValue('Chi tiết thao tác'),
        ]);

        for (final b in bills) {
          if (b.actionLogs.isNotEmpty) {
            for (final l in b.actionLogs) {
              final logTime = DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(l.timestamp));
              logSheet.appendRow([
                TextCellValue(b.billCode),
                TextCellValue(b.tableName),
                TextCellValue(logTime),
                TextCellValue(l.staffFullName.isNotEmpty ? l.staffFullName : l.staffUsername),
                TextCellValue(l.action),
                TextCellValue(l.details),
              ]);
            }
          } else {
            // Log mặc định nếu đơn cũ chưa có log
            logSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.createdAt))),
              TextCellValue(b.orderStaffSummary),
              TextCellValue('ORDER_ITEMS'),
              TextCellValue('Gọi ${b.items.length} món'),
            ]);
            logSheet.appendRow([
              TextCellValue(b.billCode),
              TextCellValue(b.tableName),
              TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(b.closedAt ?? b.createdAt))),
              TextCellValue(b.staffFullName.isNotEmpty ? b.staffFullName : b.staffUsername),
              TextCellValue('PAY_BILL'),
              TextCellValue('Thanh toán ${b.finalAmount}đ (${b.paymentMethod})'),
            ]);
          }
        }
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final safeStore = sanitizeFileName(storeName);
      final safeType = sanitizeFileName(reportType);
      final fileName = 'BaoCao_${safeType}_${safeStore}_$dateStr.xlsx';

      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      final fileBytes = excel.save();
      if (fileBytes != null) {
        final file = File(filePath);
        await file.writeAsBytes(fileBytes);
        await Share.shareXFiles([XFile(filePath)], text: 'Báo cáo $reportType - $storeName');
        return filePath;
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
