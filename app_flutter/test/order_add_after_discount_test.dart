import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/order_integrity.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';

void main() {
  group('Kiểm tra thêm món sau khi đã giảm giá món và gửi bếp', () {
    test('4 món giảm giá + gửi bếp, thêm tiếp 2 món cùng loại -> tách thành 2 dòng riêng biệt, 2 món mới KHÔNG bị giảm giá', () {
      final product = ProductModel(
        id: 101,
        name: 'Trà Sữa Trân Châu',
        price: 30000,
        unit: 'ly',
        category: 'Trà Sữa',
      );

      // Bước 1: Khách đặt 4 ly trà sữa
      final cart = <OrderItemModel>[
        OrderItemModel(
          productId: product.id,
          name: product.name,
          price: product.price,
          quantity: 4,
          isSentKitchen: false,
        ),
      ];

      // Bước 2: Nhân viên áp dụng giảm giá món 10% cho 4 ly (discountedQuantity = 4)
      cart[0] = cart[0].withLineDiscount(percent: 10, discountedQuantity: 4);
      expect(cart[0].discountPercent, 10);
      expect(cart[0].discountedQuantity, 4);
      expect(cart[0].lineDiscountTotal, 12000); // 4 * 30000 * 10% = 12000
      expect(cart[0].itemTotal, 108000); // 120000 - 12000 = 108000

      // Bước 3: Bấm gửi bếp -> đơn được lưu, isSentKitchen = true
      cart[0] = cart[0].copyWith(isSentKitchen: true);
      expect(cart[0].isSentKitchen, isTrue);

      // Bước 4: Khách gọi thêm 2 ly cùng loại (không giảm giá món)
      // Logic add to cart trong order_list_screen:
      void addToCart(ProductModel p, int qty) {
        final existingIdx = cart.indexWhere((i) =>
            !i.isSentKitchen &&
            !i.hasDiscount &&
            i.productId == p.id &&
            i.name == p.name &&
            i.selectedSize.isEmpty &&
            i.selectedToppings.isEmpty &&
            i.note.isEmpty);

        if (existingIdx >= 0) {
          cart[existingIdx] = cart[existingIdx].copyWith(
            quantity: cart[existingIdx].quantity + qty,
          );
        } else {
          cart.add(OrderItemModel(
            productId: p.id,
            name: p.name,
            price: p.price,
            quantity: qty,
            isSentKitchen: false,
          ));
        }
      }

      // Thêm 2 ly
      addToCart(product, 1);
      addToCart(product, 1);

      // Kiểm tra kết quả:
      // Phải có đúng 2 dòng trong giỏ hàng:
      expect(cart.length, 2, reason: 'Phải tách thành 2 dòng riêng biệt: 1 dòng cũ đã gửi bếp + giảm giá, 1 dòng mới');

      // Dòng 1: 4 ly đã gửi bếp, được giảm 10%
      expect(cart[0].quantity, 4);
      expect(cart[0].isSentKitchen, isTrue);
      expect(cart[0].hasDiscount, isTrue);
      expect(cart[0].discountPercent, 10);
      expect(cart[0].discountedQuantity, 4);
      expect(cart[0].lineDiscountTotal, 12000);
      expect(cart[0].itemTotal, 108000);

      // Dòng 2: 2 ly mới thêm, CHƯA gửi bếp, KHÔNG ĐƯỢC GIẢM GIÁ (giá bình thường)
      expect(cart[1].quantity, 2);
      expect(cart[1].isSentKitchen, isFalse);
      expect(cart[1].hasDiscount, isFalse);
      expect(cart[1].discountPercent, 0);
      expect(cart[1].discountAmount, 0);
      expect(cart[1].lineDiscountTotal, 0);
      expect(cart[1].itemTotal, 60000); // 2 * 30000 = 60000 nguyên giá

      // Tổng cộng: 6 sản phẩm, tổng tiền = 108.000 + 60.000 = 168.000đ
      final totalGross = cart.fold<int>(0, (s, i) => s + i.lineGross);
      final totalDiscount = cart.fold<int>(0, (s, i) => s + i.lineDiscountTotal);
      final totalPay = cart.fold<int>(0, (s, i) => s + i.itemTotal);

      expect(totalGross, 180000); // 6 * 30000
      expect(totalDiscount, 12000); // Chỉ giảm 4 ly, 2 ly không giảm
      expect(totalPay, 168000);

      // Khi bấm gửi bếp lần 2: chỉ gửi các món chưa gửi bếp
      final unsent = cart.where((i) => !i.isSentKitchen).toList();
      expect(unsent.length, 1);
      expect(unsent.first.quantity, 2);
    });

    test('Bấm nút + trên dòng đã gửi bếp hoặc đã có giảm giá: tạo/cộng vào dòng mới chưa gửi bếp và không giảm giá', () {
      final cart = <OrderItemModel>[
        OrderItemModel(
          productId: 101,
          name: 'Trà Sữa Trân Châu',
          price: 30000,
          quantity: 4,
          isSentKitchen: true,
        ).withLineDiscount(percent: 10, discountedQuantity: 4),
      ];

      // Giả lập hàm _incrementItem(0)
      void incrementItem(int index) {
        final item = cart[index];
        if (item.isSentKitchen || item.hasDiscount) {
          final existingNewIdx = cart.indexWhere((i) =>
              !i.isSentKitchen &&
              !i.hasDiscount &&
              i.productId == item.productId &&
              i.name == item.name &&
              i.selectedSize == item.selectedSize &&
              i.selectedSugar == item.selectedSugar &&
              i.selectedIce == item.selectedIce &&
              i.selectedToppings.join(',') == item.selectedToppings.join(',') &&
              i.note == item.note);
          if (existingNewIdx >= 0) {
            cart[existingNewIdx] = cart[existingNewIdx].copyWith(
              quantity: cart[existingNewIdx].quantity + 1,
            );
          } else {
            cart.add(OrderItemModel(
              productId: item.productId,
              name: item.name,
              price: item.price,
              quantity: 1,
              isSentKitchen: false,
            ));
          }
        } else {
          cart[index] = cart[index].copyWith(quantity: cart[index].quantity + 1);
        }
      }

      // Nhấn + lần 1
      incrementItem(0);
      expect(cart.length, 2);
      expect(cart[0].quantity, 4);
      expect(cart[0].hasDiscount, isTrue);
      expect(cart[1].quantity, 1);
      expect(cart[1].hasDiscount, isFalse);

      // Nhấn + lần 2
      incrementItem(0);
      expect(cart.length, 2);
      expect(cart[0].quantity, 4);
      expect(cart[1].quantity, 2);
      expect(cart[1].hasDiscount, isFalse);
    });
  });
}
