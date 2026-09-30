// lib/core/printer/receipt_printer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import '../../data/models/app_models.dart';

class ReceiptPrinter {
  static final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  /// Tạo chuỗi byte ESC/POS in hóa đơn nhà hàng chuẩn đẹp
  static Uint8List buildBillReceiptBytes({
    required StoreInfoModel store,
    required BillModel bill,
    bool isPrePrint = false, // In tạm tính trước khi thu tiền
  }) {
    final List<int> bytes = [];

    // ESC @ - Initialize printer
    bytes.addAll([0x1B, 0x40]);

    // Character code table: PC437 or WPC1258 (Standard)
    bytes.addAll([0x1B, 0x74, 0x00]);

    // Align Center
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Bold + Double height/width for Store Name
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x11]); // Double size
    bytes.addAll(_vietnameseAscii(store.storeName.toUpperCase()));
    bytes.add(0x0A); // LF

    // Normal font for address and phone
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF
    if (store.address.isNotEmpty) {
      bytes.addAll(_vietnameseAscii(store.address));
      bytes.add(0x0A);
    }
    if (store.phone.isNotEmpty) {
      bytes.addAll(_vietnameseAscii('Hotline: ${store.phone}'));
      bytes.add(0x0A);
    }

    bytes.addAll(_vietnameseAscii('--------------------------------'));
    bytes.add(0x0A);

    // Title
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    bytes.addAll(_vietnameseAscii(isPrePrint ? 'PHIEU TAM TINH' : 'HOA DON THANH TOAN'));
    bytes.add(0x0A);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    // Align Left for info
    bytes.addAll([0x1B, 0x61, 0x00]);
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(bill.createdAt));
    bytes.addAll(_vietnameseAscii('So HD: ${bill.billCode}'));
    bytes.add(0x0A);
    bytes.addAll(_vietnameseAscii('Ban: ${bill.tableName} (${bill.zone})'));
    bytes.add(0x0A);
    bytes.addAll(_vietnameseAscii('Thoi gian: $dateStr'));
    bytes.add(0x0A);
    bytes.addAll(_vietnameseAscii('Thu ngan: ${bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername}'));
    bytes.add(0x0A);

    bytes.addAll(_vietnameseAscii('--------------------------------'));
    bytes.add(0x0A);

    // Header table (32 chars line width for 58mm/80mm)
    // Format: Ten mon (16)  SL (4)  T.Tien (12)
    bytes.addAll([0x1B, 0x45, 0x01]);
    bytes.addAll(_vietnameseAscii(_padLine('Ten mon', 'SL', 'T.Tien', 32)));
    bytes.add(0x0A);
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll(_vietnameseAscii('--------------------------------'));
    bytes.add(0x0A);

    // Items list
    for (final item in bill.items) {
      final name = _vietnameseAsciiString(item.name);
      final qty = '${item.quantity}';
      final total = '${_currencyFormat.format(item.itemTotal)}d';

      if (name.length <= 16) {
        bytes.addAll(_vietnameseAscii(_padLine(name, qty, total, 32)));
        bytes.add(0x0A);
      } else {
        // Multi-line product name
        bytes.addAll(_vietnameseAscii(name));
        bytes.add(0x0A);
        bytes.addAll(_vietnameseAscii(_padLine('  x${_currencyFormat.format(item.unitPrice)}d', qty, total, 32)));
        bytes.add(0x0A);
      }

      // KiotViet Size, Sugar, Ice, Toppings
      final List<String> details = [];
      if (item.selectedSize != null) details.add('Size ${item.selectedSize}');
      if (item.selectedSugar != null) details.add(item.selectedSugar!);
      if (item.selectedIce != null) details.add(item.selectedIce!);
      if (item.selectedToppings.isNotEmpty) details.add(item.selectedToppings.join(', '));
      if (details.isNotEmpty) {
        bytes.addAll(_vietnameseAscii('  (${details.join(' - ')})'));
        bytes.add(0x0A);
      }

      if (item.note.isNotEmpty) {
        bytes.addAll(_vietnameseAscii('  * ${item.note}'));
        bytes.add(0x0A);
      }
    }

    bytes.addAll(_vietnameseAscii('--------------------------------'));
    bytes.add(0x0A);

    // Totals Breakdown
    bytes.addAll(_vietnameseAscii(_padRightLeft('Tong tien hang:', '${_currencyFormat.format(bill.subTotal)} d', 32)));
    bytes.add(0x0A);

    // Discounts breakdown
    if (bill.discounts.isNotEmpty) {
      for (final d in bill.discounts) {
        final dName = ' - ${d.promoCode ?? d.description}:';
        final dVal = '-${_currencyFormat.format(d.amount)} d';
        bytes.addAll(_vietnameseAscii(_padRightLeft(dName, dVal, 32)));
        bytes.add(0x0A);
      }
    }

    // Points discount (KiotViet CRM loyalty points)
    if (bill.pointsDiscount > 0) {
      final pVal = '-${_currencyFormat.format(bill.pointsDiscount)} d';
      bytes.addAll(_vietnameseAscii(_padRightLeft(' - Dung diem (${bill.pointsUsed} diem):', pVal, 32)));
      bytes.add(0x0A);
    }

    // VAT
    if (bill.vatRate > 0) {
      bytes.addAll(_vietnameseAscii(_padRightLeft('VAT (${bill.vatRate.toStringAsFixed(0)}%):', '+${_currencyFormat.format(bill.vatAmount)} d', 32)));
      bytes.add(0x0A);
    }

    bytes.addAll(_vietnameseAscii('================================'));
    bytes.add(0x0A);

    // Final Total
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    bytes.addAll(_vietnameseAscii(_padRightLeft('THANH TOAN:', '${_currencyFormat.format(bill.finalAmount)} d', 32)));
    bytes.add(0x0A);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal
    bytes.addAll([0x1B, 0x45, 0x00]);

    if (!isPrePrint) {
      final methodStr = bill.paymentMethod == 'TRANSFER_QR'
          ? 'Chuyen khoan QR'
          : bill.paymentMethod == 'CARD'
              ? 'The Ngan Hang'
              : 'Tien mat';
      bytes.addAll(_vietnameseAscii('HTTT: $methodStr'));
      bytes.add(0x0A);
      if (bill.customerName != null && bill.customerName!.isNotEmpty) {
        bytes.addAll(_vietnameseAscii('Khach: ${bill.customerName} (${bill.customerPhone ?? ""})'));
        bytes.add(0x0A);
      }
    }

    bytes.addAll(_vietnameseAscii('--------------------------------'));
    bytes.add(0x0A);

    // Align Center Footer
    bytes.addAll([0x1B, 0x61, 0x01]);
    if (store.wifiName.isNotEmpty) {
      bytes.addAll(_vietnameseAscii('Wifi: ${store.wifiName}'));
      bytes.add(0x0A);
    }
    bytes.addAll(_vietnameseAscii('Cam on Quy Khach - Hen gap lai!'));
    bytes.add(0x0A);

    // 4 line feeds and cut paper
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]); // GS V B 0 - Cut paper

    return Uint8List.fromList(bytes);
  }

  /// Gửi lệnh in trực tiếp qua cổng mạng LAN TCP Port 9100
  static Future<bool> printViaLan({
    required String printerIp,
    required Uint8List data,
    int port = 9100,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final ip = printerIp.trim();
    if (ip.isEmpty) return false;
    try {
      final socket = await Socket.connect(ip, port, timeout: timeout);
      socket.add(data);
      await socket.flush();
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// In hóa đơn trực tiếp ra máy in hóa đơn của quán
  static Future<bool> printBill({
    required StoreInfoModel store,
    required BillModel bill,
    bool isPrePrint = false,
  }) async {
    final bytes = buildBillReceiptBytes(store: store, bill: bill, isPrePrint: isPrePrint);
    if (store.billPrinterIp.isNotEmpty) {
      return await printViaLan(printerIp: store.billPrinterIp, data: bytes);
    }
    return false;
  }

  // Helpers for string alignment
  static String _padRightLeft(String left, String right, int width) {
    left = _vietnameseAsciiString(left);
    right = _vietnameseAsciiString(right);
    final spaces = width - left.length - right.length;
    if (spaces <= 0) return '$left $right';
    return left + (' ' * spaces) + right;
  }

  static String _padLine(String col1, String col2, String col3, int width) {
    col1 = _vietnameseAsciiString(col1);
    col2 = _vietnameseAsciiString(col2);
    col3 = _vietnameseAsciiString(col3);
    const col2Width = 4;
    const col3Width = 12;
    final col1Width = width - col2Width - col3Width;

    final c1 = col1.length > col1Width ? col1.substring(0, col1Width) : col1.padRight(col1Width);
    final c2 = col2.padLeft(col2Width);
    final c3 = col3.padLeft(col3Width);
    return '$c1$c2$c3';
  }

  static List<int> _vietnameseAscii(String text) {
    return ascii.encode(_vietnameseAsciiString(text));
  }

  static String _vietnameseAsciiString(String str) {
    var result = str;
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to   = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }
}
