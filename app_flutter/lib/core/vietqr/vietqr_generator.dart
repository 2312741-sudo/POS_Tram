// lib/core/vietqr/vietqr_generator.dart

class VietQrGenerator {
  /// Chuyển tiếng Việt có dấu thành không dấu, loại bỏ ký tự lạ
  static String toAscii(String str) {
    var result = str;
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴÈÉẸẺẼÊỀẾỆỂỄÌÍỊỈĨÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠÙÚỤỦŨƯỪỨỰỬỮỲÝỴỶỸĐ';
    const to   = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyydAAAAAAAAAAAAAAAAAEEEEEEEEEEEIIIIIOOOOOOOOOOOOOOOOOUUUUUUUUUUUYYYYYD';
    for (int i = 0; i < from.length; i++) {
      result = result.replaceAll(from[i], to[i]);
    }
    return result;
  }

  /// Chuẩn hóa nội dung chuyển khoản theo chuẩn Napas VietQR (không dấu, <= 25 ký tự, dạng: TRAM01 BAN 1)
  static String buildOrderInfo({
    required String storeCode,
    required String tableName,
    String? suffix,
  }) {
    // 1. Mã chi nhánh (TRAM01, TRAM02...)
    final cleanStore = toAscii(storeCode).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final storePart = cleanStore.isEmpty ? 'TRAM' : cleanStore;

    // 2. Tên bàn (VD: "Bàn 1" -> "BAN 1", "Bàn A1" -> "BAN A1", "Mang về 2" -> "MV 2")
    var cleanTable = toAscii(tableName).toUpperCase().trim();
    // Thay thế từ viết tắt cho gọn
    cleanTable = cleanTable.replaceAll(RegExp(r'\bMANG\s+VE\b'), 'MV');
    // Chỉ giữ chữ cái, số và khoảng trắng đơn
    cleanTable = cleanTable.replaceAll(RegExp(r'[^A-Z0-9\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

    var info = '$storePart $cleanTable';
    if (suffix != null && suffix.trim().isNotEmpty) {
      final cleanSuffix = toAscii(suffix).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
      info = '$info $cleanSuffix';
    }

    // Giới hạn tối đa 25 ký tự theo quy định chuẩn của Napas 24/7
    if (info.length > 25) {
      info = info.substring(0, 25).trim();
    }
    return info;
  }

  /// Sinh đường dẫn ảnh QR Napas VietQR động theo chuẩn ngân hàng Việt Nam
  static String generateImageUrl({
    required String bankId,
    required String bankAccount,
    required String accountName,
    required int amount,
    required String orderInfo,
    String template = 'compact2', // 'compact2', 'qr_only', 'print'
  }) {
    final cleanBankId = bankId.trim().toUpperCase();
    final cleanAccount = bankAccount.trim();
    // Luôn chuẩn hóa tên tài khoản và nội dung sang ASCII không dấu
    final cleanAccountName = Uri.encodeComponent(toAscii(accountName.trim()).toUpperCase());
    final cleanInfo = Uri.encodeComponent(toAscii(orderInfo.trim()).toUpperCase());

    return 'https://img.vietqr.io/image/$cleanBankId-$cleanAccount-$template.jpg?amount=$amount&addInfo=$cleanInfo&accountName=$cleanAccountName';
  }

  /// Danh sách các ngân hàng phổ biến tại Việt Nam
  static const List<Map<String, String>> popularBanks = [
    {'id': 'MB', 'name': 'MB Bank (Quân Đội)'},
    {'id': 'VCB', 'name': 'Vietcombank'},
    {'id': 'TCB', 'name': 'Techcombank'},
    {'id': 'ACB', 'name': 'ACB'},
    {'id': 'VPB', 'name': 'VPBank'},
    {'id': 'BIDV', 'name': 'BIDV'},
    {'id': 'CTG', 'name': 'VietinBank'},
    {'id': 'TPB', 'name': 'TPBank'},
    {'id': 'STB', 'name': 'Sacombank'},
    {'id': 'VIB', 'name': 'VIB'},
    {'id': 'HDB', 'name': 'HDBank'},
    {'id': 'OCB', 'name': 'OCB'},
    {'id': 'SHB', 'name': 'SHB'},
    {'id': 'MSB', 'name': 'MSB'},
    {'id': 'CAKE', 'name': 'CAKE by VPBank'},
  ];
}
