// lib/data/services/pooled_loyalty_service.dart
//
// Điểm DÙNG CHUNG toàn hệ thống (Chủ quán xác nhận trên Web Admin: storeInfo.sharedLoyalty.enabled).
// POS chỉ ghi được node khách của chính chi nhánh (rules) nên việc lấy điểm từ chi nhánh khác
// chạy qua Cloud Function `pullPooledPoints` (Admin SDK): chuyển phần thiếu về node khách của chi nhánh bán,
// sau đó luồng đổi điểm cũ (LoyaltyService.redeemForBill) chạy bình thường.
import 'package:cloud_functions/cloud_functions.dart';

class PooledLoyaltyService {
  static const String _region = 'asia-southeast1';
  static FirebaseFunctions? _functionsMock;

  static void setFunctionsMock(FirebaseFunctions? mock) => _functionsMock = mock;

  static FirebaseFunctions get _functions => _functionsMock ?? FirebaseFunctions.instanceFor(region: _region);

  static Future<Map<String, dynamic>> _call(Map<String, dynamic> data, Duration timeout) async {
    final callable = _functions.httpsCallable('pullPooledPoints', options: HttpsCallableOptions(timeout: timeout));
    final res = await callable.call<dynamic>(data);
    final raw = res.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// Tổng điểm của khách (cùng SĐT) ở CÁC chi nhánh khác. Ném [FirebaseFunctionsException] khi lỗi
  /// (vd. failed-precondition: chưa bật dùng chung / khách chưa có SĐT).
  static Future<int> othersPoints({
    required String storeCode,
    required String customerId,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final data = await _call({'storeCode': storeCode, 'customerId': customerId, 'balanceOnly': true}, timeout);
    return (data['othersPoints'] as num?)?.toInt() ?? 0;
  }

  /// Kéo [points] điểm từ chi nhánh khác về chi nhánh [storeCode] cho hóa đơn [billId] (idempotent theo hóa đơn).
  /// Trả về số điểm đã chuyển (0 nếu hóa đơn này đã kéo trước đó).
  static Future<int> pull({
    required String storeCode,
    required String customerId,
    required String billId,
    required int points,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final data = await _call({'storeCode': storeCode, 'customerId': customerId, 'billId': billId, 'points': points}, timeout);
    return (data['pulled'] as num?)?.toInt() ?? 0;
  }

  /// Số điểm cần kéo để đủ [needed], biết khách đang có [local] điểm ở chi nhánh.
  static int shortfall({required int needed, required int local}) => needed > local ? needed - local : 0;
}
