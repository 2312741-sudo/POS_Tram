// Service xuất báo cáo Excel và PDF theo đặc tả REPORT_SPEC.md (DOCS-REPORT-SPEC-2026-01)
// Hỗ trợ hiển thị tiếng Việt có dấu chuẩn xác (font Be Vietnam Pro)
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'report_date_utils.dart';

class ReportExportService {
  static const String brandPrimaryHex = '#7E2930';
  static final PdfColor brandPrimaryColor = PdfColor.fromHex(brandPrimaryHex);
  static final PdfColor tableHeaderBg = PdfColor.fromHex('#F8F4EE');

  /// Định dạng tiền tệ VND: phân cách hàng nghìn bằng dấu chấm (1.204.560 đ)
  static String formatCurrency(num amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return '${formatter.format(amount)} đ';
  }

  /// Định dạng tiền không kèm chữ đ (dùng cho bảng biểu kế toán)
  static String formatNumber(num amount) {
    final formatter = NumberFormat('#,###', 'vi_VN');
    return formatter.format(amount);
  }

  /// Quy ước đặt tên file chuẩn: [MaLoaiBaoCao]_[StoreCode]_[TuNgay]_[DenNgay]_[Timestamp].[ext]
  static String generateFileName({
    required String reportCode,
    required String storeCode,
    required DateTime startDate,
    required DateTime endDate,
    required String extension,
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now();
    final fromStr = ReportDateUtils.formatFileDate(startDate);
    final toStr = ReportDateUtils.formatFileDate(endDate);
    final timeStr = ReportDateUtils.formatFileTime(currentTime);
    final cleanStore = storeCode.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();
    return '${reportCode}_${cleanStore}_${fromStr}_${toStr}_$timeStr.$extension';
  }

  /// Lưu file vào Documents/Temp và mở share dialog
  static Future<String> saveAndShareFile({
    required List<int> bytes,
    required String fileName,
  }) async {
    Directory tempDir;
    try {
      tempDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      tempDir = await getTemporaryDirectory();
    }
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    try {
      await Share.shareXFiles([XFile(file.path)], text: fileName);
    } catch (_) {}
    return file.path;
  }

  // ===========================================================================
  // 1. ENGINE XUẤT EXCEL CHUẨN MỰC
  // ===========================================================================

  static Future<String> exportToExcel({
    required String reportCode,
    required String reportTitle,
    required String storeCode,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> headers,
    required List<List<dynamic>> rows,
    List<dynamic>? totalRow,
    Map<String, List<List<dynamic>>>? additionalSheets,
  }) async {
    final excel = Excel.createExcel();
    final sheetName = reportCode.length > 25 ? reportCode.substring(0, 25) : reportCode;
    final sheet = excel[sheetName];
    excel.setDefaultSheet(sheetName);

    // 1. Header cửa hàng (Góc trên bên trái)
    sheet.appendRow([TextCellValue(storeName.toUpperCase())]);
    sheet.appendRow([TextCellValue(storeAddress.isNotEmpty ? storeAddress : 'Đà Lạt, Lâm Đồng')]);
    sheet.appendRow([TextCellValue('SĐT: ${storePhone.isNotEmpty ? storePhone : "0987654321"}')]);
    sheet.appendRow([]);

    // 2. Tiêu đề báo cáo (Căn giữa)
    sheet.appendRow([TextCellValue('BÁO CÁO $reportTitle'.toUpperCase())]);
    final fromDateStr = ReportDateUtils.formatDisplayDate(startDate);
    final toDateStr = ReportDateUtils.formatDisplayDate(endDate);
    sheet.appendRow([TextCellValue('Kỳ báo cáo: Từ ngày $fromDateStr đến ngày $toDateStr')]);
    final nowStr = ReportDateUtils.formatDisplayDateTime(DateTime.now());
    sheet.appendRow([TextCellValue('Ngày giờ xuất: $nowStr (UTC+7)')]);
    sheet.appendRow([]);

    // 3. Header bảng dữ liệu
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

    // 4. Data rows
    for (final row in rows) {
      sheet.appendRow(row.map<CellValue>((cell) {
        if (cell == null) return TextCellValue('');
        if (cell is int) return IntCellValue(cell);
        if (cell is double) return DoubleCellValue(cell);
        if (cell is num) return DoubleCellValue(cell.toDouble());
        return TextCellValue(cell.toString());
      }).toList());
    }

    // 5. Total row
    if (totalRow != null && totalRow.isNotEmpty) {
      sheet.appendRow(totalRow.map<CellValue>((cell) {
        if (cell == null) return TextCellValue('');
        if (cell is int) return IntCellValue(cell);
        if (cell is double) return DoubleCellValue(cell);
        if (cell is num) return DoubleCellValue(cell.toDouble());
        return TextCellValue(cell.toString());
      }).toList());
    }

    sheet.appendRow([]);
    sheet.appendRow([]);

    // 6. Chữ ký xác nhận
    sheet.appendRow([
      TextCellValue('Người lập biểu'),
      TextCellValue(''),
      TextCellValue('Thu ngân trưởng / Quản lý'),
      TextCellValue(''),
      TextCellValue('Chủ cửa hàng / Giám đốc'),
    ]);
    sheet.appendRow([
      TextCellValue('(Ký, ghi rõ họ tên)'),
      TextCellValue(''),
      TextCellValue('(Ký, ghi rõ họ tên)'),
      TextCellValue(''),
      TextCellValue('(Ký, duyệt)'),
    ]);

    // Các sheet bổ sung (nếu có)
    if (additionalSheets != null) {
      for (final entry in additionalSheets.entries) {
        final subSheet = excel[entry.key];
        for (final row in entry.value) {
          subSheet.appendRow(row.map<CellValue>((cell) {
            if (cell == null) return TextCellValue('');
            if (cell is int) return IntCellValue(cell);
            if (cell is double) return DoubleCellValue(cell);
            if (cell is num) return DoubleCellValue(cell.toDouble());
            return TextCellValue(cell.toString());
          }).toList());
        }
      }
    }

    final bytes = excel.encode()!;
    final fileName = generateFileName(
      reportCode: reportCode,
      storeCode: storeCode,
      startDate: startDate,
      endDate: endDate,
      extension: 'xlsx',
    );

    return await saveAndShareFile(bytes: bytes, fileName: fileName);
  }

  // ===========================================================================
  // 2. ENGINE XUẤT PDF CHUẨN MỰC (TIẾNG VIỆT CÓ DẤU FONT BE VIETNAM PRO)
  // ===========================================================================

  static Future<String> exportToPdf({
    required String reportCode,
    required String reportTitle,
    required String storeCode,
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> headers,
    required List<List<dynamic>> rows,
    List<dynamic>? totalRow,
    PdfPageFormat pageFormat = PdfPageFormat.a4,
  }) async {
    final pdf = pw.Document();

    // Nạp font tiếng Việt hỗ trợ Unicode đầy đủ
    pw.Font regularFont;
    pw.Font boldFont;
    try {
      regularFont = await PdfGoogleFonts.beVietnamProRegular();
      boldFont = await PdfGoogleFonts.beVietnamProBold();
    } catch (_) {
      // Fallback nếu không có kết nối internet
      regularFont = pw.Font.helvetica();
      boldFont = pw.Font.helveticaBold();
    }

    final fromDateStr = ReportDateUtils.formatDisplayDate(startDate);
    final toDateStr = ReportDateUtils.formatDisplayDate(endDate);
    final nowStr = ReportDateUtils.formatDisplayDateTime(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // 1. Header cửa hàng
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(storeName.toUpperCase(),
                        style: pw.TextStyle(font: boldFont, fontSize: 11, fontWeight: pw.FontWeight.bold)),
                    pw.Text(storeAddress.isNotEmpty ? storeAddress : 'Đà Lạt, Lâm Đồng',
                        style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700)),
                    pw.Text('Hotline: ${storePhone.isNotEmpty ? storePhone : "0987654321"}',
                        style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700)),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: brandPrimaryColor,
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text('POS TRẠM F&B',
                      style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.white)),
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // 2. Tiêu đề báo cáo
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text('BÁO CÁO $reportTitle'.toUpperCase(),
                      style: pw.TextStyle(font: boldFont, fontSize: 15, color: brandPrimaryColor)),
                  pw.SizedBox(height: 4),
                  pw.Text('Kỳ báo cáo: Từ ngày $fromDateStr đến ngày $toDateStr',
                      style: pw.TextStyle(font: regularFont, fontSize: 10, color: PdfColors.grey800)),
                  pw.Text('Ngày giờ xuất: $nowStr (UTC+7)',
                      style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // 3. Bảng dữ liệu
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: rows.map((r) => r.map((c) => c?.toString() ?? '').toList()).toList(),
              headerStyle: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
              headerDecoration: pw.BoxDecoration(color: brandPrimaryColor),
              cellStyle: pw.TextStyle(font: regularFont, fontSize: 8),
              cellAlignment: pw.Alignment.centerLeft,
              cellAlignments: {
                for (int i = 0; i < headers.length; i++)
                  if (headers[i].contains('VND') ||
                      headers[i].contains('Giá') ||
                      headers[i].contains('Doanh thu') ||
                      headers[i].contains('Tiền') ||
                      headers[i].contains('Lợi nhuận') ||
                      headers[i].contains('%') ||
                      headers[i].contains('Số lượng'))
                    i: pw.Alignment.centerRight
                  else if (headers[i] == 'STT' || headers[i].contains('Khung giờ'))
                    i: pw.Alignment.center
                  else
                    i: pw.Alignment.centerLeft,
              },
              headerAlignments: {
                for (int i = 0; i < headers.length; i++) i: pw.Alignment.center,
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
              oddRowDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFFAFAFA)),
            ),

            // Total row nếu có
            if (totalRow != null && totalRow.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.TableHelper.fromTextArray(
                data: [totalRow.map((c) => c?.toString() ?? '').toList()],
                cellStyle: pw.TextStyle(font: boldFont, fontSize: 8, fontWeight: pw.FontWeight.bold),
                cellAlignments: {
                  for (int i = 0; i < totalRow.length; i++)
                    i: (i == 0 ? pw.Alignment.centerLeft : pw.Alignment.centerRight),
                },
                border: pw.TableBorder.all(color: brandPrimaryColor, width: 1.0),
                rowDecoration: pw.BoxDecoration(color: tableHeaderBg),
              ),
            ],

            pw.SizedBox(height: 24),

            // 4. Chữ ký xác nhận 3 bên
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  children: [
                    pw.Text('Người lập biểu', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 2),
                    pw.Text('(Ký, ghi rõ họ tên)',
                        style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey600)),
                    pw.SizedBox(height: 36),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('Thu ngân trưởng / Quản lý', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 2),
                    pw.Text('(Ký, ghi rõ họ tên)',
                        style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey600)),
                    pw.SizedBox(height: 36),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('Chủ cửa hàng / Giám đốc', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 2),
                    pw.Text('(Ký, duyệt)',
                        style: pw.TextStyle(font: regularFont, fontSize: 7, color: PdfColors.grey600)),
                    pw.SizedBox(height: 36),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    final bytes = await pdf.save();
    final fileName = generateFileName(
      reportCode: reportCode,
      storeCode: storeCode,
      startDate: startDate,
      endDate: endDate,
      extension: 'pdf',
    );

    return await saveAndShareFile(bytes: bytes, fileName: fileName);
  }
}
