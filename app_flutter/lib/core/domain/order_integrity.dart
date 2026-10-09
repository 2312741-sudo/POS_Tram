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

// ==================== IDEMPOTENCY (VÒNG KHÓA TRONG NODE) ====================

/// Danh sách ngắn các khóa thao tác đã áp dụng, lưu NGAY TRONG node được transaction
/// (VD: stock_balances/{id}/recentSaleBills, customers/{id}/loyaltyOps).
/// Vì nằm cùng node với số liệu nên kiểm tra + ghi là nguyên tử → không bao giờ áp dụng 2 lần,
/// kể cả khi app bị tắt giữa lúc commit transaction và lúc ghi marker bên ngoài.
class IdempotencyRing {
  static const int defaultSize = 20;

  static List<String> read(Object? raw) {
    if (raw is List) return raw.where((e) => e != null).map((e) => e.toString()).toList();
    if (raw is Map) {
      // RTDB có thể trả mảng dưới dạng Map {"0": .., "1": ..}
      final keys = raw.keys.map((k) => k.toString()).toList()
        ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
      return keys.map((k) => raw[k]).where((e) => e != null).map((e) => e.toString()).toList();
    }
    return const [];
  }

  static bool contains(Object? raw, String key) => read(raw).contains(key);

  /// Thêm [key] vào cuối, bỏ trùng, giữ tối đa [max] phần tử mới nhất.
  static List<String> push(Object? raw, String key, {int max = defaultSize}) {
    final list = read(raw).where((e) => e != key).toList()..add(key);
    return list.length > max ? list.sublist(list.length - max) : list;
  }
}

// ==================== TÍCH / ĐỔI ĐIỂM KHÁCH HÀNG ====================

/// Khách không đủ điểm để đổi - chặn thanh toán TRƯỚC khi ghi hóa đơn.
class InsufficientPointsException implements Exception {
  final int requested;
  final int available;
  InsufficientPointsException(this.requested, this.available);
  @override
  String toString() => 'Khách chỉ còn $available điểm, không đủ để đổi $requested điểm';
}

/// Lỗi tích/đổi điểm khác (không tìm thấy khách...)
class LoyaltyException implements Exception {
  final String message;
  LoyaltyException(this.message);
  @override
  String toString() => message;
}

enum LoyaltyOp { redeem, award, refund }

enum LoyaltyTxnStatus { applied, alreadyApplied, insufficient, missingCustomer, nothingToRefund }

class LoyaltyTxnOutcome {
  final LoyaltyTxnStatus status;

  /// Giá trị mới cho customers/{id} (null nếu không ghi)
  final Map<String, dynamic>? next;
  final int before;
  final int after;
  final int points;
  LoyaltyTxnOutcome(this.status, {this.next, this.before = 0, this.after = 0, this.points = 0});
}

class LoyaltyMath {
  static const String ringField = 'loyaltyOps';

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Khóa thao tác (cũng là giá trị lastLoyaltyOp mà rules kiểm tra): "{billId}:{op}"
  static String opKey(String billId, LoyaltyOp op) => '$billId:${op.name}';

  static int pointsOf(Map m) {
    // Cùng thứ tự với database.rules.json (diem_hien_tai → currentPoints)
    for (final k in const ['diem_hien_tai', 'currentPoints']) {
      if (m[k] is num) return (m[k] as num).toInt();
    }
    return 0;
  }

  static int totalOf(Map m) {
    if (m['totalPoints'] is num) return (m['totalPoints'] as num).toInt();
    return pointsOf(m);
  }

  /// Số điểm tích cho hóa đơn: tiền thực trả × (rate%) / (đ/điểm), làm tròn.
  static int pointsToAward({required int billAmount, required double earnRatePercent, required int redeemRate}) {
    if (billAmount <= 0 || earnRatePercent <= 0 || redeemRate <= 0) return 0;
    final p = (billAmount * (earnRatePercent / 100) / redeemRate).round();
    return p > 0 ? p : 0;
  }

  /// Hàm thuần dùng trong runTransaction trên customers/{customerId}.
  static LoyaltyTxnOutcome apply(
    Object? current, {
    required String billId,
    required LoyaltyOp op,
    required int points,
    required int now,
    String? by,
  }) {
    if (current is! Map) return LoyaltyTxnOutcome(LoyaltyTxnStatus.missingCustomer);
    final m = Map<String, dynamic>.from(current);
    final key = opKey(billId, op);
    final before = pointsOf(m);
    final total = totalOf(m);
    if (IdempotencyRing.contains(m[ringField], key)) {
      return LoyaltyTxnOutcome(LoyaltyTxnStatus.alreadyApplied, before: before, after: before, points: points);
    }
    if (points <= 0) return LoyaltyTxnOutcome(LoyaltyTxnStatus.applied, before: before, after: before);

    int after;
    int applied = points;
    int newTotal = total;
    final lastRedeem = m['lastRedeem'];
    switch (op) {
      case LoyaltyOp.redeem:
        if (before < points) {
          return LoyaltyTxnOutcome(LoyaltyTxnStatus.insufficient, before: before, after: before, points: points);
        }
        after = before - points;
        m['lastRedeem'] = {'billId': billId, 'points': points};
        break;
      case LoyaltyOp.award:
        after = before + points;
        newTotal = total + points;
        break;
      case LoyaltyOp.refund:
        if (lastRedeem is! Map || lastRedeem['billId']?.toString() != billId) {
          return LoyaltyTxnOutcome(LoyaltyTxnStatus.nothingToRefund, before: before, after: before);
        }
        final held = _int(lastRedeem['points']);
        final refund = points < held ? points : held;
        if (refund <= 0) return LoyaltyTxnOutcome(LoyaltyTxnStatus.nothingToRefund, before: before, after: before);
        after = before + refund;
        applied = refund;
        m.remove('lastRedeem');
        break;
    }

    m['diem_hien_tai'] = after;
    m['currentPoints'] = after;
    m['totalPoints'] = newTotal;
    m['lastLoyaltyOp'] = key;
    m['lastLoyaltyBillId'] = billId;
    m['lastLoyaltyType'] = op.name;
    m['lastLoyaltyAt'] = now;
    if (by != null) m['lastLoyaltyBy'] = by;
    m['ngay_cap_nhat'] = now;
    m[ringField] = IdempotencyRing.push(m[ringField], key);
    return LoyaltyTxnOutcome(LoyaltyTxnStatus.applied, next: m, before: before, after: after, points: applied);
  }
}

// ==================== TRỪ KHO CÓ THỂ THỬ LẠI ====================

class StockRetryPlanner {
  /// Trường vòng khóa trong stock_balances/{id}
  static const String ringField = 'recentSaleBills';

  /// Khóa Firebase hợp lệ cho itemId (không chứa . # $ [ ] /)
  static String lineKey(String itemId) => itemId.replaceAll(RegExp(r'[.#$\[\]/]'), '_');

  /// Các dòng nguyên liệu CÒN PHẢI trừ: [planned] trừ đi các dòng đã có marker
  /// trong bill_stock_lines/{billId} ([doneRaw] = Map lineKey -> qty).
  static Map<String, int> remaining(Map<String, int> planned, Object? doneRaw) {
    final done = <String>{};
    if (doneRaw is Map) {
      for (final e in doneRaw.entries) {
        if (e.value != null) done.add(e.key.toString());
      }
    }
    return {
      for (final e in planned.entries)
        if (e.value != 0 && !done.contains(lineKey(e.key))) e.key: e.value,
    };
  }

  static bool isComplete(Map<String, int> planned, Object? doneRaw) => remaining(planned, doneRaw).isEmpty;

  /// Áp dụng trừ kho 1 lần cho [billId] trong transaction stock_balances/{id}.
  /// Trả về null nếu hóa đơn đã được trừ cho dòng này (có trong vòng khóa) → abort.
  static Map<String, dynamic>? applyConsumptionOnce(
    Object? current, {
    required String billId,
    required String balanceId,
    required String branchId,
    required String itemId,
    required int consumeQty,
    required int now,
  }) {
    if (current is Map && IdempotencyRing.contains(current[ringField], billId)) return null;
    final next = StockConsumptionPlanner.applyConsumption(
      current,
      balanceId: balanceId,
      branchId: branchId,
      itemId: itemId,
      consumeQty: consumeQty,
      now: now,
    );
    next[ringField] = IdempotencyRing.push(current is Map ? current[ringField] : null, billId);
    return next;
  }

  /// Kế hoạch lưu trong stock_retry_queue/{billId}/plan: danh sách {itemId, qty}
  static List<Map<String, dynamic>> encodePlan(Map<String, int> plan) =>
      [for (final e in plan.entries) {'itemId': e.key, 'qty': e.value}];

  static Map<String, int>? decodePlan(Object? raw) {
    final list = raw is List ? raw : (raw is Map ? raw.values.toList() : null);
    if (list == null) return null;
    final out = <String, int>{};
    for (final e in list) {
      if (e is! Map) continue;
      final id = e['itemId']?.toString() ?? '';
      final q = e['qty'];
      if (id.isEmpty || q is! num) continue;
      out[id] = (out[id] ?? 0) + q.toInt();
    }
    return out;
  }

  /// Vai trò được phép trừ kho / chạy hàng đợi thử lại (khớp rules: Thu ngân trở lên).
  static bool canRunRetry(String? roleId, {bool isRootOwner = false}) {
    if (isRootOwner) return true;
    const allowed = {
      'owner', 'ROLE_OWNER',
      'manager', 'manager_1', 'manager_2', 'ROLE_MANAGER', 'ROLE_MANAGER_1', 'ROLE_MANAGER_2',
      'cashier', 'ROLE_CASHIER', 'employee',
    };
    return allowed.contains(roleId);
  }
}
