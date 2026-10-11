// Ô "Tìm khách": mở ra là có ngay ~10 khách (gần đây / nhiều điểm), gõ để lọc (debounce 150ms).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/domain/customer_search.dart';
import '../../../data/models/app_models.dart';

class CustomerPickerSheet extends StatefulWidget {
  final Future<List<CustomerCandidate>> Function() loadCandidates;

  /// Tra theo SĐT đầy đủ khi không có trong danh sách chi nhánh (khách ở chi nhánh khác / Firestore)
  final Future<CustomerCandidate?> Function(String phone) lookupByPhone;
  final Future<KmtCustomerModel> Function(String name, String phone) createCustomer;
  final List<LoyaltyTier> tiers;
  final bool showFullPhone;

  const CustomerPickerSheet({
    super.key,
    required this.loadCandidates,
    required this.lookupByPhone,
    required this.createCustomer,
    required this.tiers,
    this.showFullPhone = true,
  });

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<CustomerCandidate> _all = [];
  List<CustomerMatch> _results = [];
  CustomerCandidate? _remote;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.loadCandidates().then((v) {
      if (!mounted) return;
      setState(() {
        _all = v;
        _loading = false;
        _results = searchCustomers(_all, '');
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      final r = searchCustomers(_all, q);
      setState(() {
        _results = r;
        _remote = null;
      });
      final d = digitsOf(q);
      if (r.isEmpty && d.length >= 9) {
        final c = await widget.lookupByPhone(d);
        if (mounted && _ctrl.text == q) setState(() => _remote = c);
      }
    });
  }

  KmtCustomerModel _toModel(CustomerCandidate c) => KmtCustomerModel(id: c.id, fullName: c.name, phone: c.phone, currentPoints: c.points, totalPoints: c.totalPoints);

  String _phone(String p) => widget.showFullPhone ? p : maskPhone(p);

  Widget _highlight(String text, List<MatchRange> ranges, TextStyle base) {
    if (ranges.isEmpty || ranges.any((r) => r.end > text.length)) return Text(text, style: base, maxLines: 1, overflow: TextOverflow.ellipsis);
    final spans = <TextSpan>[];
    var i = 0;
    for (final r in ranges) {
      if (r.start > i) spans.add(TextSpan(text: text.substring(i, r.start)));
      spans.add(TextSpan(text: text.substring(r.start, r.end), style: base.copyWith(backgroundColor: Colors.yellow.shade200, fontWeight: FontWeight.w800)));
      i = r.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(TextSpan(style: base, children: spans), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Future<void> _addNew() async {
    final q = _ctrl.text.trim();
    final nameCtrl = TextEditingController(text: RegExp(r'[0-9]').hasMatch(q) ? '' : q);
    final phoneCtrl = TextEditingController(text: digitsOf(q).length >= 3 ? digitsOf(q) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm khách mới (0 điểm)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Họ và tên *', prefixIcon: Icon(Icons.person))),
          const SizedBox(height: 8),
          TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại *', prefixIcon: Icon(Icons.phone))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Lưu & chọn')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty || digitsOf(phoneCtrl.text).length < 9) return;
    final m = await widget.createCustomer(nameCtrl.text.trim(), phoneCtrl.text.trim());
    if (mounted) Navigator.pop(context, m);
  }

  @override
  Widget build(BuildContext context) {
    final small = GoogleFonts.beVietnamPro(fontSize: 12, color: Colors.black54);
    final bold = GoogleFonts.beVietnamPro(fontSize: 14, fontWeight: FontWeight.w700);
    final hasQuery = _ctrl.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  hintText: 'SĐT, 4 số cuối hoặc tên khách',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: hasQuery ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _ctrl.clear(); _onChanged(''); }) : null,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(alignment: Alignment.centerLeft, child: Text(hasQuery ? 'Kết quả' : 'Khách gần đây / nhiều điểm', style: small)),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        for (final m in _results)
                          ListTile(
                            onTap: () => Navigator.pop(context, _toModel(m.customer)),
                            title: _highlight(m.customer.name.isEmpty ? '(chưa có tên)' : m.customer.name, m.nameRanges, bold),
                            subtitle: m.phoneRange != null && widget.showFullPhone
                                ? _highlight(m.customer.phone, [m.phoneRange!], small)
                                : Text(_phone(m.customer.phone), style: small),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${m.customer.points} điểm', style: bold.copyWith(fontSize: 13, color: Colors.green.shade800)),
                                Text(LoyaltyTier.nameFor(m.customer.totalPoints, widget.tiers), style: small),
                              ],
                            ),
                          ),
                        if (_remote != null)
                          ListTile(
                            onTap: () => Navigator.pop(context, _toModel(_remote!)),
                            leading: const Icon(Icons.public),
                            title: Text(_remote!.name, style: bold),
                            subtitle: Text('${_phone(_remote!.phone)} • khách ở chi nhánh khác', style: small),
                            trailing: Text('${_remote!.points} điểm', style: bold.copyWith(fontSize: 13)),
                          ),
                        if (hasQuery && _results.isEmpty && _remote == null)
                          Padding(padding: const EdgeInsets.all(16), child: Text('Không thấy khách phù hợp.', style: small)),
                        ListTile(
                          leading: const Icon(Icons.person_add),
                          title: const Text('Thêm khách mới'),
                          onTap: _addNew,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
