// lib/data/models/staff_call_model.dart
// Bếp "Gọi nhân viên": stores/{code}/staff_calls/{id}. Mọi trường ngoài createdAt đều tùy chọn.
class StaffCallModel {
  final String? firebaseKey;
  final String message;
  final String fromName;
  final String? fromUsername;
  final int createdAt;
  final int? ackAt;
  final String? ackBy;

  const StaffCallModel({
    this.firebaseKey,
    this.message = '',
    this.fromName = '',
    this.fromUsername,
    required this.createdAt,
    this.ackAt,
    this.ackBy,
  });

  bool get acknowledged => ackAt != null;

  factory StaffCallModel.fromMap(Map<dynamic, dynamic> map, {String? key}) => StaffCallModel(
        firebaseKey: key,
        message: map['message']?.toString() ?? '',
        fromName: map['fromName']?.toString() ?? '',
        fromUsername: map['fromUsername']?.toString(),
        createdAt: (map['createdAt'] as num?)?.toInt() ?? 0,
        ackAt: (map['ackAt'] as num?)?.toInt(),
        ackBy: map['ackBy']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'message': message,
        'fromName': fromName,
        if (fromUsername != null) 'fromUsername': fromUsername,
        'createdAt': createdAt,
      };
}
