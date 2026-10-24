// test/cart_tree_group_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:tram_flutter/data/models/app_models.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';
import 'package:tram_flutter/features/orders/widgets/cart_tree_group_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Cart Tree Group & Promotion Discount Tests', () {
    test('buildCartProductGroups groups items of same product into single root with branches', () {
      final cart = [
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 30000,
          quantity: 1,
          selectedSize: 'M',
          selectedSugar: '50% Đường',
          selectedIce: '50% Đá',
          selectedToppings: const ['Thạch Đào'],
          toppingPrice: 5000,
        ),
        OrderItemModel(
          productId: 202,
          name: 'Bánh Mì Chảo',
          price: 45000,
          quantity: 2,
        ),
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 30000,
          quantity: 2,
          selectedSize: 'L',
          sizeExtraPrice: 5000,
          note: 'Mang về, ít ngọt',
        ),
      ];

      final promoDiscounts = <int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>>{
        2: [(campaignName: 'Combo Nước + Bánh', discountAmount: 10000, quantity: 2, isGift: false)],
      };

      final groups = buildCartProductGroups(
        cart: cart,
        linePromoDiscounts: promoDiscounts,
        isSoldOutFn: (item) => false,
      );

      // Sẽ có 2 nhóm sản phẩm: Trà Đào Cam Sả và Bánh Mì Chảo
      expect(groups.length, equals(2));

      // Nhóm 1: Trà Đào Cam Sả
      final teaGroup = groups[0];
      expect(teaGroup.productId, equals(101));
      expect(teaGroup.productName, equals('Trà Đào Cam Sả'));
      expect(teaGroup.branches.length, equals(2));
      expect(teaGroup.totalQuantity, equals(3)); // 1 + 2 = 3 phần

      // Branch 1: cartIndex 0, unitPrice = 35.000 đ, qty = 1 -> 35.000 đ
      expect(teaGroup.branches[0].cartIndex, equals(0));
      expect(teaGroup.branches[0].item.unitPrice, equals(35000));
      expect(teaGroup.branches[0].effectiveTotal, equals(35000));
      expect(teaGroup.branches[0].promoDiscounts, isEmpty);

      // Branch 2: cartIndex 2, unitPrice = 35.000 đ, qty = 2 -> gross 70.000 đ, promo -10.000 đ -> effective 60.000 đ
      expect(teaGroup.branches[1].cartIndex, equals(2));
      expect(teaGroup.branches[1].item.unitPrice, equals(35000));
      expect(teaGroup.branches[1].item.lineGross, equals(70000));
      expect(teaGroup.branches[1].totalPromoDiscount, equals(10000));
      expect(teaGroup.branches[1].effectiveTotal, equals(60000));
      expect(teaGroup.branches[1].promoDiscounts.first.campaignName, equals('Combo Nước + Bánh'));

      // Tổng nhóm Trà Đào Cam Sả: gross = 35k + 70k = 105k, effective = 35k + 60k = 95k
      expect(teaGroup.totalGross, equals(105000));
      expect(teaGroup.totalDiscount, equals(10000));
      expect(teaGroup.effectiveTotal, equals(95000));
      expect(teaGroup.hasAnyDiscount, isTrue);

      // Nhóm 2: Bánh Mì Chảo (1 branch duy nhất)
      final breadGroup = groups[1];
      expect(breadGroup.productId, equals(202));
      expect(breadGroup.branches.length, equals(1));
      expect(breadGroup.totalQuantity, equals(2));
      expect(breadGroup.effectiveTotal, equals(90000));
      expect(breadGroup.hasAnyDiscount, isFalse);
    });

    test('computeLinePromotionDiscounts calculates discounts per cart item line for combo', () {
      final cart = [
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 35000,
          quantity: 1,
        ),
        OrderItemModel(
          productId: 201,
          name: 'Bánh Croissant',
          price: 30000,
          quantity: 1,
        ),
      ];

      final products = [
        ProductModel(id: 101, name: 'Trà Đào Cam Sả', price: 35000, category: 'Nước', unit: 'Ly'),
        ProductModel(id: 201, name: 'Bánh Croissant', price: 30000, category: 'Bánh', unit: 'Cái'),
      ];

      final campaign = CampaignModel(
        campaignId: 'COMBO_1',
        programCode: 'COMBO_NUOC_BANH',
        name: 'Combo Mua Nước + Bánh Giảm 10K',
        description: 'Mua 1 nước được giảm 10k cho 1 bánh',
        campaignType: 'BUY_X_GET_Y',
        schedule: CampaignSchedule(),
        branchIds: const [],
        includedCustomerIds: const [],
        excludedCustomerIds: const [],
        includedItemIds: const [],
        includedGroupIds: const [],
        excludedItemIds: const [],
        tiers: const [],
        buyConditions: [
          CampaignBuyCondition(
            conditionId: 'COND_1',
            buyItemIds: const [],
            buyGroupIds: ['Nước'],
            requiredBuyQty: 1,
            rewardItemIds: const [],
            rewardGroupIds: ['Bánh'],
            rewardQty: 1,
            benefitMode: 'FIXED',
            value: 10000,
            multiplyByBundle: true,
          ),
        ],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: false,
        stackingMode: 'STACKABLE',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'admin',
        version: 1,
      );

      final appliedDiscounts = <BillDiscountModel>[
        BillDiscountModel(
          campaignName: campaign.name,
          description: campaign.description,
          amount: 10000,
          campaignId: campaign.campaignId,
        ),
      ];

      final discounts = CartCampaignPricing.computeLinePromotionDiscounts(
        cart: cart,
        appliedDiscounts: appliedDiscounts,
        campaignsById: {campaign.campaignId: campaign},
        products: products,
        branchId: 'TRAM_01',
      );

      // Bánh Croissant (dòng index 1) được giảm 10.000 đ
      expect(discounts.containsKey(1), isTrue);
      expect(discounts[1]!.length, equals(1));
      expect(discounts[1]!.first.discountAmount, equals(10000));
      expect(discounts[1]!.first.campaignName, equals('Combo Mua Nước + Bánh Giảm 10K'));
    });

    testWidgets('CartTreeGroupCard renders tree branches and badges properly', (tester) async {
      final cart = [
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 30000,
          quantity: 1,
          selectedSize: 'M',
        ),
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 30000,
          quantity: 1,
          selectedSize: 'L',
          note: 'Mang về',
        ),
      ];

      final promoDiscounts = <int, List<({String campaignName, int discountAmount, int quantity, bool isGift})>>{
        1: [(campaignName: 'Giảm 10k', discountAmount: 10000, quantity: 1, isGift: false)],
      };

      final groups = buildCartProductGroups(
        cart: cart,
        linePromoDiscounts: promoDiscounts,
        isSoldOutFn: (_) => false,
      );

      int incrementedIndex = -1;
      int removedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CartTreeGroupCard(
              group: groups.first,
              onRemove: (idx) => removedIndex = idx,
              onEditNote: (_) {},
              onDiscount: (_) {},
              onIncrement: (idx) => incrementedIndex = idx,
              onDecrement: (_) {},
            ),
          ),
        ),
      );

      // Kiểm tra Gốc: Tên sản phẩm và nhãn 2 nhánh
      expect(find.text('Trà Đào Cam Sả'), findsOneWidget);
      expect(find.textContaining('2 phân nhánh'), findsOneWidget);

      // Kiểm tra các Nhánh
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      expect(find.text('Ghi chú: Mang về'), findsOneWidget);
      expect(find.textContaining('🎁 Giảm KM: -10.000 đ'), findsOneWidget);

      // Bấm nút tăng số lượng của nhánh 1
      final steppers = find.byIcon(Icons.add);
      expect(steppers, findsNWidgets(2));
      await tester.tap(steppers.first);
      expect(incrementedIndex, equals(0));

      // Bấm nút xóa nhánh 2
      final deleteButtons = find.byIcon(Icons.close_rounded);
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.last);
      expect(removedIndex, equals(1));
    });

    test('Treo đơn qua giờ combo vẫn giữ được ưu đãi combo khi recalculate', () {
      final cart = [
        OrderItemModel(
          productId: 101,
          name: 'Trà Đào Cam Sả',
          price: 35000,
          quantity: 1,
        ),
        OrderItemModel(
          productId: 201,
          name: 'Bánh Croissant',
          price: 30000,
          quantity: 1,
        ),
      ];

      final products = [
        ProductModel(id: 101, name: 'Trà Đào Cam Sả', price: 35000, category: 'Nước', unit: 'Ly'),
        ProductModel(id: 201, name: 'Bánh Croissant', price: 30000, category: 'Bánh', unit: 'Cái'),
      ];

      // Combo chỉ áp dụng từ 07:00 đến 09:00
      final schedule = CampaignSchedule(
        timeSlots: [
          CampaignTimeSlot(startTime: '07:00', endTime: '09:00'),
        ],
      );

      final campaign = CampaignModel(
        campaignId: 'COMBO_MORNING',
        programCode: 'COMBO_SANG',
        name: 'Combo Sáng Giảm 10K',
        description: 'Mua nước + bánh từ 7h-9h giảm 10k',
        campaignType: 'BUY_X_GET_Y',
        schedule: schedule,
        branchIds: const [],
        includedCustomerIds: const [],
        excludedCustomerIds: const [],
        includedItemIds: const [],
        includedGroupIds: const [],
        excludedItemIds: const [],
        tiers: const [],
        buyConditions: [
          CampaignBuyCondition(
            conditionId: 'COND_1',
            buyItemIds: const [],
            buyGroupIds: ['Nước'],
            requiredBuyQty: 1,
            rewardItemIds: const [],
            rewardGroupIds: ['Bánh'],
            rewardQty: 1,
            benefitMode: 'FIXED',
            value: 10000,
            multiplyByBundle: true,
          ),
        ],
        warnRepeatedCustomer: false,
        hasCodes: false,
        autoApply: false,
        stackingMode: 'STACKABLE',
        priority: 1,
        active: true,
        createdAt: 0,
        updatedAt: 0,
        createdBy: 'admin',
        version: 1,
      );

      final appliedDiscounts = <BillDiscountModel>[
        BillDiscountModel(
          campaignId: campaign.campaignId,
          campaignName: campaign.name,
          description: campaign.description,
          amount: 10000,
        ),
      ];

      // Đơn đã áp dụng combo lúc 08:30 (trong giờ combo).
      // Giờ hiện tại là 09:30 (ngoài giờ combo, qua giờ).
      // Recalculate với isExistingOrder: true (treo đơn)
      final r = CartCampaignPricing.recalculate(
        appliedDiscounts,
        {campaign.campaignId: campaign},
        cart: cart,
        products: products,
        branchId: 'TRAM_01',
        isExistingOrder: true,
      );

      // Ưu đãi combo vẫn PHẢI ĐƯỢC GIỮ LẠI, không bị rơi vào dropped!
      expect(r.dropped, isEmpty);
      expect(r.discounts.length, equals(1));
      expect(r.discounts.first.amount, equals(10000));
      expect(r.discounts.first.campaignId, equals('COMBO_MORNING'));

      // Cũng kiểm tra computeLinePromotionDiscounts trên từng dòng món
      final linePromos = CartCampaignPricing.computeLinePromotionDiscounts(
        cart: cart,
        appliedDiscounts: r.discounts,
        campaignsById: {campaign.campaignId: campaign},
        products: products,
        branchId: 'TRAM_01',
        isExistingOrder: true,
      );
      expect(linePromos.containsKey(1), isTrue);
      expect(linePromos[1]!.first.discountAmount, equals(10000));
    });

    test('Không chia nhánh món đã gửi bếp và chưa gửi bếp nếu cùng tính chất; chỉ chia khi khác tính chất', () {
      // Giỏ hàng gồm:
      // Line 0: Trà Olong - Chanh tươi (x1, 100% đường, 100% đá, đã gửi bếp isSentKitchen = true)
      // Line 1: Trà Olong - Chanh tươi (x7, 100% đường, 100% đá, chưa gửi bếp isSentKitchen = false)
      // Line 2: Trà Olong - Chanh tươi (x2, 50% đường, 50% đá, đã gửi bếp isSentKitchen = true - tính chất khác)
      final cart = [
        OrderItemModel(
          productId: 10,
          name: 'Trà Olong - Chanh tươi',
          price: 20000,
          quantity: 1,
          selectedSugar: '100% đường',
          selectedIce: '100% đá',
          isSentKitchen: true,
        ),
        OrderItemModel(
          productId: 10,
          name: 'Trà Olong - Chanh tươi',
          price: 20000,
          quantity: 7,
          selectedSugar: '100% đường',
          selectedIce: '100% đá',
          isSentKitchen: false,
        ),
        OrderItemModel(
          productId: 10,
          name: 'Trà Olong - Chanh tươi',
          price: 20000,
          quantity: 2,
          selectedSugar: '50% đường',
          selectedIce: '50% đá',
          isSentKitchen: true,
        ),
      ];

      final groups = buildCartProductGroups(
        cart: cart,
        linePromoDiscounts: const {},
        isSoldOutFn: (_) => false,
      );

      // Cùng 1 sản phẩm Trà Olong Chanh tươi -> 1 group
      expect(groups.length, equals(1));
      final group = groups.first;
      expect(group.totalQuantity, equals(10)); // 1 + 7 + 2 = 10 phần

      // Chỉ có 2 nhánh vì Line 0 và Line 1 có cùng tính chất (100% đường, 100% đá) dù khác trạng thái bếp!
      expect(group.branches.length, equals(2));

      // Nhánh 1: 100% đường, 100% đá (gồm line 0 và line 1 gom lại)
      final branch1 = group.branches[0];
      expect(branch1.totalQuantity, equals(8)); // 1 + 7 = 8 phần
      expect(branch1.cartIndices, equals([0, 1]));
      expect(branch1.sentCount, equals(1));
      expect(branch1.unsentCount, equals(7));
      expect(branch1.item.selectedSugar, equals('100% đường'));
      expect(branch1.item.selectedIce, equals('100% đá'));
      expect(branch1.effectiveTotal, equals(160000));

      // Nhánh 2: 50% đường, 50% đá (line 2 riêng vì khác tính chất)
      final branch2 = group.branches[1];
      expect(branch2.totalQuantity, equals(2));
      expect(branch2.cartIndices, equals([2]));
      expect(branch2.sentCount, equals(2));
      expect(branch2.unsentCount, equals(0));
      expect(branch2.item.selectedSugar, equals('50% đường'));
      expect(branch2.item.selectedIce, equals('50% đá'));
      expect(branch2.effectiveTotal, equals(40000));
    });

    test('Nếu tất cả các dòng của món đều cùng tính chất thì gom thành 1 nhánh duy nhất (hiển thị thẻ đơn gọn gàng)', () {
      final cart = [
        OrderItemModel(
          productId: 10,
          name: 'Trà Olong - Chanh tươi',
          price: 20000,
          quantity: 1,
          selectedSugar: '100% đường',
          selectedIce: '100% đá',
          isSentKitchen: true,
        ),
        OrderItemModel(
          productId: 10,
          name: 'Trà Olong - Chanh tươi',
          price: 20000,
          quantity: 7,
          selectedSugar: '100% đường',
          selectedIce: '100% đá',
          isSentKitchen: true,
        ),
      ];

      final groups = buildCartProductGroups(
        cart: cart,
        linePromoDiscounts: const {},
        isSoldOutFn: (_) => false,
      );

      expect(groups.length, equals(1));
      expect(groups.first.branches.length, equals(1)); // Đúng 1 nhánh duy nhất!
      expect(groups.first.totalQuantity, equals(8));
      expect(groups.first.branches.first.sentCount, equals(8));
      expect(groups.first.branches.first.unsentCount, equals(0));
      expect(groups.first.effectiveTotal, equals(160000));
    });
  });
}
