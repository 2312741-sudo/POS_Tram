import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/widgets/offline_banner.dart';

void main() {
  Future<StreamController<bool>> pump(WidgetTester tester) async {
    final c = StreamController<bool>();
    await tester.pumpWidget(MaterialApp(
      home: OfflineBanner(
        connection: c.stream,
        offlineDelay: const Duration(seconds: 3),
        reconnectedFor: const Duration(seconds: 3),
        child: const Scaffold(body: Text('Màn bán hàng')),
      ),
    ));
    return c;
  }

  testWidgets('mất mạng quá 3 giây mới báo; có mạng lại báo xanh rồi ẩn', (tester) async {
    final c = await pump(tester);
    c.add(false);
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('Mất kết nối mạng'), findsNothing); // chập chờn ngắn: chưa báo
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Mất kết nối mạng'), findsOneWidget);
    expect(find.text('Màn bán hàng'), findsOneWidget);

    c.add(true);
    await tester.pump();
    expect(find.textContaining('Đã kết nối lại'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã kết nối lại'), findsNothing);
    expect(find.textContaining('Mất kết nối mạng'), findsNothing);
    await c.close();
  });

  testWidgets('mất mạng rất ngắn (dưới 3 giây) thì không báo gì', (tester) async {
    final c = await pump(tester);
    c.add(false);
    await tester.pump(const Duration(seconds: 1));
    c.add(true);
    await tester.pump(const Duration(seconds: 5));
    expect(find.textContaining('Mất kết nối mạng'), findsNothing);
    expect(find.textContaining('Đã kết nối lại'), findsNothing);
    await c.close();
  });
}
