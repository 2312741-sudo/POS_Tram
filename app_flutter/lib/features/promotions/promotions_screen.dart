// lib/features/promotions/promotions_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key});

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<PromotionModel> _promotions = [];
  StoreInfoModel? _storeInfo;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final promos = await _fb.getPromotions();
    final info = await _fb.getStoreInfo();
    if (mounted) {
      setState(() {
        _promotions = promos.isNotEmpty ? promos : [
          PromotionModel(
            id: 'PROMO_WELCOME',
            code: 'CHAOBAN20',
            name: 'Giảm 20% Chào Bạn Mới',
            description: 'Giảm 20% tối đa 50k cho đơn từ 50k',
            type: 'PERCENT_BILL',
            value: 20,
            maxDiscountAmount: 50000,
            minBillAmount: 50000,
            startDate: DateTime.now().millisecondsSinceEpoch,
            endDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
            isActive: true,
            maxUsage: 200,
          ),
          PromotionModel(
            id: 'PROMO_10K',
            code: 'GIAM10K',
            name: 'Giảm 10.000đ trực tiếp',
            description: 'Giảm ngay 10k cho đơn từ 60k',
            type: 'FIXED_BILL',
            value: 10000,
            minBillAmount: 60000,
            startDate: DateTime.now().millisecondsSinceEpoch,
            endDate: DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch,
            isActive: true,
            maxUsage: 100,
          ),
        ];
        _storeInfo = info;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleStackPromotions(bool value) async {
    if (_storeInfo == null) return;
    final updated = StoreInfoModel(
      storeCode: _storeInfo!.storeCode,
      storeName: _storeInfo!.storeName,
      address: _storeInfo!.address,
      phone: _storeInfo!.phone,
      wifiName: _storeInfo!.wifiName,
      bankId: _storeInfo!.bankId,
      bankAccount: _storeInfo!.bankAccount,
      accountName: _storeInfo!.accountName,
      allowStackPromotions: value,
      defaultVatRate: _storeInfo!.defaultVatRate,
      kitchenPrinterIp: _storeInfo!.kitchenPrinterIp,
      billPrinterIp: _storeInfo!.billPrinterIp,
      printerType: _storeInfo!.printerType,
    );
    await _fb.saveStoreInfo(updated);
    setState(() => _storeInfo = updated);

    await _fb.logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: _auth.currentUser?.username ?? 'admin',
      userFullName: _auth.currentUser?.fullName ?? 'Quản Lý',
      userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
      action: 'UPDATE_CONFIG',
      targetType: 'PROMOTION',
      targetId: 'STACKABLE_SETTING',
      details: '${value ? "Bật" : "Tắt"} cho phép gộp nhiều chương trình khuyến mãi cùng lúc',
    ));
  }

  Future<void> _showAddEditPromoDialog([PromotionModel? promoToEdit]) async {
    final codeCtrl = TextEditingController(text: promoToEdit?.code ?? '');
    final nameCtrl = TextEditingController(text: promoToEdit?.name ?? '');
    final descCtrl = TextEditingController(text: promoToEdit?.description ?? '');
    final valueCtrl = TextEditingController(text: promoToEdit != null ? '${promoToEdit.value}' : '10');
    final maxDiscCtrl = TextEditingController(text: promoToEdit != null ? '${promoToEdit.maxDiscountAmount}' : '0');
    final minBillCtrl = TextEditingController(text: promoToEdit != null ? '${promoToEdit.minBillAmount}' : '0');
    final maxUsageCtrl = TextEditingController(text: promoToEdit != null ? '${promoToEdit.maxUsage}' : '0');

    String selectedType = promoToEdit?.type ?? 'PERCENT_BILL';
    DateTime startDate = promoToEdit != null && promoToEdit.startDate > 0
        ? DateTime.fromMillisecondsSinceEpoch(promoToEdit.startDate)
        : DateTime.now();
    DateTime endDate = promoToEdit != null && promoToEdit.endDate > 0
        ? DateTime.fromMillisecondsSinceEpoch(promoToEdit.endDate)
        : DateTime.now().add(const Duration(days: 30));
    bool isActive = promoToEdit?.isActive ?? true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: Text(
              promoToEdit == null ? 'Tạo Khuyến Mãi / Voucher Mới' : 'Sửa Khuyến Mãi',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedType,
                      decoration: const InputDecoration(labelText: 'Loại hình khuyến mãi *'),
                      items: const [
                        DropdownMenuItem(value: 'PERCENT_BILL', child: Text('Giảm % trên tổng hóa đơn')),
                        DropdownMenuItem(value: 'FIXED_BILL', child: Text('Giảm số tiền cố định (VND)')),
                        DropdownMenuItem(value: 'VOUCHER', child: Text('Mã Voucher nhập tay')),
                      ],
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedType = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Tên chương trình * (vd: Giảm 20% Khai Trương)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Mã Code (Nhập tay khi tính tiền)',
                        hintText: selectedType == 'VOUCHER' ? 'VD: VOUCHER50K' : 'Tùy chọn',
                        prefixIcon: const Icon(Icons.confirmation_number_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: valueCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: selectedType == 'PERCENT_BILL' ? 'Mức giảm (%) *' : 'Số tiền giảm (VND) *',
                              suffixText: selectedType == 'PERCENT_BILL' ? '%' : 'đ',
                            ),
                          ),
                        ),
                        if (selectedType == 'PERCENT_BILL') ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: maxDiscCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Giảm tối đa (VND)',
                                hintText: '0 = không giới hạn',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: minBillCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Đơn tối thiểu (VND)',
                              hintText: '0 = áp dụng mọi đơn',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: maxUsageCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Giới hạn số lượt dùng',
                              hintText: '0 = vô hạn',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Date pickers
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.calendar_today, size: 16),
                            label: Text('Từ: ${DateFormat("dd/MM/yy").format(startDate)}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: startDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setDlgState(() => startDate = picked);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.event, size: 16),
                            label: Text('Đến: ${DateFormat("dd/MM/yy").format(endDate)}'),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: endDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) setDlgState(() => endDate = picked);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      title: const Text('Kích hoạt chương trình ngay'),
                      value: isActive,
                      onChanged: (val) => setDlgState(() => isActive = val),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final pId = promoToEdit?.id ?? 'PROMO_${DateTime.now().millisecondsSinceEpoch}';
                  final promo = PromotionModel(
                    id: pId,
                    code: codeCtrl.text.trim().toUpperCase(),
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    type: selectedType,
                    value: int.tryParse(valueCtrl.text.trim()) ?? 0,
                    maxDiscountAmount: int.tryParse(maxDiscCtrl.text.trim()) ?? 0,
                    minBillAmount: int.tryParse(minBillCtrl.text.trim()) ?? 0,
                    maxUsage: int.tryParse(maxUsageCtrl.text.trim()) ?? 0,
                    startDate: startDate.millisecondsSinceEpoch,
                    endDate: endDate.millisecondsSinceEpoch,
                    isActive: isActive,
                    usageCount: promoToEdit?.usageCount ?? 0,
                  );

                  await _fb.savePromotion(promo);

                  // Audit log
                  await _fb.logAction(AuditLogModel(
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                    username: _auth.currentUser?.username ?? 'admin',
                    userFullName: _auth.currentUser?.fullName ?? 'Quản Lý',
                    userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
                    action: promoToEdit == null ? 'CREATE_PROMOTION' : 'EDIT_PROMOTION',
                    targetType: 'PROMOTION',
                    targetId: pId,
                    details: '${promoToEdit == null ? "Tạo" : "Sửa"} khuyến mãi ${promo.name} (${promo.code})',
                  ));

                  Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text('Lưu Khuyến Mãi'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Khuyến Mãi & Voucher'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditPromoDialog(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Thêm Khuyến Mãi', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Settings Banner for Stacking Promotions
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.layers_outlined, color: Colors.amber, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cho phép gộp nhiều chương trình khuyến mãi',
                              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              'Khi bật, thu ngân có thể áp dụng đồng thời mã Voucher + Giảm giá hóa đơn của quán.',
                              style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _storeInfo?.allowStackPromotions ?? true,
                        activeColor: Colors.amber.shade800,
                        onChanged: _toggleStackPromotions,
                      ),
                    ],
                  ),
                ),

                // Promotions List
                Expanded(
                  child: _promotions.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.discount_outlined, size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('Chưa có chương trình khuyến mãi nào', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _promotions.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final p = _promotions[index];
                            final isExpired = p.endDate > 0 && DateTime.now().millisecondsSinceEpoch > p.endDate;

                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: p.isActive && !isExpired ? AppColors.successLight : Colors.grey.shade200,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            p.code.isNotEmpty ? p.code : 'CTKM',
                                            style: GoogleFonts.beVietnamPro(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                              color: p.isActive && !isExpired ? AppColors.success : Colors.grey.shade700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(p.name, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15)),
                                              Text(p.typeDisplay, style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                                            ],
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, size: 20),
                                          onPressed: () => _showAddEditPromoDialog(p),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Xóa khuyến mãi'),
                                                content: Text('Xóa chương trình "${p.name}"?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: const Text('Xóa'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _fb.deletePromotion(p.id);
                                              _loadData();
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 6,
                                      children: [
                                        _infoChip(Icons.percent, 'Mức giảm: ${p.type == "PERCENT_BILL" ? "${p.value}%" : FormatUtils.vnd(p.value)}'),
                                        if (p.minBillAmount > 0) _infoChip(Icons.shopping_bag_outlined, 'Đơn từ: ${FormatUtils.vnd(p.minBillAmount)}'),
                                        if (p.maxDiscountAmount > 0) _infoChip(Icons.arrow_downward, 'Tối đa: ${FormatUtils.vnd(p.maxDiscountAmount)}'),
                                        _infoChip(Icons.repeat, 'Đã dùng: ${p.usageCount}${p.maxUsage > 0 ? "/${p.maxUsage}" : ""} lượt'),
                                        _infoChip(Icons.date_range, 'Hạn: ${FormatUtils.dateOnly(p.endDate)}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
