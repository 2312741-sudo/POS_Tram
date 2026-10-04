// lib/core/printer/printer_types.dart
import 'dart:convert';
import 'dart:typed_data';

/// Khổ giấy máy in nhiệt
enum PrinterPaperSize {
  mm58, // Khổ 58mm (độ rộng ~384 dots, 32 ký tự font A)
  mm80; // Khổ 80mm (độ rộng ~576 dots, 48 ký tự font A)

  int get charWidth => this == PrinterPaperSize.mm58 ? 32 : 48;
  int get dotWidth => this == PrinterPaperSize.mm58 ? 384 : 576;
  String get label => this == PrinterPaperSize.mm58 ? 'Khổ 58mm' : 'Khổ 80mm';

  static PrinterPaperSize fromString(String? val) {
    if (val == 'mm80' || val == '80mm' || val == '80') return PrinterPaperSize.mm80;
    return PrinterPaperSize.mm58;
  }
}

/// Chế độ mã hóa chữ in tiếng Việt
enum PrinterTextEncoding {
  vietnameseAscii, // Loại bỏ dấu tiếng Việt (ESC/POS chuẩn tốc độ cao, tương thích 100% mọi máy in)
  utf8Direct,      // Gửi UTF-8 trực tiếp (dành cho máy in đời mới có hỗ trợ mã hóa UTF-8)
  rasterImage;     // Chuyển toàn bộ phiếu sang hình ảnh Bitmap Raster (đầy đủ dấu tiếng Việt sắc nét)

  String get label {
    switch (this) {
      case PrinterTextEncoding.vietnameseAscii:
        return 'Không dấu (Nhanh & Tương thích cao)';
      case PrinterTextEncoding.utf8Direct:
        return 'UTF-8 Trực tiếp (Máy in hỗ trợ UTF-8)';
      case PrinterTextEncoding.rasterImage:
        return 'Hình ảnh Raster (Có dấu tiếng Việt 100%)';
    }
  }

  static PrinterTextEncoding fromString(String? val) {
    if (val == 'rasterImage' || val == 'RASTER') return PrinterTextEncoding.rasterImage;
    if (val == 'utf8Direct' || val == 'UTF8') return PrinterTextEncoding.utf8Direct;
    return PrinterTextEncoding.vietnameseAscii;
  }
}

/// Thông tin thiết bị máy in Bluetooth
class PrinterDevice {
  final String name;
  final String macAddress;
  final bool isConnected;

  const PrinterDevice({
    required this.name,
    required this.macAddress,
    this.isConnected = false,
  });

  Map<String, dynamic> toMap() => {
    'name': name,
    'macAddress': macAddress,
    'isConnected': isConnected,
  };

  factory PrinterDevice.fromMap(Map<String, dynamic> map) => PrinterDevice(
    name: map['name']?.toString() ?? 'Máy in Bluetooth',
    macAddress: map['macAddress']?.toString() ?? '',
    isConnected: map['isConnected'] == true,
  );
}

/// Trạng thái của lệnh in trong Hàng đợi in lại
enum PrintJobStatus {
  pending,  // Đang chờ in
  printing, // Đang gửi lệnh
  success,  // In thành công
  failed;   // In thất bại (được giữ trong hàng đợi để in lại)

  String get label {
    switch (this) {
      case PrintJobStatus.pending:
        return 'Chờ in';
      case PrintJobStatus.printing:
        return 'Đang in';
      case PrintJobStatus.success:
        return 'Thành công';
      case PrintJobStatus.failed:
        return 'Lỗi (Chờ in lại)';
    }
  }
}

/// Phiếu in trong Hàng đợi in lại (Print Queue)
class PrintJob {
  final String id;
  final String title;
  final String type; // 'BILL', 'KITCHEN', 'TEST'
  final Uint8List bytes;
  final int createdAt;
  PrintJobStatus status;
  String? errorMessage;
  int retryCount;
  final String? tableName;
  final String? orderCode;
  final String? billCode;

  PrintJob({
    required this.id,
    required this.title,
    required this.type,
    required this.bytes,
    required this.createdAt,
    this.status = PrintJobStatus.pending,
    this.errorMessage,
    this.retryCount = 0,
    this.tableName,
    this.orderCode,
    this.billCode,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'type': type,
    'bytesBase64': base64Encode(bytes),
    'createdAt': createdAt,
    'status': status.name,
    'errorMessage': errorMessage,
    'retryCount': retryCount,
    'tableName': tableName,
    'orderCode': orderCode,
    'billCode': billCode,
  };

  factory PrintJob.fromMap(Map<String, dynamic> map) {
    Uint8List dataBytes = Uint8List(0);
    final b64 = map['bytesBase64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        dataBytes = base64Decode(b64);
      } catch (_) {}
    }
    return PrintJob(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Phiếu in',
      type: map['type']?.toString() ?? 'BILL',
      bytes: dataBytes,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      status: PrintJobStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PrintJobStatus.pending,
      ),
      errorMessage: map['errorMessage']?.toString(),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      tableName: map['tableName']?.toString(),
      orderCode: map['orderCode']?.toString(),
      billCode: map['billCode']?.toString(),
    );
  }
}
