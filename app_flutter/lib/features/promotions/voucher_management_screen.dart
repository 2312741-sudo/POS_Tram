import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/campaign_service.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';
import '../manager/widgets/bill_detail_sheet.dart';
import 'voucher_check.dart';

class VoucherManagementScreen extends StatefulWidget {
  final CampaignModel campaign;
  const VoucherManagementScreen({super.key, required this.campaign});

  @override
  State<VoucherManagementScreen> createState() => _VoucherManagementScreenState();
}

class _VoucherManagementScreenState extends State<VoucherManagementScreen> {
  final _campaignService = CampaignService();
  
  String _stateFilter = 'TẤT CẢ';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.surface,
      appBar: AppBar(
        title: Text('Quản lý mã - ${widget.campaign.name}'),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<VoucherModel>>(
        stream: _campaignService.vouchersStream(widget.campaign.campaignId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }

          final vouchers = snapshot.data ?? [];
          
          return Column(
            children: [
              _buildStatsRow(vouchers),
              _buildActions(vouchers),
              _buildFilters(),
              Expanded(
                child: _buildVoucherList(vouchers),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsRow(List<VoucherModel> vouchers) {
    final total = vouchers.length;
    final released = vouchers.where((v) => v.state == VoucherState.released.toMap()).length;
    final redeemed = vouchers.where((v) => v.state == VoucherState.redeemed.toMap()).length;
    final cancelled = vouchers.where((v) => v.state == VoucherState.cancelled.toMap()).length;

    return Container(
      color: context.tc.card,
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem('Tổng', total, context.tc.textPrimary),
          _buildStatItem('Phát hành', released, Colors.blue),
          _buildStatItem('Đã dùng', redeemed, Colors.green),
          _buildStatItem('Đã hủy', cancelled, Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: context.tc.textHint)),
      ],
    );
  }

  Widget _buildActions(List<VoucherModel> vouchers) {
    final draftCount = vouchers.where((v) => v.state == VoucherState.draft.toMap()).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showGenerateDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Tạo mã'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.tc.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: draftCount > 0 ? () => _releaseAll(vouchers) : null,
              icon: const Icon(Icons.send),
              label: Text('Phát hành ($draftCount)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildFilterChip('TẤT CẢ'),
          const SizedBox(width: 8),
          _buildFilterChip('DRAFT'),
          const SizedBox(width: 8),
          _buildFilterChip('RELEASED'),
          const SizedBox(width: 8),
          _buildFilterChip('REDEEMED'),
          const SizedBox(width: 8),
          _buildFilterChip('CANCELLED'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _stateFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _stateFilter = label;
          });
        }
      },
      selectedColor: context.tc.primary.withValues(alpha: 0.2),
      labelStyle: TextStyle(
        color: isSelected ? context.tc.primary : context.tc.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildVoucherList(List<VoucherModel> vouchers) {
    var filtered = vouchers;
    if (_stateFilter != 'TẤT CẢ') {
      filtered = vouchers.where((v) => v.state == _stateFilter).toList();
    }

    if (filtered.isEmpty) {
      return const EmptyState(
        icon: Icons.qr_code_scanner,
        title: 'Chưa có mã voucher nào',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final v = filtered[index];
        return _buildVoucherCard(v);
      },
    );
  }

  Widget _buildVoucherCard(VoucherModel v) {
    Color stateColor = context.tc.textHint;
    String stateText = v.state;
    if (v.state == VoucherState.draft.toMap()) {
      stateColor = Colors.orange;
    } else if (v.state == VoucherState.released.toMap()) {
      stateColor = Colors.blue;
    } else if (v.state == VoucherState.redeemed.toMap()) {
      stateColor = Colors.green;
      stateText = 'ĐÃ DÙNG';
    } else if (v.state == VoucherState.cancelled.toMap()) {
      stateColor = Colors.red;
      stateText = 'ĐÃ HỦY';
    }

    return Dismissible(
      key: Key(v.voucherId),
      direction: (v.state == VoucherState.draft.toMap() || v.state == VoucherState.released.toMap())
          ? DismissDirection.endToStart
          : DismissDirection.none,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Hủy mã?'),
            content: Text('Bạn có chắc muốn hủy mã ${v.normalizedCode} này?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('KHÔNG')),
              TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('HỦY MÃ', style: TextStyle(color: Colors.red))),
            ],
          ),
        );
      },
      onDismissed: (direction) async {
        await _campaignService.cancelVoucher(widget.campaign.campaignId, v.voucherId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã hủy mã ${v.normalizedCode}')));
        }
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.cancel, color: Colors.white),
      ),
      child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
          title: Text(
            v.normalizedCode,
            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 16),
          ),
          onTap: v.state == VoucherState.redeemed.toMap() && v.redeemedBillId != null ? () => _openBill(v) : null,
          subtitle: v.state == VoucherState.redeemed.toMap()
              ? Text(
                  'Đơn ${v.redeemedBillCode ?? v.redeemedBillId ?? "?"}${(v.tableName ?? "").isNotEmpty ? " • ${v.tableName}" : ""}\n'
                  'Lúc ${v.redeemedAt != null ? DateFormat("dd/MM/yyyy HH:mm").format(DateTime.fromMillisecondsSinceEpoch(v.redeemedAt!)) : "?"}'
                  ' • NV: ${v.redeemedByName ?? v.redeemedBy ?? "?"}',
                )
              : Text('Tạo lúc ${DateFormat("dd/MM HH:mm").format(DateTime.fromMillisecondsSinceEpoch(v.createdAt))}'),
          trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: (stateColor).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: stateColor)), child: Text(stateText, style: TextStyle(color: stateColor, fontSize: 12, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }

  /// Mở chi tiết hóa đơn đã dùng mã
  Future<void> _openBill(VoucherModel v) async {
    final bill = await FirebaseService().getBill(v.redeemedBillId!);
    if (!mounted) return;
    if (bill == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không tìm thấy hóa đơn ${v.redeemedBillCode ?? v.redeemedBillId}')));
      return;
    }
    await BillDetailSheet.show(context, bill);
  }

  Future<void> _releaseAll(List<VoucherModel> vouchers) async {
    try {
      await _campaignService.releaseVouchers(widget.campaign.campaignId, vouchers.where((v) => v.state == VoucherState.draft.toMap()).map((v) => v.voucherId).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã phát hành tất cả mã draft')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  void _showGenerateDialog() {
    bool isCustom = false;
    String customCodes = '';
    int qty = 10;
    String prefix = '';
    int length = 6;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Phát hành mã Voucher'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Hàng loạt'),
                              selected: !isCustom,
                              onSelected: (val) {
                                if (val) setDialogState(() => isCustom = false);
                              },
                              selectedColor: context.tc.primary.withValues(alpha: 0.2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Text('Tự nhập mã'),
                              selected: isCustom,
                              onSelected: (val) {
                                if (val) setDialogState(() => isCustom = true);
                              },
                              selectedColor: context.tc.primary.withValues(alpha: 0.2),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isCustom) ...[
                        TextFormField(
                          minLines: 4,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: 'Danh sách mã *',
                            hintText: 'Mỗi dòng 1 mã hoặc cách nhau bởi dấu phẩy\nVD: CHAOBAN20, GIAM10K',
                            border: OutlineInputBorder(),
                          ),
                          textCapitalization: TextCapitalization.characters,
                          validator: (val) {
                            final parsed = parseVoucherCodes(val ?? '');
                            if (parsed.valid.isEmpty && parsed.invalid.isEmpty) return 'Vui lòng nhập mã';
                            if (parsed.invalid.isNotEmpty) {
                              return 'Mã không hợp lệ (A-Z, 0-9, -, _; 3-32 ký tự): ${parsed.invalid.join(", ")}';
                            }
                            return null;
                          },
                          onSaved: (val) => customCodes = val ?? '',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Mã sẽ được kích hoạt ngay và dùng được trên cả POS lẫn Web. Mã đã tồn tại sẽ bị bỏ qua.',
                          style: TextStyle(fontSize: 12, color: context.tc.textHint),
                        ),
                      ] else ...[
                        TextFormField(
                          initialValue: qty.toString(),
                          decoration: const InputDecoration(labelText: 'Số lượng mã'),
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            if (val == null || int.tryParse(val) == null) return 'Nhập số hợp lệ';
                            if (int.parse(val) <= 0 || int.parse(val) > 1000) return 'Từ 1 đến 1000';
                            return null;
                          },
                          onSaved: (val) => qty = int.parse(val!),
                        ),
                        TextFormField(
                          initialValue: prefix,
                          decoration: const InputDecoration(labelText: 'Tiền tố (VD: TRAM)'),
                          textCapitalization: TextCapitalization.characters,
                          onSaved: (val) => prefix = (val ?? '').trim().toUpperCase(),
                        ),
                        TextFormField(
                          initialValue: length.toString(),
                          decoration: const InputDecoration(labelText: 'Độ dài chuỗi ngẫu nhiên'),
                          keyboardType: TextInputType.number,
                          validator: (val) {
                            if (val == null || int.tryParse(val) == null) return 'Nhập số hợp lệ';
                            if (int.parse(val) < 4 || int.parse(val) > 12) return 'Từ 4 đến 12';
                            return null;
                          },
                          onSaved: (val) => length = int.parse(val!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('HỦY')),
                ElevatedButton(
                  onPressed: () async {
                    if (formKey.currentState!.validate()) {
                      formKey.currentState!.save();
                      Navigator.pop(context);
                      if (isCustom) {
                        await _createCodes(parseVoucherCodes(customCodes).valid);
                      } else {
                        await _generateCodes(qty, prefix, length);
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: context.tc.primary, foregroundColor: Colors.white),
                  child: const Text('TẠO MÃ'),
                )
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _createCodes(List<String> codes) async {
    try {
      final r = await _campaignService.createVouchers(widget.campaign.campaignId, codes, autoRelease: true);
      if (mounted) {
        final skipped = r.existing.isNotEmpty ? ' Bỏ qua ${r.existing.length} mã đã tồn tại: ${r.existing.take(10).join(", ")}' : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tạo ${r.created.length} mã.$skipped')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tạo mã: $e')));
      }
    }
  }

  Future<void> _generateCodes(int qty, String prefix, int length) =>
      _createCodes(generateRandomVoucherCodes(qty, prefix: prefix, length: length));
}
