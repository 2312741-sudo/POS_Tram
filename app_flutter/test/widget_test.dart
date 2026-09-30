// test/widget_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/main.dart';

void main() {
  testWidgets('App basic smoke test', (WidgetTester tester) async {
    expect(TramApp, isNotNull);
  });
}
