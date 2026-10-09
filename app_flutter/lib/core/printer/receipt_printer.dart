// lib/core/printer/receipt_printer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/app_models.dart';
import 'printer_types.dart';
import 'esc_pos_raster_helper.dart';
import 'bluetooth_printer_service.dart';
import 'print_queue_service.dart';

class ReceiptPrinter {
  static final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  /// Tạo chuỗi byte ESC/POS in hóa đơn nhà hàng chuẩn đẹp (Hỗ trợ khổ 58mm & 80mm, có dấu hoặc không dấu)
  static Uint8List buildBillReceiptBytes({
    required StoreInfoModel store,
    required BillModel bill,
    bool isPrePrint = false, // In tạm tính trước khi thu tiền
    PrinterPaperSize paperSize = PrinterPaperSize.mm58,
    bool removeAccents = true,
  }) {
    final int width = paperSize.charWidth; // 32 chars cho 58mm, 48 chars cho 80mm
    final List<int> bytes = [];

    List<int> encodeText(String text) {
      if (removeAccents) {
        return _vietnameseAscii(text);
      } else {
        return utf8.encode(text);
      }
    }

    String normalize(String text) {
      return removeAccents ? _vietnameseAsciiString(text) : text;
    }

    final String singleDivider = '-' * width;
    final String doubleDivider = '=' * width;

    // ESC @ - Initialize printer
    bytes.addAll([0x1B, 0x40]);

    // Character code table: PC437 or WPC1258 (Standard)
    bytes.addAll([0x1B, 0x74, 0x00]);

    // Align Center
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Bold + Double height/width for Store Name
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x11]); // Double size
    bytes.addAll(encodeText(store.storeName.toUpperCase()));
    bytes.add(0x0A); // LF

    // Normal font for address and phone
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF
    if (store.address.isNotEmpty) {
      bytes.addAll(encodeText(store.address));
      bytes.add(0x0A);
    }
    if (store.phone.isNotEmpty) {
      bytes.addAll(encodeText('Hotline: ${store.phone}'));
      bytes.add(0x0A);
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Title
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    bytes.addAll(encodeText(isPrePrint
        ? (removeAccents ? 'PHIEU TAM TINH' : 'PHIẾU TẠM TÍNH')
        : (removeAccents ? 'HOA DON THANH TOAN' : 'HÓA ĐƠN THANH TOÁN')));
    bytes.add(0x0A);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal size
    bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

    // Align Left for info
    bytes.addAll([0x1B, 0x61, 0x00]);
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(bill.createdAt));
    bytes.addAll(encodeText(removeAccents ? 'So HD: ${bill.billCode}' : 'Số HĐ: ${bill.billCode}'));
    bytes.add(0x0A);
    if (bill.orderCode != null && bill.orderCode!.isNotEmpty && bill.orderCode != bill.billCode) {
      bytes.addAll(encodeText(removeAccents ? 'Ma dat mon: ${bill.orderCode}' : 'Mã đặt món: ${bill.orderCode}'));
      bytes.add(0x0A);
    }
    bytes.addAll(encodeText(removeAccents ? 'Ban: ${bill.tableName} (${bill.zone})' : 'Bàn: ${bill.tableName} (${bill.zone})'));
    bytes.add(0x0A);
    bytes.addAll(encodeText(removeAccents ? 'Thoi gian: $dateStr' : 'Thời gian: $dateStr'));
    bytes.add(0x0A);
    final staffDisplay = bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername;
    bytes.addAll(encodeText(removeAccents ? 'Thu ngan: $staffDisplay' : 'Thu ngân: $staffDisplay'));
    bytes.add(0x0A);

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Header table
    bytes.addAll([0x1B, 0x45, 0x01]);
    final col1Header = removeAccents ? 'Ten mon' : 'Tên món';
    final col3Header = removeAccents ? 'T.Tien' : 'T.Tiền';
    bytes.addAll(encodeText(_padLine(col1Header, 'SL', col3Header, width, removeAccents: removeAccents)));
    bytes.add(0x0A);
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Items list
    final int nameMaxCol = width == 48 ? 28 : 16;
    for (final item in bill.items) {
      final name = normalize(item.name);
      final qty = '${item.quantity}';
      final total = '${_currencyFormat.format(item.itemTotal)}d';

      if (name.length <= nameMaxCol) {
        bytes.addAll(encodeText(_padLine(name, qty, total, width, removeAccents: removeAccents)));
        bytes.add(0x0A);
      } else {
        // Multi-line product name
        bytes.addAll(encodeText(name));
        bytes.add(0x0A);
        bytes.addAll(encodeText(_padLine('  x${_currencyFormat.format(item.unitPrice)}d', qty, total, width, removeAccents: removeAccents)));
        bytes.add(0x0A);
      }

      // KiotViet Size, Sugar, Ice, Toppings
      final List<String> details = [];
      if (item.selectedSize.isNotEmpty) details.add('Size ${item.selectedSize}');
      if (item.selectedSugar.isNotEmpty) details.add(item.selectedSugar);
      if (item.selectedIce.isNotEmpty) details.add(item.selectedIce);
      if (item.selectedToppings.isNotEmpty) details.add(item.selectedToppings.join(', '));
      if (details.isNotEmpty) {
        bytes.addAll(encodeText(normalize('  (${details.join(' - ')})')));
        bytes.add(0x0A);
      }

      if (item.note.isNotEmpty) {
        bytes.addAll(encodeText(normalize('  * ${item.note}')));
        bytes.add(0x0A);
      }

      // Giảm giá dòng (VD: "Giam 10% x 2/5 mon -8.000d")
      if (item.hasDiscount) {
        final desc = item.discountDescription((v) => '${_currencyFormat.format(v)}d');
        bytes.addAll(encodeText(normalize('  $desc: -${_currencyFormat.format(item.lineDiscountTotal)}d')));
        bytes.add(0x0A);
      }
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Totals Breakdown
    final subTotalTitle = removeAccents ? 'Tong tien hang:' : 'Tổng tiền hàng:';
    bytes.addAll(encodeText(_padRightLeft(subTotalTitle, '${_currencyFormat.format(bill.subTotal)} d', width, removeAccents: removeAccents)));
    bytes.add(0x0A);

    // Discounts breakdown
    if (bill.discounts.isNotEmpty) {
      for (final d in bill.discounts) {
        final dName = ' - ${d.promoCode ?? d.description}:';
        final dVal = '-${_currencyFormat.format(d.amount)} d';
        bytes.addAll(encodeText(_padRightLeft(dName, dVal, width, removeAccents: removeAccents)));
        bytes.add(0x0A);
      }
    }

    // Points discount (KiotViet CRM loyalty points)
    if (bill.pointsDiscount > 0) {
      final pTitle = removeAccents
          ? ' - Dung diem (${bill.pointsUsed} diem):'
          : ' - Dùng điểm (${bill.pointsUsed} điểm):';
      final pVal = '-${_currencyFormat.format(bill.pointsDiscount)} d';
      bytes.addAll(encodeText(_padRightLeft(pTitle, pVal, width, removeAccents: removeAccents)));
      bytes.add(0x0A);
    }

    // VAT
    if (bill.vatRate > 0) {
      bytes.addAll(encodeText(_padRightLeft('VAT (${bill.vatRate.toStringAsFixed(0)}%):', '+${_currencyFormat.format(bill.vatAmount)} d', width, removeAccents: removeAccents)));
      bytes.add(0x0A);
    }

    bytes.addAll(encodeText(doubleDivider));
    bytes.add(0x0A);

    // Final Total
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    final payTitle = removeAccents ? 'THANH TOAN:' : 'THANH TOÁN:';
    bytes.addAll(encodeText(_padRightLeft(payTitle, '${_currencyFormat.format(bill.finalAmount)} d', width, removeAccents: removeAccents)));
    bytes.add(0x0A);
    bytes.addAll([0x1D, 0x21, 0x00]); // Normal
    bytes.addAll([0x1B, 0x45, 0x00]);

    if (!isPrePrint) {
      final methodStr = bill.paymentMethod == 'TRANSFER_QR'
          ? (removeAccents ? 'Chuyen khoan QR' : 'Chuyển khoản QR')
          : bill.paymentMethod == 'CARD'
              ? (removeAccents ? 'The Ngan Hang' : 'Thẻ Ngân Hàng')
              : (removeAccents ? 'Tien mat' : 'Tiền mặt');
      bytes.addAll(encodeText('HTTT: $methodStr'));
      bytes.add(0x0A);
      if (bill.customerName != null && bill.customerName!.isNotEmpty) {
        final custTitle = removeAccents ? 'Khach:' : 'Khách:';
        bytes.addAll(encodeText('$custTitle ${normalize(bill.customerName!)} (${bill.customerPhone ?? ""})'));
        bytes.add(0x0A);
      }
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Align Center Footer
    bytes.addAll([0x1B, 0x61, 0x01]);
    if (store.wifiName.isNotEmpty) {
      bytes.addAll(encodeText('Wifi: ${store.wifiName}'));
      bytes.add(0x0A);
    }
    bytes.addAll(encodeText(removeAccents ? 'Cam on Quy Khach - Hen gap lai!' : 'Cảm ơn Quý Khách - Hẹn gặp lại!'));
    bytes.add(0x0A);

    // 4 line feeds and cut paper
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]); // GS V B 0 - Cut paper

    return Uint8List.fromList(bytes);
  }

  /// Tạo chuỗi byte ESC/POS in phiếu báo bếp / quầy pha chế
  static Uint8List buildKitchenOrderReceiptBytes({
    required KitchenOrderModel kitchenOrder,
    StoreInfoModel? store,
    PrinterPaperSize paperSize = PrinterPaperSize.mm58,
    bool removeAccents = true,
  }) {
    final int width = paperSize.charWidth;
    final List<int> bytes = [];

    List<int> encodeText(String text) {
      return removeAccents ? _vietnameseAscii(text) : utf8.encode(text);
    }

    String normalize(String text) {
      return removeAccents ? _vietnameseAsciiString(text) : text;
    }

    final String singleDivider = '-' * width;

    // ESC @ - Initialize printer
    bytes.addAll([0x1B, 0x40]);

    // Align Center
    bytes.addAll([0x1B, 0x61, 0x01]);

    // Title: PHIẾU BÁO BẾP
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x11]); // Double width + height
    bytes.addAll(encodeText(removeAccents ? 'PHIEU BAO BEP' : 'PHIẾU BÁO BẾP'));
    bytes.add(0x0A);

    // Normal size for sub info
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll([0x1B, 0x45, 0x00]);
    if (store != null && store.storeName.isNotEmpty) {
      bytes.addAll(encodeText(normalize(store.storeName)));
      bytes.add(0x0A);
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Align Left: Tên bàn (In đậm, to rõ)
    bytes.addAll([0x1B, 0x61, 0x00]);
    bytes.addAll([0x1B, 0x45, 0x01]); // Bold ON
    bytes.addAll([0x1D, 0x21, 0x01]); // Double height
    bytes.addAll(encodeText(removeAccents ? 'BAN: ${kitchenOrder.tableName.toUpperCase()}' : 'BÀN: ${kitchenOrder.tableName.toUpperCase()}'));
    bytes.add(0x0A);

    // Normal size for timing
    bytes.addAll([0x1D, 0x21, 0x00]);
    bytes.addAll([0x1B, 0x45, 0x00]);
    final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(kitchenOrder.dateTime);
    bytes.addAll(encodeText(removeAccents ? 'Gio goi: $dateStr' : 'Giờ gọi: $dateStr'));
    bytes.add(0x0A);

    if (kitchenOrder.orderCode != null && kitchenOrder.orderCode!.isNotEmpty) {
      bytes.addAll(encodeText('Ma don: ${kitchenOrder.orderCode}'));
      bytes.add(0x0A);
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Table Header
    bytes.addAll([0x1B, 0x45, 0x01]);
    final col1 = removeAccents ? 'Ten mon' : 'Tên món';
    const col2 = 'SL';
    final col1W = width - 6;
    final headerStr = col1.padRight(col1W) + col2.padLeft(6);
    bytes.addAll(encodeText(headerStr));
    bytes.add(0x0A);
    bytes.addAll([0x1B, 0x45, 0x00]);
    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Items
    for (final item in kitchenOrder.items) {
      final name = normalize(item.name);
      final qtyStr = 'x${item.quantity}';

      // Tên món + SL
      bytes.addAll([0x1B, 0x45, 0x01]); // Bold
      if (name.length <= width - 8) {
        final line = name.padRight(width - 6) + qtyStr.padLeft(6);
        bytes.addAll(encodeText(line));
        bytes.add(0x0A);
      } else {
        bytes.addAll(encodeText(name));
        bytes.add(0x0A);
        bytes.addAll(encodeText((' ' * (width - 6)) + qtyStr.padLeft(6)));
        bytes.add(0x0A);
      }
      bytes.addAll([0x1B, 0x45, 0x00]); // Bold OFF

      // Option details (Size, đường, đá, topping)
      final List<String> details = [];
      if (item.selectedSize.isNotEmpty) details.add('Size ${item.selectedSize}');
      if (item.selectedSugar.isNotEmpty) details.add(item.selectedSugar);
      if (item.selectedIce.isNotEmpty) details.add(item.selectedIce);
      if (item.selectedToppings.isNotEmpty) details.add(item.selectedToppings.join(', '));
      if (details.isNotEmpty) {
        bytes.addAll(encodeText(normalize('  (${details.join(' - ')})')));
        bytes.add(0x0A);
      }

      // Note
      if (item.note.isNotEmpty) {
        bytes.addAll([0x1B, 0x45, 0x01]);
        bytes.addAll(encodeText(normalize('  * ${item.note}')));
        bytes.addAll([0x1B, 0x45, 0x00]);
        bytes.add(0x0A);
      }
    }

    // Ghi chú chung của đơn
    if (kitchenOrder.note != null && kitchenOrder.note!.trim().isNotEmpty) {
      bytes.addAll(encodeText(singleDivider));
      bytes.add(0x0A);
      bytes.addAll([0x1B, 0x45, 0x01]);
      bytes.addAll(encodeText(normalize('Ghi chu don: ${kitchenOrder.note}')));
      bytes.addAll([0x1B, 0x45, 0x00]);
      bytes.add(0x0A);
    }

    bytes.addAll(encodeText(singleDivider));
    bytes.add(0x0A);

    // Cut paper
    bytes.addAll([0x0A, 0x0A, 0x0A, 0x0A]);
    bytes.addAll([0x1D, 0x56, 0x42, 0x00]);

    return Uint8List.fromList(bytes);
  }

  /// Tạo phiếu in mẫu để kiểm tra kết nối máy in và định dạng giấy
  static Uint8List buildTestReceiptBytes({
    required String storeName,
    PrinterPaperSize paperSize = PrinterPaperSize.mm58,
    bool isKitchen = false,
  }) {
    final store = StoreInfoModel(
      storeCode: 'TEST',
      storeName: storeName.isNotEmpty ? storeName : 'POS Trạm',
      address: 'Đà Lạt - Lâm Đồng',
      phone: '0901234567',
      wifiName: 'Tram_Coffee_5G',
    );

    if (isKitchen) {
      final kitchenOrder = KitchenOrderModel(
        tableName: 'Bàn Test 01',
        orderCode: 'OD-TEST-888',
        itemsJson: jsonEncode([
          {'productId': 1, 'name': 'Cà phê muối Trạm', 'price': 35000, 'quantity': 2, 'note': 'Ít ngọt, nhiều đá'},
          {'productId': 2, 'name': 'Trà mãng cầu', 'price': 40000, 'quantity': 1, 'note': ''},
        ]),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        note: 'Phiếu in kiểm tra kết nối bếp Bluetooth thành công!',
      );
      return buildKitchenOrderReceiptBytes(kitchenOrder: kitchenOrder, store: store, paperSize: paperSize);
    }

    final bill = BillModel(
      id: 'B-TEST',
      billCode: 'HD-TEST-999',
      orderCode: 'OD-TEST-999',
      tableName: 'Bàn Test 01',
      zone: 'Khu A',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      staffUsername: 'admin',
      staffFullName: 'Quản Lý Quán',
      items: [
        OrderItemModel(productId: 1, name: 'Cà phê đen đá', price: 25000, quantity: 2),
        OrderItemModel(productId: 2, name: 'Trà đào cam sả', price: 45000, quantity: 1, note: 'Ít đường'),
      ],
      subTotal: 95000,
      finalAmount: 95000,
      paymentMethod: 'CASH',
    );

    return buildBillReceiptBytes(store: store, bill: bill, paperSize: paperSize);
  }

  /// Tạo mảng byte ESC/POS in hóa đơn ở chế độ Đồ họa Raster (Tiếng Việt có dấu 100%)
  static Future<Uint8List> buildBillReceiptRasterBytes({
    required StoreInfoModel store,
    required BillModel bill,
    bool isPrePrint = false,
    PrinterPaperSize paperSize = PrinterPaperSize.mm58,
  }) async {
    final lines = <ReceiptRasterLine>[];

    // Tên quán
    lines.add(ReceiptRasterLine(
      text: store.storeName.toUpperCase(),
      fontSize: 22.0,
      isBold: true,
      align: TextAlign.center,
    ));

    if (store.address.isNotEmpty) {
      lines.add(ReceiptRasterLine(text: store.address, fontSize: 15.0, align: TextAlign.center));
    }
    if (store.phone.isNotEmpty) {
      lines.add(ReceiptRasterLine(text: 'Hotline: ${store.phone}', fontSize: 15.0, align: TextAlign.center));
    }

    lines.add(ReceiptRasterLine.divider(paperSize));

    // Tiêu đề
    lines.add(ReceiptRasterLine(
      text: isPrePrint ? 'PHIẾU TẠM TÍNH' : 'HÓA ĐƠN THANH TOÁN',
      fontSize: 20.0,
      isBold: true,
      align: TextAlign.center,
    ));

    lines.add(ReceiptRasterLine.divider(paperSize));

    // Thông tin hóa đơn
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(bill.createdAt));
    lines.add(ReceiptRasterLine(text: 'Số HĐ: ${bill.billCode}', fontSize: 15.0));
    lines.add(ReceiptRasterLine(text: 'Bàn: ${bill.tableName} (${bill.zone})', fontSize: 15.0, isBold: true));
    lines.add(ReceiptRasterLine(text: 'Thời gian: $dateStr', fontSize: 15.0));
    final staff = bill.staffFullName.isNotEmpty ? bill.staffFullName : bill.staffUsername;
    lines.add(ReceiptRasterLine(text: 'Thu ngân: $staff', fontSize: 15.0));

    lines.add(ReceiptRasterLine.divider(paperSize));

    // Danh sách món
    for (final item in bill.items) {
      final lineText = '${item.name}  x${item.quantity}  ${_currencyFormat.format(item.itemTotal)}đ';
      lines.add(ReceiptRasterLine(text: lineText, fontSize: 16.0, isBold: true));

      final List<String> details = [];
      if (item.selectedSize.isNotEmpty) details.add('Size ${item.selectedSize}');
      if (item.selectedSugar.isNotEmpty) details.add(item.selectedSugar);
      if (item.selectedIce.isNotEmpty) details.add(item.selectedIce);
      if (item.selectedToppings.isNotEmpty) details.add(item.selectedToppings.join(', '));
      if (details.isNotEmpty) {
        lines.add(ReceiptRasterLine(text: '  (${details.join(' - ')})', fontSize: 14.0));
      }

      if (item.note.isNotEmpty) {
        lines.add(ReceiptRasterLine(text: '  * ${item.note}', fontSize: 14.0));
      }

      if (item.hasDiscount) {
        final desc = item.discountDescription((v) => '${_currencyFormat.format(v)}đ');
        lines.add(ReceiptRasterLine(text: '  $desc: -${_currencyFormat.format(item.lineDiscountTotal)}đ', fontSize: 14.0));
      }
    }

    lines.add(ReceiptRasterLine.divider(paperSize));

    // Tổng tiền
    lines.add(ReceiptRasterLine(
      text: 'Tổng tiền hàng: ${_currencyFormat.format(bill.subTotal)} đ',
      fontSize: 16.0,
      align: TextAlign.right,
    ));

    if (bill.finalAmount != bill.subTotal) {
      lines.add(ReceiptRasterLine(
        text: 'Giảm giá / Chiết khấu: -${_currencyFormat.format(bill.subTotal - bill.finalAmount)} đ',
        fontSize: 15.0,
        align: TextAlign.right,
      ));
    }

    lines.add(ReceiptRasterLine.doubleDivider(paperSize));

    lines.add(ReceiptRasterLine(
      text: 'THANH TOÁN: ${_currencyFormat.format(bill.finalAmount)} đ',
      fontSize: 20.0,
      isBold: true,
      align: TextAlign.right,
    ));

    lines.add(ReceiptRasterLine.divider(paperSize));

    if (store.wifiName.isNotEmpty) {
      lines.add(ReceiptRasterLine(text: 'Wifi: ${store.wifiName}', fontSize: 14.0, align: TextAlign.center));
    }
    lines.add(const ReceiptRasterLine(text: 'Cảm ơn Quý Khách - Hẹn gặp lại!', fontSize: 15.0, align: TextAlign.center));

    return await EscPosRasterHelper.renderLinesToRasterBytes(lines: lines, paperSize: paperSize);
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

  /// Gửi lệnh in trực tiếp qua Bluetooth
  static Future<bool> printViaBluetooth({
    required Uint8List data,
  }) async {
    return await BluetoothPrinterService.instance.printBytes(data);
  }

  /// In hóa đơn (Tự động chuyển tiếp vào Hàng Đợi In Lại nếu gặp lỗi, bảo đảm không bao giờ mất phiếu)
  static Future<bool> printBill({
    required StoreInfoModel store,
    required BillModel bill,
    bool isPrePrint = false,
  }) async {
    final bt = BluetoothPrinterService.instance;
    final paperSize = bt.paperSize;
    final encoding = bt.encoding;

    Uint8List bytes;
    if (encoding == PrinterTextEncoding.rasterImage) {
      bytes = await buildBillReceiptRasterBytes(
        store: store,
        bill: bill,
        isPrePrint: isPrePrint,
        paperSize: paperSize,
      );
    } else {
      bytes = buildBillReceiptBytes(
        store: store,
        bill: bill,
        isPrePrint: isPrePrint,
        paperSize: paperSize,
        removeAccents: encoding == PrinterTextEncoding.vietnameseAscii,
      );
    }

    // Nếu cấu hình máy in là LAN và có IP
    if (store.printerType == 'LAN' && store.billPrinterIp.isNotEmpty) {
      final ok = await printViaLan(printerIp: store.billPrinterIp, data: bytes);
      if (ok) return true;
    }

    // Gửi qua Bluetooth kèm cơ chế Print Queue an toàn
    return await PrintQueueService.instance.enqueueAndPrint(
      title: isPrePrint ? 'Tạm tính: ${bill.tableName}' : 'Hóa đơn: ${bill.billCode}',
      type: 'BILL',
      bytes: bytes,
      tableName: bill.tableName,
      billCode: bill.billCode,
      orderCode: bill.orderCode,
    );
  }

  /// In phiếu báo bếp qua Hàng đợi in lại
  static Future<bool> printKitchenOrder({
    required KitchenOrderModel kitchenOrder,
    StoreInfoModel? store,
  }) async {
    final bt = BluetoothPrinterService.instance;
    final paperSize = bt.paperSize;

    final bytes = buildKitchenOrderReceiptBytes(
      kitchenOrder: kitchenOrder,
      store: store,
      paperSize: paperSize,
      removeAccents: bt.encoding == PrinterTextEncoding.vietnameseAscii,
    );

    if (store != null && store.printerType == 'LAN' && store.kitchenPrinterIp.isNotEmpty) {
      final ok = await printViaLan(printerIp: store.kitchenPrinterIp, data: bytes);
      if (ok) return true;
    }

    return await PrintQueueService.instance.enqueueAndPrint(
      title: 'Báo bếp: ${kitchenOrder.tableName}',
      type: 'KITCHEN',
      bytes: bytes,
      tableName: kitchenOrder.tableName,
      orderCode: kitchenOrder.orderCode,
    );
  }

  // Helpers for string alignment
  static String _padRightLeft(String left, String right, int width, {bool removeAccents = true}) {
    if (removeAccents) {
      left = _vietnameseAsciiString(left);
      right = _vietnameseAsciiString(right);
    }
    final spaces = width - left.length - right.length;
    if (spaces <= 0) return '$left $right';
    return left + (' ' * spaces) + right;
  }

  static String _padLine(String col1, String col2, String col3, int width, {bool removeAccents = true}) {
    if (removeAccents) {
      col1 = _vietnameseAsciiString(col1);
      col2 = _vietnameseAsciiString(col2);
      col3 = _vietnameseAsciiString(col3);
    }
    const col2Width = 4;
    final col3Width = width == 48 ? 14 : 12;
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
