// ignore_for_file: constant_identifier_names

/// Bốn hình thức khuyến mãi chính
enum CampaignType {
  /// P-04: Giảm giá đơn hàng
  billDiscount,
  
  /// P-05: Giảm/tặng món theo giá trị đơn
  orderValueItemBenefit,
  
  /// P-06: Mua X tặng/giảm giá Y
  buyXGetY,
  
  /// P-07: Đồng giá/đồng giảm giá
  itemPriceRule;

  String toMap() => name.toUpperCase();
  
  static CampaignType fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => billDiscount,
    );
  }
}

/// Cách tính lợi ích
enum BenefitMode {
  /// Giảm theo % (Lưu ở dạng basis points: 10000 = 100%)
  percent,
  
  /// Giảm số tiền cố định (VND)
  fixed,
  
  /// Tặng món (100% off)
  freeItem,
  
  /// Đồng giá
  fixedPrice;

  String toMap() => name.toUpperCase();
  
  static BenefitMode fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => percent,
    );
  }
}

/// Trạng thái voucher nội bộ
enum VoucherState {
  /// Mã đã tạo chưa phát hành
  draft,
  
  /// Đã phát hành, có thể dùng
  released,
  
  /// Đang giữ chỗ (hold)
  reserved,
  
  /// Đã sử dụng
  redeemed,
  
  /// Đã hủy
  cancelled;

  String toMap() => name.toUpperCase();
  
  static VoucherState fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => draft,
    );
  }
}

/// Điều kiện cơ sở cho bill discount
enum ConditionBasis {
  /// Tổng tiền hàng
  totalAmount,
  
  /// Số khách
  guestCount;

  String toMap() => name.toUpperCase();
  
  static ConditionBasis fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => totalAmount,
    );
  }
}

/// Chính sách chọn món thưởng
enum BenefitSelectionPolicy {
  /// Chọn món rẻ nhất đủ điều kiện
  cheapestEligible,
  
  /// Chọn cụ thể danh sách món
  specificItems;

  String toMap() => name.toUpperCase();
  
  static BenefitSelectionPolicy fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => cheapestEligible,
    );
  }
}

/// Chính sách cộng dồn
enum StackingMode {
  /// Không cộng dồn
  disabled,
  
  /// Cho phép cộng dồn
  enabled;

  String toMap() => name.toUpperCase();
  
  static StackingMode fromMap(String value) {
    return values.firstWhere(
      (e) => e.name.toUpperCase() == value.toUpperCase(),
      orElse: () => disabled,
    );
  }
}

/// Chuẩn hóa chế độ cộng dồn: web cũ lưu "STACKABLE" (mọi kiểu chữ) = ENABLED
String normalizeStackingMode(String? raw) {
  final u = (raw ?? '').trim().toUpperCase();
  if (u == 'ENABLED' || u == 'STACKABLE' || u == 'TRUE' || u == 'YES') return StackingMode.enabled.toMap();
  return StackingMode.disabled.toMap();
}

/// Bậc điều kiện của chương trình khuyến mãi
class CampaignTier {
  final String tierId;
  final String conditionBasis; // ConditionBasis
  final int threshold; // Ngưỡng (VND for amount, count for guests)
  final String benefitMode; // BenefitMode
  final int value; // % (basis points 0-10000) or VND or fixed price
  final int maxDiscountMoney; // Trần giảm giá (0 = no cap)
  final int maxRewardQty; // Số lượng món thưởng tối đa
  final List<String> rewardItemIds; // Món thưởng (for P-05, P-06)
  final int sortOrder; // Thứ tự trong danh sách tiers

  CampaignTier({
    required this.tierId,
    required this.conditionBasis,
    required this.threshold,
    required this.benefitMode,
    required this.value,
    required this.maxDiscountMoney,
    required this.maxRewardQty,
    required this.rewardItemIds,
    required this.sortOrder,
  });

  Map<String, dynamic> toMap() {
    return {
      'tierId': tierId,
      'conditionBasis': conditionBasis,
      'threshold': threshold,
      'thresholdValue': threshold,
      'thresholdType': 'ORDER_VALUE',
      'benefitMode': benefitMode,
      'benefitType': benefitMode == BenefitMode.percent.toMap() ? 'DISCOUNT_PERCENT' : 'DISCOUNT_AMOUNT',
      'value': value,
      'benefitValue': value,
      'maxDiscountMoney': maxDiscountMoney,
      'maxBenefitValue': maxDiscountMoney,
      'maxRewardQty': maxRewardQty,
      'rewardItemIds': rewardItemIds,
      'sortOrder': sortOrder,
      'tierIndex': sortOrder,
    };
  }

  factory CampaignTier.fromMap(Map<String, dynamic> map) {
    String mode = map['benefitMode']?.toString() ?? '';
    if (mode.isEmpty) {
      final bType = map['benefitType']?.toString().toUpperCase() ?? '';
      if (bType == 'DISCOUNT_PERCENT' || bType == 'PERCENT') {
        mode = BenefitMode.percent.toMap();
      } else if (bType == 'DISCOUNT_AMOUNT' || bType == 'AMOUNT') {
        mode = BenefitMode.fixed.toMap();
      } else if (bType == 'FIXED_PRICE') {
        mode = BenefitMode.fixed.toMap();
      } else {
        mode = BenefitMode.percent.toMap();
      }
    }

    String cond = map['conditionBasis']?.toString() ?? '';
    if (cond.isEmpty) {
      final thType = map['thresholdType']?.toString().toUpperCase() ?? '';
      if (thType == 'ORDER_VALUE' || thType == 'BILL_TOTAL') {
        cond = ConditionBasis.totalAmount.toMap();
      } else {
        cond = ConditionBasis.totalAmount.toMap();
      }
    }

    final rawVal = (map['value'] ?? map['benefitValue'] ?? 0);
    final rawThreshold = (map['threshold'] ?? map['thresholdValue'] ?? 0);
    final rawMaxDiscount = (map['maxDiscountMoney'] ?? map['maxBenefitValue'] ?? 0);

    return CampaignTier(
      tierId: map['tierId']?.toString() ?? '',
      conditionBasis: cond,
      threshold: (rawThreshold as num).toInt(),
      benefitMode: mode,
      value: (rawVal as num).toInt(),
      maxDiscountMoney: (rawMaxDiscount as num).toInt(),
      maxRewardQty: (map['maxRewardQty'] as num?)?.toInt() ?? 0,
      rewardItemIds: List<String>.from(map['rewardItemIds'] ?? []),
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? (map['tierIndex'] as num?)?.toInt() ?? 0,
    );
  }
  
  CampaignTier copyWith({
    String? tierId,
    String? conditionBasis,
    int? threshold,
    String? benefitMode,
    int? value,
    int? maxDiscountMoney,
    int? maxRewardQty,
    List<String>? rewardItemIds,
    int? sortOrder,
  }) {
    return CampaignTier(
      tierId: tierId ?? this.tierId,
      conditionBasis: conditionBasis ?? this.conditionBasis,
      threshold: threshold ?? this.threshold,
      benefitMode: benefitMode ?? this.benefitMode,
      value: value ?? this.value,
      maxDiscountMoney: maxDiscountMoney ?? this.maxDiscountMoney,
      maxRewardQty: maxRewardQty ?? this.maxRewardQty,
      rewardItemIds: rewardItemIds ?? this.rewardItemIds,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Điều kiện cho Mua X tặng Y
class CampaignBuyCondition {
  final String conditionId;
  final List<String> buyItemIds; // Danh sách món mua X
  final int requiredBuyQty; // Số lượng cần mua
  final List<String> rewardItemIds; // Danh sách món thưởng Y
  final int rewardQty; // Số lượng thưởng mỗi bundle
  final String benefitMode; // BenefitMode
  final int value; // % or VND
  final bool multiplyByBundle; // Nhân theo số lượng mua (default true)

  CampaignBuyCondition({
    required this.conditionId,
    required this.buyItemIds,
    required this.requiredBuyQty,
    required this.rewardItemIds,
    required this.rewardQty,
    required this.benefitMode,
    required this.value,
    this.multiplyByBundle = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'conditionId': conditionId,
      'buyItemIds': buyItemIds,
      'requiredBuyQty': requiredBuyQty,
      'rewardItemIds': rewardItemIds,
      'rewardQty': rewardQty,
      'benefitMode': benefitMode,
      'value': value,
      'multiplyByBundle': multiplyByBundle,
    };
  }

  factory CampaignBuyCondition.fromMap(Map<String, dynamic> map) {
    return CampaignBuyCondition(
      conditionId: map['conditionId'] ?? '',
      buyItemIds: List<String>.from(map['buyItemIds'] ?? []),
      requiredBuyQty: map['requiredBuyQty']?.toInt() ?? 0,
      rewardItemIds: List<String>.from(map['rewardItemIds'] ?? []),
      rewardQty: map['rewardQty']?.toInt() ?? 0,
      benefitMode: map['benefitMode'] ?? BenefitMode.percent.toMap(),
      value: map['value']?.toInt() ?? 0,
      multiplyByBundle: map['multiplyByBundle'] ?? true,
    );
  }
  
  CampaignBuyCondition copyWith({
    String? conditionId,
    List<String>? buyItemIds,
    int? requiredBuyQty,
    List<String>? rewardItemIds,
    int? rewardQty,
    String? benefitMode,
    int? value,
    bool? multiplyByBundle,
  }) {
    return CampaignBuyCondition(
      conditionId: conditionId ?? this.conditionId,
      buyItemIds: buyItemIds ?? this.buyItemIds,
      requiredBuyQty: requiredBuyQty ?? this.requiredBuyQty,
      rewardItemIds: rewardItemIds ?? this.rewardItemIds,
      rewardQty: rewardQty ?? this.rewardQty,
      benefitMode: benefitMode ?? this.benefitMode,
      value: value ?? this.value,
      multiplyByBundle: multiplyByBundle ?? this.multiplyByBundle,
    );
  }
}

/// Khung giờ áp dụng (Happy hours)
class CampaignTimeSlot {
  final String startTime; // "HH:mm"
  final String endTime;   // "HH:mm"

  CampaignTimeSlot({
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() {
    return {
      'startTime': startTime,
      'endTime': endTime,
    };
  }

  factory CampaignTimeSlot.fromMap(Map<dynamic, dynamic> map) {
    return CampaignTimeSlot(
      startTime: map['startTime']?.toString() ?? '00:00',
      endTime: map['endTime']?.toString() ?? '23:59',
    );
  }

  /// Kiểm tra xem thời điểm (giờ, phút) có nằm trong slot này không
  bool containsTime(int hour, int minute) {
    final startParts = startTime.split(':');
    final endParts = endTime.split(':');
    if (startParts.length < 2 || endParts.length < 2) return true;

    final startMinutes = (int.tryParse(startParts[0]) ?? 0) * 60 + (int.tryParse(startParts[1]) ?? 0);
    final endMinutes = (int.tryParse(endParts[0]) ?? 23) * 60 + (int.tryParse(endParts[1]) ?? 59);
    final currentMinutes = hour * 60 + minute;

    if (startMinutes <= endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } else {
      // Khung giờ qua đêm (ví dụ 22:00 -> 02:00)
      return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
    }
  }

  CampaignTimeSlot copyWith({
    String? startTime,
    String? endTime,
  }) {
    return CampaignTimeSlot(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}

/// Lịch áp dụng chương trình
class CampaignSchedule {
  final int? absoluteStart; // Epoch ms, null = no start limit
  final int? absoluteEnd; // Epoch ms, null = no end limit
  final String timezone; // IANA timezone (default 'Asia/Ho_Chi_Minh')
  final List<String> excludedDates; // ISO dates to exclude (yyyy-MM-dd)
  final List<CampaignTimeSlot> timeSlots; // Happy hours: [{startTime: "HH:mm", endTime: "HH:mm"}]
  final List<int> daysOfWeek; // 1..7 với 1 = Thứ 2, 7 = CN

  CampaignSchedule({
    this.absoluteStart,
    this.absoluteEnd,
    this.timezone = 'Asia/Ho_Chi_Minh',
    this.excludedDates = const [],
    this.timeSlots = const [],
    this.daysOfWeek = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'absoluteStart': absoluteStart,
      'absoluteEnd': absoluteEnd,
      'timezone': timezone,
      'excludedDates': excludedDates,
      'timeSlots': timeSlots.map((e) => e.toMap()).toList(),
      'daysOfWeek': daysOfWeek,
    };
  }

  factory CampaignSchedule.fromMap(Map<String, dynamic> map) {
    var rawSlots = map['timeSlots'];
    List<CampaignTimeSlot> slots = [];
    if (rawSlots is List) {
      slots = rawSlots.map((e) => CampaignTimeSlot.fromMap(e is Map ? e : {})).toList();
    }

    var rawDays = map['daysOfWeek'];
    List<int> days = [];
    if (rawDays is List) {
      days = rawDays.map((e) => (e as num).toInt()).toList();
    }

    return CampaignSchedule(
      absoluteStart: (map['absoluteStart'] as num?)?.toInt(),
      absoluteEnd: (map['absoluteEnd'] as num?)?.toInt(),
      timezone: map['timezone'] ?? 'Asia/Ho_Chi_Minh',
      excludedDates: List<String>.from(map['excludedDates'] ?? []),
      timeSlots: slots,
      daysOfWeek: days,
    );
  }
  
  CampaignSchedule copyWith({
    int? absoluteStart,
    int? absoluteEnd,
    String? timezone,
    List<String>? excludedDates,
    List<CampaignTimeSlot>? timeSlots,
    List<int>? daysOfWeek,
  }) {
    return CampaignSchedule(
      absoluteStart: absoluteStart ?? this.absoluteStart,
      absoluteEnd: absoluteEnd ?? this.absoluteEnd,
      timezone: timezone ?? this.timezone,
      excludedDates: excludedDates ?? this.excludedDates,
      timeSlots: timeSlots ?? this.timeSlots,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    );
  }
}

/// Chương trình khuyến mãi.
class CampaignModel {
  final String campaignId;
  final String programCode; // Mã chương trình (unique trong org)
  final String name; // Tên chương trình (required)
  final String description;
  final String campaignType; // From CampaignType enum as String
  final CampaignSchedule schedule;
  final List<String> branchIds; // Chi nhánh áp dụng (empty = all)

  // Điều kiện đối tượng
  final List<String> includedCustomerIds; // Khách hàng áp dụng
  final List<String> excludedCustomerIds;
  final List<String> includedItemIds; // Món áp dụng
  final List<String> includedGroupIds; // Nhóm món áp dụng
  final List<String> excludedItemIds; // Món loại trừ

  // Tiers & Conditions
  final List<CampaignTier> tiers; // For BILL_DISCOUNT, ORDER_VALUE_ITEM_BENEFIT, ITEM_PRICE_RULE
  final List<CampaignBuyCondition> buyConditions; // For BUY_X_GET_Y

  // Hạn mức
  final int? budgetMoney; // Ngân sách tổng (VND), null=unlimited
  final int? maxUses; // Giới hạn lượt dùng tổng, null=unlimited
  final int? maxUsesPerCustomer; // Giới hạn lượt/khách, null=unlimited
  final bool warnRepeatedCustomer; // Cảnh báo khách đã dùng

  // Voucher/Mã
  final bool hasCodes; // Có phát hành mã
  final bool autoApply; // Tự động áp dụng
  final bool requireStaffNote; // Bắt buộc nhân viên nhập ghi chú khi áp dụng mã

  // Cộng dồn
  final String stackingMode; // DISABLED, ENABLED
  final int priority; // Ưu tiên (số nhỏ = cao hơn)

  // Trạng thái
  final bool active; // Cờ kích hoạt
  final int createdAt;
  final int updatedAt;
  final String createdBy;
  final int version;

  // Legacy
  final String? legacyPromotionId; // Link to old PromotionModel.id

  CampaignModel({
    required this.campaignId,
    required this.programCode,
    required this.name,
    required this.description,
    required this.campaignType,
    required this.schedule,
    required this.branchIds,
    required this.includedCustomerIds,
    required this.excludedCustomerIds,
    required this.includedItemIds,
    required this.includedGroupIds,
    required this.excludedItemIds,
    required this.tiers,
    required this.buyConditions,
    this.budgetMoney,
    this.maxUses,
    this.maxUsesPerCustomer,
    required this.warnRepeatedCustomer,
    required this.hasCodes,
    required this.autoApply,
    this.requireStaffNote = false,
    required this.stackingMode,
    required this.priority,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.version,
    this.legacyPromotionId,
  });

  bool get isStackable => normalizeStackingMode(stackingMode) == StackingMode.enabled.toMap();

  bool get isUpcoming {
    if (schedule.absoluteStart == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now < schedule.absoluteStart!;
  }

  bool get isOngoing {
    final now = DateTime.now().millisecondsSinceEpoch;
    return isEligibleAt(now);
  }

  bool get isEnded {
    if (schedule.absoluteEnd == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    return now > schedule.absoluteEnd!;
  }

  String get typeDisplay {
    final type = CampaignType.fromMap(campaignType);
    switch (type) {
      case CampaignType.billDiscount:
        return 'Giảm giá đơn hàng';
      case CampaignType.orderValueItemBenefit:
        return 'Giảm/tặng món theo giá trị hóa đơn';
      case CampaignType.buyXGetY:
        return 'Mua X tặng/giảm giá Y';
      case CampaignType.itemPriceRule:
        return 'Đồng giá/đồng giảm giá';
    }
  }

  String get statusDisplay {
    if (!active) return 'Không hoạt động';
    if (isEnded) return 'Đã kết thúc';
    if (isUpcoming) return 'Sắp diễn ra';
    if (!isOngoing) return 'Ngoài khung giờ';
    return 'Đang diễn ra';
  }

  bool isEligibleAt(int timestampMs) {
    if (schedule.absoluteStart != null && timestampMs < schedule.absoluteStart!) {
      return false;
    }
    if (schedule.absoluteEnd != null && timestampMs > schedule.absoluteEnd!) {
      return false;
    }

    final dt = DateTime.fromMillisecondsSinceEpoch(timestampMs);

    // Ngày trong tuần: 1..7 với 1 = Thứ 2, 7 = Chủ Nhật
    if (schedule.daysOfWeek.isNotEmpty) {
      if (!schedule.daysOfWeek.contains(dt.weekday)) {
        return false;
      }
    }

    // Khung giờ áp dụng (Happy hours)
    if (schedule.timeSlots.isNotEmpty) {
      bool inSlot = false;
      for (final slot in schedule.timeSlots) {
        if (slot.containsTime(dt.hour, dt.minute)) {
          inSlot = true;
          break;
        }
      }
      if (!inSlot) {
        return false;
      }
    }

    return true;
  }

  bool isEligibleForBranch(String branchId) {
    if (branchIds.isEmpty) return true;
    return branchIds.contains(branchId);
  }

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'programCode': programCode,
      'name': name,
      'description': description,
      'campaignType': campaignType,
      'schedule': schedule.toMap(),
      'branchIds': branchIds,
      'includedCustomerIds': includedCustomerIds,
      'excludedCustomerIds': excludedCustomerIds,
      'includedItemIds': includedItemIds,
      'includedGroupIds': includedGroupIds,
      'excludedItemIds': excludedItemIds,
      'tiers': tiers.map((e) => e.toMap()).toList(),
      'buyConditions': buyConditions.map((e) => e.toMap()).toList(),
      'budgetMoney': budgetMoney,
      'maxUses': maxUses,
      'maxUsesPerCustomer': maxUsesPerCustomer,
      'warnRepeatedCustomer': warnRepeatedCustomer,
      'hasCodes': hasCodes,
      'autoApply': autoApply,
      'requireStaffNote': requireStaffNote,
      'stackingMode': stackingMode,
      'priority': priority,
      'active': active,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
      'version': version,
      'legacyPromotionId': legacyPromotionId,
    };
  }

  factory CampaignModel.fromMap(Map<String, dynamic> map) {
    return CampaignModel(
      campaignId: map['campaignId'] ?? '',
      programCode: map['programCode'] ?? '',
      name: map['name'] ?? '',
      description: map['description'] ?? '',
      campaignType: map['campaignType'] ?? CampaignType.billDiscount.toMap(),
      schedule: CampaignSchedule.fromMap(map['schedule'] ?? {}),
      branchIds: List<String>.from(map['branchIds'] ?? []),
      includedCustomerIds: List<String>.from(map['includedCustomerIds'] ?? []),
      excludedCustomerIds: List<String>.from(map['excludedCustomerIds'] ?? []),
      includedItemIds: List<String>.from(map['includedItemIds'] ?? []),
      includedGroupIds: List<String>.from(map['includedGroupIds'] ?? []),
      excludedItemIds: List<String>.from(map['excludedItemIds'] ?? []),
      tiers: List<CampaignTier>.from((map['tiers'] ?? []).map((e) => CampaignTier.fromMap(e))),
      buyConditions: List<CampaignBuyCondition>.from((map['buyConditions'] ?? []).map((e) => CampaignBuyCondition.fromMap(e))),
      budgetMoney: map['budgetMoney']?.toInt(),
      maxUses: map['maxUses']?.toInt(),
      maxUsesPerCustomer: map['maxUsesPerCustomer']?.toInt(),
      warnRepeatedCustomer: map['warnRepeatedCustomer'] ?? false,
      hasCodes: map['hasCodes'] ?? false,
      autoApply: map['autoApply'] ?? false,
      requireStaffNote: map['requireStaffNote'] ?? false,
      stackingMode: normalizeStackingMode(map['stackingMode']?.toString()),
      priority: map['priority']?.toInt() ?? 0,
      active: map['active'] ?? false,
      createdAt: map['createdAt']?.toInt() ?? 0,
      updatedAt: map['updatedAt']?.toInt() ?? 0,
      createdBy: map['createdBy'] ?? '',
      version: map['version']?.toInt() ?? 0,
      legacyPromotionId: map['legacyPromotionId'],
    );
  }

  CampaignModel copyWith({
    String? campaignId,
    String? programCode,
    String? name,
    String? description,
    String? campaignType,
    CampaignSchedule? schedule,
    List<String>? branchIds,
    List<String>? includedCustomerIds,
    List<String>? excludedCustomerIds,
    List<String>? includedItemIds,
    List<String>? includedGroupIds,
    List<String>? excludedItemIds,
    List<CampaignTier>? tiers,
    List<CampaignBuyCondition>? buyConditions,
    int? budgetMoney,
    int? maxUses,
    int? maxUsesPerCustomer,
    bool? warnRepeatedCustomer,
    bool? hasCodes,
    bool? autoApply,
    bool? requireStaffNote,
    String? stackingMode,
    int? priority,
    bool? active,
    int? createdAt,
    int? updatedAt,
    String? createdBy,
    int? version,
    String? legacyPromotionId,
  }) {
    return CampaignModel(
      campaignId: campaignId ?? this.campaignId,
      programCode: programCode ?? this.programCode,
      name: name ?? this.name,
      description: description ?? this.description,
      campaignType: campaignType ?? this.campaignType,
      schedule: schedule ?? this.schedule,
      branchIds: branchIds ?? this.branchIds,
      includedCustomerIds: includedCustomerIds ?? this.includedCustomerIds,
      excludedCustomerIds: excludedCustomerIds ?? this.excludedCustomerIds,
      includedItemIds: includedItemIds ?? this.includedItemIds,
      includedGroupIds: includedGroupIds ?? this.includedGroupIds,
      excludedItemIds: excludedItemIds ?? this.excludedItemIds,
      tiers: tiers ?? this.tiers,
      buyConditions: buyConditions ?? this.buyConditions,
      budgetMoney: budgetMoney ?? this.budgetMoney,
      maxUses: maxUses ?? this.maxUses,
      maxUsesPerCustomer: maxUsesPerCustomer ?? this.maxUsesPerCustomer,
      warnRepeatedCustomer: warnRepeatedCustomer ?? this.warnRepeatedCustomer,
      hasCodes: hasCodes ?? this.hasCodes,
      autoApply: autoApply ?? this.autoApply,
      requireStaffNote: requireStaffNote ?? this.requireStaffNote,
      stackingMode: stackingMode ?? this.stackingMode,
      priority: priority ?? this.priority,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      version: version ?? this.version,
      legacyPromotionId: legacyPromotionId ?? this.legacyPromotionId,
    );
  }
}

/// Bộ đếm chương trình (tách khỏi campaign để atomic update).
class CampaignCountersModel {
  final String campaignId;
  final int spentMoney; // Tiền giảm đã commit
  final int reservedMoney; // Tiền đang hold
  final int committedUseCount;
  final int reservedUseCount;
  final int version;

  CampaignCountersModel({
    required this.campaignId,
    required this.spentMoney,
    required this.reservedMoney,
    required this.committedUseCount,
    required this.reservedUseCount,
    required this.version,
  });

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'spentMoney': spentMoney,
      'reservedMoney': reservedMoney,
      'committedUseCount': committedUseCount,
      'reservedUseCount': reservedUseCount,
      'version': version,
    };
  }

  factory CampaignCountersModel.fromMap(Map<String, dynamic> map) {
    return CampaignCountersModel(
      campaignId: map['campaignId'] ?? '',
      spentMoney: map['spentMoney']?.toInt() ?? 0,
      reservedMoney: map['reservedMoney']?.toInt() ?? 0,
      committedUseCount: map['committedUseCount']?.toInt() ?? 0,
      reservedUseCount: map['reservedUseCount']?.toInt() ?? 0,
      version: map['version']?.toInt() ?? 0,
    );
  }
  
  CampaignCountersModel copyWith({
    String? campaignId,
    int? spentMoney,
    int? reservedMoney,
    int? committedUseCount,
    int? reservedUseCount,
    int? version,
  }) {
    return CampaignCountersModel(
      campaignId: campaignId ?? this.campaignId,
      spentMoney: spentMoney ?? this.spentMoney,
      reservedMoney: reservedMoney ?? this.reservedMoney,
      committedUseCount: committedUseCount ?? this.committedUseCount,
      reservedUseCount: reservedUseCount ?? this.reservedUseCount,
      version: version ?? this.version,
    );
  }
}

/// Đếm lượt/khách.
class CustomerCampaignCounterModel {
  final String customerId;
  final String campaignId;
  final int usedCount;
  final int heldCount;

  CustomerCampaignCounterModel({
    required this.customerId,
    required this.campaignId,
    required this.usedCount,
    required this.heldCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId,
      'campaignId': campaignId,
      'usedCount': usedCount,
      'heldCount': heldCount,
    };
  }

  factory CustomerCampaignCounterModel.fromMap(Map<String, dynamic> map) {
    return CustomerCampaignCounterModel(
      customerId: map['customerId'] ?? '',
      campaignId: map['campaignId'] ?? '',
      usedCount: map['usedCount']?.toInt() ?? 0,
      heldCount: map['heldCount']?.toInt() ?? 0,
    );
  }
  
  CustomerCampaignCounterModel copyWith({
    String? customerId,
    String? campaignId,
    int? usedCount,
    int? heldCount,
  }) {
    return CustomerCampaignCounterModel(
      customerId: customerId ?? this.customerId,
      campaignId: campaignId ?? this.campaignId,
      usedCount: usedCount ?? this.usedCount,
      heldCount: heldCount ?? this.heldCount,
    );
  }
}

/// Mã voucher.
class VoucherModel {
  final String voucherId;
  final String campaignId;
  final String normalizedCode; // Uppercase, trimmed
  final String state; // From VoucherState enum
  final int? releasedAt;
  final int? reservedAt;
  final int? redeemedAt;
  final int? cancelledAt;
  final String? holdId; // Current hold reference
  final int? holdExpiresAt; // Hold TTL
  final String? redeemedBillId; // Bill that used this code
  final String? redeemedBillCode; // Mã hóa đơn hiển thị (HD-...)
  final String? redeemedBy; // Username
  final String? redeemedByName; // Họ tên nhân viên
  final String? tableName; // Bàn của hóa đơn đã dùng mã
  final bool tombstone; // Cannot reuse code
  final int createdAt;
  final int version;

  VoucherModel({
    required this.voucherId,
    required this.campaignId,
    required this.normalizedCode,
    required this.state,
    this.releasedAt,
    this.reservedAt,
    this.redeemedAt,
    this.cancelledAt,
    this.holdId,
    this.holdExpiresAt,
    this.redeemedBillId,
    this.redeemedBillCode,
    this.redeemedBy,
    this.redeemedByName,
    this.tableName,
    required this.tombstone,
    required this.createdAt,
    required this.version,
  });

  bool get isUsable => state == VoucherState.released.toMap();
  
  bool get isHeld {
    final now = DateTime.now().millisecondsSinceEpoch;
    return state == VoucherState.reserved.toMap() && holdExpiresAt != null && holdExpiresAt! > now;
  }

  Map<String, dynamic> toMap() {
    return {
      'voucherId': voucherId,
      'campaignId': campaignId,
      'code': normalizedCode,
      'normalizedCode': normalizedCode,
      'state': state,
      'status': state == VoucherState.released.toMap()
          ? 'ISSUED'
          : (state == VoucherState.redeemed.toMap()
              ? 'USED'
              : (state == VoucherState.cancelled.toMap() ? 'CANCELLED' : 'DRAFT')),
      'releasedAt': releasedAt,
      'reservedAt': reservedAt,
      'redeemedAt': redeemedAt,
      'usedAt': redeemedAt,
      'cancelledAt': cancelledAt,
      'holdId': holdId,
      'holdExpiresAt': holdExpiresAt,
      'redeemedBillId': redeemedBillId,
      'redeemedBillCode': redeemedBillCode,
      'redeemedBy': redeemedBy,
      'redeemedByName': redeemedByName,
      'tableName': tableName,
      'usedBy': redeemedBy,
      'tombstone': tombstone,
      'createdAt': createdAt,
      'version': version,
    };
  }

  factory VoucherModel.fromMap(Map<String, dynamic> map) {
    String stateStr = map['state']?.toString() ?? '';
    if (stateStr.isEmpty) {
      final status = map['status']?.toString().toUpperCase();
      if (status == 'ISSUED') {
        stateStr = VoucherState.released.toMap();
      } else if (status == 'USED') {
        stateStr = VoucherState.redeemed.toMap();
      } else if (status == 'CANCELLED') {
        stateStr = VoucherState.cancelled.toMap();
      } else {
        stateStr = VoucherState.released.toMap();
      }
    }

    final codeVal = (map['normalizedCode'] ?? map['code'] ?? '').toString();
    final redeemedTime = ((map['redeemedAt'] ?? map['usedAt']) as num?)?.toInt();
    final userVal = (map['redeemedBy'] ?? map['usedBy'])?.toString();

    return VoucherModel(
      voucherId: map['voucherId']?.toString() ?? '',
      campaignId: map['campaignId']?.toString() ?? '',
      normalizedCode: codeVal,
      state: stateStr,
      releasedAt: (map['releasedAt'] as num?)?.toInt(),
      reservedAt: (map['reservedAt'] as num?)?.toInt(),
      redeemedAt: redeemedTime,
      cancelledAt: (map['cancelledAt'] as num?)?.toInt(),
      holdId: map['holdId']?.toString(),
      holdExpiresAt: (map['holdExpiresAt'] as num?)?.toInt(),
      redeemedBillId: map['redeemedBillId']?.toString(),
      redeemedBillCode: map['redeemedBillCode']?.toString(),
      redeemedBy: userVal,
      redeemedByName: map['redeemedByName']?.toString(),
      tableName: map['tableName']?.toString(),
      tombstone: map['tombstone'] ?? false,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 0,
    );
  }
  
  VoucherModel copyWith({
    String? voucherId,
    String? campaignId,
    String? normalizedCode,
    String? state,
    int? releasedAt,
    int? reservedAt,
    int? redeemedAt,
    int? cancelledAt,
    String? holdId,
    int? holdExpiresAt,
    String? redeemedBillId,
    String? redeemedBillCode,
    String? redeemedBy,
    String? redeemedByName,
    String? tableName,
    bool? tombstone,
    int? createdAt,
    int? version,
  }) {
    return VoucherModel(
      voucherId: voucherId ?? this.voucherId,
      campaignId: campaignId ?? this.campaignId,
      normalizedCode: normalizedCode ?? this.normalizedCode,
      state: state ?? this.state,
      releasedAt: releasedAt ?? this.releasedAt,
      reservedAt: reservedAt ?? this.reservedAt,
      redeemedAt: redeemedAt ?? this.redeemedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      holdId: holdId ?? this.holdId,
      holdExpiresAt: holdExpiresAt ?? this.holdExpiresAt,
      redeemedBillId: redeemedBillId ?? this.redeemedBillId,
      redeemedBillCode: redeemedBillCode ?? this.redeemedBillCode,
      redeemedBy: redeemedBy ?? this.redeemedBy,
      redeemedByName: redeemedByName ?? this.redeemedByName,
      tableName: tableName ?? this.tableName,
      tombstone: tombstone ?? this.tombstone,
      createdAt: createdAt ?? this.createdAt,
      version: version ?? this.version,
    );
  }
}

/// Kết quả pricing engine cho từng món
class LineBenefit {
  final String lineId;
  final String campaignId;
  final String tierId;
  final int discountMoney; // Số tiền giảm cho dòng này
  final int originalPrice; // Giá gốc
  final int effectivePrice; // Giá sau giảm
  final bool isGift; // Là món tặng
  final String? giftSourceCampaignId;
  final int quantity; // Số phần được thưởng (0 = cả dòng / không xác định)

  LineBenefit({
    required this.lineId,
    required this.campaignId,
    required this.tierId,
    required this.discountMoney,
    required this.originalPrice,
    required this.effectivePrice,
    required this.isGift,
    this.giftSourceCampaignId,
    this.quantity = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'lineId': lineId,
      'campaignId': campaignId,
      'tierId': tierId,
      'discountMoney': discountMoney,
      'originalPrice': originalPrice,
      'effectivePrice': effectivePrice,
      'isGift': isGift,
      'giftSourceCampaignId': giftSourceCampaignId,
      if (quantity > 0) 'quantity': quantity,
    };
  }

  factory LineBenefit.fromMap(Map<String, dynamic> map) {
    return LineBenefit(
      lineId: map['lineId'] ?? '',
      campaignId: map['campaignId'] ?? '',
      tierId: map['tierId'] ?? '',
      discountMoney: map['discountMoney']?.toInt() ?? 0,
      originalPrice: map['originalPrice']?.toInt() ?? 0,
      effectivePrice: map['effectivePrice']?.toInt() ?? 0,
      isGift: map['isGift'] ?? false,
      giftSourceCampaignId: map['giftSourceCampaignId'],
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
    );
  }
  
  LineBenefit copyWith({
    String? lineId,
    String? campaignId,
    String? tierId,
    int? discountMoney,
    int? originalPrice,
    int? effectivePrice,
    bool? isGift,
    String? giftSourceCampaignId,
    int? quantity,
  }) {
    return LineBenefit(
      lineId: lineId ?? this.lineId,
      campaignId: campaignId ?? this.campaignId,
      tierId: tierId ?? this.tierId,
      discountMoney: discountMoney ?? this.discountMoney,
      originalPrice: originalPrice ?? this.originalPrice,
      effectivePrice: effectivePrice ?? this.effectivePrice,
      isGift: isGift ?? this.isGift,
      giftSourceCampaignId: giftSourceCampaignId ?? this.giftSourceCampaignId,
      quantity: quantity ?? this.quantity,
    );
  }
}

/// Kết quả pricing engine cho hóa đơn
class BillBenefit {
  final String campaignId;
  final String tierId;
  final int discountMoney; // Tổng giảm bill
  final Map<String, int> lineAllocations; // lineId → allocated amount

  BillBenefit({
    required this.campaignId,
    required this.tierId,
    required this.discountMoney,
    required this.lineAllocations,
  });

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'tierId': tierId,
      'discountMoney': discountMoney,
      'lineAllocations': lineAllocations,
    };
  }

  factory BillBenefit.fromMap(Map<String, dynamic> map) {
    return BillBenefit(
      campaignId: map['campaignId'] ?? '',
      tierId: map['tierId'] ?? '',
      discountMoney: map['discountMoney']?.toInt() ?? 0,
      lineAllocations: Map<String, int>.from(map['lineAllocations'] ?? {}),
    );
  }
  
  BillBenefit copyWith({
    String? campaignId,
    String? tierId,
    int? discountMoney,
    Map<String, int>? lineAllocations,
  }) {
    return BillBenefit(
      campaignId: campaignId ?? this.campaignId,
      tierId: tierId ?? this.tierId,
      discountMoney: discountMoney ?? this.discountMoney,
      lineAllocations: lineAllocations ?? this.lineAllocations,
    );
  }
}

/// Lý do không áp dụng chương trình
class QuoteReason {
  final String campaignId;
  final String reasonCode; // e.g., 'NOT_ELIGIBLE', 'OUTSIDE_SCHEDULE'
  final String reasonMessage; // Vietnamese explanation

  QuoteReason({
    required this.campaignId,
    required this.reasonCode,
    required this.reasonMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'campaignId': campaignId,
      'reasonCode': reasonCode,
      'reasonMessage': reasonMessage,
    };
  }

  factory QuoteReason.fromMap(Map<String, dynamic> map) {
    return QuoteReason(
      campaignId: map['campaignId'] ?? '',
      reasonCode: map['reasonCode'] ?? '',
      reasonMessage: map['reasonMessage'] ?? '',
    );
  }
  
  QuoteReason copyWith({
    String? campaignId,
    String? reasonCode,
    String? reasonMessage,
  }) {
    return QuoteReason(
      campaignId: campaignId ?? this.campaignId,
      reasonCode: reasonCode ?? this.reasonCode,
      reasonMessage: reasonMessage ?? this.reasonMessage,
    );
  }
}

/// Bảng báo giá (kết quả pricing engine)
class PriceQuoteModel {
  final String quoteId;
  final String orderId;
  final int orderVersion;
  final String inputHash; // Hash of inputs for staleness check
  final int expiresAt; // Quote TTL
  final int pricingPolicyVersion;

  // Amounts
  final int grossMoney; // Tổng tiền hàng trước giảm
  final int eligibleBaseMoney; // Cơ sở tính giảm
  final int totalPromotionDiscount; // Tổng giảm từ KM
  final int manualDiscount; // Giảm thủ công
  final int totalDiscountMoney; // Tổng tất cả giảm
  final int netMoney; // Sau giảm, trước thuế

  // Details
  final List<LineBenefit> lineBenefits; // Tổng hợp mỗi dòng 1 phần tử
  final List<LineBenefit> rewardBenefits; // Chi tiết món được tặng/giảm theo từng KM (Mua X tặng/giảm Y, theo giá trị HĐ)
  final List<BillBenefit> billBenefits;
  final List<String> appliedCampaignIds;
  final List<QuoteReason> reasons; // Why campaigns didn't apply

  // State
  final String state; // VALID, EXPIRED, COMMITTED
  final int createdAt;

  PriceQuoteModel({
    required this.quoteId,
    required this.orderId,
    required this.orderVersion,
    required this.inputHash,
    required this.expiresAt,
    required this.pricingPolicyVersion,
    required this.grossMoney,
    required this.eligibleBaseMoney,
    required this.totalPromotionDiscount,
    required this.manualDiscount,
    required this.totalDiscountMoney,
    required this.netMoney,
    required this.lineBenefits,
    this.rewardBenefits = const [],
    required this.billBenefits,
    required this.appliedCampaignIds,
    required this.reasons,
    required this.state,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'quoteId': quoteId,
      'orderId': orderId,
      'orderVersion': orderVersion,
      'inputHash': inputHash,
      'expiresAt': expiresAt,
      'pricingPolicyVersion': pricingPolicyVersion,
      'grossMoney': grossMoney,
      'eligibleBaseMoney': eligibleBaseMoney,
      'totalPromotionDiscount': totalPromotionDiscount,
      'manualDiscount': manualDiscount,
      'totalDiscountMoney': totalDiscountMoney,
      'netMoney': netMoney,
      'lineBenefits': lineBenefits.map((e) => e.toMap()).toList(),
      'rewardBenefits': rewardBenefits.map((e) => e.toMap()).toList(),
      'billBenefits': billBenefits.map((e) => e.toMap()).toList(),
      'appliedCampaignIds': appliedCampaignIds,
      'reasons': reasons.map((e) => e.toMap()).toList(),
      'state': state,
      'createdAt': createdAt,
    };
  }

  factory PriceQuoteModel.fromMap(Map<String, dynamic> map) {
    return PriceQuoteModel(
      quoteId: map['quoteId'] ?? '',
      orderId: map['orderId'] ?? '',
      orderVersion: map['orderVersion']?.toInt() ?? 0,
      inputHash: map['inputHash'] ?? '',
      expiresAt: map['expiresAt']?.toInt() ?? 0,
      pricingPolicyVersion: map['pricingPolicyVersion']?.toInt() ?? 0,
      grossMoney: map['grossMoney']?.toInt() ?? 0,
      eligibleBaseMoney: map['eligibleBaseMoney']?.toInt() ?? 0,
      totalPromotionDiscount: map['totalPromotionDiscount']?.toInt() ?? 0,
      manualDiscount: map['manualDiscount']?.toInt() ?? 0,
      totalDiscountMoney: map['totalDiscountMoney']?.toInt() ?? 0,
      netMoney: map['netMoney']?.toInt() ?? 0,
      lineBenefits: List<LineBenefit>.from((map['lineBenefits'] ?? []).map((e) => LineBenefit.fromMap(e))),
      rewardBenefits: List<LineBenefit>.from((map['rewardBenefits'] ?? []).map((e) => LineBenefit.fromMap(e))),
      billBenefits: List<BillBenefit>.from((map['billBenefits'] ?? []).map((e) => BillBenefit.fromMap(e))),
      appliedCampaignIds: List<String>.from(map['appliedCampaignIds'] ?? []),
      reasons: List<QuoteReason>.from((map['reasons'] ?? []).map((e) => QuoteReason.fromMap(e))),
      state: map['state'] ?? 'VALID',
      createdAt: map['createdAt']?.toInt() ?? 0,
    );
  }
  
  PriceQuoteModel copyWith({
    String? quoteId,
    String? orderId,
    int? orderVersion,
    String? inputHash,
    int? expiresAt,
    int? pricingPolicyVersion,
    int? grossMoney,
    int? eligibleBaseMoney,
    int? totalPromotionDiscount,
    int? manualDiscount,
    int? totalDiscountMoney,
    int? netMoney,
    List<LineBenefit>? lineBenefits,
    List<LineBenefit>? rewardBenefits,
    List<BillBenefit>? billBenefits,
    List<String>? appliedCampaignIds,
    List<QuoteReason>? reasons,
    String? state,
    int? createdAt,
  }) {
    return PriceQuoteModel(
      quoteId: quoteId ?? this.quoteId,
      orderId: orderId ?? this.orderId,
      orderVersion: orderVersion ?? this.orderVersion,
      inputHash: inputHash ?? this.inputHash,
      expiresAt: expiresAt ?? this.expiresAt,
      pricingPolicyVersion: pricingPolicyVersion ?? this.pricingPolicyVersion,
      grossMoney: grossMoney ?? this.grossMoney,
      eligibleBaseMoney: eligibleBaseMoney ?? this.eligibleBaseMoney,
      totalPromotionDiscount: totalPromotionDiscount ?? this.totalPromotionDiscount,
      manualDiscount: manualDiscount ?? this.manualDiscount,
      totalDiscountMoney: totalDiscountMoney ?? this.totalDiscountMoney,
      netMoney: netMoney ?? this.netMoney,
      lineBenefits: lineBenefits ?? this.lineBenefits,
      rewardBenefits: rewardBenefits ?? this.rewardBenefits,
      billBenefits: billBenefits ?? this.billBenefits,
      appliedCampaignIds: appliedCampaignIds ?? this.appliedCampaignIds,
      reasons: reasons ?? this.reasons,
      state: state ?? this.state,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
