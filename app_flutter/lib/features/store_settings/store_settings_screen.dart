// lib/features/store_settings/store_settings_screen.dart
// Cài đặt cửa hàng: thông tin, VietQR, tùy chọn bán hàng và NGÀY KINH DOANH (giờ chia doanh thu qua 0h).
// Logic ngày kinh doanh: core/domain/business_day.dart (bản web: web/lib/business-day.ts).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/business_day.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen> {
  static const _banks = {
    'MB': 'MB Bank (Quân Đội)',
    'VCB': 'Vietcombank',
    'TCB': 'Techcombank',
    'ACB': 'ACB (Á Châu)',
    'VPB': 'VPBank',
    'TPB': 'TPBank',
    'BIDV': 'BIDV',
    'VIB': 'VIB',
    'CTG': 'VietinBank',
  };

  final _fb = FirebaseService();
  final _auth = AuthService();

  StoreInfoModel? _info;
  bool _loading = true;
  bool _saving = false;

  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _wifiCtrl = TextEditingController();
  final _bankAccountCtrl = TextEditingController();
  final _accountNameCtrl = TextEditingController();
  final _vatCtrl = TextEditingController();
  String _bankId = 'MB';
  bool _allowStack = true;
  bool _allowViewDiff = true;
  int _dayStart = 0;

  bool get _canEdit => _auth.isRootOwner || _auth.can(AppPermissions.manageStoreSettings);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _addressCtrl, _phoneCtrl, _wifiCtrl, _bankAccountCtrl, _accountNameCtrl, _vatCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final info = await _fb.getStoreInfo();
    if (!mounted) return;
    setState(() {
      _info = info;
      _nameCtrl.text = info.storeName;
      _addressCtrl.text = info.address;
      _phoneCtrl.text = info.phone;
      _wifiCtrl.text = info.wifiName;
      _bankAccountCtrl.text = info.bankAccount;
      _accountNameCtrl.text = info.accountName;
      _vatCtrl.text = info.defaultVatRate.toString();
      _bankId = _banks.containsKey(info.bankId) ? info.bankId : 'MB';
      _allowStack = info.allowStackPromotions;
      _allowViewDiff = info.allowStaffViewShiftDifference;
      _dayStart = info.businessDayStartMinute;
      _loading = false;
    });
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? context.tc.danger : null));
  }

  Future<void> _pickDayStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _dayStart ~/ 60, minute: _dayStart % 60),
      helpText: 'Giờ bắt đầu ngày kinh doanh (00:00 – 12:00)',
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    if (minutes > BusinessDay.maxStartMinute) {
      _snack('Giờ bắt đầu ngày kinh doanh tối đa 12:00 trưa', error: true);
      return;
    }
    setState(() => _dayStart = minutes);
  }

  /// Ví dụ minh họa: hóa đơn lúc 01:30 sáng nay thuộc ngày nào
  String? get _example {
    if (_dayStart == 0) return null;
    final nowVn = DateTime.now().toUtc().add(const Duration(hours: 7));
    final ts = DateTime.utc(nowVn.year, nowVn.month, nowVn.day, 1, 30).subtract(const Duration(hours: 7)).millisecondsSinceEpoch;
    final ymd = BusinessDay.dateOf(ts, _dayStart).split('-').reversed.join('/');
    final today = '${nowVn.day.toString().padLeft(2, '0')}/${nowVn.month.toString().padLeft(2, '0')}';
    return 'Hóa đơn lúc 01:30 sáng $today sẽ tính vào doanh thu ngày $ymd.';
  }

  Future<void> _save() async {
    final info = _info;
    if (info == null || !_canEdit) return;
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Vui lòng nhập tên cửa hàng', error: true);
      return;
    }
    final vat = double.tryParse(_vatCtrl.text.trim().replaceAll(',', '.')) ?? 0.0;
    final updated = info.copyWith(
      storeName: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      wifiName: _wifiCtrl.text.trim(),
      bankId: _bankId,
      bankAccount: _bankAccountCtrl.text.trim(),
      accountName: _accountNameCtrl.text.trim().toUpperCase(),
      defaultVatRate: vat < 0 ? 0 : vat,
      allowStackPromotions: _allowStack,
      allowStaffViewShiftDifference: _allowViewDiff,
    );
    setState(() => _saving = true);
    try {
      await _fb.saveStoreSettings(updated, businessDayStartMinute: _dayStart);
      _snack('Đã lưu cài đặt cửa hàng');
      await _load();
    } catch (e) {
      _snack('Không lưu được: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tc.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.tc.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 18, color: context.tc.primary),
          const SizedBox(width: 8),
          Text(title, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w800, fontSize: 15, color: context.tc.textPrimary)),
        ]),
        const SizedBox(height: 12),
        ...children,
      ]),
    );
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          enabled: _canEdit,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary,
        title: Text('Cài đặt cửa hàng', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: context.tc.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_canEdit)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text('Bạn chỉ được xem. Chỉ Chủ quán (hoặc tài khoản được cấp quyền) mới sửa được cài đặt.',
                        style: GoogleFonts.beVietnamPro(color: context.tc.warningInk, fontWeight: FontWeight.w600)),
                  ),
                _section('Ngày kinh doanh & chia doanh thu', Icons.schedule, [
                  Text(
                    'Cửa hàng hoạt động qua 0h: hóa đơn trước giờ này được tính vào doanh thu của ngày hôm trước. '
                    'Để 00:00 nếu chốt doanh thu đúng nửa đêm (mặc định). Biểu đồ theo khung giờ vẫn dùng giờ thực.',
                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    OutlinedButton.icon(
                      onPressed: _canEdit ? _pickDayStart : null,
                      icon: const Icon(Icons.access_time),
                      label: Text('Bắt đầu ngày lúc ${BusinessDay.formatMinutes(_dayStart)}'),
                    ),
                    const SizedBox(width: 8),
                    Wrap(spacing: 6, children: [
                      for (final m in const [0, 120, 240, 360])
                        ChoiceChip(
                          label: Text(BusinessDay.formatMinutes(m)),
                          selected: _dayStart == m,
                          onSelected: _canEdit ? (_) => setState(() => _dayStart = m) : null,
                        ),
                    ]),
                  ]),
                  if (_example != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_example!, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700, color: context.tc.primary, fontSize: 13)),
                    ),
                ]),
                _section('Thông tin cửa hàng', Icons.storefront_outlined, [
                  _field('Tên cửa hàng *', _nameCtrl),
                  _field('Địa chỉ', _addressCtrl),
                  _field('Số điện thoại', _phoneCtrl, type: TextInputType.phone),
                  _field('Tên WiFi (in trên hóa đơn)', _wifiCtrl),
                ]),
                _section('Thanh toán chuyển khoản (VietQR)', Icons.qr_code_2, [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DropdownButtonFormField<String>(
                      initialValue: _bankId,
                      decoration: const InputDecoration(labelText: 'Ngân hàng', border: OutlineInputBorder(), isDense: true),
                      items: _banks.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                      onChanged: _canEdit ? (v) => setState(() => _bankId = v ?? 'MB') : null,
                    ),
                  ),
                  _field('Số tài khoản', _bankAccountCtrl, type: TextInputType.number),
                  _field('Tên chủ tài khoản', _accountNameCtrl),
                ]),
                _section('Tùy chọn bán hàng', Icons.receipt_long_outlined, [
                  _field('VAT mặc định (%)', _vatCtrl, type: const TextInputType.numberWithOptions(decimal: true)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho phép cộng dồn khuyến mãi'),
                    subtitle: const Text('Một đơn dùng được nhiều chương trình cùng lúc'),
                    value: _allowStack,
                    onChanged: _canEdit ? (v) => setState(() => _allowStack = v) : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Cho nhân viên xem chênh lệch két khi kết ca'),
                    value: _allowViewDiff,
                    onChanged: _canEdit ? (v) => setState(() => _allowViewDiff = v) : null,
                  ),
                ]),
                const SizedBox(height: 4),
                if (_canEdit)
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Lưu cài đặt'),
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
              ],
            ),
    );
  }
}
