import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/features/orders/widgets/cart_item_card.dart';
import 'package:tram_flutter/features/tables/widgets/table_card.dart';

import 'support/real_fonts.dart';

/// Thẻ bàn và dòng món không được tràn chữ ở kích thước điện thoại (font thật Be Vietnam Pro).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(loadRealFonts);

  final now = DateTime.now().millisecondsSinceEpoch;
  TableModel busy() => TableModel(
        name: 'Bàn VIP 12 Sân vườn',
        zone: 'Tầng 2 - Sân thượng',
        inUse: true,
        currentBillId: 'HD2610300012345',
        openedAt: now - 95 * 60000,
        guestCount: 12,
        customerId: 'c1',
        customerName: 'Nguyễn Thị Thanh Hương Ngọc Bích',
        note: 'Khách quen, cần ghế em bé và bàn gần cửa sổ',
        prePrintedAt: now - 60000,
      );
  TableModel reserved() => TableModel(
        name: 'Bàn 05',
        zone: 'Tầng 1',
        isReserved: true,
        reservationCustomer: 'Trần Văn Hoàng Long Đặt Bàn Sinh Nhật',
        reservationPhone: '0909 123 456',
        reservationTime: '19:30',
        reservationDeposit: 500000,
      );
  TableModel ordering() => TableModel(
        name: 'Bàn 07',
        zone: 'Khu ngoài trời có mái che',
        orderingBy: 'u1',
        orderingByName: 'Lê Thị Phục Vụ Ca Tối',
        orderingAt: now,
      );

  for (final w in [140.0, 180.0, 230.0]) {
    for (final entry in {'đang dùng': busy, 'đặt trước': reserved, 'đang chọn món': ordering}.entries) {
      testWidgets('Thẻ bàn ${entry.key} rộng $w', (t) async {
        await t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: w,
                height: 156, // mainAxisExtent của lưới bàn
                child: TableCard(table: entry.value(), onTap: () {}, onLongPress: () {}, onMenuSelected: (_) {}),
              ),
            ),
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  }

  for (final w in [320.0, 360.0]) {
    testWidgets('Dòng món trong giỏ rộng $w', (t) async {
      final item = OrderItemModel(
        productId: 1,
        name: 'Trà Đào Cam Sả Hạt Chia Kem Muối Size Lớn Đặc Biệt',
        price: 59000,
        quantity: 12,
        selectedSize: 'L (Lớn)',
        selectedSugar: '30% Đường',
        selectedIce: 'Ít đá',
        selectedToppings: const ['Thạch đào', 'Trân châu trắng', 'Kem cheese'],
        toppingPrice: 15000,
        note: 'Mang về, để riêng đá, thêm ống hút giấy',
      );
      t.view.physicalSize = Size(w * 3, 2400);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(padding: const EdgeInsets.all(12), children: [
            CartItemCard(
              item: item,
              onRemove: () {},
              onEditNote: () {},
              onDiscount: () {},
              onIncrement: () {},
              onDecrement: () {},
              kitchenBadgeLabel: 'Đã gửi bếp 2',
              promoDiscounts: const [(campaignName: 'Combo Bánh và Nước giảm 10K giờ vàng', discountAmount: 10000, quantity: 1, isGift: false)],
            ),
          ]),
        ),
      ));
      await t.pump();
      expect(t.takeException(), isNull);
    });
  }
}
