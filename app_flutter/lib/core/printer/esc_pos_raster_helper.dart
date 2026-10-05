// lib/core/printer/esc_pos_raster_helper.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'printer_types.dart';

/// Dòng nội dung khi vẽ phiếu in dạng Raster Image
class ReceiptRasterLine {
  final String text;
  final double fontSize;
  final bool isBold;
  final TextAlign align;
  final bool isDivider;
  final bool isDoubleLine;
  final double topSpacing;
  final double bottomSpacing;

  const ReceiptRasterLine({
    required this.text,
    this.fontSize = 18.0,
    this.isBold = false,
    this.align = TextAlign.left,
    this.isDivider = false,
    this.isDoubleLine = false,
    this.topSpacing = 2.0,
    this.bottomSpacing = 2.0,
  });

  static ReceiptRasterLine divider([PrinterPaperSize paperSize = PrinterPaperSize.mm58]) =>
      ReceiptRasterLine(
        text: paperSize == PrinterPaperSize.mm58
            ? '--------------------------------'
            : '------------------------------------------------',
        fontSize: 16.0,
        align: TextAlign.center,
        isDivider: true,
      );

  static ReceiptRasterLine doubleDivider([PrinterPaperSize paperSize = PrinterPaperSize.mm58]) =>
      ReceiptRasterLine(
        text: paperSize == PrinterPaperSize.mm58
            ? '================================'
            : '================================================',
        fontSize: 16.0,
        align: TextAlign.center,
        isDivider: true,
        isDoubleLine: true,
      );
}

/// Trình hỗ trợ tạo lệnh ESC/POS in ảnh đồ họa Raster (GS v 0)
/// Đảm bảo mọi máy in nhiệt ESC/POS đều in được chữ tiếng Việt có dấu 100% sắc nét.
class EscPosRasterHelper {
  /// Chuyển đổi ma trận điểm ảnh đơn sắc (1 bit / pixel) thành chuỗi byte ESC/POS GS v 0
  static Uint8List monochromeToEscPosRaster({
    required Uint8List monoBytes,
    required int widthPixels,
    required int heightPixels,
    bool cutPaper = true,
  }) {
    final widthBytes = (widthPixels + 7) ~/ 8;
    final xL = widthBytes & 0xFF;
    final xH = (widthBytes >> 8) & 0xFF;
    final yL = heightPixels & 0xFF;
    final yH = (heightPixels >> 8) & 0xFF;

    final List<int> bytes = [];

    // ESC @: Khởi tạo máy in
    bytes.addAll([0x1B, 0x40]);

    // Căn giữa hình ảnh (ESC a 1)
    bytes.addAll([0x1B, 0x61, 0x01]);

    // GS v 0 0 xL xH yL yH data...
    // 0x1D, 0x76, 0x30, 0x00: Chế độ in raster bình thường (203 DPI)
    bytes.addAll([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);
    bytes.addAll(monoBytes);

    // Đẩy giấy
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);

    // Cắt giấy nếu được bật (GS V B 0)
    if (cutPaper) {
      bytes.addAll([0x1D, 0x56, 0x42, 0x00]);
    }

    return Uint8List.fromList(bytes);
  }

  /// Chuyển đổi raw RGBA byte buffer thành 1-bit monochrome byte buffer (MSB first, 1 = đốt nóng/đen, 0 = trắng)
  static Uint8List rgbaToMonochrome({
    required Uint8List rgbaBytes,
    required int width,
    required int height,
    int threshold = 180, // Điểm ngưỡng đen/trắng (0-255)
  }) {
    final widthBytes = (width + 7) ~/ 8;
    final monoBytes = Uint8List(widthBytes * height);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final pixelOffset = (y * width + x) * 4;
        if (pixelOffset + 3 >= rgbaBytes.length) break;

        final r = rgbaBytes[pixelOffset];
        final g = rgbaBytes[pixelOffset + 1];
        final b = rgbaBytes[pixelOffset + 2];
        final a = rgbaBytes[pixelOffset + 3];

        // Tính độ sáng pixel (Luminance)
        final isBlack = (a > 100) && ((0.299 * r + 0.587 * g + 0.114 * b) < threshold);

        if (isBlack) {
          final byteIndex = y * widthBytes + (x ~/ 8);
          final bitIndex = 7 - (x % 8);
          monoBytes[byteIndex] |= (1 << bitIndex);
        }
      }
    }

    return monoBytes;
  }

  /// Vẽ danh sách các dòng văn bản tiếng Việt có dấu thành hình ảnh Canvas rồi xuất ra byte ESC/POS GS v 0
  static Future<Uint8List> renderLinesToRasterBytes({
    required List<ReceiptRasterLine> lines,
    PrinterPaperSize paperSize = PrinterPaperSize.mm58,
    bool cutPaper = true,
  }) async {
    final width = paperSize.dotWidth.toDouble();

    // 1. Tính toán chiều cao tổng thể của phiếu
    double totalHeight = 24.0; // Padding trên/dưới
    final painters = <TextPainter>[];

    for (final line in lines) {
      final style = TextStyle(
        fontSize: line.fontSize,
        fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
        color: Colors.black,
        fontFamily: 'Roboto',
      );

      final painter = TextPainter(
        text: TextSpan(text: line.text, style: style),
        textAlign: line.align,
        textDirection: TextDirection.ltr,
      );

      painter.layout(maxWidth: width - 8); // Chừa lề 4px mỗi bên
      painters.add(painter);

      totalHeight += line.topSpacing + painter.height + line.bottomSpacing;
    }

    final int targetWidth = paperSize.dotWidth;
    final int targetHeight = totalHeight.ceil();

    // 2. Vẽ lên Canvas
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Nền trắng tinh
    final bgPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(0, 0, width, targetHeight.toDouble()), bgPaint);

    double currentY = 12.0;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final painter = painters[i];

      currentY += line.topSpacing;

      double xPos = 4.0;
      if (line.align == TextAlign.center) {
        xPos = (width - painter.width) / 2;
      } else if (line.align == TextAlign.right) {
        xPos = width - painter.width - 4.0;
      }

      painter.paint(canvas, Offset(xPos, currentY));
      currentY += painter.height + line.bottomSpacing;
    }

    // 3. Kết xuất ui.Image
    final picture = recorder.endRecording();
    final uiImage = await picture.toImage(targetWidth, targetHeight);
    final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);

    if (byteData == null) {
      return Uint8List(0);
    }

    // 4. Chuyển đổi thành Monochrome Raster bytes
    final monoBytes = rgbaToMonochrome(
      rgbaBytes: byteData.buffer.asUint8List(),
      width: targetWidth,
      height: targetHeight,
    );

    return monochromeToEscPosRaster(
      monoBytes: monoBytes,
      widthPixels: targetWidth,
      heightPixels: targetHeight,
      cutPaper: cutPaper,
    );
  }
}
