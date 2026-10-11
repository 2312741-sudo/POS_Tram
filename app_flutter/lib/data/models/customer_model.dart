// ==================== LOYALTY TIER ====================
/// Mốc hạng thành viên do Chủ quán tự đặt (storeInfo.loyaltyTiers), xét theo tổng điểm đã tích lũy.
class LoyaltyTier {
  final String name;
  final int minPoints;
  const LoyaltyTier(this.name, this.minPoints);

  /// Chưa cấu hình: chỉ có hạng gốc 0 điểm, các mốc do Chủ quán tự đặt.
  static const List<LoyaltyTier> defaults = [LoyaltyTier('Thành viên', 0)];

  /// Đọc mảng/map từ RTDB; sai định dạng → [defaults]. Kết quả sắp tăng dần, hạng thấp nhất luôn từ 0 điểm.
  static List<LoyaltyTier> parseList(Object? raw) {
    final Iterable<Object?> items = raw is List
        ? raw
        : raw is Map
            ? raw.values
            : const <Object?>[];
    final tiers = <LoyaltyTier>[];
    for (final item in items) {
      if (item is! Map) continue;
      final name = item['name']?.toString().trim() ?? '';
      final min = item['minPoints'];
      final minInt = min is num ? min.toInt() : int.tryParse(min?.toString() ?? '');
      if (name.isEmpty || minInt == null || minInt < 0) continue;
      tiers.add(LoyaltyTier(name, minInt));
    }
    if (tiers.isEmpty) return defaults;
    tiers.sort((a, b) => a.minPoints.compareTo(b.minPoints));
    if (tiers.first.minPoints > 0) tiers[0] = LoyaltyTier(tiers.first.name, 0);
    return tiers;
  }

  /// Hạng cao nhất mà [totalPoints] đạt được.
  static String nameFor(int totalPoints, List<LoyaltyTier> tiers) {
    final sorted = [...(tiers.isEmpty ? defaults : tiers)]..sort((a, b) => a.minPoints.compareTo(b.minPoints));
    var name = sorted.first.name;
    for (final t in sorted) {
      if (totalPoints >= t.minPoints) name = t.name;
    }
    return name;
  }
}

// ==================== KIOTVIET CUSTOMER LOYALTY MODEL ====================
class KmtCustomerModel {
  final String id;
  final String code; // Mã khách hàng KiotViet (KH000001...)
  final String name;
  final String phone;
  final String gender;
  final String birthday;
  int currentPoints; // Điểm tích lũy hiện tại
  int totalPoints;   // Tổng điểm lịch sử
  final int? createdAt;

  KmtCustomerModel({
    required this.id,
    this.code = '',
    String? name,
    String? fullName,
    required this.phone,
    this.gender = 'Khác',
    this.birthday = '',
    this.currentPoints = 0,
    this.totalPoints = 0,
    this.createdAt,
  }) : name = fullName ?? name ?? '';

  String get fullName => name;
  /// Hạng theo mốc của cửa hàng (xét tổng điểm tích lũy) — xem [LoyaltyTier].
  String tierName(List<LoyaltyTier> tiers) => LoyaltyTier.nameFor(totalPoints, tiers);

  factory KmtCustomerModel.fromMap(Map<dynamic, dynamic> map, String id) {
    // Parse createdAt timestamp or int
    int? createdTimestamp;
    final rawCreated = map['ngay_tao'] ?? map['ngayTao'] ?? map['createdAt'];
    if (rawCreated != null) {
      if (rawCreated is int) {
        createdTimestamp = rawCreated;
      } else if (rawCreated is num) {
        createdTimestamp = rawCreated.toInt();
      } else {
        try {
          createdTimestamp = DateTime.parse(rawCreated.toString()).millisecondsSinceEpoch;
        } catch (_) {}
      }
    }

    return KmtCustomerModel(
      id: id,
      code: map['ma_khach_hang']?.toString() ??
          map['maKhachHang']?.toString() ??
          map['code']?.toString() ??
          id,
      name: map['ho_ten']?.toString() ??
          map['hoTen']?.toString() ??
          map['name']?.toString() ??
          map['tenKhachHang']?.toString() ??
          '',
      phone: map['so_dien_thoai']?.toString() ??
          map['soDienThoai']?.toString() ??
          map['phone']?.toString() ??
          map['dienThoai']?.toString() ??
          '',
      gender: map['gioi_tinh']?.toString() ??
          map['gioiTinh']?.toString() ??
          map['gender']?.toString() ??
          'Khác',
      birthday: map['ngay_sinh']?.toString() ??
          map['ngaySinh']?.toString() ??
          map['birthday']?.toString() ??
          '',
      currentPoints: (map['diem_hien_tai'] as num?)?.toInt() ??
          (map['diemHienTai'] as num?)?.toInt() ??
          (map['currentPoints'] as num?)?.toInt() ??
          0,
      totalPoints: (map['tongDiem'] as num?)?.toInt() ??
          (map['totalPoints'] as num?)?.toInt() ??
          (map['diem_hien_tai'] as num?)?.toInt() ??
          (map['currentPoints'] as num?)?.toInt() ??
          0,
      createdAt: createdTimestamp,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'ma_khach_hang': code.isNotEmpty ? code : id,
    'code': code.isNotEmpty ? code : id,
    'ho_ten': name,
    'name': name,
    'so_dien_thoai': phone,
    'phone': phone,
    'gioi_tinh': gender,
    'gender': gender,
    'ngay_sinh': birthday,
    'birthday': birthday,
    'diem_hien_tai': currentPoints,
    'currentPoints': currentPoints,
    'totalPoints': totalPoints,
    'ho_ten_upper': name.toUpperCase(),
    'ngay_cap_nhat': DateTime.now().millisecondsSinceEpoch,
  };

  /// Hạng thành viên theo mốc mặc định (chưa cấu hình). Nên dùng [tierName] với mốc của cửa hàng.
  String get memberTier => tierName(LoyaltyTier.defaults);
}
