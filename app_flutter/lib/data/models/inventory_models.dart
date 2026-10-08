/// File: inventory_models.dart
/// Chứa tất cả các model liên quan đến quản lý kho (Inventory) cho hệ thống POS Trạm F&B.
/// Quy ước chung:
/// - Tiền tệ: int (VND, không có số thập phân)
/// - Thời gian: int (epoch milliseconds UTC)
/// - Null safety được đảm bảo.

// ---------------------------------------------------------------------------
// 1. Enums
// ---------------------------------------------------------------------------

/// Loại hàng hoá/vật tư
enum CatalogItemKind {
  rawMaterial,
  tool,
  directSale,
  madeToOrder,
  manufactured,
  topping,
  service
}

/// Loại phiếu kho
enum InventoryDocType {
  purchaseReceipt,
  purchaseReturn,
  stocktake,
  transfer,
  waste,
  internalUse,
  production,
  adjustment,
  opening
}

/// Trạng thái phiếu kho
enum InventoryDocStatus { draft, committing, completed, cancelled }

/// Trạng thái điều chuyển kho
enum TransferStatus { draft, inTransit, received, cancelled }

/// Trạng thái kiểm kê
enum StocktakeStatus { draft, committing, balanced, cancelled }

// ---------------------------------------------------------------------------
// 2. CatalogItemModel
// ---------------------------------------------------------------------------

/// Hàng kho/nguyên vật liệu.
class CatalogItemModel {
  /// ID duy nhất
  final String itemId;

  /// Mã hàng tự động hoặc nhập
  final String? sku;

  /// Tên hàng
  final String name;

  /// Phân loại (RAW_MATERIAL, TOOL, DIRECT_SALE, MADE_TO_ORDER, MANUFACTURED, TOPPING, SERVICE)
  final String? kind;

  /// Nhóm quản lý (e.g., 'Nguyên liệu pha chế', 'Công cụ dụng cụ')
  final String? managementGroup;

  /// Nhóm/danh mục
  final List<String> groupIds;

  /// Thương hiệu
  final String? brandId;

  /// Đơn vị cơ bản (g, ml, cái, chai...)
  final String baseUnitId;

  /// Số chữ số thập phân cho quantity (1=integer, 1000=3 decimals via g)
  final int quantityScale;

  /// Có quản lý tồn kho
  final bool trackStock;

  /// Chi nhánh sử dụng
  final List<String> enabledBranches;

  /// Giá vốn (VND)
  final int costPrice;

  /// Tồn kho tối thiểu (base unit)
  final int minStock;

  /// Tồn kho tối đa (0=unlimited)
  final int maxStock;

  /// URL ảnh
  final String? imageUrl;

  /// Mô tả
  final String description;

  /// Trạng thái (ACTIVE, DISCONTINUED)
  final String status;

  /// Link to old ProductModel.id
  final int? legacyProductId;

  /// Vị trí lưu kho
  final String? location;

  /// Thương hiệu
  final String? brand;

  /// Trọng lượng
  final int weight;

  /// Đơn vị trọng lượng (g, kg...)
  final String? weightUnit;

  /// Tỷ lệ quy đổi
  final int conversionRate;

  /// Thời gian tạo (Epoch ms)
  final int createdAt;

  /// Thời gian cập nhật (Epoch ms)
  final int updatedAt;

  /// Phiên bản document
  final int version;

  CatalogItemModel({
    required this.itemId,
    this.sku,
    required this.name,
    this.kind,
    this.managementGroup,
    this.groupIds = const [],
    this.brandId,
    required this.baseUnitId,
    this.quantityScale = 1,
    this.trackStock = true,
    this.enabledBranches = const [],
    this.costPrice = 0,
    this.minStock = 0,
    this.maxStock = 0,
    this.imageUrl,
    this.description = '',
    this.status = 'ACTIVE',
    this.legacyProductId,
    this.location,
    this.brand,
    this.weight = 0,
    this.weightUnit,
    this.conversionRate = 1,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isDiscontinued => status == 'DISCONTINUED';

  factory CatalogItemModel.fromMap(Map<String, dynamic> map) {
    return CatalogItemModel(
      itemId: map['itemId'] as String? ?? '',
      sku: map['sku'] as String?,
      name: map['name'] as String? ?? '',
      kind: map['kind'] as String?,
      managementGroup: map['managementGroup'] as String?,
      groupIds: List<String>.from(map['groupIds'] ?? []),
      brandId: map['brandId'] as String?,
      baseUnitId: map['baseUnitId'] as String? ?? '',
      quantityScale: (map['quantityScale'] as num?)?.toInt() ?? 1,
      trackStock: map['trackStock'] as bool? ?? true,
      enabledBranches: List<String>.from(map['enabledBranches'] ?? []),
      costPrice: (map['costPrice'] as num?)?.toInt() ?? 0,
      minStock: (map['minStock'] as num?)?.toInt() ?? 0,
      maxStock: (map['maxStock'] as num?)?.toInt() ?? 0,
      imageUrl: map['imageUrl'] as String?,
      description: map['description'] as String? ?? '',
      status: map['status'] as String? ?? 'ACTIVE',
      legacyProductId: (map['legacyProductId'] as num?)?.toInt(),
      location: map['location'] as String?,
      brand: map['brand'] as String?,
      weight: (map['weight'] as num?)?.toInt() ?? 0,
      weightUnit: map['weightUnit'] as String?,
      conversionRate: (map['conversionRate'] as num?)?.toInt() ?? 1,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'itemId': itemId,
      'name': name,
      'groupIds': groupIds,
      'baseUnitId': baseUnitId,
      'quantityScale': quantityScale,
      'trackStock': trackStock,
      'enabledBranches': enabledBranches,
      'costPrice': costPrice,
      'minStock': minStock,
      'maxStock': maxStock,
      'description': description,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'version': version,
    };
    if (sku != null) map['sku'] = sku;
    if (kind != null) map['kind'] = kind;
    if (managementGroup != null) map['managementGroup'] = managementGroup;
    if (brandId != null) map['brandId'] = brandId;
    if (imageUrl != null) map['imageUrl'] = imageUrl;
    if (legacyProductId != null) map['legacyProductId'] = legacyProductId;
    if (location != null) map['location'] = location;
    if (brand != null) map['brand'] = brand;
    if (weight > 0) map['weight'] = weight;
    if (weightUnit != null) map['weightUnit'] = weightUnit;
    if (conversionRate != 1) map['conversionRate'] = conversionRate;
    return map;
  }

  CatalogItemModel copyWith({
    String? itemId,
    String? sku,
    String? name,
    String? kind,
    String? managementGroup,
    List<String>? groupIds,
    String? brandId,
    String? baseUnitId,
    int? quantityScale,
    bool? trackStock,
    List<String>? enabledBranches,
    int? costPrice,
    int? minStock,
    int? maxStock,
    String? imageUrl,
    String? description,
    String? status,
    int? legacyProductId,
    String? location,
    String? brand,
    int? weight,
    String? weightUnit,
    int? conversionRate,
    int? createdAt,
    int? updatedAt,
    int? version,
  }) {
    return CatalogItemModel(
      itemId: itemId ?? this.itemId,
      sku: sku ?? this.sku,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      managementGroup: managementGroup ?? this.managementGroup,
      groupIds: groupIds ?? this.groupIds,
      brandId: brandId ?? this.brandId,
      baseUnitId: baseUnitId ?? this.baseUnitId,
      quantityScale: quantityScale ?? this.quantityScale,
      trackStock: trackStock ?? this.trackStock,
      enabledBranches: enabledBranches ?? this.enabledBranches,
      costPrice: costPrice ?? this.costPrice,
      minStock: minStock ?? this.minStock,
      maxStock: maxStock ?? this.maxStock,
      imageUrl: imageUrl ?? this.imageUrl,
      description: description ?? this.description,
      status: status ?? this.status,
      legacyProductId: legacyProductId ?? this.legacyProductId,
      location: location ?? this.location,
      brand: brand ?? this.brand,
      weight: weight ?? this.weight,
      weightUnit: weightUnit ?? this.weightUnit,
      conversionRate: conversionRate ?? this.conversionRate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }
}

// ---------------------------------------------------------------------------
// 3. UnitConversionModel
// ---------------------------------------------------------------------------

/// Quy đổi đơn vị.
class UnitConversionModel {
  final String conversionId;
  /// Link to CatalogItem
  final String itemId;
  /// Tên đơn vị (e.g., 'kg', 'thùng', 'chai')
  final String unitId;
  /// Tên hiển thị
  final String unitName;
  /// Tử số quy đổi
  final int numerator;
  /// Mẫu số quy đổi
  final int denominator;
  /// Đây có phải đơn vị cơ bản
  final bool isBaseUnit;
  final bool active;
  final int version;

  UnitConversionModel({
    required this.conversionId,
    required this.itemId,
    required this.unitId,
    required this.unitName,
    required this.numerator,
    this.denominator = 1,
    required this.isBaseUnit,
    this.active = true,
    this.version = 1,
  }) {
    assert(numerator > 0, 'Numerator must be greater than 0');
    assert(denominator > 0, 'Denominator must be greater than 0');
  }

  double get conversionRate => numerator / denominator;

  factory UnitConversionModel.fromMap(Map<String, dynamic> map) {
    return UnitConversionModel(
      conversionId: map['conversionId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      unitId: map['unitId'] as String? ?? '',
      unitName: map['unitName'] as String? ?? '',
      numerator: (map['numerator'] as num?)?.toInt() ?? 1,
      denominator: (map['denominator'] as num?)?.toInt() ?? 1,
      isBaseUnit: map['isBaseUnit'] as bool? ?? false,
      active: map['active'] as bool? ?? true,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'conversionId': conversionId,
      'itemId': itemId,
      'unitId': unitId,
      'unitName': unitName,
      'numerator': numerator,
      'denominator': denominator,
      'isBaseUnit': isBaseUnit,
      'active': active,
      'version': version,
    };
  }

  UnitConversionModel copyWith({
    String? conversionId,
    String? itemId,
    String? unitId,
    String? unitName,
    int? numerator,
    int? denominator,
    bool? isBaseUnit,
    bool? active,
    int? version,
  }) {
    return UnitConversionModel(
      conversionId: conversionId ?? this.conversionId,
      itemId: itemId ?? this.itemId,
      unitId: unitId ?? this.unitId,
      unitName: unitName ?? this.unitName,
      numerator: numerator ?? this.numerator,
      denominator: denominator ?? this.denominator,
      isBaseUnit: isBaseUnit ?? this.isBaseUnit,
      active: active ?? this.active,
      version: version ?? this.version,
    );
  }
}

// ---------------------------------------------------------------------------
// 4. RecipeVersionModel + RecipeIngredient
// ---------------------------------------------------------------------------

/// Thành phần công thức
class RecipeIngredient {
  /// CatalogItem ID nguyên liệu
  final String itemId;
  /// Cached name
  final String itemName;
  /// Đơn vị sử dụng
  final String unitId;
  /// Số lượng theo đơn vị cơ bản
  final int quantityBase;
  /// Hao hụt (basis points, 0-10000)
  final int wasteRateBps;

  RecipeIngredient({
    required this.itemId,
    required this.itemName,
    required this.unitId,
    required this.quantityBase,
    required this.wasteRateBps,
  });

  factory RecipeIngredient.fromMap(Map<String, dynamic> map) {
    return RecipeIngredient(
      itemId: map['itemId'] as String? ?? '',
      itemName: map['itemName'] as String? ?? '',
      unitId: map['unitId'] as String? ?? '',
      quantityBase: (map['quantityBase'] as num?)?.toInt() ?? 0,
      wasteRateBps: (map['wasteRateBps'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'unitId': unitId,
      'quantityBase': quantityBase,
      'wasteRateBps': wasteRateBps,
    };
  }
}

/// Công thức chế biến.
class RecipeVersionModel {
  final String recipeId;
  /// Thành phẩm
  final String outputItemId;
  /// Size/variant
  final String? outputVariant;
  /// Số lượng output
  final int outputQuantityBase;
  final String outputUnitId;
  final List<RecipeIngredient> ingredients;
  /// null = all branches
  final String? branchScope;
  /// Epoch ms
  final int effectiveFrom;
  /// ACTIVE, ARCHIVED
  final String status;
  final int version;

  RecipeVersionModel({
    required this.recipeId,
    required this.outputItemId,
    this.outputVariant,
    required this.outputQuantityBase,
    required this.outputUnitId,
    required this.ingredients,
    this.branchScope,
    required this.effectiveFrom,
    required this.status,
    this.version = 1,
  });

  factory RecipeVersionModel.fromMap(Map<String, dynamic> map) {
    return RecipeVersionModel(
      recipeId: map['recipeId'] as String? ?? '',
      outputItemId: map['outputItemId'] as String? ?? '',
      outputVariant: map['outputVariant'] as String?,
      outputQuantityBase: (map['outputQuantityBase'] as num?)?.toInt() ?? 0,
      outputUnitId: map['outputUnitId'] as String? ?? '',
      ingredients: (map['ingredients'] as List?)
              ?.map((e) => RecipeIngredient.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      branchScope: map['branchScope'] as String?,
      effectiveFrom: (map['effectiveFrom'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'ACTIVE',
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'recipeId': recipeId,
      'outputItemId': outputItemId,
      'outputQuantityBase': outputQuantityBase,
      'outputUnitId': outputUnitId,
      'ingredients': ingredients.map((e) => e.toMap()).toList(),
      'effectiveFrom': effectiveFrom,
      'status': status,
      'version': version,
    };
    if (outputVariant != null) map['outputVariant'] = outputVariant;
    if (branchScope != null) map['branchScope'] = branchScope;
    return map;
  }

  RecipeVersionModel copyWith({
    String? recipeId,
    String? outputItemId,
    String? outputVariant,
    int? outputQuantityBase,
    String? outputUnitId,
    List<RecipeIngredient>? ingredients,
    String? branchScope,
    int? effectiveFrom,
    String? status,
    int? version,
  }) {
    return RecipeVersionModel(
      recipeId: recipeId ?? this.recipeId,
      outputItemId: outputItemId ?? this.outputItemId,
      outputVariant: outputVariant ?? this.outputVariant,
      outputQuantityBase: outputQuantityBase ?? this.outputQuantityBase,
      outputUnitId: outputUnitId ?? this.outputUnitId,
      ingredients: ingredients ?? this.ingredients,
      branchScope: branchScope ?? this.branchScope,
      effectiveFrom: effectiveFrom ?? this.effectiveFrom,
      status: status ?? this.status,
      version: version ?? this.version,
    );
  }
}

// ---------------------------------------------------------------------------
// 5. StockBalanceModel
// ---------------------------------------------------------------------------

/// Số dư tồn kho theo branch + itemVariant.
class StockBalanceModel {
  /// '{branchId}_{itemId}'
  final String balanceId;
  final String branchId;
  final String itemId;
  /// For size variants
  final String? itemVariantId;
  /// Tồn kho thực tế (base unit)
  final int onHandQty;
  /// Đang giữ chỗ
  final int reservedQty;
  /// Tổng giá trị tồn (VND)
  final int inventoryValue;
  /// Giá vốn TB (VND, scaled by 100 for precision)
  final int averageCostScaled;
  /// Sequence number event cuối
  final int lastEventSeq;
  final int updatedAt;
  final int version;

  StockBalanceModel({
    required this.balanceId,
    required this.branchId,
    required this.itemId,
    this.itemVariantId,
    required this.onHandQty,
    this.reservedQty = 0,
    required this.inventoryValue,
    required this.averageCostScaled,
    required this.lastEventSeq,
    required this.updatedAt,
    this.version = 1,
  }) {
    assert(reservedQty >= 0, 'reservedQty cannot be negative');
    assert(availableQty >= 0, 'availableQty cannot be negative in normal cases');
  }

  int get availableQty => onHandQty - reservedQty;

  factory StockBalanceModel.fromMap(Map<String, dynamic> map) {
    return StockBalanceModel(
      balanceId: map['balanceId'] as String? ?? '',
      branchId: map['branchId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      itemVariantId: map['itemVariantId'] as String?,
      onHandQty: (map['onHandQty'] as num?)?.toInt() ?? 0,
      reservedQty: (map['reservedQty'] as num?)?.toInt() ?? 0,
      inventoryValue: (map['inventoryValue'] as num?)?.toInt() ?? 0,
      averageCostScaled: (map['averageCostScaled'] as num?)?.toInt() ?? 0,
      lastEventSeq: (map['lastEventSeq'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'balanceId': balanceId,
      'branchId': branchId,
      'itemId': itemId,
      'onHandQty': onHandQty,
      'reservedQty': reservedQty,
      'inventoryValue': inventoryValue,
      'averageCostScaled': averageCostScaled,
      'lastEventSeq': lastEventSeq,
      'updatedAt': updatedAt,
      'version': version,
    };
    if (itemVariantId != null) map['itemVariantId'] = itemVariantId;
    return map;
  }

  StockBalanceModel copyWith({
    String? balanceId,
    String? branchId,
    String? itemId,
    String? itemVariantId,
    int? onHandQty,
    int? reservedQty,
    int? inventoryValue,
    int? averageCostScaled,
    int? lastEventSeq,
    int? updatedAt,
    int? version,
  }) {
    return StockBalanceModel(
      balanceId: balanceId ?? this.balanceId,
      branchId: branchId ?? this.branchId,
      itemId: itemId ?? this.itemId,
      itemVariantId: itemVariantId ?? this.itemVariantId,
      onHandQty: onHandQty ?? this.onHandQty,
      reservedQty: reservedQty ?? this.reservedQty,
      inventoryValue: inventoryValue ?? this.inventoryValue,
      averageCostScaled: averageCostScaled ?? this.averageCostScaled,
      lastEventSeq: lastEventSeq ?? this.lastEventSeq,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }
}

// ---------------------------------------------------------------------------
// 6. StockEventModel
// ---------------------------------------------------------------------------

/// Biến động kho (sổ bất biến, append-only).
class StockEventModel {
  final String eventId;
  /// Idempotency link
  final String commandId;
  /// Phiếu gốc
  final String documentId;
  /// PURCHASE_RECEIPT, PURCHASE_RETURN, SALE, STOCKTAKE_ADJUST, TRANSFER_SEND, TRANSFER_RECEIVE, WASTE, INTERNAL_USE, PRODUCTION_INPUT, PRODUCTION_OUTPUT, ADJUSTMENT, OPENING
  final String documentType;
  /// Dòng cụ thể
  final String? documentLineId;
  final String branchId;
  final String itemId;
  final String? itemVariantId;
  /// Thay đổi số lượng (+ nhập, - xuất)
  final int qtyDeltaBase;
  /// Thay đổi giá trị (VND)
  final int valueDeltaMoney;
  /// Giá vốn tại thời điểm (VND)
  final int unitCostSnapshot;
  /// JSON snapshot quy đổi
  final String? conversionSnapshot;
  /// Thời điểm xảy ra
  final int occurredAt;
  /// Thời điểm ghi nhận
  final int committedAt;
  /// Người thao tác
  final String actorId;
  /// Liên kết giao dịch
  final String? correlationId;
  /// Event bị đảo ngược
  final String? reversalOf;
  /// Số thứ tự
  final int sequence;
  /// Lý do
  final String? reason;

  StockEventModel({
    required this.eventId,
    required this.commandId,
    required this.documentId,
    required this.documentType,
    this.documentLineId,
    required this.branchId,
    required this.itemId,
    this.itemVariantId,
    required this.qtyDeltaBase,
    required this.valueDeltaMoney,
    required this.unitCostSnapshot,
    this.conversionSnapshot,
    required this.occurredAt,
    required this.committedAt,
    required this.actorId,
    this.correlationId,
    this.reversalOf,
    required this.sequence,
    this.reason,
  });

  factory StockEventModel.fromMap(Map<String, dynamic> map) {
    return StockEventModel(
      eventId: map['eventId'] as String? ?? '',
      commandId: map['commandId'] as String? ?? '',
      documentId: map['documentId'] as String? ?? '',
      documentType: map['documentType'] as String? ?? '',
      documentLineId: map['documentLineId'] as String?,
      branchId: map['branchId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      itemVariantId: map['itemVariantId'] as String?,
      qtyDeltaBase: (map['qtyDeltaBase'] as num?)?.toInt() ?? 0,
      valueDeltaMoney: (map['valueDeltaMoney'] as num?)?.toInt() ?? 0,
      unitCostSnapshot: (map['unitCostSnapshot'] as num?)?.toInt() ?? 0,
      conversionSnapshot: map['conversionSnapshot'] as String?,
      occurredAt: (map['occurredAt'] as num?)?.toInt() ?? 0,
      committedAt: (map['committedAt'] as num?)?.toInt() ?? 0,
      actorId: map['actorId'] as String? ?? '',
      correlationId: map['correlationId'] as String?,
      reversalOf: map['reversalOf'] as String?,
      sequence: (map['sequence'] as num?)?.toInt() ?? 0,
      reason: map['reason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'eventId': eventId,
      'commandId': commandId,
      'documentId': documentId,
      'documentType': documentType,
      'branchId': branchId,
      'itemId': itemId,
      'qtyDeltaBase': qtyDeltaBase,
      'valueDeltaMoney': valueDeltaMoney,
      'unitCostSnapshot': unitCostSnapshot,
      'occurredAt': occurredAt,
      'committedAt': committedAt,
      'actorId': actorId,
      'sequence': sequence,
    };
    if (documentLineId != null) map['documentLineId'] = documentLineId;
    if (itemVariantId != null) map['itemVariantId'] = itemVariantId;
    if (conversionSnapshot != null) map['conversionSnapshot'] = conversionSnapshot;
    if (correlationId != null) map['correlationId'] = correlationId;
    if (reversalOf != null) map['reversalOf'] = reversalOf;
    if (reason != null) map['reason'] = reason;
    return map;
  }
}

// ---------------------------------------------------------------------------
// 7. SupplierModel
// ---------------------------------------------------------------------------

/// Nhà cung cấp.
class SupplierModel {
  final String supplierId;
  /// Mã NCC tự động
  final String supplierCode;
  final String name;
  final String? phone;
  final String? email;
  /// MST
  final String? taxId;
  final String? contactPerson;
  final String? address;
  final String? province;
  final String? district;
  final String? ward;
  /// Nhóm NCC
  final String? groupId;
  final String? note;
  final List<String> enabledBranches;
  /// ACTIVE, INACTIVE
  final String status;
  final int createdAt;
  final int updatedAt;
  final int version;

  SupplierModel({
    required this.supplierId,
    required this.supplierCode,
    required this.name,
    this.phone,
    this.email,
    this.taxId,
    this.contactPerson,
    this.address,
    this.province,
    this.district,
    this.ward,
    this.groupId,
    this.note,
    this.enabledBranches = const [],
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
  });

  factory SupplierModel.fromMap(Map<String, dynamic> map) {
    return SupplierModel(
      supplierId: map['supplierId'] as String? ?? '',
      supplierCode: map['supplierCode'] as String? ?? '',
      name: map['name'] as String? ?? '',
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      taxId: map['taxId'] as String?,
      contactPerson: map['contactPerson'] as String?,
      address: map['address'] as String?,
      province: map['province'] as String?,
      district: map['district'] as String?,
      ward: map['ward'] as String?,
      groupId: map['groupId'] as String?,
      note: map['note'] as String?,
      enabledBranches: List<String>.from(map['enabledBranches'] ?? []),
      status: map['status'] as String? ?? 'ACTIVE',
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (map['updatedAt'] as num?)?.toInt() ?? 0,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'supplierId': supplierId,
      'supplierCode': supplierCode,
      'name': name,
      'enabledBranches': enabledBranches,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'version': version,
    };
    if (phone != null) map['phone'] = phone;
    if (email != null) map['email'] = email;
    if (taxId != null) map['taxId'] = taxId;
    if (contactPerson != null) map['contactPerson'] = contactPerson;
    if (address != null) map['address'] = address;
    if (province != null) map['province'] = province;
    if (district != null) map['district'] = district;
    if (ward != null) map['ward'] = ward;
    if (groupId != null) map['groupId'] = groupId;
    if (note != null) map['note'] = note;
    return map;
  }

  SupplierModel copyWith({
    String? supplierId,
    String? supplierCode,
    String? name,
    String? phone,
    String? email,
    String? taxId,
    String? contactPerson,
    String? address,
    String? province,
    String? district,
    String? ward,
    String? groupId,
    String? note,
    List<String>? enabledBranches,
    String? status,
    int? createdAt,
    int? updatedAt,
    int? version,
  }) {
    return SupplierModel(
      supplierId: supplierId ?? this.supplierId,
      supplierCode: supplierCode ?? this.supplierCode,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxId: taxId ?? this.taxId,
      contactPerson: contactPerson ?? this.contactPerson,
      address: address ?? this.address,
      province: province ?? this.province,
      district: district ?? this.district,
      ward: ward ?? this.ward,
      groupId: groupId ?? this.groupId,
      note: note ?? this.note,
      enabledBranches: enabledBranches ?? this.enabledBranches,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
    );
  }
}

// ---------------------------------------------------------------------------
// 8. SupplierLedgerEntryModel
// ---------------------------------------------------------------------------

/// Sổ công nợ NCC.
class SupplierLedgerEntryModel {
  final String entryId;
  final String supplierId;
  final String branchId;
  /// OPENING, PURCHASE, RETURN, PAYMENT, ADJUSTMENT
  final String entryType;
  /// Số tiền (dương = nợ tăng, âm = nợ giảm)
  final int amountMoney;
  /// Phiếu liên kết
  final String? referenceDocId;
  final String? referenceDocType;
  final String? description;
  /// CASH, TRANSFER, CARD
  final String? paymentMethod;
  final int occurredAt;
  final int committedAt;
  final String actorId;
  final String? reversedBy;
  final int version;

  SupplierLedgerEntryModel({
    required this.entryId,
    required this.supplierId,
    required this.branchId,
    required this.entryType,
    required this.amountMoney,
    this.referenceDocId,
    this.referenceDocType,
    this.description,
    this.paymentMethod,
    required this.occurredAt,
    required this.committedAt,
    required this.actorId,
    this.reversedBy,
    this.version = 1,
  });

  factory SupplierLedgerEntryModel.fromMap(Map<String, dynamic> map) {
    return SupplierLedgerEntryModel(
      entryId: map['entryId'] as String? ?? '',
      supplierId: map['supplierId'] as String? ?? '',
      branchId: map['branchId'] as String? ?? '',
      entryType: map['entryType'] as String? ?? '',
      amountMoney: (map['amountMoney'] as num?)?.toInt() ?? 0,
      referenceDocId: map['referenceDocId'] as String?,
      referenceDocType: map['referenceDocType'] as String?,
      description: map['description'] as String?,
      paymentMethod: map['paymentMethod'] as String?,
      occurredAt: (map['occurredAt'] as num?)?.toInt() ?? 0,
      committedAt: (map['committedAt'] as num?)?.toInt() ?? 0,
      actorId: map['actorId'] as String? ?? '',
      reversedBy: map['reversedBy'] as String?,
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'entryId': entryId,
      'supplierId': supplierId,
      'branchId': branchId,
      'entryType': entryType,
      'amountMoney': amountMoney,
      'occurredAt': occurredAt,
      'committedAt': committedAt,
      'actorId': actorId,
      'version': version,
    };
    if (referenceDocId != null) map['referenceDocId'] = referenceDocId;
    if (referenceDocType != null) map['referenceDocType'] = referenceDocType;
    if (description != null) map['description'] = description;
    if (paymentMethod != null) map['paymentMethod'] = paymentMethod;
    if (reversedBy != null) map['reversedBy'] = reversedBy;
    return map;
  }
}

// ---------------------------------------------------------------------------
// 9. InventoryDocumentModel + InventoryDocLine
// ---------------------------------------------------------------------------

/// Dòng chi tiết phiếu kho
class InventoryDocLine {
  final String lineId;
  final String itemId;
  /// Snapshot
  final String itemName;
  final String? itemVariantId;
  final String unitId;
  final int conversionNumerator;
  final int conversionDenominator;
  /// Theo đơn vị nhập/xuất
  final int quantity;
  /// Quy về đơn vị cơ bản
  final int quantityBase;
  /// Đơn giá (VND)
  final int unitPrice;
  /// Giảm giá dòng (VND)
  final int lineDiscountMoney;
  /// Giảm giá % (basis points)
  final int lineDiscountPercent;
  /// Thuế dòng
  final int lineTaxMoney;
  /// Thành tiền sau giảm
  final int lineNetMoney;
  /// Chi phí phân bổ
  final int costAllocation;
  final String? note;
  /// Tồn sổ sách (For stocktake)
  final int? bookQty;
  /// Tồn thực tế (null = chưa kiểm) (For stocktake)
  final int? actualQty;
  /// Số lượng nhận thực tế (For transfer receive)
  final int? receivedQty;
  final String? varianceReason;

  InventoryDocLine({
    required this.lineId,
    required this.itemId,
    required this.itemName,
    this.itemVariantId,
    required this.unitId,
    required this.conversionNumerator,
    required this.conversionDenominator,
    required this.quantity,
    required this.quantityBase,
    required this.unitPrice,
    required this.lineDiscountMoney,
    required this.lineDiscountPercent,
    required this.lineTaxMoney,
    required this.lineNetMoney,
    required this.costAllocation,
    this.note,
    this.bookQty,
    this.actualQty,
    this.receivedQty,
    this.varianceReason,
  });

  factory InventoryDocLine.fromMap(Map<String, dynamic> map) {
    return InventoryDocLine(
      lineId: map['lineId'] as String? ?? '',
      itemId: map['itemId'] as String? ?? '',
      itemName: map['itemName'] as String? ?? '',
      itemVariantId: map['itemVariantId'] as String?,
      unitId: map['unitId'] as String? ?? '',
      conversionNumerator: (map['conversionNumerator'] as num?)?.toInt() ?? 1,
      conversionDenominator: (map['conversionDenominator'] as num?)?.toInt() ?? 1,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      quantityBase: (map['quantityBase'] as num?)?.toInt() ?? 0,
      unitPrice: (map['unitPrice'] as num?)?.toInt() ?? 0,
      lineDiscountMoney: (map['lineDiscountMoney'] as num?)?.toInt() ?? 0,
      lineDiscountPercent: (map['lineDiscountPercent'] as num?)?.toInt() ?? 0,
      lineTaxMoney: (map['lineTaxMoney'] as num?)?.toInt() ?? 0,
      lineNetMoney: (map['lineNetMoney'] as num?)?.toInt() ?? 0,
      costAllocation: (map['costAllocation'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      bookQty: (map['bookQty'] as num?)?.toInt(),
      actualQty: (map['actualQty'] as num?)?.toInt(),
      receivedQty: (map['receivedQty'] as num?)?.toInt(),
      varianceReason: map['varianceReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'lineId': lineId,
      'itemId': itemId,
      'itemName': itemName,
      'unitId': unitId,
      'conversionNumerator': conversionNumerator,
      'conversionDenominator': conversionDenominator,
      'quantity': quantity,
      'quantityBase': quantityBase,
      'unitPrice': unitPrice,
      'lineDiscountMoney': lineDiscountMoney,
      'lineDiscountPercent': lineDiscountPercent,
      'lineTaxMoney': lineTaxMoney,
      'lineNetMoney': lineNetMoney,
      'costAllocation': costAllocation,
    };
    if (itemVariantId != null) map['itemVariantId'] = itemVariantId;
    if (note != null) map['note'] = note;
    if (bookQty != null) map['bookQty'] = bookQty;
    if (actualQty != null) map['actualQty'] = actualQty;
    if (receivedQty != null) map['receivedQty'] = receivedQty;
    if (varianceReason != null) map['varianceReason'] = varianceReason;
    return map;
  }
}

/// Phiếu kho tổng quát (nhập/trả/kiểm/chuyển/xuất/sản xuất).
class InventoryDocumentModel {
  final String documentId;
  /// Mã phiếu tự động (PN-yyMMdd-001)
  final String documentCode;
  /// From InventoryDocType
  final String docType;
  /// From InventoryDocStatus
  final String status;
  final String branchId;
  final String? warehouseId;
  /// For receipt/return
  final String? supplierId;
  /// Snapshot
  final String? supplierName;
  /// For transfer
  final String? sourceBranchId;
  /// For transfer
  final String? destinationBranchId;
  /// For return → receipt link
  final String? sourceDocumentId;
  /// Số hóa đơn đầu vào
  final String? externalInvoiceNumber;
  /// Ngày hóa đơn
  final String? externalInvoiceDate;
  final List<InventoryDocLine> lines;
  final int totalQuantity;
  /// Tổng tiền hàng
  final int totalMoney;
  /// Giảm giá toàn phiếu
  final int globalDiscountMoney;
  /// Tổng thuế
  final int totalTaxMoney;
  /// Tổng sau giảm+thuế
  final int totalNetMoney;
  /// Đã thanh toán
  final int paidMoney;
  /// Còn nợ
  final int debtMoney;
  final String note;
  /// Username
  final String createdBy;
  /// Full name snapshot
  final String createdByName;
  final String? completedBy;
  final String? completedByName;
  final int createdAt;
  final int? completedAt;
  final int? cancelledAt;
  final String? cancelReason;
  /// Lý do xuất/hủy
  final String? reason;
  /// StockEvent IDs created
  final List<String> committedEventIds;
  final String idempotencyKey;
  final int version;

  InventoryDocumentModel({
    required this.documentId,
    required this.documentCode,
    required this.docType,
    required this.status,
    required this.branchId,
    this.warehouseId,
    this.supplierId,
    this.supplierName,
    this.sourceBranchId,
    this.destinationBranchId,
    this.sourceDocumentId,
    this.externalInvoiceNumber,
    this.externalInvoiceDate,
    required this.lines,
    required this.totalQuantity,
    required this.totalMoney,
    required this.globalDiscountMoney,
    required this.totalTaxMoney,
    required this.totalNetMoney,
    required this.paidMoney,
    required this.debtMoney,
    this.note = '',
    this.reason,
    required this.createdBy,
    required this.createdByName,
    this.completedBy,
    this.completedByName,
    required this.createdAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.committedEventIds = const [],
    required this.idempotencyKey,
    this.version = 1,
  });

  factory InventoryDocumentModel.fromMap(Map<String, dynamic> map) {
    return InventoryDocumentModel(
      documentId: map['documentId'] as String? ?? '',
      documentCode: map['documentCode'] as String? ?? '',
      docType: map['docType'] as String? ?? '',
      status: map['status'] as String? ?? '',
      branchId: map['branchId'] as String? ?? '',
      warehouseId: map['warehouseId'] as String?,
      supplierId: map['supplierId'] as String?,
      supplierName: map['supplierName'] as String?,
      sourceBranchId: map['sourceBranchId'] as String?,
      destinationBranchId: map['destinationBranchId'] as String?,
      sourceDocumentId: map['sourceDocumentId'] as String?,
      externalInvoiceNumber: map['externalInvoiceNumber'] as String?,
      externalInvoiceDate: map['externalInvoiceDate'] as String?,
      lines: (map['lines'] as List?)
              ?.map((e) => InventoryDocLine.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
      totalQuantity: (map['totalQuantity'] as num?)?.toInt() ?? 0,
      totalMoney: (map['totalMoney'] as num?)?.toInt() ?? 0,
      globalDiscountMoney: (map['globalDiscountMoney'] as num?)?.toInt() ?? 0,
      totalTaxMoney: (map['totalTaxMoney'] as num?)?.toInt() ?? 0,
      totalNetMoney: (map['totalNetMoney'] as num?)?.toInt() ?? 0,
      paidMoney: (map['paidMoney'] as num?)?.toInt() ?? 0,
      debtMoney: (map['debtMoney'] as num?)?.toInt() ?? 0,
      note: map['note'] as String? ?? '',
      reason: map['reason'] as String?,
      createdBy: map['createdBy'] as String? ?? '',
      createdByName: map['createdByName'] as String? ?? '',
      completedBy: map['completedBy'] as String?,
      completedByName: map['completedByName'] as String?,
      createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
      completedAt: (map['completedAt'] as num?)?.toInt(),
      cancelledAt: (map['cancelledAt'] as num?)?.toInt(),
      cancelReason: map['cancelReason'] as String?,
      committedEventIds: List<String>.from(map['committedEventIds'] ?? []),
      idempotencyKey: map['idempotencyKey'] as String? ?? '',
      version: (map['version'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'documentId': documentId,
      'documentCode': documentCode,
      'docType': docType,
      'status': status,
      'branchId': branchId,
      'lines': lines.map((e) => e.toMap()).toList(),
      'totalQuantity': totalQuantity,
      'totalMoney': totalMoney,
      'globalDiscountMoney': globalDiscountMoney,
      'totalTaxMoney': totalTaxMoney,
      'totalNetMoney': totalNetMoney,
      'paidMoney': paidMoney,
      'debtMoney': debtMoney,
      'note': note,
      'createdBy': createdBy,
      'createdByName': createdByName,
      'createdAt': createdAt,
      'committedEventIds': committedEventIds,
      'idempotencyKey': idempotencyKey,
      'version': version,
    };
    if (warehouseId != null) map['warehouseId'] = warehouseId;
    if (supplierId != null) map['supplierId'] = supplierId;
    if (supplierName != null) map['supplierName'] = supplierName;
    if (sourceBranchId != null) map['sourceBranchId'] = sourceBranchId;
    if (destinationBranchId != null) map['destinationBranchId'] = destinationBranchId;
    if (sourceDocumentId != null) map['sourceDocumentId'] = sourceDocumentId;
    if (externalInvoiceNumber != null) map['externalInvoiceNumber'] = externalInvoiceNumber;
    if (externalInvoiceDate != null) map['externalInvoiceDate'] = externalInvoiceDate;
    if (reason != null) map['reason'] = reason;
    if (completedBy != null) map['completedBy'] = completedBy;
    if (completedByName != null) map['completedByName'] = completedByName;
    if (completedAt != null) map['completedAt'] = completedAt;
    if (cancelledAt != null) map['cancelledAt'] = cancelledAt;
    if (cancelReason != null) map['cancelReason'] = cancelReason;
    return map;
  }

  InventoryDocumentModel copyWith({
    String? documentId,
    String? documentCode,
    String? docType,
    String? status,
    String? branchId,
    String? warehouseId,
    String? supplierId,
    String? supplierName,
    String? sourceBranchId,
    String? destinationBranchId,
    String? sourceDocumentId,
    String? externalInvoiceNumber,
    String? externalInvoiceDate,
    List<InventoryDocLine>? lines,
    int? totalQuantity,
    int? totalMoney,
    int? globalDiscountMoney,
    int? totalTaxMoney,
    int? totalNetMoney,
    int? paidMoney,
    int? debtMoney,
    String? note,
    String? reason,
    String? createdBy,
    String? createdByName,
    String? completedBy,
    String? completedByName,
    int? createdAt,
    int? completedAt,
    int? cancelledAt,
    String? cancelReason,
    List<String>? committedEventIds,
    String? idempotencyKey,
    int? version,
  }) {
    return InventoryDocumentModel(
      documentId: documentId ?? this.documentId,
      documentCode: documentCode ?? this.documentCode,
      docType: docType ?? this.docType,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      warehouseId: warehouseId ?? this.warehouseId,
      supplierId: supplierId ?? this.supplierId,
      supplierName: supplierName ?? this.supplierName,
      sourceBranchId: sourceBranchId ?? this.sourceBranchId,
      destinationBranchId: destinationBranchId ?? this.destinationBranchId,
      sourceDocumentId: sourceDocumentId ?? this.sourceDocumentId,
      externalInvoiceNumber: externalInvoiceNumber ?? this.externalInvoiceNumber,
      externalInvoiceDate: externalInvoiceDate ?? this.externalInvoiceDate,
      lines: lines ?? this.lines,
      totalQuantity: totalQuantity ?? this.totalQuantity,
      totalMoney: totalMoney ?? this.totalMoney,
      globalDiscountMoney: globalDiscountMoney ?? this.globalDiscountMoney,
      totalTaxMoney: totalTaxMoney ?? this.totalTaxMoney,
      totalNetMoney: totalNetMoney ?? this.totalNetMoney,
      paidMoney: paidMoney ?? this.paidMoney,
      debtMoney: debtMoney ?? this.debtMoney,
      note: note ?? this.note,
      reason: reason ?? this.reason,
      createdBy: createdBy ?? this.createdBy,
      createdByName: createdByName ?? this.createdByName,
      completedBy: completedBy ?? this.completedBy,
      completedByName: completedByName ?? this.completedByName,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      committedEventIds: committedEventIds ?? this.committedEventIds,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      version: version ?? this.version,
    );
  }
}
