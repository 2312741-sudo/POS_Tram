// test/user_management_dialog_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/features/user_management/user_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({required Size screenSize}) {
    return MediaQuery(
      data: MediaQueryData(size: screenSize),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const UserManagementScreen(),
      ),
    );
  }

  testWidgets('Màn hình UserManagementScreen mở dialog Thêm Nhân Viên không bị lỗi layout trên màn hình hẹp (375x667)', (tester) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(screenSize: const Size(375, 667)));
    await tester.pumpAndSettle();

    // Bấm nút FAB 'Thêm Nhân Viên'
    final fab = find.byType(FloatingActionButton);
    expect(fab, findsOneWidget);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // Kiểm tra AlertDialog xuất hiện
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Thêm Nhân Viên Mới'), findsOneWidget);

    // Kiểm tra khối "Quyền riêng lẻ bổ sung" hiển thị đầy đủ
    expect(find.text('Quyền riêng lẻ bổ sung'), findsOneWidget);
    expect(find.text('Không có quyền bổ sung'), findsOneWidget);
    expect(find.text('Tùy chỉnh quyền'), findsOneWidget);

    // Kiểm tra hai nút hành động Hủy và TẠO NHÂN VIÊN nằm cạnh nhau trong Row
    final cancelBtn = find.widgetWithText(OutlinedButton, 'Hủy');
    final createBtn = find.widgetWithText(ElevatedButton, 'TẠO NHÂN VIÊN');
    expect(cancelBtn, findsOneWidget);
    expect(createBtn, findsOneWidget);

    // Kiểm tra vị trí dọc của hai nút bằng nhau (nằm trên cùng 1 hàng, không bị xếp chồng)
    final cancelTop = tester.getTopLeft(cancelBtn).dy;
    final createTop = tester.getTopLeft(createBtn).dy;
    expect(cancelTop, equals(createTop), reason: 'Nút Hủy và Tạo Nhân Viên phải nằm cùng một hàng ngang');

    // Không có ngoại lệ RenderFlex overflow
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dialog Thêm Nhân Viên hiển thị chuẩn trên màn hình nhỏ (320x568)', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(screenSize: const Size(320, 568)));
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Thêm Nhân Viên Mới'), findsOneWidget);
    expect(find.text('Quyền riêng lẻ bổ sung'), findsOneWidget);
    expect(find.text('Không có quyền bổ sung'), findsOneWidget);

    final cancelBtn = find.widgetWithText(OutlinedButton, 'Hủy');
    final createBtn = find.widgetWithText(ElevatedButton, 'TẠO NHÂN VIÊN');
    expect(cancelBtn, findsOneWidget);
    expect(createBtn, findsOneWidget);

    final cancelTop = tester.getTopLeft(cancelBtn).dy;
    final createTop = tester.getTopLeft(createBtn).dy;
    expect(cancelTop, equals(createTop));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Bấm Tùy chỉnh quyền mở dialog phân quyền và cập nhật số lượng quyền đã cấp', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(screenSize: const Size(390, 844)));
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    // Bấm nút 'Tùy chỉnh quyền'
    final tuneBtn = find.widgetWithText(OutlinedButton, 'Tùy chỉnh quyền');
    expect(tuneBtn, findsOneWidget);
    await tester.tap(tuneBtn);
    await tester.pumpAndSettle();

    // Hộp thoại cấp quyền riêng xuất hiện
    expect(find.text('Cấp Quyền Riêng Biệt (Custom Permissions)'), findsOneWidget);

    // Kiểm tra hai nút Hủy và Xác Nhận trong dialog quyền nằm cùng hàng ngang
    final permsCancel = find.widgetWithText(OutlinedButton, 'Hủy').last;
    final permsConfirm = find.widgetWithText(ElevatedButton, 'Xác Nhận');
    expect(permsCancel, findsOneWidget);
    expect(permsConfirm, findsOneWidget);

    final permsCancelTop = tester.getTopLeft(permsCancel).dy;
    final permsConfirmTop = tester.getTopLeft(permsConfirm).dy;
    expect(permsCancelTop, equals(permsConfirmTop));

    // Chọn 1 quyền đầu tiên
    final firstCheckbox = find.byType(CheckboxListTile).first;
    await tester.tap(firstCheckbox);
    await tester.pumpAndSettle();

    // Bấm Xác Nhận
    await tester.tap(permsConfirm);
    await tester.pumpAndSettle();

    // Subtitle được cập nhật thành "1 quyền riêng biệt đã cấp thêm"
    expect(find.text('1 quyền riêng biệt đã cấp thêm'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Dialog Thêm Nhân Viên hiển thị chuẩn trên màn hình Tablet (768x1024)', (tester) async {
    tester.view.physicalSize = const Size(768, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(buildTestApp(screenSize: const Size(768, 1024)));
    await tester.pumpAndSettle();

    final fab = find.byType(FloatingActionButton);
    await tester.tap(fab);
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Thêm Nhân Viên Mới'), findsOneWidget);
    expect(find.text('Quyền riêng lẻ bổ sung'), findsOneWidget);

    final cancelBtn = find.widgetWithText(OutlinedButton, 'Hủy');
    final createBtn = find.widgetWithText(ElevatedButton, 'TẠO NHÂN VIÊN');
    expect(cancelBtn, findsOneWidget);
    expect(createBtn, findsOneWidget);

    final cancelTop = tester.getTopLeft(cancelBtn).dy;
    final createTop = tester.getTopLeft(createBtn).dy;
    expect(cancelTop, equals(createTop));

    expect(tester.takeException(), isNull);
  });
}
