import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';

class SupplierDialog extends StatefulWidget {
  final SupplierModel? supplier;

  const SupplierDialog({super.key, this.supplier});

  @override
  State<SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _inventoryService = InventoryService();
  
  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _taxIdCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _groupCtrl;
  late TextEditingController _noteCtrl;
  
  bool _isActive = true;

  @override
  void initState() {
    super.initState();
    final sup = widget.supplier;
    _codeCtrl = TextEditingController(text: sup?.supplierCode ?? '');
    _nameCtrl = TextEditingController(text: sup?.name ?? '');
    _phoneCtrl = TextEditingController(text: sup?.phone ?? '');
    _emailCtrl = TextEditingController(text: sup?.email ?? '');
    _taxIdCtrl = TextEditingController(text: sup?.taxId ?? '');
    _addressCtrl = TextEditingController(text: sup?.address ?? '');
    _groupCtrl = TextEditingController(text: sup?.groupId ?? '');
    _noteCtrl = TextEditingController(text: sup?.note ?? '');
    
    if (sup != null) {
      _isActive = sup.status == 'ACTIVE';
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _taxIdCtrl.dispose();
    _addressCtrl.dispose();
    _groupCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final newSup = SupplierModel(
        supplierId: widget.supplier?.supplierId ?? DateTime.now().millisecondsSinceEpoch.toString(),
        supplierCode: _codeCtrl.text.isEmpty ? 'NCC${now.toString().substring(5)}' : _codeCtrl.text,
        name: _nameCtrl.text,
        phone: _phoneCtrl.text,
        email: _emailCtrl.text,
        taxId: _taxIdCtrl.text,
        address: _addressCtrl.text,
        groupId: _groupCtrl.text,
        note: _noteCtrl.text,
        status: _isActive ? 'ACTIVE' : 'INACTIVE',
        createdAt: widget.supplier?.createdAt ?? now,
        updatedAt: now,
      );

      await _inventoryService.saveSupplier(newSup);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Lưu nhà cung cấp thành công', style: TextStyle(color: Colors.white)), backgroundColor: context.tc.successLight)
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu: $e', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.danger)
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
                widget.supplier == null ? 'Thêm nhà cung cấp' : 'Cập nhật nhà cung cấp',
                style: GoogleFonts.beVietnamPro(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _codeCtrl,
                decoration: const InputDecoration(labelText: 'Mã NCC (để trống tự tạo)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Tên nhà cung cấp *'),
                validator: (v) => v == null || v.isEmpty ? 'Không được để trống' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(labelText: 'Số điện thoại *'),
                validator: (v) => v == null || v.isEmpty ? 'Không được để trống' : null,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _taxIdCtrl,
                decoration: const InputDecoration(labelText: 'Mã số thuế'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: 'Ghi chú'),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
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
