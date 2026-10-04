import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/core/domain/checkout_validator.dart';
import '../lib/core/domain/stock_engine.dart';
import '../lib/core/domain/pricing_engine.dart';
import '../lib/data/models/app_models.dart';
import '../lib/data/models/campaign_models.dart';
import '../lib/data/models/inventory_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Group 1: CheckoutValidator', () {
    test('Empty bill items → error', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [], subTotal: 0, finalAmount: 0, paymentMethod: 'CASH'
      );
      final result = CheckoutValidator.validateBillStructure(bill);
      expect(result.canProceed, false);
      expect(result.errors.any((e) => e.code == 'EMPTY_ITEMS'), true);
    });

    test('Negative finalAmount → error', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100, quantity: 1, discountAmount: 200)],
        subTotal: 100, totalDiscount: 200, finalAmount: -100, paymentMethod: 'CASH'
      );
      final result = CheckoutValidator.validateBillStructure(bill);
      expect(result.canProceed, false);
      expect(result.errors.any((e) => e.code == 'NEGATIVE_AMOUNT'), true);
    });
    
    test('Discount exceeds subtotal → error', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100, quantity: 1, discountAmount: 150)],
        subTotal: 100, totalDiscount: 150, finalAmount: 0, paymentMethod: 'CASH'
      );
      final result = CheckoutValidator.validateBillStructure(bill);
      expect(result.canProceed, false);
      expect(result.errors.any((e) => e.code == 'DISCOUNT_EXCEEDS_SUBTOTAL'), true);
    });

    test('Budget exceeded → warning', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100000, quantity: 1, discountAmount: 20000)],
        subTotal: 100000, totalDiscount: 20000, finalAmount: 80000, paymentMethod: 'CASH'
      );
      
      final campaign = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: 'Camp', description: '',
        campaignType: 'BILL_DISCOUNT', schedule: CampaignSchedule(),
        branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [], buyConditions: [],
        budgetMoney: 100000, warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 0, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      
      final counters = {
        'c1': CampaignCountersModel(
          campaignId: 'c1', spentMoney: 90000, reservedMoney: 0, committedUseCount: 9, reservedUseCount: 0, version: 1
        )
      };
      
      final result = CheckoutValidator.validate(bill: bill, appliedCampaigns: [campaign], counters: counters);
      expect(result.canProceed, true); 
      expect(result.warnings.any((w) => w.code == 'BUDGET_EXCEEDED'), true);
    });

    test('Quota exhausted → error', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100000, quantity: 1, discountAmount: 10000)],
        subTotal: 100000, totalDiscount: 10000, finalAmount: 90000, paymentMethod: 'CASH'
      );
      
      final campaign = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: 'Camp', description: '',
        campaignType: 'BILL_DISCOUNT', schedule: CampaignSchedule(),
        branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [], buyConditions: [],
        maxUses: 10, warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 0, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      
      final counters = {
        'c1': CampaignCountersModel(
          campaignId: 'c1', spentMoney: 90000, reservedMoney: 0, committedUseCount: 10, reservedUseCount: 0, version: 1
        )
      };
      
      final result = CheckoutValidator.validate(bill: bill, appliedCampaigns: [campaign], counters: counters);
      expect(result.canProceed, false);
      expect(result.errors.any((e) => e.code == 'QUOTA_EXHAUSTED'), true);
    });

    test('Valid bill → canProceed = true', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100000, quantity: 1, discountAmount: 10000)],
        subTotal: 100000, totalDiscount: 10000, finalAmount: 90000, paymentMethod: 'CASH'
      );
      
      final result = CheckoutValidator.validateBillStructure(bill);
      expect(result.canProceed, true);
    });

    test('Empty payment method → error', () {
      final bill = BillModel(
        id: '1', billCode: 'HD01', tableName: 'T1', zone: 'A',
        createdAt: 0, staffUsername: 'u1', staffFullName: 'U1',
        items: [OrderItemModel(productId: 1, name: 'Item 1', price: 100000, quantity: 1)],
        subTotal: 100000, finalAmount: 100000, paymentMethod: ''
      );
      
      final result = CheckoutValidator.validateBillStructure(bill);
      expect(result.canProceed, false);
      expect(result.errors.any((e) => e.code == 'EMPTY_PAYMENT_METHOD'), true);
    });
  });

  group('Group 2: StockEngine', () {
    test('Moving weighted average: normal case', () {
      final result = StockEngine.calculateMovingWeightedAverage(
        oldQty: 10, oldAvgCostScaled: 1000000, newQty: 10, newUnitCostScaled: 2000000,
      );
      expect(result, 1500000); 
    });

    test('Moving weighted average: zero old qty (first purchase)', () {
      final result = StockEngine.calculateMovingWeightedAverage(
        oldQty: 0, oldAvgCostScaled: 0, newQty: 10, newUnitCostScaled: 2000000,
      );
      expect(result, 2000000);
    });

    test('Moving weighted average: zero new qty (no change)', () {
      final result = StockEngine.calculateMovingWeightedAverage(
        oldQty: 10, oldAvgCostScaled: 1000000, newQty: 0, newUnitCostScaled: 2000000,
      );
      expect(result, 1000000);
    });

    test('Moving weighted average: both zero → returns 0', () {
      final result = StockEngine.calculateMovingWeightedAverage(
        oldQty: 0, oldAvgCostScaled: 1000000, newQty: 0, newUnitCostScaled: 2000000,
      );
      expect(result, 0);
    });

    test('Recipe consumption: single ingredient', () {
      final recipe = RecipeVersionModel(
        recipeId: 'r1', outputItemId: 'item1', outputQuantityBase: 1, outputUnitId: 'u1',
        effectiveFrom: 0, status: 'ACTIVE',
        ingredients: [
          RecipeIngredient(itemId: 'ing1', itemName: 'Ing 1', unitId: 'u1', quantityBase: 2, wasteRateBps: 0),
        ],
      );
      final result = StockEngine.calculateRecipeConsumption(recipe: recipe, quantity: 2);
      expect(result, {'ing1': 4});
    });

    test('Stock shortage detection: sufficient stock', () {
      final required = {'ing1': 5, 'ing2': 3};
      final balances = <String, StockBalanceModel>{
        'ing1': StockBalanceModel(balanceId: '1', branchId: 'b1', itemId: 'ing1', onHandQty: 10, inventoryValue: 0, averageCostScaled: 0, lastEventSeq: 0, updatedAt: 0),
        'ing2': StockBalanceModel(balanceId: '2', branchId: 'b1', itemId: 'ing2', onHandQty: 3, inventoryValue: 0, averageCostScaled: 0, lastEventSeq: 0, updatedAt: 0),
      };
      final shortages = StockEngine.checkStockAvailability(requiredIngredients: required, balances: balances);
      expect(shortages.isEmpty, true);
    });

    test('Stock shortage detection: insufficient stock', () {
      final required = {'ing1': 5, 'ing2': 3};
      final balances = <String, StockBalanceModel>{
        'ing1': StockBalanceModel(balanceId: '1', branchId: 'b1', itemId: 'ing1', onHandQty: 2, inventoryValue: 0, averageCostScaled: 0, lastEventSeq: 0, updatedAt: 0),
        'ing2': StockBalanceModel(balanceId: '2', branchId: 'b1', itemId: 'ing2', onHandQty: 5, inventoryValue: 0, averageCostScaled: 0, lastEventSeq: 0, updatedAt: 0),
      };
      final shortages = StockEngine.checkStockAvailability(requiredIngredients: required, balances: balances);
      expect(shortages.length, 1);
      expect(shortages[0].itemId, 'ing1');
      expect(shortages[0].shortage, 3);
    });
  });

  group('Group 3: Pricing Engine edge cases', () {
    test('Zero quantity line (should be ignored)', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 0, unitPrice: 50000),
      ];
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [], counters: {}, customerCounters: {});
      expect(result.grossMoney, 0);
      expect(result.netMoney, 0);
    });

    test('Gift line (isGift=true, should not be discounted)', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 1, unitPrice: 50000, isGift: true),
      ];
      final campaign = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: 'Discount', description: '', campaignType: 'BILL_DISCOUNT',
        schedule: CampaignSchedule(), branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [
          CampaignTier(tierId: 't1', conditionBasis: 'TOTALAMOUNT', threshold: 0, benefitMode: 'PERCENT', value: 1000, maxDiscountMoney: 10000, maxRewardQty: 0, rewardItemIds: [], sortOrder: 1)
        ],
        buyConditions: [], warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 0, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [campaign], counters: {}, customerCounters: {});
      
      expect(result.grossMoney, 0); // Gifts don't count towards gross money
      expect(result.totalPromotionDiscount, 0);
    });

    test('Multiple campaigns same type, no-stack picks best', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 1, unitPrice: 100000),
      ];
      final c1 = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: '10%', description: '', campaignType: 'BILL_DISCOUNT',
        schedule: CampaignSchedule(), branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [
          CampaignTier(tierId: 't1', conditionBasis: 'TOTALAMOUNT', threshold: 0, benefitMode: 'PERCENT', value: 1000, maxDiscountMoney: 0, maxRewardQty: 0, rewardItemIds: [], sortOrder: 1)
        ],
        buyConditions: [], warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 2, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      final c2 = CampaignModel(
        campaignId: 'c2', programCode: 'C2', name: '20%', description: '', campaignType: 'BILL_DISCOUNT',
        schedule: CampaignSchedule(), branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [
          CampaignTier(tierId: 't2', conditionBasis: 'TOTALAMOUNT', threshold: 0, benefitMode: 'PERCENT', value: 2000, maxDiscountMoney: 0, maxRewardQty: 0, rewardItemIds: [], sortOrder: 1)
        ],
        buyConditions: [], warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 1, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [c1, c2], counters: {}, customerCounters: {});
      expect(result.totalPromotionDiscount, 20000); // 20%
    });

    test('Empty campaign list → no discount', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 1, unitPrice: 100000),
      ];
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [], counters: {}, customerCounters: {});
      expect(result.totalPromotionDiscount, 0);
      expect(result.netMoney, 100000);
    });

    test('Bill with 0 amount → no discount applied', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 1, unitPrice: 0),
      ];
      final c1 = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: '10k', description: '', campaignType: 'BILL_DISCOUNT',
        schedule: CampaignSchedule(), branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [
          CampaignTier(tierId: 't1', conditionBasis: 'TOTALAMOUNT', threshold: 0, benefitMode: 'FIXED', value: 10000, maxDiscountMoney: 0, maxRewardQty: 0, rewardItemIds: [], sortOrder: 1)
        ],
        buyConditions: [], warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 0, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [c1], counters: {}, customerCounters: {});
      expect(result.totalPromotionDiscount, 0);
    });

    test('Allocation with single line (gets full discount)', () {
      final lines = [
        PricingLineItem(lineId: 'line1', itemId: 'item1', quantity: 1, unitPrice: 100000),
      ];
      final c1 = CampaignModel(
        campaignId: 'c1', programCode: 'C1', name: '10k', description: '', campaignType: 'BILL_DISCOUNT',
        schedule: CampaignSchedule(), branchIds: [], includedCustomerIds: [], excludedCustomerIds: [], includedItemIds: [], includedGroupIds: [], excludedItemIds: [],
        tiers: [
          CampaignTier(tierId: 't1', conditionBasis: 'TOTALAMOUNT', threshold: 0, benefitMode: 'FIXED', value: 15000, maxDiscountMoney: 0, maxRewardQty: 0, rewardItemIds: [], sortOrder: 1)
        ],
        buyConditions: [], warnRepeatedCustomer: false, hasCodes: false, autoApply: true, stackingMode: 'DISABLED', priority: 0, active: true, createdAt: 0, updatedAt: 0, createdBy: '', version: 1
      );
      final input = PricingInput(branchId: 'b1', serverNowMs: 0, lines: lines);
      final result = calculatePrice(input: input, activeCampaigns: [c1], counters: {}, customerCounters: {});
      expect(result.lineBenefits[0].discountMoney, 15000);
    });
  });
}
