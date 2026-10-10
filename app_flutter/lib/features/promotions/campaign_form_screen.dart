import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/campaign_models.dart';
import '../../data/models/product_model.dart';
import '../../data/models/category_model.dart';
import '../../data/services/campaign_service.dart';
import '../../data/services/firebase_service.dart';
import '../../core/services/auth_service.dart';
import 'voucher_check.dart';
import 'voucher_management_screen.dart';

class CampaignFormScreen extends StatefulWidget {
  final CampaignModel? campaign;
  const CampaignFormScreen({super.key, this.campaign});

  @override
  State<CampaignFormScreen> createState() => _CampaignFormScreenState();
}

class _CampaignFormScreenState extends State<CampaignFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _campaignService = CampaignService();
  final _auth = AuthService();

  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _descController;
  late TextEditingController _budgetController;
  late TextEditingController _maxUsesController;
  late TextEditingController _maxUsesPerCustomerController;
  late TextEditingController _priorityController;

  // Discount config controllers
  late TextEditingController _thresholdController;
  late TextEditingController _discountValueController;
  late TextEditingController _maxDiscountController;
  String _discountType = 'PERCENT'; // 'PERCENT' | 'AMOUNT'

  CampaignType _campaignType = CampaignType.billDiscount;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _autoApply = true;
  bool _hasCodes = false;
  bool _requireStaffNote = false;
  bool _stackingMode = false;
  bool _active = true;

  // Included items & categories
  List<String> _includedItemIds = [];
  List<String> _includedGroupIds = [];

  // Happy hours & days of week
  List<int> _daysOfWeek = []; // 1..7 (1 = Thứ 2, 7 = CN)
  List<CampaignTimeSlot> _timeSlots = [];

  // Available metadata
  List<ProductModel> _allProducts = [];
  List<CategoryModel> _allCategories = [];

  List<CampaignTier> _tiers = [];
  List<CampaignBuyCondition> _buyConditions = [];

  // Danh sách mã voucher chủ quán tự định nghĩa (khi bật "Phát hành mã")
  final TextEditingController _codesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.campaign?.name ?? '');
    _codeController = TextEditingController(text: widget.campaign?.programCode ?? '');
    _descController = TextEditingController(text: widget.campaign?.description ?? '');
    _budgetController = TextEditingController(text: widget.campaign?.budgetMoney?.toString() ?? '');
    _maxUsesController = TextEditingController(text: widget.campaign?.maxUses?.toString() ?? '');
    _maxUsesPerCustomerController = TextEditingController(text: widget.campaign?.maxUsesPerCustomer?.toString() ?? '');
    _priorityController = TextEditingController(text: widget.campaign?.priority.toString() ?? '1');

    if (widget.campaign != null) {
      _campaignType = CampaignType.fromMap(widget.campaign!.campaignType);
      if (widget.campaign!.schedule.absoluteStart != null) {
        _startDate = DateTime.fromMillisecondsSinceEpoch(widget.campaign!.schedule.absoluteStart!);
      }
      if (widget.campaign!.schedule.absoluteEnd != null) {
        _endDate = DateTime.fromMillisecondsSinceEpoch(widget.campaign!.schedule.absoluteEnd!);
      }
      _autoApply = widget.campaign!.autoApply;
      _hasCodes = widget.campaign!.hasCodes;
      _requireStaffNote = widget.campaign!.requireStaffNote;
      _stackingMode = widget.campaign!.isStackable;
      _active = widget.campaign!.active;
      _tiers = List.from(widget.campaign!.tiers);
      _buyConditions = List.from(widget.campaign!.buyConditions);

      _includedItemIds = List.from(widget.campaign!.includedItemIds);
      _includedGroupIds = List.from(widget.campaign!.includedGroupIds);
      _daysOfWeek = List.from(widget.campaign!.schedule.daysOfWeek);
      _timeSlots = List.from(widget.campaign!.schedule.timeSlots);

      if (_tiers.isNotEmpty && _campaignType == CampaignType.billDiscount) {
        final tier = _tiers.first;
        final isPercent = tier.benefitMode == BenefitMode.percent.toMap() || tier.benefitMode == 'PERCENT';
        _discountType = isPercent ? 'PERCENT' : 'AMOUNT';
        final val = isPercent ? (tier.value > 100 ? tier.value ~/ 100 : tier.value) : tier.value;
        _discountValueController = TextEditingController(text: val > 0 ? val.toString() : '');
        _thresholdController = TextEditingController(text: tier.threshold > 0 ? tier.threshold.toString() : '');
        _maxDiscountController = TextEditingController(text: tier.maxDiscountMoney > 0 ? tier.maxDiscountMoney.toString() : '');
      } else {
        _thresholdController = TextEditingController();
        _discountValueController = TextEditingController();
        _maxDiscountController = TextEditingController();
      }
    } else {
      _thresholdController = TextEditingController();
      _discountValueController = TextEditingController();
      _maxDiscountController = TextEditingController();
      _generateCode();
    }

    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final prods = await FirebaseService().getProducts();
      final cats = await FirebaseService().getCategories();
      if (mounted) {
        setState(() {
          _allProducts = prods;
          _allCategories = cats;
        });
      }
    } catch (_) {}
  }

  Future<void> _generateCode() async {
    final code = _campaignService.generateProgramCode(DateTime.now().millisecond);
    if (mounted) {
      setState(() {
        _codeController.text = code;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _descController.dispose();
    _budgetController.dispose();
    _maxUsesController.dispose();
    _maxUsesPerCustomerController.dispose();
    _priorityController.dispose();
    _thresholdController.dispose();
    _discountValueController.dispose();
    _maxDiscountController.dispose();
    _codesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_campaignType == CampaignType.orderValueItemBenefit &&
        (_tiers.isEmpty || _tiers.any((t) => t.rewardItemIds.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng thêm ít nhất 1 mức ưu đãi và chọn món được tặng/giảm')));
      return;
    }
    if (_campaignType == CampaignType.buyXGetY &&
        (_buyConditions.isEmpty || _buyConditions.any((c) => c.buyItemIds.isEmpty || c.rewardItemIds.isEmpty))) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng thêm điều kiện: chọn món mua (X) và món được tặng/giảm (Y)')));
      return;
    }
    final parsedCodes = parseVoucherCodes(_codesController.text);
    if (_hasCodes && parsedCodes.invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Mã không hợp lệ (chỉ dùng A-Z, 0-9, "-", "_", 3-32 ký tự): ${parsedCodes.invalid.join(", ")}')));
      return;
    }

    try {
      final schedule = CampaignSchedule(
        absoluteStart: _startDate?.millisecondsSinceEpoch,
        absoluteEnd: _endDate?.millisecondsSinceEpoch,
        daysOfWeek: _daysOfWeek,
        timeSlots: _timeSlots,
      );

      // Xây dựng Tiers nếu là billDiscount
      List<CampaignTier> finalTiers = List.from(_tiers);
      if (_campaignType == CampaignType.billDiscount) {
        final val = int.tryParse(_discountValueController.text.trim()) ?? 0;
        final threshold = int.tryParse(_thresholdController.text.trim()) ?? 0;
        final maxDisc = int.tryParse(_maxDiscountController.text.trim()) ?? 0;
        final isPercent = _discountType == 'PERCENT';

        finalTiers = [
          CampaignTier(
            tierId: _tiers.isNotEmpty ? _tiers.first.tierId : 'TIER_1',
            conditionBasis: ConditionBasis.totalAmount.toMap(),
            threshold: threshold,
            benefitMode: isPercent ? BenefitMode.percent.toMap() : BenefitMode.fixed.toMap(),
            value: isPercent ? val * 100 : val, // basis points cho %
            maxDiscountMoney: maxDisc,
            maxRewardQty: 0,
            rewardItemIds: const [],
            sortOrder: 1,
          )
        ];
      } else if (_campaignType == CampaignType.buyXGetY) {
        finalTiers = [];
      } else if (_campaignType == CampaignType.orderValueItemBenefit) {
        finalTiers = [
          for (int i = 0; i < _tiers.length; i++) _tiers[i].copyWith(sortOrder: i + 1),
        ];
      }
      // Giảm giá đơn hàng / theo giá trị hóa đơn: áp dụng toàn bộ hóa đơn (không chọn món/nhóm)
      final scoped = _campaignType == CampaignType.itemPriceRule;

      final model = CampaignModel(
        campaignId: widget.campaign?.campaignId ?? _campaignService.generateCampaignId(),
        programCode: _codeController.text,
        name: _nameController.text.trim(),
        description: _descController.text.trim(),
        campaignType: _campaignType.toMap(),
        schedule: schedule,
        branchIds: widget.campaign?.branchIds ?? [],
        includedCustomerIds: widget.campaign?.includedCustomerIds ?? [],
        excludedCustomerIds: widget.campaign?.excludedCustomerIds ?? [],
        includedItemIds: scoped ? _includedItemIds : const [],
        includedGroupIds: scoped ? _includedGroupIds : const [],
        excludedItemIds: widget.campaign?.excludedItemIds ?? [],
        tiers: finalTiers,
        buyConditions: _campaignType == CampaignType.buyXGetY ? _buyConditions : const [],
        budgetMoney: int.tryParse(_budgetController.text),
        maxUses: int.tryParse(_maxUsesController.text),
        maxUsesPerCustomer: int.tryParse(_maxUsesPerCustomerController.text),
        warnRepeatedCustomer: false,
        hasCodes: _hasCodes,
        autoApply: _hasCodes ? false : _autoApply,
        requireStaffNote: _requireStaffNote,
        stackingMode: _stackingMode ? 'ENABLED' : 'DISABLED',
        priority: int.tryParse(_priorityController.text) ?? 1,
        active: _active,
        createdAt: widget.campaign?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        createdBy: widget.campaign?.createdBy ?? _auth.currentUser?.uid ?? '',
        version: (widget.campaign?.version ?? 0) + 1,
      );

      await _campaignService.saveCampaign(model);

      String codeMsg = '';
      if (_hasCodes && parsedCodes.valid.isNotEmpty) {
        final r = await _campaignService.createVouchers(model.campaignId, parsedCodes.valid, autoRelease: true);
        codeMsg = ' Đã tạo ${r.created.length} mã.';
        if (r.existing.isNotEmpty) codeMsg += ' Bỏ qua ${r.existing.length} mã đã tồn tại: ${r.existing.take(10).join(", ")}';
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lưu thành công!$codeMsg')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  void _showCategorySelector() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            return AlertDialog(
              title: const Text('Chọn nhóm hàng áp dụng'),
              content: SizedBox(
                width: 400,
                height: 350,
                child: _allCategories.isEmpty
                    ? const Center(child: Text('Không có nhóm hàng nào'))
                    : ListView.builder(
                        itemCount: _allCategories.length,
                        itemBuilder: (context, i) {
                          final cat = _allCategories[i];
                          final isChecked = _includedGroupIds.contains(cat.name);
                          return CheckboxListTile(
                            title: Text(cat.name),
                            value: isChecked,
                            onChanged: (val) {
                              setDlgState(() {
                                if (val == true) {
                                  _includedGroupIds.add(cat.name);
                                } else {
                                  _includedGroupIds.remove(cat.name);
                                }
                              });
                              setState(() {});
                            },
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Xong'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showProductSelector() => _pickProducts('Chọn món hàng áp dụng', _includedItemIds, () => setState(() {}));

  /// Hộp chọn nhiều món, cập nhật trực tiếp [selected]
  Future<void> _pickProducts(String title, List<String> selected, VoidCallback onChanged) {
    String searchKeyword = '';
    return showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final filteredProds = _allProducts.where((p) {
              return p.name.toLowerCase().contains(searchKeyword.toLowerCase());
            }).toList();

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 400,
                height: 450,
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Tìm kiếm món...',
                        prefixIcon: Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        setDlgState(() {
                          searchKeyword = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredProds.isEmpty
                          ? const Center(child: Text('Không tìm thấy món'))
                          : ListView.builder(
                              itemCount: filteredProds.length,
                              itemBuilder: (context, i) {
                                final p = filteredProds[i];
                                final isChecked = selected.contains(p.id.toString());
                                return CheckboxListTile(
                                  title: Text(p.name),
                                  subtitle: Text('${FormatUtils.vnd(p.price)} • ${p.category}'),
                                  value: isChecked,
                                  onChanged: (val) {
                                    setDlgState(() {
                                      if (val == true) {
                                        selected.add(p.id.toString());
                                      } else {
                                        selected.remove(p.id.toString());
                                      }
                                    });
                                    onChanged();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Xong'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _addTimeSlot() async {
    final startPicked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (startPicked == null) return;

    if (!mounted) return;
    final endPicked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (startPicked.hour + 2) % 24, minute: startPicked.minute),
    );
    if (endPicked == null) return;

    final startStr = '${startPicked.hour.toString().padLeft(2, '0')}:${startPicked.minute.toString().padLeft(2, '0')}';
    final endStr = '${endPicked.hour.toString().padLeft(2, '0')}:${endPicked.minute.toString().padLeft(2, '0')}';

    setState(() {
      _timeSlots.add(CampaignTimeSlot(startTime: startStr, endTime: endStr));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.surface,
      appBar: AppBar(
        title: Text(widget.campaign == null ? 'Tạo Khuyến mãi' : 'Sửa Khuyến mãi'),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _save,
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionTitle('Thông tin cơ bản'),
            _buildCard([
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Tên chương trình *', border: OutlineInputBorder()),
                validator: (val) => val == null || val.trim().isEmpty ? 'Vui lòng nhập tên chương trình' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Mã chương trình (Tự động)',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(icon: const Icon(Icons.refresh), onPressed: _generateCode),
                ),
                readOnly: widget.campaign != null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Mô tả', border: OutlineInputBorder()),
                maxLines: 2,
              ),
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Loại Khuyến Mãi'),
            RadioGroup<CampaignType>(
              groupValue: _campaignType,
              onChanged: (val) => setState(() => _campaignType = val!),
              child: _buildCard([
                RadioListTile<CampaignType>(
                  title: const Text('Giảm giá đơn hàng'),
                  subtitle: const Text('Giảm theo % hoặc số tiền trên tổng hóa đơn'),
                  value: CampaignType.billDiscount,
                  activeColor: context.tc.primary,
                ),
                RadioListTile<CampaignType>(
                  title: const Text('Giảm/tặng món theo giá trị hóa đơn'),
                  subtitle: const Text('Tặng hoặc giảm giá món khi hóa đơn đạt ngưỡng'),
                  value: CampaignType.orderValueItemBenefit,
                  activeColor: context.tc.primary,
                ),
                RadioListTile<CampaignType>(
                  title: const Text('Mua X tặng/giảm giá Y'),
                  subtitle: const Text('Mua đủ số lượng món X được tặng hoặc giảm giá món Y'),
                  value: CampaignType.buyXGetY,
                  activeColor: context.tc.primary,
                ),
                RadioListTile<CampaignType>(
                  title: const Text('Đồng giá / Đồng giảm'),
                  subtitle: const Text('Áp dụng mức giá cố định cho một số món'),
                  value: CampaignType.itemPriceRule,
                  activeColor: context.tc.primary,
                ),
              ]),
            ),

            if (_campaignType == CampaignType.billDiscount) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('Cấu hình mức giảm giá'),
              _buildCard([
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Áp dụng cho toàn bộ hóa đơn (không cần chọn món).',
                      style: TextStyle(fontSize: 12, color: context.tc.textHint, fontStyle: FontStyle.italic)),
                ),
                RadioGroup<String>(
                  groupValue: _discountType,
                  onChanged: (v) => setState(() => _discountType = v!),
                  child: Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Giảm theo %'),
                          value: 'PERCENT',
                          activeColor: context.tc.primary,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Giảm số tiền (VND)'),
                          value: 'AMOUNT',
                          activeColor: context.tc.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _discountValueController,
                  decoration: InputDecoration(
                    labelText: _discountType == 'PERCENT' ? 'Tỷ lệ giảm (%) *' : 'Số tiền giảm trực tiếp (VND) *',
                    suffixText: _discountType == 'PERCENT' ? '%' : 'đ',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'Vui lòng nhập mức giảm';
                    final n = int.tryParse(val.trim());
                    if (n == null || n <= 0) return 'Giá trị phải lớn hơn 0';
                    if (_discountType == 'PERCENT' && n > 100) return 'Tỷ lệ % tối đa là 100%';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_discountType == 'PERCENT') ...[
                  TextFormField(
                    controller: _maxDiscountController,
                    decoration: const InputDecoration(
                      labelText: 'Giảm tối đa (VND)',
                      hintText: 'Bỏ trống = Không giới hạn',
                      suffixText: 'đ',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _thresholdController,
                  decoration: const InputDecoration(
                    labelText: 'Đơn hàng từ (VND)',
                    hintText: 'Bỏ trống = Áp dụng mọi hóa đơn',
                    suffixText: 'đ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ]),
            ],

            if (_campaignType == CampaignType.orderValueItemBenefit) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('Mức ưu đãi theo giá trị hóa đơn'),
              _buildOrderValueTiers(),
            ],

            if (_campaignType == CampaignType.buyXGetY) ...[
              const SizedBox(height: 16),
              _buildSectionTitle('Điều kiện Mua X tặng/giảm giá Y'),
              _buildBuyConditions(),
            ],

            if (_campaignType == CampaignType.itemPriceRule) ...[
            const SizedBox(height: 16),
            _buildSectionTitle('Phạm vi áp dụng (Nhóm & Món)'),
            _buildCard([
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Nhóm hàng áp dụng:', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _showCategorySelector,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Chọn nhóm'),
                  ),
                ],
              ),
              if (_includedGroupIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Tất cả nhóm hàng (Không giới hạn)', style: TextStyle(color: context.tc.textHint, fontStyle: FontStyle.italic)),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _includedGroupIds.map((catName) {
                    return Chip(
                      label: Text(catName),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _includedGroupIds.remove(catName)),
                      backgroundColor: context.tc.surface,
                    );
                  }).toList(),
                ),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Món hàng áp dụng:', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _showProductSelector,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Chọn món'),
                  ),
                ],
              ),
              if (_includedItemIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Tất cả món hàng (Không giới hạn)', style: TextStyle(color: context.tc.textHint, fontStyle: FontStyle.italic)),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _includedItemIds.map((itemId) {
                    final prod = _allProducts.where((p) => p.id.toString() == itemId).firstOrNull;
                    final name = prod?.name ?? 'Món #$itemId';
                    return Chip(
                      label: Text(name),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () => setState(() => _includedItemIds.remove(itemId)),
                      backgroundColor: context.tc.surface,
                    );
                  }).toList(),
                ),
            ]),
            ],

            const SizedBox(height: 16),
            _buildSectionTitle('Khung giờ & Ngày áp dụng'),
            _buildCard([
              const Text('Ngày trong tuần:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  {'label': 'T2', 'day': 1},
                  {'label': 'T3', 'day': 2},
                  {'label': 'T4', 'day': 3},
                  {'label': 'T5', 'day': 4},
                  {'label': 'T6', 'day': 5},
                  {'label': 'T7', 'day': 6},
                  {'label': 'CN', 'day': 7},
                ].map((d) {
                  final dayNum = d['day'] as int;
                  final isSelected = _daysOfWeek.contains(dayNum);
                  return FilterChip(
                    label: Text(d['label'] as String),
                    selected: isSelected,
                    selectedColor: context.tc.primary.withValues(alpha: 0.2),
                    checkmarkColor: context.tc.primary,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _daysOfWeek.add(dayNum);
                        } else {
                          _daysOfWeek.remove(dayNum);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 12),
                child: Text(
                  _daysOfWeek.isEmpty ? 'Áp dụng tất cả các ngày trong tuần' : 'Chỉ áp dụng các ngày đã chọn',
                  style: TextStyle(fontSize: 12, color: context.tc.textHint),
                ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Khung giờ (Happy hours):', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addTimeSlot,
                    icon: const Icon(Icons.add_alarm, size: 16),
                    label: const Text('Thêm khung giờ'),
                  ),
                ],
              ),
              if (_timeSlots.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('Áp dụng toàn bộ khung giờ trong ngày', style: TextStyle(color: context.tc.textHint, fontStyle: FontStyle.italic)),
                )
              else
                Column(
                  children: _timeSlots.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final slot = entry.value;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.access_time, color: context.tc.primary),
                      title: Text('${slot.startTime} - ${slot.endTime}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => setState(() => _timeSlots.removeAt(idx)),
                      ),
                    );
                  }).toList(),
                ),
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Lịch áp dụng (Ngày)'),
            _buildCard([
              ListTile(
                title: const Text('Ngày bắt đầu'),
                subtitle: Text(_startDate == null ? 'Không giới hạn' : DateFormat('dd/MM/yyyy HH:mm').format(_startDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setState(() => _startDate = date);
                  }
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Ngày kết thúc'),
                subtitle: Text(_endDate == null ? 'Không giới hạn' : DateFormat('dd/MM/yyyy HH:mm').format(_endDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? (_startDate ?? DateTime.now()),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (date != null) {
                    setState(() => _endDate = date);
                  }
                },
              ),
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Hạn mức'),
            _buildCard([
              TextFormField(
                controller: _budgetController,
                decoration: const InputDecoration(labelText: 'Ngân sách tổng (VND)', border: OutlineInputBorder(), hintText: 'Bỏ trống = Không giới hạn'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxUsesController,
                decoration: const InputDecoration(labelText: 'Giới hạn tổng số lượt', border: OutlineInputBorder(), hintText: 'Bỏ trống = Không giới hạn'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxUsesPerCustomerController,
                decoration: const InputDecoration(labelText: 'Giới hạn lượt/khách', border: OutlineInputBorder(), hintText: 'Bỏ trống = Không giới hạn'),
                keyboardType: TextInputType.number,
              ),
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Cài đặt khác'),
            _buildCard([
              SwitchListTile(
                title: const Text('Bắt buộc ghi chú khi dùng mã'),
                subtitle: const Text('Nhân viên phải nhập lý do/ghi chú khi áp dụng mã'),
                value: _requireStaffNote,
                onChanged: (val) => setState(() => _requireStaffNote = val),
                activeThumbColor: context.tc.primary,
              ),
              SwitchListTile(
                title: const Text('Có phát hành mã (Voucher)'),
                subtitle: const Text('Khách cần nhập mã để được áp dụng'),
                value: _hasCodes,
                onChanged: (val) => setState(() {
                  _hasCodes = val;
                  if (val) _autoApply = false;
                }),
                activeThumbColor: context.tc.primary,
              ),
              if (_hasCodes) _buildCodesEditor(),
              SwitchListTile(
                title: const Text('Tự động áp dụng'),
                subtitle: Text(_hasCodes ? 'Không áp dụng khi chương trình dùng mã' : 'Tự động tính giảm giá cho bill hợp lệ'),
                value: _hasCodes ? false : _autoApply,
                onChanged: _hasCodes ? null : (val) => setState(() => _autoApply = val),
                activeThumbColor: context.tc.primary,
              ),
              SwitchListTile(
                title: const Text('Cho phép cộng dồn'),
                subtitle: const Text('Được áp dụng chung với KM khác'),
                value: _stackingMode,
                onChanged: (val) => setState(() => _stackingMode = val),
                activeThumbColor: context.tc.primary,
              ),
              SwitchListTile(
                title: const Text('Kích hoạt chương trình'),
                subtitle: const Text('Bật để chương trình hoạt động ngay'),
                value: _active,
                onChanged: (val) => setState(() => _active = val),
                activeThumbColor: context.tc.primary,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextFormField(
                  controller: _priorityController,
                  decoration: const InputDecoration(labelText: 'Mức độ ưu tiên (Số nhỏ = Ưu tiên cao hơn)', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                ),
              ),
            ]),

            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.tc.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('LƯU CHƯƠNG TRÌNH', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ==================== MÃ VOUCHER ====================

  Widget _buildCodesEditor() {
    final parsed = parseVoucherCodes(_codesController.text);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _codesController,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: widget.campaign == null ? 'Danh sách mã' : 'Thêm mã mới',
              hintText: 'Mỗi dòng 1 mã hoặc cách nhau bởi dấu phẩy\nVD: TRAM10K, CHAOBAN20',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${parsed.valid.length} mã hợp lệ'
            '${parsed.duplicated.isNotEmpty ? " • trùng: ${parsed.duplicated.join(", ")}" : ""}'
            '${parsed.invalid.isNotEmpty ? " • KHÔNG hợp lệ: ${parsed.invalid.join(", ")}" : ""}',
            style: TextStyle(fontSize: 12, color: parsed.invalid.isNotEmpty ? Colors.red : context.tc.textHint),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: _showRandomCodesDialog,
                icon: const Icon(Icons.casino_outlined, size: 16),
                label: const Text('Tạo mã ngẫu nhiên'),
              ),
              if (widget.campaign != null)
                TextButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => VoucherManagementScreen(campaign: widget.campaign!))),
                  icon: const Icon(Icons.list_alt, size: 16),
                  label: const Text('Xem danh sách mã đã tạo'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showRandomCodesDialog() async {
    final qtyCtrl = TextEditingController(text: '10');
    final prefixCtrl = TextEditingController();
    final lenCtrl = TextEditingController(text: '6');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo mã ngẫu nhiên'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số lượng mã (1-1000)')),
            TextField(controller: prefixCtrl, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Tiền tố (VD: TRAM)')),
            TextField(controller: lenCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Độ dài phần ngẫu nhiên (4-12)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
        ],
      ),
    );
    if (ok != true) return;
    final qty = (int.tryParse(qtyCtrl.text.trim()) ?? 0).clamp(1, 1000);
    final len = (int.tryParse(lenCtrl.text.trim()) ?? 6).clamp(4, 12);
    final codes = generateRandomVoucherCodes(qty, prefix: prefixCtrl.text, length: len);
    setState(() {
      final cur = _codesController.text.trim();
      _codesController.text = [if (cur.isNotEmpty) cur, ...codes].join('\n');
    });
  }

  // ==================== CẤU HÌNH ƯU ĐÃI MÓN ====================

  static const _benefitModes = {
    'FREEITEM': 'Tặng (100%)',
    'PERCENT': 'Giảm %',
    'FIXED': 'Giảm số tiền',
  };

  String _modeKey(String mode) {
    final u = mode.toUpperCase().replaceAll('_', '');
    if (u == 'FREEITEM' || u == 'FREE' || u == 'GIFT') return 'FREEITEM';
    if (u == 'PERCENT' || u == 'DISCOUNTPERCENT') return 'PERCENT';
    return 'FIXED';
  }

  String _benefitText(String mode, int value) {
    switch (_modeKey(mode)) {
      case 'FREEITEM':
        return 'Tặng';
      case 'PERCENT':
        return 'Giảm ${value ~/ 100}%';
      default:
        return 'Giảm ${FormatUtils.vnd(value)}';
    }
  }

  String _productNames(List<String> ids) {
    if (ids.isEmpty) return '(chưa chọn)';
    return ids.map((id) => _allProducts.where((p) => p.id.toString() == id).firstOrNull?.name ?? 'Món #$id').join(', ');
  }

  /// Ô nhập + chọn cách tính ưu đãi dùng chung cho 2 loại
  List<Widget> _benefitInputs(
    String mode,
    TextEditingController valueCtrl,
    void Function(String) onMode,
  ) {
    return [
      DropdownButtonFormField<String>(
        initialValue: _modeKey(mode),
        decoration: const InputDecoration(labelText: 'Ưu đãi cho món', border: OutlineInputBorder()),
        items: _benefitModes.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) => onMode(v ?? 'FREEITEM'),
      ),
      if (_modeKey(mode) != 'FREEITEM') ...[
        const SizedBox(height: 8),
        TextField(
          controller: valueCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: _modeKey(mode) == 'PERCENT' ? 'Giảm (%) mỗi món' : 'Giảm số tiền mỗi món (VND)',
            suffixText: _modeKey(mode) == 'PERCENT' ? '%' : 'đ',
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    ];
  }

  int _valueFromInput(String mode, String text) {
    final n = int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    switch (_modeKey(mode)) {
      case 'FREEITEM':
        return 0;
      case 'PERCENT':
        return n.clamp(0, 100) * 100; // basis points
      default:
        return n;
    }
  }

  String _valueToInput(String mode, int value) {
    if (_modeKey(mode) == 'PERCENT') return value > 0 ? '${value ~/ 100}' : '';
    if (_modeKey(mode) == 'FIXED') return value > 0 ? '$value' : '';
    return '';
  }

  Widget _buildOrderValueTiers() {
    return _buildCard([
      if (_tiers.isEmpty)
        Text('Chưa có mức ưu đãi nào', style: TextStyle(color: context.tc.textHint, fontStyle: FontStyle.italic)),
      ..._tiers.asMap().entries.map((e) {
        final t = e.value;
        final qty = t.maxRewardQty > 0 ? t.maxRewardQty : 1;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.card_giftcard),
          title: Text('Đơn hàng từ ${FormatUtils.vnd(t.threshold)}'),
          subtitle: Text('${_benefitText(t.benefitMode, t.value)} tối đa $qty món: ${_productNames(t.rewardItemIds)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editTier(e.key)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => _tiers.removeAt(e.key))),
          ]),
        );
      }),
      TextButton.icon(onPressed: () => _editTier(null), icon: const Icon(Icons.add), label: const Text('Thêm mức ưu đãi')),
      Text('Món được tặng/giảm phải có trong hóa đơn (nhân viên thêm món vào đơn). Đơn đạt nhiều mức sẽ lấy mức cao nhất.',
          style: TextStyle(fontSize: 12, color: context.tc.textHint)),
    ]);
  }

  Future<void> _editTier(int? index) async {
    final old = index != null ? _tiers[index] : null;
    final thresholdCtrl = TextEditingController(text: old != null && old.threshold > 0 ? '${old.threshold}' : '');
    String mode = old?.benefitMode ?? 'FREEITEM';
    final valueCtrl = TextEditingController(text: old != null ? _valueToInput(old.benefitMode, old.value) : '');
    final qtyCtrl = TextEditingController(text: '${old != null && old.maxRewardQty > 0 ? old.maxRewardQty : 1}');
    final rewardIds = List<String>.from(old?.rewardItemIds ?? const []);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Mức ưu đãi'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  controller: thresholdCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Áp dụng khi đơn hàng từ', suffixText: 'đ', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ..._benefitInputs(mode, valueCtrl, (m) => setDlg(() => mode = m)),
                const SizedBox(height: 8),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng món tối đa được tặng/giảm', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Món được tặng/giảm'),
                  subtitle: Text(_productNames(rewardIds)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickProducts('Chọn món được tặng/giảm', rewardIds, () => setDlg(() {})),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                if (rewardIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn món được tặng/giảm')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final tier = CampaignTier(
      tierId: old?.tierId ?? 'TIER_${DateTime.now().millisecondsSinceEpoch}',
      conditionBasis: ConditionBasis.totalAmount.toMap(),
      threshold: int.tryParse(thresholdCtrl.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      benefitMode: _modeKey(mode),
      value: _valueFromInput(mode, valueCtrl.text),
      maxDiscountMoney: 0,
      maxRewardQty: (int.tryParse(qtyCtrl.text.trim()) ?? 1).clamp(1, 999),
      rewardItemIds: rewardIds,
      sortOrder: (index ?? _tiers.length) + 1,
    );
    setState(() {
      if (index != null) {
        _tiers[index] = tier;
      } else {
        _tiers.add(tier);
      }
    });
  }

  Widget _buildBuyConditions() {
    return _buildCard([
      if (_buyConditions.isEmpty)
        Text('Chưa có điều kiện nào', style: TextStyle(color: context.tc.textHint, fontStyle: FontStyle.italic)),
      ..._buyConditions.asMap().entries.map((e) {
        final c = e.value;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.shopping_basket_outlined),
          title: Text('Mua ${c.requiredBuyQty}: ${_productNames(c.buyItemIds)}'),
          subtitle: Text('${_benefitText(c.benefitMode, c.value)} ${c.rewardQty}: ${_productNames(c.rewardItemIds)}'
              '${c.multiplyByBundle ? "\n(Nhân theo số món X bán ra)" : ""}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _editCondition(e.key)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => setState(() => _buyConditions.removeAt(e.key))),
          ]),
        );
      }),
      TextButton.icon(onPressed: () => _editCondition(null), icon: const Icon(Icons.add), label: const Text('Thêm điều kiện')),
      Text('Món Y phải có trong hóa đơn; ưu đãi áp vào món Y rẻ nhất trước.', style: TextStyle(fontSize: 12, color: context.tc.textHint)),
    ]);
  }

  Future<void> _editCondition(int? index) async {
    final old = index != null ? _buyConditions[index] : null;
    final buyIds = List<String>.from(old?.buyItemIds ?? const []);
    final rewardIds = List<String>.from(old?.rewardItemIds ?? const []);
    final buyQtyCtrl = TextEditingController(text: '${old != null && old.requiredBuyQty > 0 ? old.requiredBuyQty : 1}');
    final rewardQtyCtrl = TextEditingController(text: '${old != null && old.rewardQty > 0 ? old.rewardQty : 1}');
    // Điều kiện cũ có thể lưu PERCENT/0 mặc định -> hiển thị là Tặng
    String mode = old == null || (_modeKey(old.benefitMode) != 'FREEITEM' && old.value <= 0) ? 'FREEITEM' : old.benefitMode;
    final valueCtrl = TextEditingController(text: old != null ? _valueToInput(old.benefitMode, old.value) : '');
    bool multiply = old?.multiplyByBundle ?? true;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Điều kiện Mua X tặng/giảm giá Y'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hàng mua (X)'),
                  subtitle: Text(_productNames(buyIds)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickProducts('Chọn hàng mua (X)', buyIds, () => setDlg(() {})),
                ),
                TextField(
                  controller: buyQtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng X cần mua', border: OutlineInputBorder()),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Hàng được tặng/giảm giá (Y)'),
                  subtitle: Text(_productNames(rewardIds)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickProducts('Chọn hàng được tặng/giảm (Y)', rewardIds, () => setDlg(() {})),
                ),
                TextField(
                  controller: rewardQtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Số lượng Y được tặng/giảm', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                ..._benefitInputs(mode, valueCtrl, (m) => setDlg(() => mode = m)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: multiply,
                  onChanged: (v) => setDlg(() => multiply = v ?? false),
                  title: const Text('Áp dụng số món Y tặng theo số món X bán ra'),
                  subtitle: Text(multiply
                      ? 'VD: mua 1 tặng 1, bán 5 X → 5 Y được ưu đãi'
                      : 'Mua bao nhiêu X cũng chỉ ưu đãi đúng số lượng Y đã nhập (1 lần)'),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                if (buyIds.isEmpty || rewardIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn hàng mua (X) và hàng tặng/giảm (Y)')));
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final cond = CampaignBuyCondition(
      conditionId: old?.conditionId ?? 'BC_${DateTime.now().millisecondsSinceEpoch}',
      buyItemIds: buyIds,
      requiredBuyQty: (int.tryParse(buyQtyCtrl.text.trim()) ?? 1).clamp(1, 999),
      rewardItemIds: rewardIds,
      rewardQty: (int.tryParse(rewardQtyCtrl.text.trim()) ?? 1).clamp(1, 999),
      benefitMode: _modeKey(mode),
      value: _valueFromInput(mode, valueCtrl.text),
      multiplyByBundle: multiply,
    );
    setState(() {
      if (index != null) {
        _buyConditions[index] = cond;
      } else {
        _buyConditions.add(cond);
      }
    });
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.bold, color: context.tc.textHint, fontSize: 13),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: context.tc.border)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}
