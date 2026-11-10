// lib/core/domain/order_merge.dart
//
// GỘP ĐƠN KHI NHIỀU MÁY CÙNG SỬA MỘT BÀN.
//
// Trước đây mỗi lần lưu bàn ghi đè cả currentOrderJson bằng giỏ hàng của máy đang lưu → 2 người cùng gọi món
// cho một bàn thì người lưu sau xóa mất món người lưu trước vừa thêm.
//
// Nay mỗi máy nhớ bản đơn nó đã đọc từ server (base). Khi lưu, chỉ những gì MÁY NÀY đổi so với base
// (thêm dòng / xóa dòng / đổi số lượng / đổi ghi chú, giảm giá...) được áp lên bản MỚI NHẤT trên server
// (trong transaction), nên thay đổi của máy khác được giữ nguyên.
//  - Dòng món nhận diện bằng OrderItemModel.lineKey (dữ liệu cũ: mã suy ra, trùng thì thêm #2, #3...).
//  - Số lượng gộp theo CHÊNH LỆCH: máy này +1, máy kia +2 → server +3.
//  - Trường khác: trường nào máy này đổi thì lấy giá trị của máy này, còn lại giữ của server.
//  - Dòng máy này xóa → xóa trên server; dòng máy khác đã xóa mà máy này không đổi → vẫn xóa.
import 'dart:convert';
import '../../data/models/order_item_model.dart';

class OrderMerge {
  OrderMerge._();

  static List<OrderItemModel> _parse(String json) {
    if (json.trim().isEmpty) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      return [for (final e in raw) if (e is Map) OrderItemModel.fromMap(e)];
    } catch (_) {
      return const [];
    }
  }

  /// Dòng món kèm mã (mã trùng trong cùng đơn → thêm #2, #3 theo thứ tự để hai bên tách giống nhau)
  static List<MapEntry<String, Map<String, dynamic>>> _keyed(String json) {
    final seen = <String, int>{};
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    for (final it in _parse(json)) {
      final n = (seen[it.lineKey] ?? 0) + 1;
      seen[it.lineKey] = n;
      final key = n == 1 ? it.lineKey : '${it.lineKey}#$n';
      final m = it.toMap();
      m['lineKey'] = key;
      out.add(MapEntry(key, m));
    }
    return out;
  }

  static bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

  static int _qty(Map<String, dynamic> m) => (m['quantity'] as num?)?.toInt() ?? 1;

  /// Gộp đơn: [base] = bản máy này đã đọc, [local] = bản máy này muốn lưu, [server] = bản mới nhất trên server.
  static String mergeJson({required String base, required String local, required String server}) {
    if (local == base) return server; // máy này không đổi món → giữ nguyên server
    if (server == base) return local; // không ai khác đổi → bản của máy này

    final baseMap = {for (final e in _keyed(base)) e.key: e.value};
    final localList = _keyed(local);
    final localKeys = {for (final e in localList) e.key};
    // Giữ thứ tự của server, dòng mới của máy này nối vào cuối
    final result = <String, Map<String, dynamic>>{for (final e in _keyed(server)) e.key: e.value};

    // Bản app cũ / web ghi lại đơn có thể làm mất mã dòng → dòng trên server mang mã khác. Khi không thấy theo mã,
    // tìm dòng "giống hệt về nhận diện" (món + giờ gọi + tùy chọn) chưa thuộc về dòng nào máy này biết.
    String? locate(String k, Map<String, dynamic> baseLine) {
      if (result.containsKey(k)) return k;
      final sig = _signature(baseLine);
      for (final e in result.entries) {
        if (baseMap.containsKey(e.key) || localKeys.contains(e.key)) continue;
        if (_signature(e.value) == sig) return e.key;
      }
      return null;
    }

    // Dòng máy này đã xóa
    for (final e in baseMap.entries) {
      if (localKeys.contains(e.key)) continue;
      final at = locate(e.key, e.value);
      if (at != null) result.remove(at);
    }

    for (final e in localList) {
      final k = e.key;
      final l = e.value;
      final b = baseMap[k];
      if (b == null) {
        // Dòng mới của máy này
        result[k] = l;
        continue;
      }
      if (_same(l, b)) continue; // máy này không đổi dòng này
      final at = locate(k, b);
      if (at == null) continue; // máy khác đã xóa dòng này → tôn trọng
      final r = result[at]!;
      final merged = Map<String, dynamic>.from(r);
      for (final f in {...l.keys, ...b.keys}) {
        if (f == 'lineKey' || _same(l[f], b[f])) continue;
        if (l.containsKey(f)) {
          merged[f] = l[f];
        } else {
          merged.remove(f);
        }
      }
      final qty = _qty(r) + (_qty(l) - _qty(b));
      if (qty <= 0) {
        result.remove(at);
        continue;
      }
      merged['quantity'] = qty;
      // Chuẩn hóa (chặn số phần giảm giá theo số lượng mới, tính lại tổng giảm của dòng)
      result[at] = OrderItemModel.fromMap(merged).toMap()..['lineKey'] = at;
    }
    return jsonEncode(result.values.toList());
  }

  static String _signature(Map<String, dynamic> m) {
    final it = OrderItemModel.fromMap(m);
    return OrderItemModel.legacyLineKey(
      productId: it.productId,
      name: it.name,
      orderedAt: it.orderedAt,
      size: it.selectedSize,
      sugar: it.selectedSugar,
      ice: it.selectedIce,
      toppings: it.selectedToppings,
      rewardCampaignId: it.rewardCampaignId,
    );
  }

  /// Đơn trên server có khác bản máy này đã đọc không (so nội dung từng dòng, bỏ qua mã dòng / định dạng)
  static bool differs(String a, String b) {
    if (a == b) return false;
    List<String> norm(String j) => [
          for (final it in _parse(j)) jsonEncode((it.toMap()..remove('lineKey'))),
        ]..sort();
    final x = norm(a), y = norm(b);
    if (x.length != y.length) return true;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return true;
    }
    return false;
  }

  /// Hợp hai danh sách JSON chỉ-thêm (nhật ký thao tác, món đã xóa): giữ bản server, nối phần máy này mới có
  static String? unionJsonLists(Object? serverJson, Object? localJson) {
    List<dynamic> parse(Object? v) {
      if (v is! String || v.trim().isEmpty) return const [];
      try {
        final d = jsonDecode(v);
        return d is List ? d : const [];
      } catch (_) {
        return const [];
      }
    }

    final s = parse(serverJson);
    final l = parse(localJson);
    if (s.isEmpty && l.isEmpty) return (localJson is String && localJson.isNotEmpty) ? localJson : null;
    final seen = {for (final e in s) jsonEncode(e)};
    final out = [...s, for (final e in l) if (seen.add(jsonEncode(e))) e];
    return jsonEncode(out);
  }
}
