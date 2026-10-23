import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';

void main() {
  group('Campaign Stacking & Max Campaigns Per Order Tests', () {
    final comboCampaign = CampaignModel(
      campaignId: 'CAMP_COMBO',
      programCode: 'COMBO01',
      name: 'Combo Nước + Bánh',
      description: 'Mua nước + bánh giảm 10k',
      campaignType: CampaignType.buyXGetY.toMap(),
      schedule: CampaignSchedule(),
      branchIds: const [],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: const [],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      stackingMode: 'DISABLED', // Độc quyền: không cho phép cộng dồn!
      priority: 1,
      active: true,
      createdAt: 1000,
      updatedAt: 1000,
      createdBy: 'admin',
      version: 1,
    );

    final birthdayCampaign = CampaignModel(
      campaignId: 'CAMP_BDAY',
      programCode: 'BDAY01',
      name: 'Giảm giá Sinh nhật 20%',
      description: 'Giảm 20% đúng ngày sinh nhật',
      campaignType: CampaignType.billDiscount.toMap(),
      schedule: CampaignSchedule(),
      branchIds: const [],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: const [],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: true,
      birthdayOnly: true,
      stackingMode: 'ENABLED',
      priority: 2,
      active: true,
      createdAt: 1000,
      updatedAt: 1000,
      createdBy: 'admin',
      version: 1,
    );

    final limitedCampaign = CampaignModel(
      campaignId: 'CAMP_LIMIT2',
      programCode: 'LIMIT02',
      name: 'KM Giới Hạn Tối Đa 2',
      description: 'Tối đa 2 CTKM trong 1 đơn',
      campaignType: CampaignType.billDiscount.toMap(),
      schedule: CampaignSchedule(),
      branchIds: const [],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: const [],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      stackingMode: 'ENABLED',
      maxCampaignsPerOrder: 2,
      priority: 3,
      active: true,
      createdAt: 1000,
      updatedAt: 1000,
      createdBy: 'admin',
      version: 1,
    );

    final stackableCampaign = CampaignModel(
      campaignId: 'CAMP_STACK',
      programCode: 'STACK01',
      name: 'KM Cộng Dồn Bth',
      description: 'Cộng dồn bình thường',
      campaignType: CampaignType.billDiscount.toMap(),
      schedule: CampaignSchedule(),
      branchIds: const [],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: const [],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      stackingMode: 'ENABLED',
      priority: 4,
      active: true,
      createdAt: 1000,
      updatedAt: 1000,
      createdBy: 'admin',
      version: 1,
    );

    final byId = {
      comboCampaign.campaignId: comboCampaign,
      birthdayCampaign.campaignId: birthdayCampaign,
      limitedCampaign.campaignId: limitedCampaign,
      stackableCampaign.campaignId: stackableCampaign,
    };

    test('CTKM tắt cộng dồn (stackingMode: DISABLED) thì isStackable = false & effectiveMax = 1', () {
      expect(comboCampaign.isStackable, isFalse);
      expect(comboCampaign.effectiveMaxCampaignsPerOrder, equals(1));
      expect(birthdayCampaign.isStackable, isTrue);
      expect(limitedCampaign.effectiveMaxCampaignsPerOrder, equals(2));
    });

    test('Đơn đã có Combo (không cộng dồn) -> Không cho áp dụng thêm Sinh nhật (checkStacking chặn)', () {
      final currentDiscounts = [
        BillDiscountModel(
          campaignId: comboCampaign.campaignId,
          description: comboCampaign.name,
          amount: 10000,
          comboCount: 1,
        ),
      ];

      final check = CartCampaignPricing.checkStacking(
        currentDiscounts: currentDiscounts,
        incoming: birthdayCampaign,
        campaignsById: byId,
        allowStackPromotions: true,
      );

      // Chặn: Đơn đã có Combo độc quyền
      expect(check.canStack, isFalse);
      expect(check.conflictingExclusiveCampaign?.campaignId, equals(comboCampaign.campaignId));
      expect(check.reason, contains('độc quyền'));
    });

    test('Đơn đã có Sinh nhật -> Khi chọn Combo (không cộng dồn), checkStacking yêu cầu gỡ các ưu đãi cũ', () {
      final currentDiscounts = [
        BillDiscountModel(
          campaignId: birthdayCampaign.campaignId,
          description: birthdayCampaign.name,
          amount: 25000,
        ),
      ];

      final check = CartCampaignPricing.checkStacking(
        currentDiscounts: currentDiscounts,
        incoming: comboCampaign,
        campaignsById: byId,
        allowStackPromotions: true,
      );

      expect(check.canStack, isFalse);
      expect(check.requiresClearingExisting, isTrue);
      expect(check.conflictingExclusiveCampaign, isNull);
    });

    test('Giới hạn số lượng CTKM tối đa trên 1 đơn (maxCampaignsPerOrder)', () {
      // Đơn đã có 2 CTKM: [Sinh nhật, Giới hạn 2]
      final currentDiscounts = [
        BillDiscountModel(
          campaignId: birthdayCampaign.campaignId,
          description: birthdayCampaign.name,
          amount: 20000,
        ),
        BillDiscountModel(
          campaignId: limitedCampaign.campaignId,
          description: limitedCampaign.name,
          amount: 15000,
        ),
      ];

      // Thử thêm CTKM thứ 3 -> Bị chặn vì đạt giới hạn tối đa 2
      final check = CartCampaignPricing.checkStacking(
        currentDiscounts: currentDiscounts,
        incoming: stackableCampaign,
        campaignsById: byId,
        allowStackPromotions: true,
      );

      expect(check.canStack, isFalse);
      expect(check.maxAllowedCampaigns, equals(2));
      expect(check.reason, contains('Đơn đã đạt giới hạn tối đa 2'));
    });

    test('addWithStacking gỡ ưu đãi khi thêm CTKM độc quyền và tôn trọng giới hạn số lượng', () {
      final d1 = BillDiscountModel(campaignId: birthdayCampaign.campaignId, description: birthdayCampaign.name, amount: 20000);
      final dCombo = BillDiscountModel(campaignId: comboCampaign.campaignId, description: comboCampaign.name, amount: 10000);

      // Thêm combo độc quyền -> Gỡ sinh nhật
      final res1 = CartCampaignPricing.addWithStacking(
        currentDiscounts: [d1],
        incomingDiscount: dCombo,
        incomingCampaign: comboCampaign,
        campaignsById: byId,
        allowStackPromotions: true,
      );
      expect(res1.discounts.map((e) => e.campaignId), equals([comboCampaign.campaignId]));
      expect(res1.removed, contains(birthdayCampaign.name));

      // Thêm CTKM giới hạn 2 vào giỏ có 2 CTKM -> Giữ tối đa 2
      final d2 = BillDiscountModel(campaignId: stackableCampaign.campaignId, description: stackableCampaign.name, amount: 5000);
      final dLimit = BillDiscountModel(campaignId: limitedCampaign.campaignId, description: limitedCampaign.name, amount: 12000);
      final res2 = CartCampaignPricing.addWithStacking(
        currentDiscounts: [d1, d2],
        incomingDiscount: dLimit,
        incomingCampaign: limitedCampaign,
        campaignsById: byId,
        allowStackPromotions: true,
      );
      expect(res2.discounts.length, equals(2));
      expect(res2.discounts.map((e) => e.campaignId), contains(limitedCampaign.campaignId));
    });
  });
}
