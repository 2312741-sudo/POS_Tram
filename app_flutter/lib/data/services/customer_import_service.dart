// lib/data/services/customer_import_service.dart
//
// Nhập khách hàng chỉ có trên Firestore (kmt_customers) vào RTDB stores/{s}/customers/{id}
// qua Cloud Function `importCustomerToStore` (Admin SDK, số dư thật, idempotent, có audit log).
// Client KHÔNG tự sao chép nữa: rules chỉ cho Thu ngân tạo khách mới với 0 điểm.
import 'package:cloud_functions/cloud_functions.dart';

class CustomerImportResult {
  /// true nếu lần gọi này thực sự tạo node RTDB (false: đã có sẵn)
  final bool created;
  final int currentPoints;
  const CustomerImportResult({required this.created, required this.currentPoints});
}

class CustomerImportService {
  static const String _region = 'asia-southeast1';
  static FirebaseFunctions? _functionsMock;

  static void setFunctionsMock(FirebaseFunctions? mock) => _functionsMock = mock;

  static FirebaseFunctions get _functions => _functionsMock ?? FirebaseFunctions.instanceFor(region: _region);

  /// Ném [FirebaseFunctionsException] (vd. not-found, permission-denied) khi thất bại.
  static Future<CustomerImportResult> importToStore({
    required String storeCode,
    required String customerId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final callable = _functions.httpsCallable(
      'importCustomerToStore',
      options: HttpsCallableOptions(timeout: timeout),
    );
    final res = await callable.call<dynamic>({'storeCode': storeCode, 'customerId': customerId});
    final raw = res.data;
    final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return CustomerImportResult(
      created: data['created'] == true,
      currentPoints: (data['currentPoints'] as num?)?.toInt() ?? 0,
    );
  }
}
