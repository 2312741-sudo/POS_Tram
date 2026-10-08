import 'package:flutter_test/flutter_test.dart';
import 'package:tram_payment_bot/main.dart';

void main() {
  testWidgets('TramPaymentBotApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const TramPaymentBotApp());
    expect(find.text('Trạm Payment Bot'), findsWidgets);
  });
}
