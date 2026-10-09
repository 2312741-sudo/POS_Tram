// test/table_card_theme_test.dart
//
// Sơ đồ bàn ở chế độ Sáng/Tối: thẻ bàn + thanh lọc trạng thái phải render không
// lỗi layout, màu 4 trạng thái phải khác nhau và đủ tương phản ở cả 2 theme.
// Kèm test hồi quy lỗi "BoxConstraints forces an infinite width": theme đặt
// minimumSize = Size.fromHeight(52) (rộng vô hạn) cho Elevated/OutlinedButton,
// nên nút đặt trong Row phải có Expanded/Flexible hoặc minimumSize có chiều rộng.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/table_model.dart';
import 'package:tram_flutter/features/tables/widgets/table_card.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

String _json(List<OrderItemModel> items) => jsonEncode(items.map((e) => e.toMap()).toList());

List<TableModel> _tables() {
  final serving = TableModel(
    name: 'B1',
    zone: 'Khu A',
    inUse: true,
    guestCount: 4,
    openedAt: DateTime.now().millisecondsSinceEpoch,
    currentOrderJson: _json([OrderItemModel(productId: 1, name: 'Cà phê sữa', price: 25000, quantity: 2)]),
  );
  final awaiting = TableModel(
    name: 'B2',
    zone: 'Khu A',
    inUse: true,
    currentOrderJson: _json([OrderItemModel(productId: 2, name: 'Trà đào', price: 35000, quantity: 1)]),
  )..markPrePrinted(by: 'thungan', at: DateTime(2026, 1, 1, 9, 30).millisecondsSinceEpoch);
  final reserved = TableModel(
    name: 'B3',
    zone: 'Khu B',
    isReserved: true,
    reservationCustomer: 'Anh Nam',
    reservationPhone: '0900000000',
    reservationTime: '19:00',
    reservationDeposit: 100000,
  );
  return [TableModel(name: 'B0', zone: 'Khu A', capacity: 4), serving, awaiting, reserved];
}

Widget _host(ThemeData theme, Widget child) => MaterialApp(
      theme: theme,
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('TableStatusStyle', () {
    for (final dark in [false, true]) {
      final mode = dark ? 'tối' : 'sáng';
      final card = dark ? TramTokens.dark.card : TramTokens.light.card;

      test('4 trạng thái khác màu nhau ($mode)', () {
        final colors = TableVisualStatus.values.map((s) => TableStatusStyle.of(s, dark: dark).color.toARGB32()).toSet();
        expect(colors.length, TableVisualStatus.values.length);
      });

      test('chữ trắng trên nhãn và chữ trạng thái trên nền thẻ đủ tương phản ($mode)', () {
        for (final s in TableVisualStatus.values) {
          final st = TableStatusStyle.of(s, dark: dark);
          expect(_contrast(Colors.white, st.color), greaterThan(3.9), reason: 'nhãn $s');
          expect(_contrast(st.ink, st.background), greaterThan(4.5), reason: 'chữ $s trên nền thẻ');
          expect(_contrast(st.color, card), greaterThan(3), reason: 'viền/dải màu $s trên nền tối/sáng');
        }
      });
    }

    test('Chờ thanh toán dùng tông tím đồng bộ web (#5B3FB0 / #B39DF2)', () {
      expect(TableStatusStyle.of(TableVisualStatus.awaitingPayment).color, const Color(0xFF5B3FB0));
      expect(TableStatusStyle.of(TableVisualStatus.awaitingPayment, dark: true).ink, const Color(0xFFB39DF2));
      final hue = HSLColor.fromColor(TramColors.tableAwaitingPayment).hue;
      expect(hue, inInclusiveRange(245, 270));
    });
  });

  for (final entry in <String, ThemeData Function()>{'sáng': () => AppTheme.lightTheme, 'tối': () => AppTheme.appDarkTheme}.entries) {
    testWidgets('Thẻ bàn + thanh lọc render không lỗi (theme ${entry.key})', (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final tables = _tables();
      await tester.pumpWidget(_host(
        entry.value(),
        Column(
          children: [
            TableStatusFilterBar(
              selected: 'AWAITING',
              total: 4,
              emptyCount: 1,
              inUseCount: 1,
              awaitingCount: 1,
              reservedCount: 1,
              onSelected: (_) {},
            ),
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                childAspectRatio: 230 / 156,
                children: [
                  for (final t in tables)
                    TableCard(table: t, onTap: () {}, onLongPress: () {}, onMenuSelected: (_) {}),
                ],
              ),
            ),
          ],
        ),
      ));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Chờ thanh toán'), findsOneWidget); // nhãn trên thẻ B2
      expect(find.text('Chờ thanh toán (1)'), findsOneWidget); // chip chú thích
      expect(find.textContaining('Đã in tạm tính 09:30'), findsOneWidget);
      expect(find.text('Anh Nam'), findsOneWidget);

      // Menu thao tác nhanh của bàn có khách mở được (popup trong theme hiện tại).
      await tester.tap(find.byTooltip('Thao tác nhanh').at(1));
      await tester.pumpAndSettle();
      expect(find.text('Hủy hóa đơn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  group('Nút trong Row với theme Size.fromHeight(52)', () {
    testWidgets('hồi quy: nút theme mặc định trong Row gây lỗi chiều rộng vô hạn', (tester) async {
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add; // gom lỗi mong đợi, không in ra log
      try {
        await tester.pumpWidget(_host(
          AppTheme.lightTheme,
          Row(children: [ElevatedButton(onPressed: () {}, child: const Text('Lưu'))]),
        ));
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors.map((e) => e.exceptionAsString()).join('\n'), contains('infinite width'));
    });

    testWidgets('minimumSize có chiều rộng / Expanded thì không lỗi (sáng & tối)', (tester) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.appDarkTheme]) {
        await tester.pumpWidget(_host(
          theme,
          Row(children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
              onPressed: () {},
              child: const Text('Bỏ qua'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
              onPressed: () {},
              child: const Text('Tiếp tục'),
            ),
            Expanded(child: ElevatedButton(onPressed: () {}, child: const Text('Nhập'))),
          ]),
        ));
        expect(tester.takeException(), isNull);
      }
    });
  });
}
