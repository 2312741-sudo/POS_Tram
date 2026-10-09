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
      _stackingMode = widget.campaign!.stackingMode == 'ENABLED';
      _active = widget.campaign!.active;
      _tiers = List.from(widget.campaign!.tiers);
      _buyConditions = List.from(widget.campaign!.buyConditions);

      _includedItemIds = List.from(widget.campaign!.includedItemIds);
      _includedGroupIds = List.from(widget.campaign!.includedGroupIds);
      _daysOfWeek = List.from(widget.campaign!.schedule.daysOfWeek);
      _timeSlots = List.from(widget.campaign!.schedule.timeSlots);

      if (_tiers.isNotEmpty) {
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
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

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
            maxDiscountMoney: isPercent ? maxDisc : 0,
            maxRewardQty: 0,
            rewardItemIds: const [],
            sortOrder: 1,
          )
        ];
      }

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
        includedItemIds: _includedItemIds,
        includedGroupIds: _includedGroupIds,
        excludedItemIds: widget.campaign?.excludedItemIds ?? [],
        tiers: finalTiers,
        buyConditions: _buyConditions,
        budgetMoney: int.tryParse(_budgetController.text),
        maxUses: int.tryParse(_maxUsesController.text),
        maxUsesPerCustomer: int.tryParse(_maxUsesPerCustomerController.text),
        warnRepeatedCustomer: false,
        hasCodes: _hasCodes,
        autoApply: _autoApply,
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lưu thành công!')));
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

  void _showProductSelector() {
    String searchKeyword = '';
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            final filteredProds = _allProducts.where((p) {
              return p.name.toLowerCase().contains(searchKeyword.toLowerCase());
            }).toList();

            return AlertDialog(
              title: const Text('Chọn món hàng áp dụng'),
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
                                final isChecked = _includedItemIds.contains(p.id.toString());
                                return CheckboxListTile(
                                  title: Text(p.name),
                                  subtitle: Text('${FormatUtils.vnd(p.price)} • ${p.category}'),
                                  value: isChecked,
                                  onChanged: (val) {
                                    setDlgState(() {
                                      if (val == true) {
                                        _includedItemIds.add(p.id.toString());
                                      } else {
                                        _includedItemIds.remove(p.id.toString());
                                      }
                                    });
                                    setState(() {});
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
                  title: const Text('Tặng món theo GTĐ'),
                  subtitle: const Text('Tặng món khi hóa đơn đạt ngưỡng'),
                  value: CampaignType.orderValueItemBenefit,
                  activeColor: context.tc.primary,
                ),
                RadioListTile<CampaignType>(
                  title: const Text('Mua X tặng Y'),
                  subtitle: const Text('Mua đủ số lượng sẽ được tặng món'),
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
                      labelText: 'Trần tiền giảm tối đa (VND)',
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
                    labelText: 'Ngưỡng giá trị đơn tối thiểu (VND)',
                    hintText: 'Bỏ trống = Không yêu cầu đơn tối thiểu',
                    suffixText: 'đ',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ]),
            ],

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
                onChanged: (val) => setState(() => _hasCodes = val),
                activeThumbColor: context.tc.primary,
              ),
              SwitchListTile(
                title: const Text('Tự động áp dụng'),
                subtitle: const Text('Tự động tính giảm giá cho bill hợp lệ'),
                value: _autoApply,
                onChanged: (val) => setState(() => _autoApply = val),
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
