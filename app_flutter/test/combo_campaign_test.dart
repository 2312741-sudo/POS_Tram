import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/reports/report_calculator.dart';
import 'package:tram_flutter/core/reports/report_models.dart';
import 'package:tram_flutter/data/models/bill_model.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';
import 'package:tram_flutter/features/orders/widgets/combo_reward_picker_sheet.dart';

void main() {
  final waterProduct = ProductModel(id: 101, name: 'Trà Đào Cam Sả', price: 35000, category: 'Nước', unit: 'Ly');
  final cakeProduct1 = ProductModel(id: 201, name: 'Bánh Croissant', price: 30000, category: 'Bánh', unit: 'Cái');
  final cakeProduct2 = ProductModel(id: 202, name: 'Bánh Tiramisu', price: 45000, category: 'Bánh', unit: 'Cái');
  final otherProduct = ProductModel(id: 301, name: 'Khăn lạnh', price: 5000, category: 'Khác', unit: 'Cái');
  final List<ProductModel> allProducts = [waterProduct, cakeProduct1, cakeProduct2, otherProduct];

  final comboCampaign = CampaignModel(
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
    stackingMode: 'DISABLED',
    priority: 1,
    active: true,
    createdAt: 0,
    updatedAt: 0,
    createdBy: 'admin',
    version: 1,
  );

  group('CartCampaignPricing Combo Info Tests', () {
    test('1 nước trong giỏ -> tối đa 1 bánh giảm giá', () {
      final cart = [
        OrderItemModel(productId: 101, name: 'Trà Đào Cam Sả', price: 35000, quantity: 1),
      ];

      final info = CartCampaignPricing.getComboInfo(comboCampaign, cart: cart, products: allProducts);
      expect(info, isNotNull);
      expect(info!.buyUnits, equals(1));
      expect(info.maxRewardAllowed, equals(1));
      expect(info.remainingRewardUnits, equals(1));
      expect(info.candidates.map((p) => p.id), containsAll([201, 202]));
      expect(info.candidates.map((p) => p.id), isNot(contains(301))); // Khăn lạnh không nằm trong nhóm Bánh
    });

    test('3 nước trong giỏ -> tối đa 3 bánh giảm giá', () {
      final cart = [
        OrderItemModel(productId: 101, name: 'Trà Đào Cam Sả', price: 35000, quantity: 3),
      ];

      final info = CartCampaignPricing.getComboInfo(comboCampaign, cart: cart, products: allProducts);
      expect(info, isNotNull);
      expect(info!.buyUnits, equals(3));
      expect(info.maxRewardAllowed, equals(3));
      expect(info.remainingRewardUnits, equals(3));
    });

    test('3 nước + 1 bánh trong giỏ -> còn được chọn thêm 2 bánh giảm giá', () {
      final cart = [
        OrderItemModel(productId: 101, name: 'Trà Đào Cam Sả', price: 35000, quantity: 3),
        OrderItemModel(productId: 201, name: 'Bánh Croissant', price: 30000, quantity: 1),
      ];

      final info = CartCampaignPricing.getComboInfo(comboCampaign, cart: cart, products: allProducts);
      expect(info, isNotNull);
      expect(info!.buyUnits, equals(3));
      expect(info.rewardUnitsInCart, equals(1));
      expect(info.maxRewardAllowed, equals(3));
      expect(info.remainingRewardUnits, equals(2));
    });
  });

  group('BillDiscountModel & Pricing Engine Combo Count Tests', () {
    test('Tính giá combo 3 nước + 3 bánh giảm 30k và comboCount = 3', () {
      final cart = [
        OrderItemModel(productId: 101, name: 'Trà Đào Cam Sả', price: 35000, quantity: 3),
        OrderItemModel(productId: 201, name: 'Bánh Croissant', price: 30000, quantity: 2),
        OrderItemModel(productId: 202, name: 'Bánh Tiramisu', price: 45000, quantity: 1),
      ];

      final quote = CartCampaignPricing.quote(
        comboCampaign,
        cart: cart,
        products: allProducts,
        branchId: 'TRAM01',
      );

      expect(quote.totalPromotionDiscount, equals(30000));
      final comboCount = quote.rewardBenefits
          .where((b) => b.campaignId == comboCampaign.campaignId)
          .fold<int>(0, (s, b) => s + b.quantity);
      expect(comboCount, equals(3));

      final discount = CartCampaignPricing.discount(
        comboCampaign,
        quote.totalPromotionDiscount,
        comboCount: comboCount,
      );

      expect(discount.amount, equals(30000));
      expect(discount.comboCount, equals(3));
      final map = discount.toMap();
      expect(map['comboCount'], equals(3));

      final fromMap = BillDiscountModel.fromMap(map);
      expect(fromMap.comboCount, equals(3));
    });
  });

  group('Reports Combo Count Tests', () {
    test('calculateCampaignReport tổng hợp đúng số combo', () {
      final bill1 = BillModel(
        id: 'B1',
        billCode: 'HD001',
        tableName: 'Bàn 1',
        zone: 'Khu A',
        staffUsername: 'staff',
        staffFullName: 'Nhân viên',
        items: const [],
        status: 'PAID',
        createdAt: 1000,
        closedAt: 1000,
        subTotal: 100000,
        finalAmount: 70000,
        discounts: [
          BillDiscountModel(
            campaignId: 'COMBO_1',
            campaignName: 'Combo Nước + Bánh',
            campaignType: 'BUY_X_GET_Y',
            description: 'Combo Nước + Bánh',
            amount: 30000,
            comboCount: 3,
          ),
        ],
      );

      final bill2 = BillModel(
        id: 'B2',
        billCode: 'HD002',
        tableName: 'Bàn 2',
        zone: 'Khu A',
        staffUsername: 'staff',
        staffFullName: 'Nhân viên',
        items: const [],
        status: 'PAID',
        createdAt: 2000,
        closedAt: 2000,
        subTotal: 65000,
        finalAmount: 55000,
        discounts: [
          BillDiscountModel(
            campaignId: 'COMBO_1',
            campaignName: 'Combo Nước + Bánh',
            campaignType: 'BUY_X_GET_Y',
            description: 'Combo Nước + Bánh',
            amount: 10000,
            comboCount: 1,
          ),
        ],
      );

      final reports = ReportCalculator.calculateCampaignReport([bill1, bill2]);
      expect(reports.length, equals(1));
      final comboReport = reports.first;
      expect(comboReport.campaignId, equals('COMBO_1'));
      expect(comboReport.billCount, equals(2));
      expect(comboReport.comboCount, equals(4)); // 3 + 1 = 4 combo
      expect(comboReport.discountAmount, equals(40000));
    });
  });

  group('ComboRewardPickerSheet Widget Tests', () {
    testWidgets('Hiển thị giới hạn số lượng và không cho chọn vượt quá giới hạn nước', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      Map<ProductModel, int>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await showModalBottomSheet<Map<ProductModel, int>>(
                    context: context,
                    builder: (_) => ComboRewardPickerSheet(
                      campaign: comboCampaign,
                      maxAllowedUnits: 2,
                      waterCount: 2,
                      candidateProducts: [cakeProduct1, cakeProduct2],
                      discountPerUnit: 10000,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Kiểm tra header & giới hạn
      expect(find.text('Chọn món giảm giá Combo'), findsOneWidget);
      expect(find.textContaining('Đơn có 2 món nước • Tối đa 2 món giảm giá'), findsOneWidget);
      expect(find.text('0 / 2'), findsOneWidget);
      expect(find.text('Bánh Croissant'), findsOneWidget);
      expect(find.text('Bánh Tiramisu'), findsOneWidget);

      // Thêm 1 Bánh Croissant
      final addButtons = find.byIcon(Icons.add_circle_outline_rounded);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      expect(find.text('1 / 2'), findsOneWidget);

      // Thêm 1 Bánh Tiramisu -> Đủ 2/2
      await tester.tap(addButtons.last);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);

      // Cố thêm bánh thứ 3 -> Bị chặn, snackbar cảnh báo
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      expect(find.textContaining('Đã chọn tối đa 2 món giảm giá'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);

      // Bấm nút Xác nhận
      await tester.tap(find.text('Xác nhận (2 món)'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result![cakeProduct1], equals(1));
      expect(result![cakeProduct2], equals(1));
    });
  });
}
