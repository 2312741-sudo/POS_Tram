import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/app_permissions.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';
import '../../core/utils/format_utils.dart';

class PurchaseReceiptScreen extends StatefulWidget {
  final String? documentId;

  const PurchaseReceiptScreen({super.key, this.documentId});

  @override
  State<PurchaseReceiptScreen> createState() => _PurchaseReceiptScreenState();
}

class _PurchaseReceiptScreenState extends State<PurchaseReceiptScreen> {
  final _inventoryService = InventoryService();
  final _auth = AuthService();

  InventoryDocumentModel? _doc;
  bool _isLoading = false;

  final _invoiceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  SupplierModel? _selectedSupplier;
  List<InventoryDocLine> _lines = [];

  @override
  void initState() {
    super.initState();
    if (widget.documentId != null) {
      _loadDoc();
    }
  }

  Future<void> _loadDoc() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _inventoryService.getInventoryDocument(widget.documentId!);
      if (doc != null) {
        setState(() {
          _doc = doc;
          _invoiceCtrl.text = doc.externalInvoiceNumber ?? '';
          _noteCtrl.text = doc.note;
          _lines = List.from(doc.lines);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi tải phiếu: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _addLine(CatalogItemModel item) {
    setState(() {
      _lines.add(InventoryDocLine(
        lineId: DateTime.now().millisecondsSinceEpoch.toString(),
        itemId: item.itemId,
        itemName: item.name,
        unitId: item.baseUnitId,
        conversionNumerator: 1,
        conversionDenominator: 1,
        quantity: 1,
        quantityBase: 1,
        unitPrice: item.costPrice,
        lineDiscountMoney: 0,
        lineDiscountPercent: 0,
        lineTaxMoney: 0,
        lineNetMoney: item.costPrice,
        costAllocation: 0,
      ));
    });
  }

  Future<void> _save({required bool complete}) async {
    if (complete && !_auth.can(AppPermissions.completeReceipt)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bạn không có quyền duyệt phiếu')));
      }
      return;
    }

    if (_selectedSupplier == null && widget.documentId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn nhà cung cấp')));
      }
      return;
    }
    
    if (_lines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn ít nhất 1 mặt hàng')));
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      int totalQty = _lines.fold(0, (sum, line) => sum + line.quantity);
      int totalMoney = _lines.fold(0, (sum, line) => sum + line.lineNetMoney);
      
      final docToSave = InventoryDocumentModel(
        documentId: _doc?.documentId ?? now.toString(),
        documentCode: _doc?.documentCode ?? 'PN-${now.toString().substring(5)}',
        docType: 'PURCHASE_RECEIPT',
        status: complete ? 'COMPLETED' : 'DRAFT',
        branchId: _doc?.branchId ?? 'default_branch',
        supplierId: _selectedSupplier?.supplierId ?? _doc?.supplierId,
        supplierName: _selectedSupplier?.name ?? _doc?.supplierName,
        externalInvoiceNumber: _invoiceCtrl.text,
        lines: _lines,
        totalQuantity: totalQty,
        totalMoney: totalMoney,
        globalDiscountMoney: 0,
        totalTaxMoney: 0,
        totalNetMoney: totalMoney,
        paidMoney: 0,
        debtMoney: totalMoney,
        note: _noteCtrl.text,
        createdBy: _doc?.createdBy ?? _auth.currentUser?.username ?? '',
        createdByName: _doc?.createdByName ?? _auth.currentUser?.fullName ?? '',
        createdAt: _doc?.createdAt ?? now,
        idempotencyKey: _doc?.idempotencyKey ?? now.toString(),
      );

      await _inventoryService.saveInventoryDocumentDraft(docToSave);
      if (complete) {
        await _inventoryService.completeInventoryDocument(docToSave);
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(complete ? 'Phiếu nhập hoàn thành' : 'Đã lưu phiếu tạm'),
          backgroundColor: Colors.green,
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Lỗi: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentId == null ? 'Tạo phiếu nhập hàng' : 'Chi tiết phiếu nhập'),
        backgroundColor: TramColors.brandPrimary,
        foregroundColor: Colors.white,
        actions: [
          if (_doc?.status != 'COMPLETED')
            IconButton(
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _save(complete: false),
              tooltip: 'Lưu tạm',
            ),
          if (_doc?.status != 'COMPLETED')
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: () => _save(complete: true),
              tooltip: 'Hoàn thành',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(),
                Expanded(child: _buildLines()),
                _buildFooter(),
              ],
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _invoiceCtrl,
              decoration: const InputDecoration(labelText: 'Số hóa đơn'),
              readOnly: _doc?.status == 'COMPLETED',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
              readOnly: _doc?.status == 'COMPLETED',
            ),
            if (_doc?.status != 'COMPLETED')
              const SizedBox(height: 12),
            if (_doc?.status != 'COMPLETED')
              ElevatedButton.icon(
                onPressed: () async {
                   final sups = await _inventoryService.getSuppliers();
                   if (sups.isNotEmpty && mounted) {
                     setState(() => _selectedSupplier = sups.first);
                   }
                },
                icon: const Icon(Icons.business),
                label: Text(_selectedSupplier?.name ?? 'Chọn nhà cung cấp'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLines() {
    if (_lines.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_alt, size: 48, color: Colors.grey),
            SizedBox(height: 8),
            Text('Chưa có hàng hóa trong phiếu', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        return ListTile(
          title: Text(line.itemName),
          subtitle: Text('SL: ${line.quantity} ${line.unitId} - Đơn giá: ${FormatUtils.currency(line.unitPrice)}'),
          trailing: Text(FormatUtils.currency(line.lineNetMoney)),
        );
      },
    );
  }

  Widget _buildFooter() {
    int totalQty = _lines.fold(0, (sum, line) => sum + line.quantity);
    int totalMoney = _lines.fold(0, (sum, line) => sum + line.lineNetMoney);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TramColors.brandSurface,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_doc?.status != 'COMPLETED')
            ElevatedButton.icon(
              onPressed: () async {
                 final items = await _inventoryService.getCatalogItems();
                 if (items.isNotEmpty && mounted) {
                   _addLine(items.first);
                 }
              },
              icon: const Icon(Icons.add),
              label: const Text('Thêm hàng vào phiếu'),
              style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
            ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng số lượng:'),
              Text(totalQty.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng tiền:'),
              Text(FormatUtils.currency(totalMoney), style: TextStyle(fontWeight: FontWeight.bold, color: TramColors.brandPrimary, fontSize: 18)),
            ],
          ),
        ],
      ),
    );
  }
}
