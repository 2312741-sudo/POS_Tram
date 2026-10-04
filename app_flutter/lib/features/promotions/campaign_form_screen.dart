import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/campaign_service.dart';
import '../../core/services/auth_service.dart';

class CampaignFormScreen extends StatefulWidget {
  final CampaignModel? campaign;
  const CampaignFormScreen({Key? key, this.campaign}) : super(key: key);

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

  CampaignType _campaignType = CampaignType.billDiscount;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _autoApply = true;
  bool _hasCodes = false;
  bool _stackingMode = false;
  bool _active = true;

  // Tiện ích cho Form (chưa implement full detail cho từng bậc)
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
      _stackingMode = widget.campaign!.stackingMode == 'ENABLED';
      _active = widget.campaign!.active;
      _tiers = List.from(widget.campaign!.tiers);
      _buyConditions = List.from(widget.campaign!.buyConditions);
    } else {
      _generateCode();
    }
  }

  Future<void> _generateCode() async {
    final code = await _campaignService.generateProgramCode(DateTime.now().millisecond);
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
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final schedule = CampaignSchedule(
        absoluteStart: _startDate?.millisecondsSinceEpoch,
        absoluteEnd: _endDate?.millisecondsSinceEpoch,
      );

      final model = CampaignModel(
        campaignId: widget.campaign?.campaignId ?? _campaignService.generateCampaignId(),
        programCode: _codeController.text,
        name: _nameController.text,
        description: _descController.text,
        campaignType: _campaignType.toMap(),
        schedule: schedule,
        branchIds: widget.campaign?.branchIds ?? [], // Thêm UI chọn branch sau
        includedCustomerIds: widget.campaign?.includedCustomerIds ?? [],
        excludedCustomerIds: widget.campaign?.excludedCustomerIds ?? [],
        includedItemIds: widget.campaign?.includedItemIds ?? [],
        includedGroupIds: widget.campaign?.includedGroupIds ?? [],
        excludedItemIds: widget.campaign?.excludedItemIds ?? [],
        tiers: _tiers,
        buyConditions: _buyConditions,
        budgetMoney: int.tryParse(_budgetController.text),
        maxUses: int.tryParse(_maxUsesController.text),
        maxUsesPerCustomer: int.tryParse(_maxUsesPerCustomerController.text),
        warnRepeatedCustomer: false,
        hasCodes: _hasCodes,
        autoApply: _autoApply,
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: \$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TramColors.brandSurface,
      appBar: AppBar(
        title: Text(widget.campaign == null ? 'Tạo Khuyến mãi' : 'Sửa Khuyến mãi'),
        backgroundColor: TramColors.brandPrimary,
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
                validator: (val) => val == null || val.isEmpty ? 'Vui lòng nhập tên' : null,
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
                maxLines: 3,
              ),
            ]),
            
            const SizedBox(height: 16),
            _buildSectionTitle('Loại KM'),
            _buildCard([
              RadioListTile<CampaignType>(
                title: const Text('Giảm giá đơn hàng'),
                subtitle: const Text('Giảm theo % hoặc số tiền trên tổng hóa đơn'),
                value: CampaignType.billDiscount,
                groupValue: _campaignType,
                onChanged: (val) {
                  setState(() => _campaignType = val!);
                },
                activeColor: TramColors.brandPrimary,
              ),
              RadioListTile<CampaignType>(
                title: const Text('Tặng món theo GTĐ'),
                subtitle: const Text('Tặng món khi hóa đơn đạt ngưỡng'),
                value: CampaignType.orderValueItemBenefit,
                groupValue: _campaignType,
                onChanged: (val) {
                  setState(() => _campaignType = val!);
                },
                activeColor: TramColors.brandPrimary,
              ),
              RadioListTile<CampaignType>(
                title: const Text('Mua X tặng Y'),
                subtitle: const Text('Mua đủ số lượng sẽ được tặng món'),
                value: CampaignType.buyXGetY,
                groupValue: _campaignType,
                onChanged: (val) {
                  setState(() => _campaignType = val!);
                },
                activeColor: TramColors.brandPrimary,
              ),
              RadioListTile<CampaignType>(
                title: const Text('Đồng giá / Đồng giảm'),
                subtitle: const Text('Áp dụng mức giá cố định cho một số món'),
                value: CampaignType.itemPriceRule,
                groupValue: _campaignType,
                onChanged: (val) {
                  setState(() => _campaignType = val!);
                },
                activeColor: TramColors.brandPrimary,
              ),
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Điều kiện & Bậc (Tóm tắt)'),
            _buildCard([
              const Text('Cấu hình chi tiết điều kiện áp dụng dựa theo loại KM được chọn.'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Show complex dialog for tiers configuration
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tính năng thêm điều kiện chi tiết đang phát triển')));
                },
                icon: const Icon(Icons.add),
                label: const Text('Thêm bậc/điều kiện'),
                style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary, foregroundColor: Colors.white),
              )
            ]),

            const SizedBox(height: 16),
            _buildSectionTitle('Lịch áp dụng'),
            _buildCard([
              ListTile(
                title: const Text('Ngày bắt đầu'),
                subtitle: Text(_startDate == null ? 'Không giới hạn' : DateFormat('dd/MM/yyyy HH:mm').format(_startDate!)),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final date = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
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
                  final date = await showDatePicker(context: context, initialDate: _endDate ?? (_startDate ?? DateTime.now()), firstDate: DateTime(2020), lastDate: DateTime(2030));
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
                title: const Text('Tự động áp dụng'),
                subtitle: const Text('Tự động tính giảm giá cho bill hợp lệ'),
                value: _autoApply,
                onChanged: (val) => setState(() => _autoApply = val),
                activeColor: TramColors.brandPrimary,
              ),
              SwitchListTile(
                title: const Text('Có phát hành mã (Voucher)'),
                subtitle: const Text('Khách cần nhập mã để được áp dụng'),
                value: _hasCodes,
                onChanged: (val) => setState(() => _hasCodes = val),
                activeColor: TramColors.brandPrimary,
              ),
              SwitchListTile(
                title: const Text('Cho phép cộng dồn'),
                subtitle: const Text('Được áp dụng chung với KM khác'),
                value: _stackingMode,
                onChanged: (val) => setState(() => _stackingMode = val),
                activeColor: TramColors.brandPrimary,
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
                backgroundColor: TramColors.brandPrimary,
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
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey[300]!)),
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
