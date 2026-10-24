import 'package:flutter_test/flutter_test.dart';
import 'package:tram_flutter/core/domain/pricing_engine.dart';
import 'package:tram_flutter/data/models/campaign_models.dart';
import 'package:tram_flutter/data/models/order_item_model.dart';
import 'package:tram_flutter/data/models/product_model.dart';
import 'package:tram_flutter/data/models/promotion_model.dart';
import 'package:tram_flutter/features/orders/widgets/campaign_pricing.dart';
import 'package:tram_flutter/features/promotions/voucher_check.dart';

CampaignModel _c({
  String id = 'C',
  required String type,
  List<CampaignTier> tiers = const [],
  List<CampaignBuyCondition> conds = const [],
  List<String> items = const [],
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
      includedGroupIds: const [],
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
      sortOrder: 1,
    );

CampaignBuyCondition _bxgy({
  List<String> x = const ['X'],
  int buy = 1,
  List<String> y = const ['Y'],
  int get = 1,
  String mode = 'FREEITEM',
  int value = 0,
  bool multiply = true,
}) =>
    CampaignBuyCondition(
      conditionId: 'BC',
      buyItemIds: x,
      requiredBuyQty: buy,
      rewardItemIds: y,
      rewardQty: get,
      benefitMode: mode,
      value: value,
      multiplyByBundle: multiply,
    );

PricingLineItem _l(String id, String item, int qty, int price, {int pct = 0, int dq = 0}) =>
    PricingLineItem(lineId: id, itemId: item, quantity: qty, unitPrice: price, discountPercent: pct, discountedQuantity: dq);

PriceQuoteModel _q(CampaignModel c, List<PricingLineItem> lines) => calculatePrice(
      input: PricingInput(branchId: 'B', serverNowMs: 1000, lines: lines),
      activeCampaigns: [c],
      counters: const {},
      customerCounters: const {},
    );

void main() {
  group('BILL_DISCOUNT', () {
    test('không chọn món → áp dụng toàn bộ hóa đơn, phân bổ mọi dòng', () {
      final q = _q(_c(type: 'BILLDISCOUNT', tiers: [_t(mode: 'PERCENT', value: 1000)]),
          [_l('1', 'A', 1, 100000), _l('2', 'B', 2, 50000)]);
      expect(q.totalPromotionDiscount, 20000);
      expect(q.billBenefits.single.lineAllocations.keys.toSet(), {'1', '2'});
    });

    test('giảm % có "Giảm tối đa"', () {
      final q = _q(_c(type: 'BILL_DISCOUNT', tiers: [_t(mode: 'PERCENT', value: 2000, cap: 30000)]), [_l('1', 'A', 1, 500000)]);
      expect(q.totalPromotionDiscount, 30000);
    });

    test('giảm số tiền: cap cũng được tôn trọng & không vượt tiền đơn', () {
      expect(_q(_c(type: 'BILLDISCOUNT', tiers: [_t(mode: 'FIXED', value: 50000, cap: 20000)]), [_l('1', 'A', 1, 100000)]).totalPromotionDiscount,
          20000);
      expect(_q(_c(type: 'BILLDISCOUNT', tiers: [_t(mode: 'FIXED', value: 50000)]), [_l('1', 'A', 1, 30000)]).totalPromotionDiscount, 30000);
    });

    test('"Đơn hàng từ" (threshold) và cơ sở tính sau giảm theo dòng', () {
      final c = _c(type: 'BILLDISCOUNT', tiers: [_t(threshold: 200000, mode: 'FIXED', value: 20000)]);
      expect(_q(c, [_l('1', 'A', 1, 199000)]).totalPromotionDiscount, 0);
      expect(_q(c, [_l('1', 'A', 1, 199000)]).reasons.single.reasonCode, 'ORDER_VALUE_NOT_REACHED');
      expect(_q(c, [_l('1', 'A', 2, 100000)]).totalPromotionDiscount, 20000);
      // 2 x 100k giảm thủ công 10% 1 phần → còn 190k < 200k
      expect(_q(c, [_l('1', 'A', 2, 100000, pct: 10, dq: 1)]).totalPromotionDiscount, 0);
    });
  });

  group('BUY_X_GET_Y', () {
    test('tặng Y, nhân theo số X (5 X mua 1 tặng 1 → 5 Y)', () {
      final q = _q(_c(type: 'BUYXGETY', conds: [_bxgy()]), [_l('x', 'X', 5, 30000), _l('y', 'Y', 6, 20000)]);
      expect(q.totalPromotionDiscount, 100000);
      expect(q.rewardBenefits.single.quantity, 5);
      expect(q.rewardBenefits.single.isGift, true);
      expect(q.appliedCampaignIds, ['C']);
    });

    test('không nhân: bao nhiêu X cũng chỉ thưởng rewardQty 1 lần', () {
      final q = _q(_c(type: 'BUYXGETY', conds: [_bxgy(get: 2, multiply: false)]), [_l('x', 'X', 5, 30000), _l('y', 'Y', 6, 20000)]);
      expect(q.totalPromotionDiscount, 40000);
    });

    test('giảm % và giảm số tiền cho Y, chọn Y rẻ nhất trước', () {
      final lines = [_l('x', 'X', 2, 30000), _l('y1', 'Y1', 1, 50000), _l('y2', 'Y2', 1, 20000)];
      final pct = _q(_c(type: 'BUYXGETY', conds: [_bxgy(buy: 2, y: ['Y1', 'Y2'], mode: 'PERCENT', value: 5000)]), lines);
      expect(pct.totalPromotionDiscount, 10000); // 50% của món 20k
      expect(pct.rewardBenefits.single.lineId, 'y2');
      final amt = _q(_c(type: 'BUYXGETY', conds: [_bxgy(buy: 2, y: ['Y1', 'Y2'], mode: 'FIXED', value: 30000)]), lines);
      expect(amt.totalPromotionDiscount, 20000); // chặn theo giá món
    });

    test('X trùng Y: mua 2 tặng 1 cùng món', () {
      final c = _c(type: 'BUYXGETY', conds: [_bxgy(x: ['X'], buy: 2, y: ['X'])]);
      expect(_q(c, [_l('1', 'X', 2, 10000)]).totalPromotionDiscount, 0);
      expect(_q(c, [_l('1', 'X', 3, 10000)]).totalPromotionDiscount, 10000);
      expect(_q(c, [_l('1', 'X', 6, 10000)]).totalPromotionDiscount, 20000);
    });

    test('chưa có Y trong đơn → lý do REWARD_ITEM_NOT_IN_BILL', () {
      final q = _q(_c(type: 'BUYXGETY', conds: [_bxgy()]), [_l('x', 'X', 1, 30000)]);
      expect(q.totalPromotionDiscount, 0);
      expect(q.reasons.first.reasonCode, 'REWARD_ITEM_NOT_IN_BILL');
    });

    test('tôn trọng giảm giá đã có trên dòng Y', () {
      // Y đã giảm thủ công 50% → tặng chỉ giảm phần còn lại 10k
      final q = _q(_c(type: 'BUYXGETY', conds: [_bxgy()]), [_l('x', 'X', 1, 30000), _l('y', 'Y', 1, 20000, pct: 50, dq: 1)]);
      expect(q.totalPromotionDiscount, 10000);
      expect(q.netMoney, 50000 - 10000 - 10000);
    });

    test('web lưu FREEITEM value 10000 vẫn là tặng 100%', () {
      final q = _q(_c(type: 'BUY_X_GET_Y', conds: [_bxgy(mode: 'FREEITEM', value: 10000)]), [_l('x', 'X', 1, 1), _l('y', 'Y', 1, 25000)]);
      expect(q.totalPromotionDiscount, 25000);
    });
  });

  group('ORDER_VALUE_ITEM_BENEFIT', () {
    final c = _c(type: 'ORDERVALUEITEMBENEFIT', tiers: [
      _t(threshold: 200000, mode: 'FREEITEM', maxQty: 1, reward: ['G']),
      _t(threshold: 500000, mode: 'FREEITEM', maxQty: 2, reward: ['G']),
    ]);

    test('dưới ngưỡng → không áp dụng', () {
      final q = _q(c, [_l('a', 'A', 1, 120000), _l('g', 'G', 3, 20000)]); // 180k < 200k
      expect(q.totalPromotionDiscount, 0);
      expect(q.reasons.single.reasonCode, 'ORDER_VALUE_NOT_REACHED');
    });

    test('đạt ngưỡng → tặng tối đa maxRewardQty, lấy bậc cao nhất', () {
      expect(_q(c, [_l('a', 'A', 1, 200000), _l('g', 'G', 3, 20000)]).totalPromotionDiscount, 20000);
      expect(_q(c, [_l('a', 'A', 1, 500000), _l('g', 'G', 3, 20000)]).totalPromotionDiscount, 40000);
    });

    test('giảm % món thưởng; chưa có món thưởng → lý do', () {
      final pc = _c(type: 'ORDERVALUEITEMBENEFIT', tiers: [_t(threshold: 100000, mode: 'PERCENT', value: 5000, maxQty: 1, reward: ['G'])]);
      expect(_q(pc, [_l('a', 'A', 1, 100000), _l('g', 'G', 2, 30000)]).totalPromotionDiscount, 15000);
      expect(_q(pc, [_l('a', 'A', 1, 100000)]).reasons.single.reasonCode, 'REWARD_ITEM_NOT_IN_BILL');
    });
  });

  group('Bản ghi bill.discounts', () {
    test('ghi đủ trường campaign + giữ promoId/promoCode', () {
      final c = _c(type: 'BILLDISCOUNT', hasCodes: true);
      final m = CartCampaignPricing.discount(c, 12000, voucherCode: 'tram10').toMap();
      expect(m['campaignId'], 'C');
      expect(m['campaignName'], 'CT C');
      expect(m['programCode'], 'KM_C');
      expect(m['campaignType'], 'BILLDISCOUNT');
      expect(m['voucherCode'], 'TRAM10');
      expect(m['amount'], 12000);
      expect(m['promoId'], 'C');
      expect(m['promoCode'], 'TRAM10');
      final back = BillDiscountModel.fromMap(m);
      expect(back.campaignName, 'CT C');
      expect(back.voucherCode, 'TRAM10');
    });
  });

  group('Voucher', () {
    VoucherModel v(String state, {String? bill}) => VoucherModel(
          voucherId: 'V1',
          campaignId: 'C',
          normalizedCode: 'ABC123',
          state: state,
          redeemedBillId: bill,
          redeemedBillCode: bill == null ? null : 'HD-261010-0001',
          redeemedAt: bill == null ? null : DateTime(2026, 10, 10, 9, 30).millisecondsSinceEpoch,
          redeemedBy: 'thungan1',
          redeemedByName: 'Thu Ngân 1',
          tableName: 'Bàn 5',
          tombstone: false,
          createdAt: 0,
          version: 1,
        );
    final camp = _c(type: 'BILLDISCOUNT', hasCodes: true, tiers: [_t(mode: 'FIXED', value: 10000, threshold: 50000)]);

    VoucherCheckResult eval(VoucherModel? vv, CampaignModel? cc, {PriceQuoteModel? quote, int now = 1000}) =>
        evaluateVoucher(code: ' abc123 ', voucher: vv, campaign: cc, nowMs: now, branchId: 'B', quote: quote);

    test('ánh xạ trạng thái → thông báo', () {
      expect(eval(null, null).status, VoucherCheckStatus.notFound);
      expect(eval(null, null).message, 'Mã ABC123 không tồn tại');
      final used = eval(v('REDEEMED', bill: 'BILL1'), camp);
      expect(used.status, VoucherCheckStatus.redeemed);
      expect(used.message, contains('HD-261010-0001'));
      expect(used.message, contains('Thu Ngân 1'));
      expect(used.message, contains('10/10/2026 09:30'));
      expect(eval(v('CANCELLED'), camp).message, 'Mã đã hủy');
      expect(eval(v('RELEASED'), camp.copyWith(schedule: CampaignSchedule(absoluteStart: 5000))).status, VoucherCheckStatus.notStarted);
      expect(eval(v('RELEASED'), camp.copyWith(schedule: CampaignSchedule(absoluteEnd: 500))).status, VoucherCheckStatus.ended);
    });

    test('không áp dụng được cho đơn → nêu lý do; hợp lệ → số tiền giảm', () {
      final low = _q(camp, [_l('1', 'A', 1, 30000)]);
      final na = eval(v('RELEASED'), camp, quote: low);
      expect(na.status, VoucherCheckStatus.notApplicable);
      expect(na.message, contains('chưa đạt'));
      final ok = eval(v('RELEASED'), camp, quote: _q(camp, [_l('1', 'A', 1, 60000)]));
      expect(ok.isValid, true);
      expect(ok.discount, 10000);
      expect(ok.message, contains('CT C'));
    });

    test('tách danh sách mã nhập tay', () {
      final p = parseVoucherCodes('tram10, TRAM10\nchaoban20;  ab\nx.y  GIAM-5K');
      expect(p.valid, ['TRAM10', 'CHAOBAN20', 'GIAM-5K']);
      expect(p.duplicated, ['TRAM10']);
      expect(p.invalid, ['AB', 'X.Y']);
      final r = generateRandomVoucherCodes(50, prefix: 'tr', length: 6);
      expect(r.length, 50);
      expect(r.every((c) => c.startsWith('TR') && c.length == 8), true);
    });

    test('voucher map round-trip có redeemedBillCode/tableName/redeemedByName', () {
      final m = v('REDEEMED', bill: 'BILL1').toMap();
      final back = VoucherModel.fromMap(m);
      expect(back.redeemedBillCode, 'HD-261010-0001');
      expect(back.tableName, 'Bàn 5');
      expect(back.redeemedByName, 'Thu Ngân 1');
    });
  });

  test('stackingMode STACKABLE (web cũ) = ENABLED', () {
    final m = _c(type: 'BILLDISCOUNT').toMap()..['stackingMode'] = 'stackable';
    final c = CampaignModel.fromMap(m);
    expect(c.stackingMode, 'ENABLED');
    expect(c.isStackable, true);
  });

  test('evaluateVoucher hỗ trợ nhập programCode của chương trình không phát hành mã voucher (hasCodes: false)', () {
    final camp = _c(id: 'KM_G003', type: 'ITEMPRICERULE', hasCodes: false, items: ['Trà Olong - Xoài'], tiers: [
      _t(mode: 'FIXEDPRICE', value: 14000)
    ]);
    final lines = [
      PricingLineItem(lineId: '1', itemId: '2', itemName: 'Trà Olong - Xoài', quantity: 1, unitPrice: 30000),
    ];
    final quote = _q(camp, lines);
    // Nhập code KM_KM_G003 trực tiếp (voucher == null)
    final res = evaluateVoucher(code: 'KM_KM_G003', voucher: null, campaign: camp, nowMs: 1000, branchId: 'B', quote: quote);
    expect(res.isValid, true);
    expect(res.discount, 16000);
  });

  test('Tặng 1 trà chanh cho đơn trên 100k - rewardPlan tìm thấy món Trà Olong - Chanh tươi khớp theo tên', () {
    final c = CampaignModel(
      campaignId: 'CAM_1792678534437_g4b5',
      programCode: 'KM/G-002',
      name: 'Grab- Tặng 1 trà chanh cho hóa đơn trên 100K',
      description: '',
      campaignType: 'ORDERVALUEITEMBENEFIT',
      schedule: CampaignSchedule(),
      branchIds: const ['TRAM01'],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: [
        CampaignTier(
          tierId: 'TIER_1',
          conditionBasis: 'TOTALAMOUNT',
          threshold: 100000,
          benefitMode: 'FREEITEM',
          value: 10000,
          maxDiscountMoney: 0,
          maxRewardQty: 1,
          rewardItemIds: const ['Trà Olong - Chanh tươi'],
          sortOrder: 1,
        )
      ],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      stackingMode: 'ENABLED',
      priority: 0,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 'Admin',
      version: 1,
    );

    final cart = [
      OrderItemModel(productId: 200, name: 'Trà Olong - Quả mọng', price: 30000, quantity: 1),
      OrderItemModel(productId: 201, name: 'Bánh lăn choco - vừa', price: 30000, quantity: 1),
      OrderItemModel(productId: 202, name: 'Bánh lăn choco - nhỏ', price: 15000, quantity: 1),
      OrderItemModel(productId: 203, name: 'Món khác', price: 50000, quantity: 1),
    ];

    final products = [
      ProductModel(id: 1, name: 'Trà Olong - Chanh tươi', code: 'DR202500002', price: 20000, unit: 'Ly', category: 'TRÀ TRÁI CÂY'),
      ProductModel(id: 200, name: 'Trà Olong - Quả mọng', code: 'DR202600200', price: 30000, unit: 'Ly', category: 'TRÀ TRÁI CÂY'),
      ProductModel(id: 201, name: 'Bánh lăn choco - vừa', code: 'CK001', price: 30000, unit: 'Cái', category: 'BÁNH LĂN NƯỚNG'),
      ProductModel(id: 202, name: 'Bánh lăn choco - nhỏ', code: 'CK002', price: 15000, unit: 'Cái', category: 'BÁNH LĂN NƯỚNG'),
      ProductModel(id: 203, name: 'Món khác', code: 'OT001', price: 50000, unit: 'Phần', category: 'KHÁC'),
    ];

    final plan = CartCampaignPricing.rewardPlan(c, cart: cart, products: products);
    expect(plan, isNotNull);
    expect(plan!.units, 1);
    expect(plan.candidates.first.name, 'Trà Olong - Chanh tươi');

    // Sau khi tự động thêm món trà chanh vào đơn
    cart.add(OrderItemModel(
      productId: plan.candidates.first.id,
      name: plan.candidates.first.name,
      price: plan.candidates.first.price,
      quantity: plan.units,
    ));

    final quote = CartCampaignPricing.quote(c, cart: cart, products: products, branchId: 'TRAM01');
    expect(quote.totalPromotionDiscount, 20000); // Tặng 100% ly trà chanh 20k
    expect(quote.appliedCampaignIds, contains('CAM_1792678534437_g4b5'));
  });

  test('Treo đơn qua giờ combo: đơn đã áp dụng combo khi tính lại giữ nguyên ưu đãi (ignoreSchedule: true)', () {
    final c = CampaignModel(
      campaignId: 'CAM_1792679049224_lzvb',
      programCode: 'KM/HD0001',
      name: 'Combo bánh và nước giảm 10K',
      description: '',
      campaignType: 'BUYXGETY',
      schedule: CampaignSchedule(
        timeSlots: [
          CampaignTimeSlot(startTime: '18:00', endTime: '20:00'),
        ],
      ),
      branchIds: const ['TRAM01', 'TRAM02', 'TRAM03', 'TRAM04'],
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
          buyGroupIds: const ['TRÀ TRÁI CÂY'],
          rewardItemIds: const [],
          rewardGroupIds: const ['BÁNH LĂN NƯỚNG'],
          requiredBuyQty: 1,
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
      priority: 0,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 'Admin',
      version: 1,
    );

    final cart = [
      OrderItemModel(productId: 10, name: 'Trà Olong - Xoài', price: 30000, quantity: 2),
      OrderItemModel(productId: 20, name: 'Bánh lăn choco chip', price: 30000, quantity: 2),
    ];

    final products = [
      ProductModel(id: 10, name: 'Trà Olong - Xoài', code: 'DR01', price: 30000, unit: 'Ly', category: 'TRÀ TRÁI CÂY'),
      ProductModel(id: 20, name: 'Bánh lăn choco chip', code: 'CK01', price: 30000, unit: 'Cái', category: 'BÁNH LĂN NƯỚNG'),
    ];

    // Lúc 21:30 (ngoài khung giờ 18:00 - 20:00)
    // Nếu là đơn mới bấm (ignoreSchedule: false) -> Bị chặn ngoài khung giờ
    final nowMsOutside = DateTime(2026, 10, 24, 21, 30).millisecondsSinceEpoch;
    final quoteNew = CartCampaignPricing.quote(
      c,
      cart: cart,
      products: products,
      branchId: 'TRAM01',
      nowMs: nowMsOutside,
      ignoreSchedule: false,
    );
    expect(quoteNew.totalPromotionDiscount, 0);
    expect(quoteNew.reasons.first.reasonCode, 'OUTSIDE_SCHEDULE');

    // Nếu là đơn đã áp dụng trước đó được treo qua giờ (ignoreSchedule: true) -> Giữ nguyên ưu đãi 20.000đ
    final quoteExisting = CartCampaignPricing.quote(
      c,
      cart: cart,
      products: products,
      branchId: 'TRAM01',
      nowMs: nowMsOutside,
      ignoreSchedule: true,
    );
    expect(quoteExisting.totalPromotionDiscount, 20000); // 2 combo x 10k
    expect(quoteExisting.appliedCampaignIds, contains('CAM_1792679049224_lzvb'));
  });

  test('Quy tắc độc quyền (stackingMode: DISABLED): Combo không cho phép cộng dồn với Sinh nhật', () {
    final combo = CampaignModel(
      campaignId: 'CAM_COMBO',
      programCode: 'KM/HD0001',
      name: 'Combo bánh và nước giảm 10K',
      description: '',
      campaignType: 'BUYXGETY',
      schedule: CampaignSchedule(),
      branchIds: const ['TRAM01', 'TRAM02', 'TRAM03', 'TRAM04'],
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
      stackingMode: 'DISABLED', // Độc quyền
      priority: 0,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 'Admin',
      version: 1,
    );

    final sinhNhat = CampaignModel(
      campaignId: 'CAM_BDAY',
      programCode: 'KM/D-008',
      name: 'Giảm 30% sinh nhật khách hàng',
      description: '',
      campaignType: 'BILLDISCOUNT',
      schedule: CampaignSchedule(),
      branchIds: const ['TRAM01', 'TRAM02', 'TRAM03', 'TRAM04'],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: [
        CampaignTier(
          tierId: 'T1',
          conditionBasis: 'TOTALAMOUNT',
          threshold: 0,
          benefitMode: 'PERCENT',
          value: 3000,
          maxDiscountMoney: 0,
          maxRewardQty: 0,
          rewardItemIds: const [],
          sortOrder: 1,
        )
      ],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      stackingMode: 'ENABLED',
      priority: 0,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 'Admin',
      version: 1,
    );

    final currentDiscounts = [
      BillDiscountModel(
        campaignId: 'CAM_COMBO',
        promoCode: 'KM/HD0001',
        description: 'Combo bánh và nước giảm 10K',
        amount: 20000,
      ),
    ];

    final check = CartCampaignPricing.checkStacking(
      currentDiscounts: currentDiscounts,
      incoming: sinhNhat,
      campaignsById: {'CAM_COMBO': combo, 'CAM_BDAY': sinhNhat},
      allowStackPromotions: true,
    );

    // Không thể cộng dồn vì Combo là độc quyền
    expect(check.canStack, false);
    expect(check.conflictingExclusiveCampaign?.name, 'Combo bánh và nước giảm 10K');
  });

  test('Khuyến mãi sinh nhật: chỉ áp dụng khi khách hàng có ngày sinh đúng hôm nay (birthdayOnly: true)', () {
    final bdayCamp = CampaignModel(
      campaignId: 'CAM_BDAY',
      programCode: 'KM/D-008',
      name: 'Giảm 30% sinh nhật khách hàng',
      description: '',
      campaignType: 'BILLDISCOUNT',
      schedule: CampaignSchedule(),
      branchIds: const ['TRAM01', 'TRAM02', 'TRAM03', 'TRAM04'],
      includedCustomerIds: const [],
      excludedCustomerIds: const [],
      includedItemIds: const [],
      includedGroupIds: const [],
      excludedItemIds: const [],
      tiers: [
        CampaignTier(
          tierId: 'T1',
          conditionBasis: 'TOTALAMOUNT',
          threshold: 0,
          benefitMode: 'PERCENT',
          value: 3000,
          maxDiscountMoney: 0,
          maxRewardQty: 0,
          rewardItemIds: const [],
          sortOrder: 1,
        )
      ],
      buyConditions: const [],
      warnRepeatedCustomer: false,
      hasCodes: false,
      autoApply: false,
      birthdayOnly: true, // Chỉ đúng sinh nhật
      stackingMode: 'ENABLED',
      priority: 0,
      active: true,
      createdAt: 0,
      updatedAt: 0,
      createdBy: 'Admin',
      version: 1,
    );

    final cart = [
      OrderItemModel(productId: 10, name: 'Trà Olong - Xoài', price: 100000, quantity: 1),
    ];
    final products = [
      ProductModel(id: 10, name: 'Trà Olong - Xoài', code: 'DR01', price: 100000, unit: 'Ly', category: 'TRÀ TRÁI CÂY'),
    ];

    // Ngày 24/10
    final todayMs = DateTime(2026, 10, 24, 12, 0).millisecondsSinceEpoch;

    // Trường hợp 1: Không có thông tin khách / ngày sinh -> Lỗi BIRTHDAY_CUSTOMER_REQUIRED
    final qNoBday = CartCampaignPricing.quote(
      bdayCamp,
      cart: cart,
      products: products,
      branchId: 'TRAM01',
      customerBirthday: null,
      nowMs: todayMs,
    );
    expect(qNoBday.totalPromotionDiscount, 0);
    expect(qNoBday.reasons.first.reasonCode, 'BIRTHDAY_CUSTOMER_REQUIRED');

    // Trường hợp 2: Khách sinh nhật ngày 01/01 (không phải hôm nay) -> Lỗi NOT_BIRTHDAY
    final qDiffBday = CartCampaignPricing.quote(
      bdayCamp,
      cart: cart,
      products: products,
      branchId: 'TRAM01',
      customerBirthday: '1995-01-01',
      nowMs: todayMs,
    );
    expect(qDiffBday.totalPromotionDiscount, 0);
    expect(qDiffBday.reasons.first.reasonCode, 'NOT_BIRTHDAY');

    // Trường hợp 3: Khách sinh nhật đúng ngày 24/10 -> Áp dụng giảm 30% (30.000đ)
    final qSameBday = CartCampaignPricing.quote(
      bdayCamp,
      cart: cart,
      products: products,
      branchId: 'TRAM01',
      customerBirthday: '1995-10-24',
      nowMs: todayMs,
    );
    expect(qSameBday.totalPromotionDiscount, 30000);
    expect(qSameBday.appliedCampaignIds, contains('CAM_BDAY'));
  });
}
