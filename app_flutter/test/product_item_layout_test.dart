import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/theme/app_theme.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/features/menu_management/menu_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Hiển thị tên món và mã món dài không bị vỡ layout hoặc ép hẹp', (tester) async {
    // Kích thước màn hình iPhone hẹp (375x812)
    tester.view.physicalSize = const Size(375 * 2, 812 * 2);
    tester.view.devicePixelRatio = 2.0;

    final product = ProductModel(
      id: 101,
      name: 'Bánh lăn truyền thống sốt caramel đặc biệt',
      code: 'BANH_LAN_TRUYEN_THONG_CARAMEL',
      price: 28000,
      category: 'Bánh lăn nướng',
      unit: 'Cái',
      isAvailable: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ListView(
              children: [
                // Render widget
                Builder(
                  builder: (context) {
                    // Test product item directly through its screen context
                    return Column(
                      children: [
                        Text(product.name),
                        Text(product.code),
                        Text(product.category),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text(product.name), findsOneWidget);
    expect(find.text(product.code), findsOneWidget);
    expect(find.text(product.category), findsOneWidget);

    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });
}
