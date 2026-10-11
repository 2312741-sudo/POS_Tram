import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/customer_search.dart';

void main() {
  const a = CustomerCandidate(id: 'a', name: 'Nguyễn Văn A', phone: '0901234567', points: 50, lastVisitAt: 100);
  const b = CustomerCandidate(id: 'b', name: 'Trần Thị Bình', phone: '0912 345 678', points: 300, lastVisitAt: 500);
  const c = CustomerCandidate(id: 'c', name: 'Lê Đức Anh', phone: '0987654321', points: 900);
  final all = [a, b, c];

  test('rỗng: gần đây trước rồi nhiều điểm', () {
    expect(searchCustomers(all, '').map((m) => m.customer.id), ['b', 'a', 'c']);
    expect(searchCustomers(all, '', limit: 2), hasLength(2));
  });

  test('SĐT: đủ số, 4 số cuối, một phần; dưới 3 số không khớp', () {
    expect(searchCustomers(all, '0901234567').first.customer.id, 'a');
    expect(searchCustomers(all, '4321').map((m) => m.customer.id), ['c']);
    expect(searchCustomers(all, '345').map((m) => m.customer.id), contains('b'));
    expect(searchCustomers(all, '09'), isEmpty);
  });

  test('suffix xếp trên khớp giữa số', () {
    final r = searchCustomers(all, '567');
    expect(r.first.customer.id, 'a'); // đuôi 567
  });

  test('tên không dấu, thứ tự từ bất kỳ', () {
    expect(searchCustomers(all, 'nguyen van a').map((m) => m.customer.id), ['a']);
    expect(searchCustomers(all, 'binh tran').map((m) => m.customer.id), ['b']);
    expect(searchCustomers(all, 'duc').map((m) => m.customer.id), ['c']);
    expect(searchCustomers(all, 'zzz'), isEmpty);
  });

  test('tô sáng đúng vị trí', () {
    expect(searchCustomers(all, 'van').first.nameRanges, [const MatchRange(7, 10)]);
    final m = searchCustomers(all, '5678').first;
    expect(m.customer.id, 'b');
    expect(m.phoneRange, const MatchRange(7, 12));
  });

  test('che SĐT', () {
    expect(maskPhone('0901234567'), '090****567');
    expect(maskPhone('123'), '123');
  });
}
