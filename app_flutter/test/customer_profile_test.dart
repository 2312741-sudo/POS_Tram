import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/customer_search.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/features/orders/widgets/customer_picker_sheet.dart';

void main() {
  group('KmtCustomerModel Gender & Birthday Tests', () {
    test('Default values for gender and birthday', () {
      final c = KmtCustomerModel(id: 'C1', phone: '0901234567', fullName: 'Nguyễn Văn A');
      expect(c.gender, 'Khác');
      expect(c.birthday, '');
      expect(c.fullName, 'Nguyễn Văn A');
    });

    test('fromMap parses various gender and birthday keys correctly', () {
      // Vietnamese keys
      final c1 = KmtCustomerModel.fromMap({
        'ho_ten': 'Trần Thị B',
        'so_dien_thoai': '0912345678',
        'gioi_tinh': 'Nữ',
        'ngay_sinh': '1995-10-25',
      }, 'C2');
      expect(c1.gender, 'Nữ');
      expect(c1.birthday, '1995-10-25');

      // English keys
      final c2 = KmtCustomerModel.fromMap({
        'name': 'Lê Văn C',
        'phone': '0987654321',
        'gender': 'Nam',
        'birthday': '1990-01-15',
      }, 'C3');
      expect(c2.gender, 'Nam');
      expect(c2.birthday, '1990-01-15');

      // Missing keys fallback
      final c3 = KmtCustomerModel.fromMap({
        'name': 'Phạm D',
        'phone': '0933333333',
      }, 'C4');
      expect(c3.gender, 'Khác');
      expect(c3.birthday, '');
    });

    test('toMap serializes gender and birthday keys', () {
      final c = KmtCustomerModel(
        id: 'C5',
        fullName: 'Hoàng E',
        phone: '0944444444',
        gender: 'Nữ',
        birthday: '2000-05-20',
      );
      final map = c.toMap();
      expect(map['gioi_tinh'], 'Nữ');
      expect(map['gender'], 'Nữ');
      expect(map['ngay_sinh'], '2000-05-20');
      expect(map['birthday'], '2000-05-20');
    });

    test('copyWith updates gender and birthday correctly', () {
      final c = KmtCustomerModel(
        id: 'C6',
        fullName: 'Ngô F',
        phone: '0955555555',
        gender: 'Nam',
        birthday: '1992-03-12',
      );

      final updated = c.copyWith(
        gender: 'Nữ',
        birthday: '1993-04-15',
      );

      expect(updated.id, 'C6');
      expect(updated.fullName, 'Ngô F');
      expect(updated.phone, '0955555555');
      expect(updated.gender, 'Nữ');
      expect(updated.birthday, '1993-04-15');

      // Unchanged copyWith preserves values
      final preserved = updated.copyWith(fullName: 'Ngô F Updated');
      expect(preserved.fullName, 'Ngô F Updated');
      expect(preserved.gender, 'Nữ');
      expect(preserved.birthday, '1993-04-15');
    });
  });

  group('CustomerPickerSheet Widget Tests', () {
    testWidgets('Quick create customer form shows gender and birthday fields', (tester) async {
      String? createdName;
      String? createdPhone;
      String? createdGender;
      String? createdBirthday;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomerPickerSheet(
              loadCandidates: () async => [
                const CustomerCandidate(id: '1', name: 'Khách Cũ', phone: '0901111111', points: 10, totalPoints: 50),
              ],
              lookupByPhone: (_) async => null,
              createCustomer: (name, phone, {gender = 'Khác', birthday = ''}) async {
                createdName = name;
                createdPhone = phone;
                createdGender = gender;
                createdBirthday = birthday;
                return KmtCustomerModel(id: 'new_id', fullName: name, phone: phone, gender: gender, birthday: birthday);
              },
              tiers: LoyaltyTier.defaults,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find "Thêm khách mới" tile and tap it
      final addTile = find.text('Thêm khách mới');
      expect(addTile, findsOneWidget);
      await tester.tap(addTile);
      await tester.pumpAndSettle();

      // Modal dialog should open
      expect(find.text('Thêm khách mới (0 điểm)'), findsOneWidget);
      expect(find.text('Họ và tên *'), findsOneWidget);
      expect(find.text('Số điện thoại *'), findsOneWidget);
      expect(find.text('Giới tính'), findsOneWidget);
      expect(find.text('Nam'), findsOneWidget);
      expect(find.text('Nữ'), findsOneWidget);
      expect(find.text('Khác'), findsOneWidget);
      expect(find.text('Ngày sinh'), findsOneWidget);

      // Try submitting without data -> shows validation error
      final saveBtn = find.text('Lưu & chọn');
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.text('Vui lòng nhập họ và tên'), findsOneWidget);

      // Enter name and invalid phone
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(1), 'Nguyễn Văn Nam'); // Name field (first is search behind or in dialog)
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();
      expect(find.text('Số điện thoại phải có ít nhất 9 chữ số'), findsOneWidget);

      // Enter valid phone
      await tester.enterText(textFields.at(2), '0988776655'); // Phone field

      // Select Gender 'Nữ'
      await tester.tap(find.text('Nữ'));
      await tester.pumpAndSettle();

      // Submit form
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Verify createCustomer was invoked with expected values
      expect(createdName, 'Nguyễn Văn Nam');
      expect(createdPhone, '0988776655');
      expect(createdGender, 'Nữ');
      expect(createdBirthday, '');
    });
  });
}
