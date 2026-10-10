import 'dart:async';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import '../../data/models/campaign_models.dart';
import '../../core/services/auth_service.dart';
import '../../core/domain/order_integrity.dart';

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

  /// Tạo danh sách voucher - mặc định tự động RELEASED để sử dụng được ngay.
  /// Bỏ qua mã đã tồn tại (ở bất kỳ chương trình nào) hoặc trùng trong danh sách.
  Future<VoucherCreateResult> createVouchers(String campaignId, List<String> codes, {bool autoRelease = true}) async {
    final Map<String, dynamic> updates = {};
    final now = DateTime.now().millisecondsSinceEpoch;
    final created = <String>[];
    final existing = <String>[];

    // Đọc 1 lần toàn bộ bảng tra cứu để phát hiện mã đã tồn tại
    final lookupSnap = await _storeRef.child('voucher_lookup').get();
    final taken = lookupSnap.value is Map ? (lookupSnap.value as Map).keys.map((k) => k.toString()).toSet() : <String>{};

    int seq = 0;
    for (String code in codes) {
      final normalized = code.trim().toUpperCase();
      if (normalized.isEmpty || created.contains(normalized) || existing.contains(normalized)) continue;
      if (taken.contains(normalized)) {
        existing.add(normalized);
        continue;
      }
      final voucherId = '${generateVoucherId()}_${seq++}';
      created.add(normalized);
      
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
    return VoucherCreateResult(created, existing);
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
      'status': 'CANCELLED',
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

  /// Handler transaction đổi voucher: chỉ đổi được khi voucher ở trạng thái hợp lệ.
  /// [onReject] nhận lý do từ chối ('MINE' nếu đã được chính hóa đơn này đổi trước đó).
  TransactionHandler _redeemVoucherHandler({
    required String billId,
    required String username,
    String? billCode,
    String? tableName,
    String? staffName,
    String? staffNote,
    required void Function(String reason) onReject,
  }) {
    return (Object? current) {
      // Cache cục bộ có thể chưa có dữ liệu: ghi null để server trả về giá trị thật và chạy lại
      if (current == null) return Transaction.success(null);
      final now = DateTime.now().millisecondsSinceEpoch;
      final m = Map<String, dynamic>.from(current as Map);
      final state = m['state']?.toString() ?? '';
      if (state == VoucherState.redeemed.toMap()) {
        onReject(m['redeemedBillId'] == billId ? 'MINE' : 'Mã voucher đã được sử dụng');
        return Transaction.abort();
      }
      if (state == VoucherState.cancelled.toMap()) {
        onReject('Mã voucher đã bị hủy');
        return Transaction.abort();
      }
      if (state == VoucherState.draft.toMap()) {
        onReject('Mã voucher chưa được phát hành');
        return Transaction.abort();
      }
      if (state == VoucherState.reserved.toMap()) {
        final exp = (m['holdExpiresAt'] as num?)?.toInt();
        if (exp != null && now < exp) {
          onReject('Mã voucher đang được giữ bởi giao dịch khác');
          return Transaction.abort();
        }
      }
      m['state'] = VoucherState.redeemed.toMap();
      m['redeemedAt'] = now;
      m['redeemedBillId'] = billId;
      m['redeemedBillCode'] = (billCode != null && billCode.isNotEmpty) ? billCode : billId;
      m['redeemedBy'] = username;
      m['usedBy'] = username;
      m['usedAt'] = now;
      m['status'] = 'USED';
      if (staffName != null && staffName.isNotEmpty) m['redeemedByName'] = staffName;
      if (tableName != null && tableName.isNotEmpty) m['tableName'] = tableName;
      m['holdId'] = null;
      m['holdExpiresAt'] = null;
      m['version'] = ((m['version'] as num?)?.toInt() ?? 0) + 1;
      if (staffNote != null && staffNote.isNotEmpty) m['staffNote'] = staffNote;
      return Transaction.success(m);
    };
  }

  /// Đổi voucher (transaction - chống 2 máy cùng dùng 1 mã)
  Future<VoucherModel?> redeemVoucher(String code, String billId, String username, {String? staffNote}) async {
    final normalized = code.trim().toUpperCase();
    final voucher = await lookupVoucherByCode(normalized);
    if (voucher == null) {
      throw Exception('Không tìm thấy mã voucher');
    }
    String? reason;
    final res = await _storeRef.child('vouchers/${voucher.campaignId}/${voucher.voucherId}').runTransaction(
      _redeemVoucherHandler(billId: billId, username: username, staffNote: staffNote, onReject: (r) => reason = r),
    );
    if (!res.committed || res.snapshot.value == null) {
      if (reason == 'MINE') return voucher;
      throw Exception(reason ?? 'Không tìm thấy mã voucher');
    }
    return VoucherModel.fromMap(Map<String, dynamic>.from(res.snapshot.value as Map<dynamic, dynamic>));
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
      
      // Kiểm tra thời gian, ngày trong tuần, và happy hours
      if (!c.isEligibleAt(now)) return false;
      
      // Kiểm tra chi nhánh
      if (!c.isEligibleForBranch(branchId)) return false;
      
      return true;
    }).toList();
    
    // Sort đã được làm trong getCampaigns()
    return activeCampaigns;
  }

  // ==================== COMMIT PROMOTION TO BILL ====================

  DatabaseReference _refFor(String? storeCode) =>
      (storeCode != null && storeCode.trim().isNotEmpty) ? _db.ref('stores/${storeCode.trim().toUpperCase()}') : _storeRef;

  /// Chạy transaction có timeout.
  /// true = đã commit, false = bị từ chối (abort / vượt giới hạn),
  /// null = chưa xác nhận được (offline) - transaction vẫn tiếp tục chạy nền khi có mạng.
  Future<bool?> _runTxn(
    DatabaseReference ref,
    TransactionHandler handler, {
    required Duration timeout,
    required bool offline,
    required String label,
    void Function(String message)? onLateFailure,
  }) async {
    final fut = ref.runTransaction(handler);
    void watchLate() {
      fut.then((res) {
        if (!res.committed) onLateFailure?.call('$label: bị từ chối khi đồng bộ (vượt giới hạn?)');
      }, onError: (Object e) {
        onLateFailure?.call('$label: $e');
      });
    }

    if (offline) {
      watchLate();
      return null;
    }
    try {
      final res = await fut.timeout(timeout);
      return res.committed;
    } on TimeoutException {
      watchLate();
      return null;
    }
  }

  /// Giữ/ghi nhận lượt dùng khuyến mãi cho hóa đơn một cách nguyên tử (transaction),
  /// kiểm tra giới hạn maxUses / budgetMoney / maxUsesPerCustomer và trạng thái voucher
  /// NGAY TRONG transaction. Ném [PromotionLimitExceededException] nếu vượt giới hạn
  /// (các bước đã áp dụng sẽ được hoàn tác).
  ///
  /// Khi mất mạng (timeout) không chặn bán hàng: các transaction còn lại được xếp hàng
  /// chạy nền, reservation.unverified = true, lỗi muộn báo qua [onLateFailure].
  Future<PromotionUsageReservation> reservePromotionUsage({
    required String campaignId,
    required int discountMoney,
    String? customerId,
    String? voucherCode,
    String? staffNote,
    required String billId,
    required String username,
    String? billCode,
    String? tableName,
    String? staffName,
    String? storeCode,
    Duration timeout = const Duration(seconds: 4),
    void Function(String message)? onLateFailure,
  }) async {
    final store = _refFor(storeCode);
    final r = PromotionUsageReservation(
      campaignId: campaignId,
      discountMoney: discountMoney,
      customerId: (customerId != null && customerId.isNotEmpty) ? customerId : null,
      voucherCode: (voucherCode != null && voucherCode.trim().isNotEmpty) ? voucherCode.trim().toUpperCase() : null,
      billId: billId,
      storeCode: storeCode,
    );
    bool offline = false;

    CampaignModel? campaign;
    try {
      final snap = await store.child('campaigns/$campaignId').get().timeout(timeout);
      if (snap.value != null) {
        campaign = CampaignModel.fromMap(Map<String, dynamic>.from(snap.value as Map<dynamic, dynamic>));
      }
    } catch (_) {
      offline = true; // Không đọc được cấu hình -> không kiểm tra được giới hạn, không chặn bán
    }
    final campaignName = campaign?.name ?? campaignId;

    Future<void> fail(String message) async {
      await rollbackPromotionUsage(r, timeout: timeout);
      throw PromotionLimitExceededException(message);
    }

    // 1. Voucher (mã dùng 1 lần)
    if (r.voucherCode != null) {
      try {
        if (offline) throw TimeoutException('offline');
        final lookup = await store.child('voucher_lookup/${r.voucherCode}').get().timeout(timeout);
        if (lookup.value is Map) {
          final m = Map<String, dynamic>.from(lookup.value as Map);
          r.voucherCampaignId = m['campaignId']?.toString();
          r.voucherId = m['voucherId']?.toString();
        }
      } catch (_) {
        offline = true;
      }
      if (r.voucherId != null && r.voucherCampaignId != null) {
        String? reason;
        final ok = await _runTxn(
          store.child('vouchers/${r.voucherCampaignId}/${r.voucherId}'),
          _redeemVoucherHandler(
            billId: billId,
            username: username,
            billCode: billCode,
            tableName: tableName,
            staffName: staffName,
            staffNote: staffNote,
            onReject: (x) => reason = x,
          ),
          timeout: timeout,
          offline: offline,
          label: 'Đổi voucher ${r.voucherCode} (HĐ $billId)',
          onLateFailure: onLateFailure,
        );
        if (ok == null) {
          offline = true;
          r.voucherRedeemed = true; // Đã xếp hàng, coi như áp dụng
        } else if (ok) {
          r.voucherRedeemed = true;
        } else if (reason == 'MINE') {
          r.voucherRedeemed = false; // đã đổi từ trước bởi chính hóa đơn này, không hoàn tác
        } else {
          await fail('${reason ?? "Mã voucher không khả dụng"} (${r.voucherCode})');
        }
      } else if (offline) {
        onLateFailure?.call('Chưa xác nhận được voucher ${r.voucherCode} cho HĐ $billId (mất mạng)');
      }
    }

    // 2. Bộ đếm tổng của chương trình
    final counterOk = await _runTxn(
      store.child('campaign_counters/$campaignId'),
      (cur) {
        final next = PromotionUsageMath.applyCampaignUsage(
          cur,
          campaignId: campaignId,
          spentDelta: discountMoney,
          useDelta: 1,
          maxUses: campaign?.maxUses,
          budgetMoney: campaign?.budgetMoney,
        );
        return next == null ? Transaction.abort() : Transaction.success(next);
      },
      timeout: timeout,
      offline: offline,
      label: 'Bộ đếm khuyến mãi $campaignName (HĐ $billId)',
      onLateFailure: onLateFailure,
    );
    if (counterOk == false) {
      await fail('Khuyến mãi "$campaignName" đã hết lượt sử dụng hoặc hết ngân sách');
    }
    if (counterOk == null) offline = true;
    r.counterApplied = true;

    // 3. Bộ đếm theo khách hàng
    if (r.customerId != null) {
      final key = '${campaignId}_${r.customerId}';
      final custOk = await _runTxn(
        store.child('customer_campaign_counters/$key'),
        (cur) {
          final next = PromotionUsageMath.applyCustomerUsage(
            cur,
            campaignId: campaignId,
            customerId: r.customerId!,
            delta: 1,
            maxUsesPerCustomer: campaign?.maxUsesPerCustomer,
          );
          return next == null ? Transaction.abort() : Transaction.success(next);
        },
        timeout: timeout,
        offline: offline,
        label: 'Lượt dùng của khách ${r.customerId} - $campaignName (HĐ $billId)',
        onLateFailure: onLateFailure,
      );
      if (custOk == false) {
        await fail('Khách hàng đã dùng hết số lượt cho phép của khuyến mãi "$campaignName"');
      }
      if (custOk == null) offline = true;
      r.customerApplied = true;
    }

    r.unverified = offline;
    return r;
  }

  /// Hoàn tác các bước đã áp dụng của [r] (khi ghi hóa đơn thất bại / vượt giới hạn).
  /// Trả về danh sách lỗi (rỗng nếu thành công) - không ném lỗi.
  Future<List<String>> rollbackPromotionUsage(
    PromotionUsageReservation r, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final store = _refFor(r.storeCode);
    final errors = <String>[];
    Future<void> guard(String label, Future<void> Function() op) async {
      try {
        await op().timeout(timeout);
      } catch (e) {
        errors.add('$label: $e');
      }
    }

    if (r.customerApplied && r.customerId != null) {
      await guard('Hoàn tác lượt khách', () async {
        await store.child('customer_campaign_counters/${r.campaignId}_${r.customerId}').runTransaction((cur) {
          if (cur == null) return Transaction.success(null);
          return Transaction.success(PromotionUsageMath.applyCustomerUsage(cur,
              campaignId: r.campaignId, customerId: r.customerId!, delta: -1));
        });
      });
      r.customerApplied = false;
    }
    if (r.counterApplied) {
      await guard('Hoàn tác bộ đếm khuyến mãi', () async {
        await store.child('campaign_counters/${r.campaignId}').runTransaction((cur) {
          if (cur == null) return Transaction.success(null);
          return Transaction.success(PromotionUsageMath.applyCampaignUsage(cur,
              campaignId: r.campaignId, spentDelta: -r.discountMoney, useDelta: -1));
        });
      });
      r.counterApplied = false;
    }
    if (r.voucherRedeemed && r.voucherId != null && r.voucherCampaignId != null) {
      await guard('Hoàn tác voucher', () async {
        await store.child('vouchers/${r.voucherCampaignId}/${r.voucherId}').runTransaction((cur) {
          if (cur == null) return Transaction.success(null);
          final m = Map<String, dynamic>.from(cur as Map);
          if (m['redeemedBillId'] != r.billId) return Transaction.abort();
          m['state'] = VoucherState.released.toMap();
          m['redeemedAt'] = null;
          m['redeemedBillId'] = null;
          m['redeemedBillCode'] = null;
          m['redeemedBy'] = null;
          m['redeemedByName'] = null;
          m['tableName'] = null;
          m['usedBy'] = null;
          m['usedAt'] = null;
          m['status'] = 'ISSUED';
          m['version'] = ((m['version'] as num?)?.toInt() ?? 0) + 1;
          return Transaction.success(m);
        });
      });
      r.voucherRedeemed = false;
    }
    return errors;
  }

  /// Xác nhận sử dụng khuyến mãi cho hóa đơn (giữ tương thích API cũ).
  Future<void> commitPromotionUsage({
    required String campaignId,
    required int discountMoney,
    String? customerId,
    String? voucherCode,
    String? staffNote,
    required String billId,
    required String username,
  }) async {
    await reservePromotionUsage(
      campaignId: campaignId,
      discountMoney: discountMoney,
      customerId: customerId,
      voucherCode: voucherCode,
      staffNote: staffNote,
      billId: billId,
      username: username,
    );
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

/// Kết quả tạo mã voucher hàng loạt
class VoucherCreateResult {
  final List<String> created;
  final List<String> existing; // mã đã tồn tại, bị bỏ qua
  const VoucherCreateResult(this.created, this.existing);
}

/// Kết quả giữ lượt dùng khuyến mãi cho 1 hóa đơn (dùng để hoàn tác nếu ghi hóa đơn lỗi)
class PromotionUsageReservation {
  final String campaignId;
  final int discountMoney;
  final String? customerId;
  final String? voucherCode;
  final String billId;
  final String? storeCode;
  String? voucherCampaignId;
  String? voucherId;
  bool voucherRedeemed = false;
  bool counterApplied = false;
  bool customerApplied = false;

  /// true nếu có bước chưa được server xác nhận (offline) - đang chạy nền
  bool unverified = false;

  PromotionUsageReservation({
    required this.campaignId,
    required this.discountMoney,
    this.customerId,
    this.voucherCode,
    required this.billId,
    this.storeCode,
  });
}
