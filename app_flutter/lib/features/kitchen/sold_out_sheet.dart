// lib/features/kitchen/sold_out_sheet.dart
// Màn "Hết món" cho bếp: toàn bộ món theo nhóm, tìm kiếm, lọc "Đang hết", bật/tắt tức thì.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/domain/product_availability.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import 'sold_out_actions.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SoldOutSheet extends StatefulWidget {
  const SoldOutSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.kitchenBg,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => Theme(data: AppTheme.darkTheme, child: const SoldOutSheet()),
      );

  @override
  State<SoldOutSheet> createState() => _SoldOutSheetState();
}

class _SoldOutSheetState extends State<SoldOutSheet> {
  final _fb = FirebaseService();
  final _actions = SoldOutActions();
  final _searchCtrl = TextEditingController();
  StreamSubscription<List<ProductModel>>? _sub;
  List<ProductModel> _products = [];
  bool _loading = true;
  bool _onlySoldOut = false;
  bool _untilTomorrow = false;
  bool _cleaned = false;
  String _query = '';
  // Trạng thái "còn bán" hiển thị tạm thời trong lúc chờ ghi (lạc quan); xóa khi ghi xong/lỗi.
  final Map<String, bool> _optimistic = {};

  @override
  void initState() {
    super.initState();
    _sub = _fb.productsStream(storeCode: AuthService().currentStoreCode).listen((list) {
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
      if (!_cleaned) {
        _cleaned = true;
        _actions.clearStale(list);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _keyOf(ProductModel p) => p.dbKey ?? p.name;

  bool _available(ProductModel p) => _optimistic[_keyOf(p)] ?? isProductAvailable(p);

  Future<void> _toggle(ProductModel p, bool available) async {
    final k = _keyOf(p);
    setState(() => _optimistic[k] = available);
    try {
      await _actions.setSoldOut(p, !available, untilNextReset: _untilTomorrow);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Không cập nhật được ${p.name}: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      // Stream sẽ trả giá trị thật; bỏ ghi đè tạm (lỗi => tự quay về trạng thái cũ).
      if (mounted) setState(() => _optimistic.remove(k));
    }
  }

  Future<void> _restoreAll() async {
    final soldOut = _products.where((p) => !isProductAvailable(p)).toList();
    if (soldOut.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bật lại tất cả?'),
        content: Text('Đưa ${soldOut.length} món đang hết về trạng thái còn bán.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bật lại')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final n = await _actions.restoreAll(soldOut);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(n == soldOut.length ? 'Đã bật lại $n món' : 'Bật lại được $n/${soldOut.length} món'),
      backgroundColor: n == soldOut.length ? AppColors.success : AppColors.danger,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final soldOutCount = countSoldOut(_products);
    final groups = groupProductsForSoldOut(_products, query: _query, onlySoldOut: _onlySoldOut);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.kitchenCardBorder, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text('Báo hết món', style: GoogleFonts.beVietnamPro(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                if (soldOutCount > 0)
                  TextButton.icon(
                    onPressed: _restoreAll,
                    icon: const Icon(LucideIcons.rotateCcw, size: 18),
                    label: const Text('Bật lại tất cả'),
                  ),
                IconButton(icon: const Icon(LucideIcons.x), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Tìm món theo tên hoặc mã',
                prefixIcon: const Icon(LucideIcons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(icon: const Icon(LucideIcons.x), onPressed: () => setState(() { _searchCtrl.clear(); _query = ''; })),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: Text('Đang hết ($soldOutCount)'),
                  selected: _onlySoldOut,
                  onSelected: (v) => setState(() => _onlySoldOut = v),
                ),
                InkWell(
                  onTap: () => setState(() => _untilTomorrow = !_untilTomorrow),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(value: _untilTomorrow, onChanged: (v) => setState(() => _untilTomorrow = v ?? false)),
                      Text('Tự bật lại vào đầu ngày mai', style: GoogleFonts.beVietnamPro(color: AppColors.darkTextSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.kitchenAccent))
                : groups.isEmpty
                    ? Center(
                        child: Text(_onlySoldOut && _query.isEmpty ? 'Không có món nào đang hết' : 'Không tìm thấy món',
                            style: GoogleFonts.beVietnamPro(color: AppColors.darkTextSecondary)),
                      )
                    : ListView(
                        controller: scroll,
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [for (final g in groups) ..._buildGroup(g)],
                      ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(ProductGroup g) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text(g.category.toUpperCase(),
              style: GoogleFonts.beVietnamPro(color: AppColors.kitchenAccent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
        ),
        for (final p in g.items) _buildRow(p),
      ];

  Widget _buildRow(ProductModel p) {
    final available = _available(p);
    final note = available ? '' : soldOutNote(p);
    return SwitchListTile(
      key: ValueKey(_keyOf(p)),
      value: available,
      onChanged: (v) => _toggle(p, v),
      activeThumbColor: AppColors.success,
      title: Text(
        p.name,
        style: GoogleFonts.beVietnamPro(
          color: available ? Colors.white : AppColors.darkTextSecondary,
          fontWeight: FontWeight.w600,
          decoration: available ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        available ? 'Còn' : (note.isEmpty ? 'Hết' : note),
        style: GoogleFonts.beVietnamPro(color: available ? AppColors.darkTextSecondary : AppColors.danger, fontSize: 12),
      ),
    );
  }
}
