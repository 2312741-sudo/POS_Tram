// lib/core/domain/order_integrity.dart
//
// Logic thuần (không phụ thuộc Firebase) phục vụ toàn vẹn dữ liệu đơn hàng:
// - Sinh mã hóa đơn tuần tự / dự phòng
// - Gộp dòng món khi ghép bàn (chỉ gộp các dòng cấu hình giống hệt nhau)
// - Tính toán bộ đếm khuyến mãi có kiểm tra giới hạn (dùng trong transaction)
// - Lập kế hoạch trừ kho theo công thức (kể cả topping)
// - Dựng bản ghi hóa đơn đầy đủ cho bills/ và history/
import 'dart:convert';
import 'dart:math';

import '../../data/models/bill_model.dart';
import '../../data/models/inventory_models.dart';
import '../../data/models/order_item_model.dart';
import 'stock_engine.dart';

// ==================== EXCEPTIONS ====================

/// Lỗi ghi dữ liệu quan trọng (hóa đơn, bàn, đơn bếp) lên server.
class DataWriteException implements Exception {
  final String message;
  final Object? cause;
  DataWriteException(this.message, [this.cause]);
  @override
  String toString() => message;
}

/// Khuyến mãi / voucher đã vượt giới hạn sử dụng (lượt, ngân sách, mỗi khách...)
class PromotionLimitExceededException implements Exception {
  final String message;
  PromotionLimitExceededException(this.message);
  @override
  String toString() => message;
}

// ==================== MÃ HÓA ĐƠN ====================

class BillCodeGenerator {
  /// Mã tuần tự chính thức: HD-yyMMdd-NNNN (4+ chữ số)
  static final RegExp _sequentialPattern = RegExp(r'^[A-Z]+-\d{6}-\d{4,}$');

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Khóa ngày dùng cho bộ đếm counters/bill_seq/{yyMMdd}
  static String dayKey(DateTime at) => '${_two(at.year % 100)}${_two(at.month)}${_two(at.day)}';

  /// HD-yyMMdd-0001
  static String sequential(int seq, {required DateTime at, String prefix = 'HD'}) {
    return '$prefix-${dayKey(at)}-${seq.toString().padLeft(4, '0')}';
  }

  /// Mã dự phòng khi offline / transaction lỗi: HD-yyMMdd-HHmmss-XXXX (hậu tố ngẫu nhiên)
  /// Có thêm 1 đoạn nên không bao giờ trùng định dạng với mã tuần tự.
  static String fallback({required DateTime at, Random? random, String prefix = 'HD'}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = random ?? Random.secure();
    final suffix = List.generate(4, (_) => chars[rnd.nextInt(chars.length)]).join();
    final time = '${_two(at.hour)}${_two(at.minute)}${_two(at.second)}';
    return '$prefix-${dayKey(at)}-$time-$suffix';
  }

  static bool isSequential(String code) => _sequentialPattern.hasMatch(code);
}

// ==================== GỘP DÒNG MÓN ====================

class OrderLineMerger {
  /// Khóa cấu hình dòng món: chỉ các dòng có khóa giống nhau mới được cộng dồn số lượng.
  /// Cấu hình giảm giá dòng (chế độ, %/đơn giá giảm mỗi phần, lý do) là một phần của khóa:
  /// dòng có giảm giá khác nhau (kể cả có/không giảm) luôn là các dòng khác nhau.
  static String lineKey(OrderItemModel i) {
    final toppings = [...i.selectedToppings]..sort();
    return jsonEncode([
      i.productId,
      i.price,
      i.selectedSize,
      i.sizeExtraPrice,
      i.selectedSugar,
      i.selectedIce,
      toppings,
      i.toppingPrice,
      i.note.trim(),
      i.discountMode,
      i.discountPercent,
      i.discountUnitAmount,
      i.discountReason,
      i.isSentKitchen,
    ]);
  }

  /// Gộp [source] vào [target]. Không làm thay đổi 2 danh sách đầu vào.
  static List<OrderItemModel> merge(List<OrderItemModel> target, List<OrderItemModel> source) {
    final result = target.map((e) => e.copyWith()).toList();
    final index = <String, int>{};
    for (int i = 0; i < result.length; i++) {
      index.putIfAbsent(lineKey(result[i]), () => i);
    }
    for (final item in source) {
      final key = lineKey(item);
      final idx = index[key];
      if (idx != null) {
        final existing = result[idx];
        // Cộng dồn số phần được giảm và tổng giảm đã lưu (không tính lại) để
        // tổng tiền sau gộp đúng bằng tổng 2 dòng trước gộp.
        result[idx] = existing.copyWith(
          quantity: existing.quantity + item.quantity,
          discountedQuantity: existing.discountedQuantity + item.discountedQuantity,
          discountAmount: existing.lineDiscountTotal + item.lineDiscountTotal,
        );
      } else {
        result.add(item.copyWith());
        index[key] = result.length - 1;
      }
    }
    return result;
  }
}

// ==================== BỘ ĐẾM KHUYẾN MÃI ====================

class PromotionUsageMath {
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Tính giá trị mới cho campaign_counters/{id}. Trả về null nếu vượt giới hạn
  /// (chỉ kiểm tra khi delta dương; giới hạn null hoặc <= 0 = không giới hạn).
  static Map<String, dynamic>? applyCampaignUsage(
    Object? current, {
    required String campaignId,
    required int spentDelta,
    required int useDelta,
    int? maxUses,
    int? budgetMoney,
  }) {
    final data = current is Map ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    final spent = _int(data['spentMoney']) + spentDelta;
    final uses = _int(data['committedUseCount']) + useDelta;
    if (useDelta > 0 && maxUses != null && maxUses > 0 && uses > maxUses) return null;
    if (spentDelta > 0 && budgetMoney != null && budgetMoney > 0 && spent > budgetMoney) return null;
    return {
      ...data,
      'campaignId': campaignId,
      'spentMoney': spent < 0 ? 0 : spent,
      'reservedMoney': _int(data['reservedMoney']),
      'committedUseCount': uses < 0 ? 0 : uses,
      'reservedUseCount': _int(data['reservedUseCount']),
      'version': _int(data['version']) + 1,
    };
  }

  /// customer_campaign_counters/{campaignId_customerId}. Null nếu vượt giới hạn/khách.
  static Map<String, dynamic>? applyCustomerUsage(
    Object? current, {
    required String campaignId,
    required String customerId,
    required int delta,
    int? maxUsesPerCustomer,
  }) {
    final data = current is Map ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    final used = _int(data['usedCount']) + delta;
    if (delta > 0 && maxUsesPerCustomer != null && maxUsesPerCustomer > 0 && used > maxUsesPerCustomer) {
      return null;
    }
    return {
      ...data,
      'campaignId': campaignId,
      'customerId': customerId,
      'usedCount': used < 0 ? 0 : used,
      'heldCount': _int(data['heldCount']),
    };
  }

  /// Khuyến mãi cũ (promotions/{id}): trả về usageCount mới hoặc null nếu vượt maxUsage.
  static int? applyLegacyUsage(Object? currentCount, {int delta = 1, int maxUsage = 0}) {
    final next = _int(currentCount) + delta;
    if (delta > 0 && maxUsage > 0 && next > maxUsage) return null;
    return next < 0 ? 0 : next;
  }
}

// ==================== KẾ HOẠCH TRỪ KHO ====================

/// Một dòng bán hàng cần trừ kho
class StockSaleLine {
  final int productId;
  final int quantity;
  final String size;
  final List<String> toppings;

  StockSaleLine({required this.productId, required this.quantity, this.size = '', this.toppings = const []});

  /// Hỗ trợ cả OrderItemModel và Map (khóa 'productId' hoặc 'product_id' cũ)
  static StockSaleLine? from(dynamic raw) {
    if (raw is OrderItemModel) {
      return StockSaleLine(
        productId: raw.productId,
        quantity: raw.quantity,
        size: raw.selectedSize,
        toppings: raw.selectedToppings,
      );
    }
    if (raw is Map) {
      final pid = (raw['productId'] as num?)?.toInt() ?? (raw['product_id'] as num?)?.toInt() ?? (raw['id'] as num?)?.toInt();
      if (pid == null) return null;
      return StockSaleLine(
        productId: pid,
        quantity: (raw['quantity'] as num?)?.toInt() ?? 1,
        size: raw['selectedSize']?.toString() ?? '',
        toppings: raw['selectedToppings'] is List ? List<String>.from((raw['selectedToppings'] as List).map((e) => e.toString())) : const [],
      );
    }
    return null;
  }
}

class StockConsumptionPlan {
  /// itemId nguyên liệu -> số lượng (đơn vị cơ bản) cần trừ
  final Map<String, int> qtyByItem;

  /// Món / topping không tìm thấy công thức (không trừ kho)
  final List<String> unmapped;

  StockConsumptionPlan(this.qtyByItem, this.unmapped);
}

class StockConsumptionPlanner {
  static String normalizeName(String s) => s.trim().toLowerCase();

  /// Chọn công thức đang hiệu lực cho thành phẩm, ưu tiên đúng size, rồi công thức không size.
  static RecipeVersionModel? pickRecipe(
    List<RecipeVersionModel> recipes,
    String outputItemId, {
    String size = '',
    String? branchId,
  }) {
    final candidates = recipes.where((r) =>
        r.outputItemId == outputItemId &&
        r.status == 'ACTIVE' &&
        (r.branchScope == null || r.branchScope!.isEmpty || branchId == null || r.branchScope == branchId)).toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      final v = b.version.compareTo(a.version);
      return v != 0 ? v : b.effectiveFrom.compareTo(a.effectiveFrom);
    });
    final s = normalizeName(size);
    if (s.isNotEmpty) {
      final bySize = candidates.where((r) => normalizeName(r.outputVariant ?? '') == s);
      if (bySize.isNotEmpty) return bySize.first;
    }
    final noVariant = candidates.where((r) => (r.outputVariant ?? '').isEmpty);
    if (noVariant.isNotEmpty) return noVariant.first;
    return candidates.first;
  }

  /// [catalogIdByLegacyProductId]: legacyProductId -> catalog itemId
  /// [catalogIdByName]: tên (đã normalize) -> catalog itemId (dùng cho topping)
  static StockConsumptionPlan plan({
    required List<StockSaleLine> lines,
    required List<RecipeVersionModel> recipes,
    required Map<int, String> catalogIdByLegacyProductId,
    required Map<String, String> catalogIdByName,
    String? branchId,
  }) {
    final qty = <String, int>{};
    final unmapped = <String>[];

    void addRecipe(RecipeVersionModel r, int count) {
      StockEngine.calculateRecipeConsumption(recipe: r, quantity: count).forEach((k, v) {
        if (v != 0) qty[k] = (qty[k] ?? 0) + v;
      });
    }

    for (final line in lines) {
      if (line.quantity <= 0) continue;
      final itemId = catalogIdByLegacyProductId[line.productId] ?? line.productId.toString();
      final recipe = pickRecipe(recipes, itemId, size: line.size, branchId: branchId);
      if (recipe != null) {
        addRecipe(recipe, line.quantity);
      } else {
        unmapped.add('product:${line.productId}');
      }
      for (final topping in line.toppings) {
        final tId = catalogIdByName[normalizeName(topping)];
        final tRecipe = tId == null ? null : pickRecipe(recipes, tId, branchId: branchId);
        if (tRecipe != null) {
          addRecipe(tRecipe, line.quantity);
        } else {
          unmapped.add('topping:$topping');
        }
      }
    }
    return StockConsumptionPlan(qty, unmapped);
  }

  /// Giá trị mới cho stock_balances/{balanceId} khi xuất [consumeQty] (dùng trong transaction).
  static Map<String, dynamic> applyConsumption(
    Object? current, {
    required String balanceId,
    required String branchId,
    required String itemId,
    required int consumeQty,
    required int now,
  }) {
    int toInt(Object? v) => v is num ? v.toInt() : 0;
    final data = current is Map ? Map<String, dynamic>.from(current) : <String, dynamic>{};
    final avg = toInt(data['averageCostScaled']);
    final valueDelta = avg > 0 ? -((consumeQty * avg) / 100).round() : 0;
    return {
      ...data,
      'balanceId': data['balanceId'] ?? balanceId,
      'branchId': data['branchId'] ?? branchId,
      'itemId': data['itemId'] ?? itemId,
      'onHandQty': toInt(data['onHandQty']) - consumeQty,
      'reservedQty': toInt(data['reservedQty']),
      'inventoryValue': toInt(data['inventoryValue']) + valueDelta,
      'averageCostScaled': avg,
      'lastEventSeq': toInt(data['lastEventSeq']),
      'updatedAt': now,
      'version': toInt(data['version']) + 1,
    };
  }
}

// ==================== BẢN GHI HÓA ĐƠN ====================

class BillRecordBuilder {
  /// Bản ghi đầy đủ ghi vào cả bills/{id} và history/{id}: toàn bộ BillModel.toMap()
  /// cộng các trường mà web admin đọc (storeCode, storeName, totalAmount, discountAmount,
  /// timestamp, itemsJson, guestCount).
  static Map<String, dynamic> build(
    BillModel bill, {
    required String storeCode,
    required String storeName,
    int? guestCount,
    Map<String, dynamic> extra = const {},
  }) {
    final base = bill.toMap();
    return {
      ...base,
      'storeCode': storeCode,
      'storeName': storeName,
      'orderCode': bill.orderCode ?? bill.billCode,
      'totalAmount': bill.finalAmount,
      'discountAmount': bill.totalDiscount,
      'timestamp': bill.closedAt ?? bill.createdAt,
      'itemsJson': jsonEncode(base['items']),
      if (guestCount != null && guestCount > 0) 'guestCount': guestCount,
      ...extra,
    };
  }
}
