import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/store_info_model.dart';

/// TRAM02 lâu lâu hiện tài khoản ngân hàng của người khác trên QR: storeInfo đọc chậm → bản mặc định có tài khoản cứng.
void main() {
  test('không có tài khoản ngân hàng mặc định', () {
    final s = StoreInfoModel(storeCode: 'TRAM02', storeName: 'Trạm 02');
    expect(s.bankAccount, '');
    expect(s.accountName, '');
    expect(s.hasBankAccount, isFalse);
    final m = StoreInfoModel.fromMap({'storeName': 'Trạm 02'}, 'TRAM02');
    expect(m.bankAccount, '');
    expect(m.hasBankAccount, isFalse);
  });

  test('bản tạm do mạng lỗi (isFallback) không bao giờ dùng để tạo QR, kể cả khi copyWith', () {
    final f = StoreInfoModel(storeCode: 'TRAM02', storeName: 'x', bankAccount: '123', accountName: 'A', isFallback: true);
    expect(f.hasBankAccount, isFalse);
    expect(f.copyWith(storeName: 'y').isFallback, isTrue);
  });

  test('tài khoản thật của cửa hàng → tạo QR được', () {
    final s = StoreInfoModel.fromMap({'storeName': 'Trạm 02', 'bankId': 'VCB', 'bankAccount': '1900123', 'accountName': 'TRAM 02'}, 'TRAM02');
    expect(s.hasBankAccount, isTrue);
  });
}
