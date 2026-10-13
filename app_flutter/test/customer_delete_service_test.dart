import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/features/crm/customer_delete_service.dart';

void main() {
  test('xác nhận XOA', () {
    expect(isDeleteCustomerConfirmed('XOA'), isTrue);
    expect(isDeleteCustomerConfirmed(' xoa '), isTrue);
    expect(isDeleteCustomerConfirmed('xóa'), isFalse);
    expect(isDeleteCustomerConfirmed(''), isFalse);
  });
  test('thông báo theo removedMember', () {
    expect(deleteCustomerSuccessMessage(removedMember: true), contains('toàn bộ điểm'));
    expect(deleteCustomerSuccessMessage(removedMember: false), contains('chi nhánh khác'));
  });
}
