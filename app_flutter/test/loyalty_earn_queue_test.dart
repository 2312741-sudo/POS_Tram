import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tram_flutter/data/services/loyalty_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tích điểm lỗi vào hàng đợi, báo thu ngân, không trùng theo hóa đơn', () async {
    SharedPreferences.setMockInitialValues({});
    final msgs = <String>[];
    final sub = LoyaltyEarnQueue.failures.stream.listen(msgs.add);
    await LoyaltyEarnQueue.add(storeCode: 'A', billId: 'b1', customerId: 'c1', billCode: 'HD-1', error: 'mạng');
    await LoyaltyEarnQueue.add(storeCode: 'A', billId: 'b1', customerId: 'c1', billCode: 'HD-1', error: 'mạng 2');
    await Future<void>.delayed(Duration.zero);
    expect(await LoyaltyEarnQueue.pending(), 1);
    expect(msgs.first, contains('Chưa cộng được điểm'));
    await sub.cancel();
  });
}
