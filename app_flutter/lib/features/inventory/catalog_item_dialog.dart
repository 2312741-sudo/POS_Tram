import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';

class CatalogItemDialog extends StatefulWidget {
  final CatalogItemModel? item;

  const CatalogItemDialog({super.key, this.item});

  @override
  State<CatalogItemDialog> createState() => _CatalogItemDialogState();
}

class _CatalogItemDialogState extends State<CatalogItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _inventoryService = InventoryService();
  
  late TextEditingController _skuCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _groupCtrl;
  late TextEditingController _unitCtrl;
  late TextEditingController _costCtrl;
  late TextEditingController _minStockCtrl;
  late TextEditingController _maxStockCtrl;
  late TextEditingController _descCtrl;
  
  String _selectedKind = 'rawMaterial';
  bool _trackStock = true;
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _skuCtrl = TextEditingController(text: item?.sku ?? '');
    _nameCtrl = TextEditingController(text: item?.name ?? '');
    _groupCtrl = TextEditingController(text: item?.managementGroup ?? '');
    _unitCtrl = TextEditingController(text: item?.baseUnitId ?? '');
    _costCtrl = TextEditingController(text: item?.costPrice.toString() ?? '0');
    _minStockCtrl = TextEditingController(text: item?.minStock.toString() ?? '0');
    _maxStockCtrl = TextEditingController(text: item?.maxStock.toString() ?? '0');
    _descCtrl = TextEditingController(text: item?.description ?? '');
    
    if (item != null) {
      _selectedKind = item.kind ?? 'rawMaterial';
      _trackStock = item.trackStock;
      _isActive = item.isActive;
    }
  }

  @override
  void dispose() {
    _skuCtrl.dispose();
    _nameCtrl.dispose();
    _groupCtrl.dispose();
    _unitCtrl.dispose();
    _costCtrl.dispose();
    _minStockCtrl.dispose();
    _maxStockCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newItem = CatalogItemModel(
        itemId: widget.item?.itemId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        sku: _skuCtrl.text.isEmpty ? null : _skuCtrl.text,
        name: _nameCtrl.text,
        kind: _selectedKind,
        managementGroup: _groupCtrl.text,
        baseUnitId: _unitCtrl.text,
        costPrice: int.tryParse(_costCtrl.text) ?? 0,
        minStock: int.tryParse(_minStockCtrl.text) ?? 0,
        maxStock: int.tryParse(_maxStockCtrl.text) ?? 0,
        trackStock: _trackStock,
        status: _isActive ? 'ACTIVE' : 'DISCONTINUED',
        description: _descCtrl.text,
        createdAt: widget.item?.createdAt ?? now,
        updatedAt: now,
      );

      await _inventoryService.saveCatalogItem(newItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lưu hàng hóa thành công', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.successLight)
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu: \$e', style: const TextStyle(color: Colors.white)), backgroundColor: AppColors.danger)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16, right: 16, top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.item == null ? 'Thêm hàng hóa mới' : 'Cập nhật hàng hóa',
                style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _skuCtrl,
                decoration: const InputDecoration(labelText: 'Mã hàng (để trống tự tạo)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Tên hàng *'),
                validator: (v) => v == null || v.isEmpty ? 'Không được để trống' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedKind,
                decoration: const InputDecoration(labelText: 'Loại'),
                items: const [
                  DropdownMenuItem(value: 'rawMaterial', child: Text('Nguyên vật liệu (NVL)')),
                  DropdownMenuItem(value: 'tool', child: Text('Công cụ dụng cụ (CCDC)')),
                  DropdownMenuItem(value: 'directSale', child: Text('Hàng bán trực tiếp')),
                ],
                onChanged: (v) => setState(() => _selectedKind = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _groupCtrl,
                decoration: const InputDecoration(labelText: 'Nhóm quản lý'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitCtrl,
                decoration: const InputDecoration(labelText: 'Đơn vị cơ bản *'),
                validator: (v) => v == null || v.isEmpty ? 'Không được để trống' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costCtrl,
                      decoration: const InputDecoration(labelText: 'Giá vốn'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _minStockCtrl,
                      decoration: const InputDecoration(labelText: 'Tồn tối thiểu'),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Quản lý tồn kho'),
                value: _trackStock,
                onChanged: (v) => setState(() => _trackStock = v),
              ),
              SwitchListTile(
                title: const Text('Đang hoạt động'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _save,
                child: const Text('Lưu lại'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
