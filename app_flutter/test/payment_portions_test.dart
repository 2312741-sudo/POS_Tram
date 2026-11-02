import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/bill_model.dart';

void main() {
  test('hóa đơn hỗn hợp chia theo paymentSplits; TM + QR = thực thu', () {
    final split = BillModel.fromMap({
      'id': 'c', 'billCode': 'HD-1', 'status': 'PAID', 'finalAmount': 405000, 'subTotal': 405000, 'paymentMethod': 'SPLIT',
      'paymentSplits': [
        {'method': 'CASH', 'amount': 185000},
        {'method': 'TRANSFER_QR', 'amount': 220000},
      ],
    }, 'c');
    expect(split.paymentPortions, {'CASH': 185000, 'TRANSFER_QR': 220000, 'CARD': 0});
    final qr = BillModel.fromMap({'id': 'b', 'status': 'PAID', 'finalAmount': 200000, 'paymentMethod': 'TRANSFER_QR'}, 'b');
    expect(qr.paymentPortions, {'CASH': 0, 'TRANSFER_QR': 200000, 'CARD': 0});
  });
}
