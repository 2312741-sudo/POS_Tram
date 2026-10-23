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

      // Kiểm tra Gốc: Tên sản phẩm và nhãn 2 nhánh • 2 phần
      expect(find.text('Trà Đào Cam Sả'), findsOneWidget);
      expect(find.text('2 nhánh biến thể • 2 phần'), findsOneWidget);

      // Kiểm tra các Nhánh
      expect(find.text('Nhánh #1'), findsOneWidget);
      expect(find.text('Nhánh #2'), findsOneWidget);
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
  });
}
