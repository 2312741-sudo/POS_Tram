// lib/features/crm/customer_delete_service.dart
import 'package:cloud_functions/cloud_functions.dart';

/// Từ khóa xác nhận xóa khách hàng.
const String kDeleteCustomerConfirm = 'XOA';

/// Người dùng đã gõ đúng từ khóa xác nhận chưa (không phân biệt hoa thường, bỏ khoảng trắng đầu/cuối).
bool isDeleteCustomerConfirmed(String input) => input.trim().toUpperCase() == kDeleteCustomerConfirm;

/// Thông báo sau khi xóa thành công.
String deleteCustomerSuccessMessage({required bool removedMember}) => removedMember
    ? 'Đã xóa khách hàng và toàn bộ điểm tích lũy.'
    : 'Đã xóa khách hàng khỏi chi nhánh này. Điểm được giữ vì khách còn ở chi nhánh khác.';

class CustomerDeleteException implements Exception {
  const CustomerDeleteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Gọi Cloud Function `deleteCustomer` (chỉ Chủ quán / Quản lý). Trả về removedMember.
class CustomerDeleteService {
  CustomerDeleteService({FirebaseFunctions? functions}) : _functionsOverride = functions;

  final FirebaseFunctions? _functionsOverride;
  FirebaseFunctions get _functions => _functionsOverride ?? FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  Future<bool> deleteCustomer({required String storeCode, required String customerId}) async {
    try {
      final callable = _functions.httpsCallable(
        'deleteCustomer',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final res = await callable.call<dynamic>({
        'storeCode': storeCode,
        'customerId': customerId,
        'confirm': kDeleteCustomerConfirm,
      });
      final data = res.data;
      return data is Map && data['removedMember'] == true;
    } on FirebaseFunctionsException catch (e) {
      throw CustomerDeleteException(e.message ?? 'Không thể xóa khách hàng. Vui lòng thử lại.');
    } catch (_) {
      throw const CustomerDeleteException('Không thể kết nối đến máy chủ. Vui lòng thử lại.');
    }
  }
}
