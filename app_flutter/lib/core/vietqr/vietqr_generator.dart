// lib/core/vietqr/vietqr_generator.dart
import 'dart:convert';

class VietQrGenerator {
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
    final cleanAccountName = Uri.encodeComponent(accountName.trim());
    final cleanInfo = Uri.encodeComponent(orderInfo.trim());

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
