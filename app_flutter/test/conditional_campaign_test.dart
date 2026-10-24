import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';
import 'package:tram_flutter/data/models/customer_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';
import 'package:tram_flutter/features/orders/widgets/cart_panels.dart';

CampaignModel _c({
  String id = 'C',
  required String type,
  List<CampaignTier> tiers = const [],
  List<CampaignBuyCondition> conds = const [],
  List<String> items = const [],
  List<String> groups = const [],
  bool hasCodes = false,
  CampaignSchedule? schedule,
  String stacking = 'DISABLED',
}) =>
    CampaignModel(
      campaignId: id,
      programCode: 'KM_$id',
      name: 'CT $id',
      description: '',
      campaignType: type,
      schedule: schedule ?? CampaignSchedule(),
      branchIds: const [],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: items,
      includedGroupIds: groups,
      excludedItemIds: const [],
      tiers: tiers,
      buyConditions: conds,
      warnRepeatedCustomer: false,
      hasCodes: hasCodes,
      autoApply: !hasCodes,
      stackingMode: stacking,
      priority: 1,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 't',
      version: 1,
    );

CampaignTier _t({int threshold = 0, String mode = 'PERCENT', int value = 0, int cap = 0, int maxQty = 0, List<String> reward = const []}) =>
    CampaignTier(
      tierId: 'T$threshold',
      conditionBasis: 'TOTALAMOUNT',
      threshold: threshold,
      benefitMode: mode,
      value: value,
      maxDiscountMoney: cap,
      maxRewardQty: maxQty,
      rewardItemIds: reward,
      rewardGroupIds: const [],
      sortOrder: 1,
    );

void main() {
  group('Campaign & Promotion Midnight End-Date Fix', () {
    test('CampaignModel isEligibleAt returns true throughout the end date even if saved as 00:00:00', () {
      final endAtMidnight = DateTime(2026, 10, 24, 0, 0, 0).millisecondsSinceEpoch;
      final campaign = _c(
        id: 'CP_1',
        type: 'BILLDISCOUNT',
        schedule: CampaignSchedule(absoluteEnd: endAtMidnight),
        tiers: [
          _t(threshold: 0, mode: 'PERCENT', value: 1000),
        ],
      );

      // Thử test vào lúc 10:30 sáng của ngày 24/10/2026
      final testTime10am = DateTime(2026, 10, 24, 10, 30, 0).millisecondsSinceEpoch;
      expect(campaign.isEligibleAt(testTime10am), isTrue,
          reason: 'Chương trình kết thúc ngày 24/10 phải còn hiệu lực lúc 10:30 sáng ngày 24/10');

      // Thử test vào lúc 23:59 tối của ngày 24/10/2026
      final testTime23pm = DateTime(2026, 10, 24, 23, 59, 0).millisecondsSinceEpoch;
      expect(campaign.isEligibleAt(testTime23pm), isTrue,
          reason: 'Chương trình kết thúc ngày 24/10 phải còn hiệu lực lúc 23:59 tối ngày 24/10');

      // Sang ngày hôm sau 25/10/2026 thì mới hết hạn
      final testTimeNextDay = DateTime(2026, 10, 25, 0, 1, 0).millisecondsSinceEpoch;
      expect(campaign.isEligibleAt(testTimeNextDay), isFalse,
          reason: 'Chương trình phải hết hiệu lực khi sang ngày 25/10');
    });

    test('PromotionModel isValid returns true throughout the end date even if saved as 00:00:00', () {
      final now = DateTime.now();
      final endAtMidnight = DateTime(now.year, now.month, now.day, 0, 0, 0).millisecondsSinceEpoch;
      final promo = PromotionModel(
        id: 'P1',
        name: 'Giảm 20k',
        type: 'FIXED_BILL',
        value: 20000,
        startDate: 0,
        endDate: endAtMidnight,
        isActive: true,
      );

      expect(promo.isValid(50000), isTrue);
    });
  });

  group('BUYXGETY and needsRewardItems', () {
    test('CartCampaignPricing.needsRewardItems returns true for BUYXGETY when reward item is not in bill', () {
      final buyXGetY = _c(
        id: 'CP_BUYXGETY',
        type: 'BUYXGETY',
        conds: [
          CampaignBuyCondition(
            conditionId: 'BC1',
            buyItemIds: ['101'],
            requiredBuyQty: 2,
            rewardItemIds: ['202'],
            rewardQty: 1,
            benefitMode: 'FREEITEM',
            value: 0,
            multiplyByBundle: true,
          ),
        ],
      );

      final products = [
        ProductModel(id: 101, name: 'Cà phê đen', price: 25000, unit: 'ly', category: 'Cà phê'),
        ProductModel(id: 202, name: 'Bánh flan', price: 15000, unit: 'cái', category: 'Tráng miệng'),
      ];

      // Đơn hàng có 2 Cà phê đen, nhưng chưa có Bánh flan
      final cart = [
        OrderItemModel(productId: 101, name: 'Cà phê đen', price: 25000, quantity: 2),
      ];

      final quote = CartCampaignPricing.quote(
        buyXGetY,
        cart: cart,
        products: products,
        branchId: 'STORE1',
      );

      expect(quote.totalPromotionDiscount, 0);
      expect(quote.reasons.any((r) => r.reasonCode == 'REWARD_ITEM_NOT_IN_BILL'), isTrue);

      // needsRewardItems PHẢI trả về true để UI cho phép bấm vào tự thêm món Bánh flan
      expect(CartCampaignPricing.needsRewardItems(quote, buyXGetY), isTrue);

      // Kế hoạch thêm món phải trả về đúng 1 phần Bánh flan
      final plan = CartCampaignPricing.rewardPlan(buyXGetY, cart: cart, products: products);
      expect(plan, isNotNull);
      expect(plan!.units, 1);
      expect(plan.candidates.map((p) => p.id), contains(202));
    });

    test('Case-insensitive category matching in BUYXGETY', () {
      final buyXGetY = _c(
        id: 'CP_CAT',
        type: 'BUYXGETY',
        conds: [
          CampaignBuyCondition(
            conditionId: 'BC2',
            buyItemIds: const [],
            buyGroupIds: ['Trà '], // Có khoảng trắng thừa
            requiredBuyQty: 1,
            rewardItemIds: const [],
            rewardGroupIds: ['topping'], // Viết thường
            rewardQty: 1,
            benefitMode: 'FREEITEM',
            value: 0,
          ),
        ],
      );

      final quote = calculatePrice(
        input: PricingInput(
          branchId: 'B1',
          serverNowMs: 1000,
          lines: [
            PricingLineItem(lineId: 'L1', itemId: '1', groupId: 'trà', quantity: 1, unitPrice: 30000),
            PricingLineItem(lineId: 'L2', itemId: '2', groupId: 'Topping', quantity: 1, unitPrice: 10000),
          ],
        ),
        activeCampaigns: [buyXGetY],
        counters: const {},
        customerCounters: const {},
      );

      expect(quote.totalPromotionDiscount, 10000,
          reason: 'Khớp nhóm hàng không phân biệt hoa thường và khoảng trắng');
    });
  });

  group('ITEMPRICERULE (Đồng giá / Đồng giảm)', () {
    test('Pricing engine applies FIXEDPRICE tier correctly to scoped items', () {
      final itemPriceRule = _c(
        id: 'CP_FIXED',
        type: 'ITEMPRICERULE',
        groups: ['Trà sữa'],
        tiers: [
          _t(
            threshold: 0,
            mode: 'FIXEDPRICE',
            value: 19000, // Đồng giá 19k
          ),
        ],
      );

      final quote = calculatePrice(
        input: PricingInput(
          branchId: 'B1',
          serverNowMs: 1000,
          lines: [
            // Trà sữa trân châu 35k -> đồng giá 19k (giảm 16k x 2 = 32k)
            PricingLineItem(lineId: 'L1', itemId: '10', groupId: 'Trà sữa', quantity: 2, unitPrice: 35000),
            // Cà phê 25k (không thuộc nhóm Trà sữa -> không giảm)
            PricingLineItem(lineId: 'L2', itemId: '20', groupId: 'Cà phê', quantity: 1, unitPrice: 25000),
          ],
        ),
        activeCampaigns: [itemPriceRule],
        counters: const {},
        customerCounters: const {},
      );

      expect(quote.totalPromotionDiscount, 32000);
      expect(quote.appliedCampaignIds, contains('CP_FIXED'));
    });
  });

  group('CartCustomerBar UI Edit Action', () {
    testWidgets('CartCustomerBar shows edit button and triggers onEdit when customer attached', (tester) async {
      bool editClicked = false;
      bool clearClicked = false;
      bool usePointsClicked = false;

      final customer = KmtCustomerModel(
        id: 'C1',
        fullName: 'Nguyễn Văn A',
        phone: '0901234567',
        gender: 'Nam',
        birthday: '1995-10-20',
        currentPoints: 100,
        totalPoints: 500,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CartCustomerBar(
              customer: customer,
              pointsUsed: 0,
              onLookup: () {},
              onUsePoints: () => usePointsClicked = true,
              onClear: () => clearClicked = true,
              onEdit: () => editClicked = true,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Nguyễn Văn A • 0901234567'), findsOneWidget);
      expect(find.byTooltip('Sửa thông tin khách'), findsOneWidget);

      await tester.tap(find.byTooltip('Sửa thông tin khách'));
      await tester.pumpAndSettle();
      expect(editClicked, isTrue);

      // Thử bấm trực tiếp vào tên khách
      editClicked = false;
      await tester.tap(find.text('Nguyễn Văn A • 0901234567'));
      await tester.pumpAndSettle();
      expect(editClicked, isTrue);
    });
  });
}
