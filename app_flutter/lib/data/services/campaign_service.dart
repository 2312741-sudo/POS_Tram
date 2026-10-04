import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import '../../data/models/campaign_models.dart';
import '../../core/services/auth_service.dart';

/// Dịch vụ quản lý Chương trình khuyến mãi & Voucher
class CampaignService {
  static final CampaignService _instance = CampaignService._internal();
  factory CampaignService() => _instance;
  CampaignService._internal();

  final _db = FirebaseDatabase.instance;
  String? _manualStoreCode;
  
  String get _currentStoreCode {
    if (_manualStoreCode != null && _manualStoreCode!.isNotEmpty) {
      return _manualStoreCode!;
    }
    try {
      final code = AuthService().currentStoreCode;
      if (code.isNotEmpty) return code;
    } catch (_) {}
    return 'TRAM01';
  }
  
  DatabaseReference get _storeRef => _db.ref('stores/$_currentStoreCode');
  
  void switchStore(String storeCode) {
    _manualStoreCode = storeCode;
  }

  // ==================== CAMPAIGNS CRUD ====================

  /// Stream danh sách khuyến mãi, sắp xếp theo độ ưu tiên
  Stream<List<CampaignModel>> campaignsStream() {
    return _storeRef.child('campaigns').onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      final list = map.values
          .map((e) => CampaignModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
      
      list.sort((a, b) {
        int cmp = a.priority.compareTo(b.priority);
        if (cmp != 0) return cmp;
        return a.createdAt.compareTo(b.createdAt);
      });
      return list;
    });
  }

  /// Lấy danh sách khuyến mãi 1 lần
  Future<List<CampaignModel>> getCampaigns() async {
    final snapshot = await _storeRef.child('campaigns').get();
    if (snapshot.value == null) return [];
    final Map<dynamic, dynamic> map = snapshot.value as Map<dynamic, dynamic>;
    final list = map.values
        .map((e) => CampaignModel.fromMap(Map<String, dynamic>.from(e)))
        .toList();
    
    list.sort((a, b) {
      int cmp = a.priority.compareTo(b.priority);
      if (cmp != 0) return cmp;
      return a.createdAt.compareTo(b.createdAt);
    });
    return list;
  }

  /// Lấy thông tin 1 khuyến mãi theo ID
  Future<CampaignModel?> getCampaign(String campaignId) async {
    final snapshot = await _storeRef.child('campaigns/$campaignId').get();
    if (snapshot.value == null) return null;
    return CampaignModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Tạo hoặc cập nhật khuyến mãi
  Future<void> saveCampaign(CampaignModel campaign) async {
    await _storeRef.child('campaigns/${campaign.campaignId}').set(campaign.toMap());
  }

  /// Xóa mềm khuyến mãi (chỉ set active = false, không xóa hẳn)
  Future<void> deleteCampaign(String campaignId) async {
    final campaign = await getCampaign(campaignId);
    if (campaign != null) {
      final updated = campaign.copyWith(active: false);
      await saveCampaign(updated);
    }
  }

  /// Bật/Tắt khuyến mãi
  Future<void> toggleCampaignActive(String campaignId, bool active) async {
    final campaign = await getCampaign(campaignId);
    if (campaign != null) {
      final updated = campaign.copyWith(active: active);
      await saveCampaign(updated);
    }
  }

  /// Tạo ID campaign mới
  String generateCampaignId() {
    return 'CAM_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000).toString().padLeft(4, '0')}';
  }

  /// Tạo mã code chương trình hiển thị
  String generateProgramCode(int sequence) {
    return 'KM${sequence.toString().padLeft(4, '0')}';
  }

  // ==================== CAMPAIGN COUNTERS ====================

  /// Stream thống kê lượt dùng/ngân sách của khuyến mãi
  Stream<CampaignCountersModel?> campaignCountersStream(String campaignId) {
    return _storeRef.child('campaign_counters/$campaignId').onValue.map((event) {
      if (event.snapshot.value == null) return null;
      return CampaignCountersModel.fromMap(Map<String, dynamic>.from(event.snapshot.value as Map<dynamic, dynamic>));
    });
  }

  /// Lấy thống kê hiện tại (trả về 0 nếu chưa có)
  Future<CampaignCountersModel> getCampaignCounters(String campaignId) async {
    final snapshot = await _storeRef.child('campaign_counters/$campaignId').get();
    if (snapshot.value == null) {
      return CampaignCountersModel(
        campaignId: campaignId,
        spentMoney: 0,
        reservedMoney: 0,
        committedUseCount: 0,
        reservedUseCount: 0,
        version: 1,
      );
    }
    return CampaignCountersModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Cập nhật atomics bộ đếm khuyến mãi
  Future<void> _updateCampaignCounters(String campaignId, {int spentDelta = 0, int useDelta = 0}) async {
    final ref = _storeRef.child('campaign_counters/$campaignId');
    await ref.runTransaction((Object? postData) {
      if (postData == null) {
        return Transaction.success({
          'campaignId': campaignId,
          'spentMoney': spentDelta,
          'reservedMoney': 0,
          'committedUseCount': useDelta,
          'reservedUseCount': 0,
          'version': 1,
        });
      }
      
      Map<dynamic, dynamic> data = postData as Map<dynamic, dynamic>;
      data['spentMoney'] = (data['spentMoney'] as int? ?? 0) + spentDelta;
      data['committedUseCount'] = (data['committedUseCount'] as int? ?? 0) + useDelta;
      data['version'] = (data['version'] as int? ?? 0) + 1;
      
      return Transaction.success(data);
    });
  }

  // ==================== CUSTOMER CAMPAIGN COUNTERS ====================

  /// Lấy số lần khách hàng đã dùng khuyến mãi này
  Future<CustomerCampaignCounterModel> getCustomerCounter(String campaignId, String customerId) async {
    final key = '${campaignId}_$customerId';
    final snapshot = await _storeRef.child('customer_campaign_counters/$key').get();
    if (snapshot.value == null) {
      return CustomerCampaignCounterModel(
        campaignId: campaignId,
        customerId: customerId,
        usedCount: 0,
        heldCount: 0,
      );
    }
    return CustomerCampaignCounterModel.fromMap(Map<String, dynamic>.from(snapshot.value as Map<dynamic, dynamic>));
  }

  /// Tăng số lượt dùng của khách hàng
  Future<void> _incrementCustomerCounter(String campaignId, String customerId) async {
    final key = '${campaignId}_$customerId';
    final ref = _storeRef.child('customer_campaign_counters/$key');
    await ref.runTransaction((Object? postData) {
      if (postData == null) {
        return Transaction.success({
          'campaignId': campaignId,
          'customerId': customerId,
          'usedCount': 1,
          'heldCount': 0,
        });
      }
      
      Map<dynamic, dynamic> data = postData as Map<dynamic, dynamic>;
      data['usedCount'] = (data['usedCount'] as int? ?? 0) + 1;
      
      return Transaction.success(data);
    });
  }

  // ==================== VOUCHERS ====================

  /// Stream danh sách vouchers của 1 campaign
  Stream<List<VoucherModel>> vouchersStream(String campaignId) {
    return _storeRef.child('vouchers/$campaignId').onValue.map((event) {
      if (event.snapshot.value == null) return [];
      final Map<dynamic, dynamic> map = event.snapshot.value as Map<dynamic, dynamic>;
      return map.values
          .map((e) => VoucherModel.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    });
  }

  /// Tạo danh sách voucher - mặc định tự động RELEASED để sử dụng được ngay
  Future<void> createVouchers(String campaignId, List<String> codes, {bool autoRelease = true}) async {
    final Map<String, dynamic> updates = {};
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (String code in codes) {
      final normalized = code.trim().toUpperCase();
      if (normalized.isEmpty) continue;
      final voucherId = generateVoucherId();
      
      final voucher = VoucherModel(
        voucherId: voucherId,
        campaignId: campaignId,
        normalizedCode: normalized,
        state: autoRelease ? VoucherState.released.toMap() : VoucherState.draft.toMap(),
        releasedAt: autoRelease ? now : null,
        tombstone: false,
        createdAt: now,
        version: 1,
      );
      
      updates['vouchers/$campaignId/$voucherId'] = voucher.toMap();
      updates['voucher_lookup/$normalized'] = {
        'campaignId': campaignId,
        'voucherId': voucherId,
      };
    }
    
    if (updates.isNotEmpty) {
      updates['campaigns/$campaignId/hasCodes'] = true;
      updates['campaigns/$campaignId/updatedAt'] = now;
      await _storeRef.update(updates);
    }
  }

  /// Phát hành danh sách voucher
  Future<void> releaseVouchers(String campaignId, List<String> voucherIds) async {
    final Map<String, dynamic> updates = {};
    final now = DateTime.now().millisecondsSinceEpoch;
    
    for (String voucherId in voucherIds) {
      updates['vouchers/$campaignId/$voucherId/state'] = VoucherState.released.toMap();
      updates['vouchers/$campaignId/$voucherId/releasedAt'] = now;
    }
    
    if (updates.isNotEmpty) {
      await _storeRef.update(updates);
    }
  }

  /// Hủy 1 voucher
  Future<void> cancelVoucher(String campaignId, String voucherId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _storeRef.child('vouchers/$campaignId/$voucherId').update({
      'state': VoucherState.cancelled.toMap(),
      'cancelledAt': now,
    });
  }

  /// Tra cứu voucher theo mã code
  Future<VoucherModel?> lookupVoucherByCode(String code) async {
    final normalized = code.trim().toUpperCase();
    final lookupSnap = await _storeRef.child('voucher_lookup/$normalized').get();
    
    if (lookupSnap.value == null) return null;
    
    final lookupData = Map<String, dynamic>.from(lookupSnap.value as Map<dynamic, dynamic>);
    final campaignId = lookupData['campaignId'] as String;
    final voucherId = lookupData['voucherId'] as String;
    
    final voucherSnap = await _storeRef.child('vouchers/$campaignId/$voucherId').get();
    if (voucherSnap.value == null) return null;
    
    return VoucherModel.fromMap(Map<String, dynamic>.from(voucherSnap.value as Map<dynamic, dynamic>));
  }

  /// Đổi voucher
  Future<VoucherModel?> redeemVoucher(String code, String billId, String username) async {
    final normalized = code.trim().toUpperCase();
    final voucher = await lookupVoucherByCode(normalized);
    
    if (voucher == null) {
      throw Exception('Không tìm thấy mã voucher');
    }
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Kiểm tra trạng thái và hạn hold
    if (voucher.state == VoucherState.cancelled.toMap()) {
      throw Exception('Mã voucher đã bị hủy');
    }
    if (voucher.state == VoucherState.redeemed.toMap()) {
      throw Exception('Mã voucher đã được sử dụng');
    }
    if (voucher.state == VoucherState.reserved.toMap()) {
      if (voucher.holdExpiresAt != null && now < voucher.holdExpiresAt!) {
        throw Exception('Mã voucher đang được giữ bởi giao dịch khác');
      }
      // Nếu hết hạn hold thì cho phép redeem
    }
    if (voucher.state == VoucherState.draft.toMap()) {
      throw Exception('Mã voucher chưa được phát hành');
    }

    // Cập nhật trạng thái voucher
    final updatedVoucher = voucher.copyWith(
      state: VoucherState.redeemed.toMap(),
      redeemedAt: now,
      redeemedBillId: billId,
      redeemedBy: username,
    );
    final map = updatedVoucher.toMap();
    map['holdId'] = null;
    map['holdExpiresAt'] = null;
    map['version'] = voucher.version + 1;
    
    await _storeRef.child('vouchers/${voucher.campaignId}/${voucher.voucherId}').set(map);
    
    return updatedVoucher;
  }

  /// Giữ voucher (reserve) với TTL
  Future<void> holdVoucher(String code, String holdId, int ttlMs) async {
    final voucher = await lookupVoucherByCode(code);
    if (voucher == null) throw Exception('Không tìm thấy mã voucher');
    
    final now = DateTime.now().millisecondsSinceEpoch;
    
    if (voucher.state != VoucherState.released.toMap()) {
      if (voucher.state == VoucherState.reserved.toMap() && voucher.holdExpiresAt != null && now > voucher.holdExpiresAt!) {
        // Hết hạn hold, có thể chiếm
      } else {
        throw Exception('Voucher không sẵn sàng để giữ (Trạng thái: ${voucher.state})');
      }
    }
    
    final updatedVoucher = voucher.copyWith(
      state: VoucherState.reserved.toMap(),
      holdId: holdId,
      holdExpiresAt: now + ttlMs,
      reservedAt: now,
    );
    final map = updatedVoucher.toMap();
    map['version'] = voucher.version + 1;
    
    await _storeRef.child('vouchers/${voucher.campaignId}/${voucher.voucherId}').set(map);
  }

  /// Hủy giữ voucher, trả lại trạng thái RELEASED
  Future<void> releaseHold(String code, String holdId) async {
    final voucher = await lookupVoucherByCode(code);
    if (voucher == null) return;
    
    if (voucher.state == VoucherState.reserved.toMap() && voucher.holdId == holdId) {
      final updatedVoucher = voucher.copyWith(
        state: VoucherState.released.toMap(),
      );
      final map = updatedVoucher.toMap();
      map['holdId'] = null;
      map['holdExpiresAt'] = null;
      map['version'] = voucher.version + 1;
      
      await _storeRef.child('vouchers/${voucher.campaignId}/${voucher.voucherId}').set(map);
    }
  }

  /// Tạo ID cho Voucher
  String generateVoucherId() {
    return 'VCH_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(10000).toString().padLeft(4, '0')}';
  }

  // ==================== ACTIVE CAMPAIGN QUERY ====================

  /// Lấy danh sách khuyến mãi đang active cho một chi nhánh
  Future<List<CampaignModel>> getActiveCampaignsForBranch(String branchId) async {
    final campaigns = await getCampaigns();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final activeCampaigns = campaigns.where((c) {
      if (!c.active) return false;
      
      // Kiểm tra thời gian
      if (c.schedule.absoluteStart != null && now < c.schedule.absoluteStart!) return false;
      if (c.schedule.absoluteEnd != null && now > c.schedule.absoluteEnd!) return false;
      
      // Kiểm tra chi nhánh
      if (c.branchIds.isNotEmpty && !c.branchIds.contains(branchId)) return false;
      
      return true;
    }).toList();
    
    // Sort đã được làm trong getCampaigns()
    return activeCampaigns;
  }

  // ==================== COMMIT PROMOTION TO BILL ====================

  /// Xác nhận sử dụng khuyến mãi cho hóa đơn
  Future<void> commitPromotionUsage({
    required String campaignId,
    required int discountMoney,
    String? customerId,
    String? voucherCode,
    required String billId,
    required String username,
  }) async {
    // 1. Cập nhật campaign counters
    await _updateCampaignCounters(campaignId, spentDelta: discountMoney, useDelta: 1);
    
    // 2. Cập nhật customer counter nếu có
    if (customerId != null && customerId.isNotEmpty) {
      await _incrementCustomerCounter(campaignId, customerId);
    }
    
    // 3. Redeem voucher nếu có
    if (voucherCode != null && voucherCode.isNotEmpty) {
      await redeemVoucher(voucherCode, billId, username);
    }
  }

  // ==================== HELPER ====================

  /// Lấy map counters cho nhiều campaigns (để hiển thị UI)
  Future<Map<String, CampaignCountersModel>> getCampaignCountersMap(List<String> campaignIds) async {
    final Map<String, CampaignCountersModel> result = {};
    for (String id in campaignIds) {
      result[id] = await getCampaignCounters(id);
    }
    return result;
  }
}
