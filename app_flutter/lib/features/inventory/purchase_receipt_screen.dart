import 'package:flutter/material.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/app_permissions.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';
import '../../core/utils/format_utils.dart';

class PurchaseReceiptScreen extends StatefulWidget {
  final String? documentId;
  final String docType; // 'PURCHASE_RECEIPT', 'INTERNAL_USE', 'WASTE'

  const PurchaseReceiptScreen({
    super.key,
    this.documentId,
    this.docType = 'PURCHASE_RECEIPT',
  });

  @override
  State<PurchaseReceiptScreen> createState() => _PurchaseReceiptScreenState();
}

class _PurchaseReceiptScreenState extends State<PurchaseReceiptScreen> {
  final _inventoryService = InventoryService();
  final _auth = AuthService();

  InventoryDocumentModel? _doc;
  late String _currentDocType;
  bool _isLoading = false;

  final _invoiceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  SupplierModel? _selectedSupplier;
  List<InventoryDocLine> _lines = [];

  static const List<String> _internalUseReasons = [
    'Xuất quầy pha chế',
    'Xuất bếp nấu',
    'Xuất dùng thử / kiểm định',
    'Xuất hỗ trợ chi nhánh khác',
    'Xuất tiếp khách',
    'Khác...',
  ];

  static const List<String> _wasteReasons = [
    'Hết hạn sử dụng',
    'Hỏng hóc / Ẩm mốc',
    'Rơi vỡ / Đổ vỡ trong ca',
    'Sai hỏng trong chế biến',
    'Bảo quản không đạt chuẩn',
    'Khác...',
  ];

  @override
  void initState() {
    super.initState();
    _currentDocType = widget.docType;
    if (widget.documentId != null) {
      _loadDoc();
    }
  }

  @override
  void dispose() {
    _invoiceCtrl.dispose();
    _noteCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  String get _docTypeName {
    switch (_currentDocType) {
      case 'INTERNAL_USE':
        return 'Phiếu xuất kho';
      case 'WASTE':
        return 'Phiếu xuất hủy';
      case 'PURCHASE_RECEIPT':
      default:
        return 'Phiếu nhập hàng';
    }
  }

  String get _docPrefix {
    switch (_currentDocType) {
      case 'INTERNAL_USE':
        return 'PX-';
      case 'WASTE':
        return 'PH-';
      case 'PURCHASE_RECEIPT':
      default:
        return 'PN-';
    }
  }

  bool _canCreateOrEditDoc() {
    if (_auth.currentUser?.role == UserRole.owner) return true;
    switch (_currentDocType) {
      case 'INTERNAL_USE':
        return _auth.can(AppPermissions.inventoryStockOut) || _auth.can(AppPermissions.createInternalUse);
      case 'WASTE':
        return _auth.can(AppPermissions.inventoryWaste) || _auth.can(AppPermissions.createWaste);
      case 'PURCHASE_RECEIPT':
      default:
        return _auth.can(AppPermissions.inventoryStockIn) || _auth.can(AppPermissions.createReceipt);
    }
  }

  bool _canCompleteDoc() {
    if (_auth.currentUser?.role == UserRole.owner) return true;
    return _auth.can(AppPermissions.completeReceipt);
  }

  Future<void> _loadDoc() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _inventoryService.getInventoryDocument(widget.documentId!);
      if (doc != null) {
        setState(() {
          _doc = doc;
          _currentDocType = doc.docType;
          _invoiceCtrl.text = doc.externalInvoiceNumber ?? '';
          _noteCtrl.text = doc.note;
          _reasonCtrl.text = doc.reason ?? '';
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

  Future<void> _showAddItemDialog() async {
    final items = await _inventoryService.getCatalogItems();
    if (!mounted) return;

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Danh mục hàng kho trống! Vui lòng tạo mặt hàng trước.')),
      );
      return;
    }

    CatalogItemModel selectedItem = items.first;
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(text: selectedItem.costPrice.toString());

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('Thêm hàng vào $_docTypeName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<CatalogItemModel>(
                  key: ValueKey<Object?>(selectedItem),
                  initialValue: selectedItem,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Chọn mặt hàng'),
                  items: items.map((it) => DropdownMenuItem(
                    value: it,
                    child: Text('${it.name} (${it.baseUnitId})'),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setDlgState(() {
                        selectedItem = val;
                        priceCtrl.text = val.costPrice.toString();
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Số lượng (${selectedItem.baseUnitId})',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Đơn giá (VND)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                final int qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
                final int price = int.tryParse(priceCtrl.text.trim()) ?? selectedItem.costPrice;
                if (qty <= 0) return;

                setState(() {
                  _lines.add(InventoryDocLine(
                    lineId: 'LINE_${DateTime.now().millisecondsSinceEpoch}',
                    itemId: selectedItem.itemId,
                    itemName: selectedItem.name,
                    unitId: selectedItem.baseUnitId,
                    conversionNumerator: 1,
                    conversionDenominator: 1,
                    quantity: qty,
                    quantityBase: qty,
                    unitPrice: price,
                    lineDiscountMoney: 0,
                    lineDiscountPercent: 0,
                    lineTaxMoney: 0,
                    lineNetMoney: qty * price,
                    costAllocation: 0,
                  ));
                });
                Navigator.pop(ctx);
              },
              child: const Text('Thêm'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save({required bool complete}) async {
    if (!_canCreateOrEditDoc()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bạn không có quyền thao tác $_docTypeName')),
        );
      }
      return;
    }

    if (complete && !_canCompleteDoc()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bạn không có quyền duyệt hoàn thành phiếu')),
        );
      }
      return;
    }

    if (_currentDocType == 'PURCHASE_RECEIPT' && _selectedSupplier == null && _doc?.supplierId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn nhà cung cấp cho phiếu nhập')),
        );
      }
      return;
    }

    if ((_currentDocType == 'INTERNAL_USE' || _currentDocType == 'WASTE') && _reasonCtrl.text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vui lòng nhập lý do ${_currentDocType == "INTERNAL_USE" ? "xuất kho" : "hủy kho"}')),
        );
      }
      return;
    }

    if (_lines.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vui lòng chọn ít nhất 1 mặt hàng')),
        );
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
        documentCode: _doc?.documentCode ?? '$_docPrefix${now.toString().substring(5)}',
        docType: _currentDocType,
        status: complete ? 'COMPLETED' : 'DRAFT',
        branchId: _doc?.branchId ?? _inventoryService.currentStoreCode,
        supplierId: _currentDocType == 'PURCHASE_RECEIPT'
            ? (_selectedSupplier?.supplierId ?? _doc?.supplierId)
            : null,
        supplierName: _currentDocType == 'PURCHASE_RECEIPT'
            ? (_selectedSupplier?.name ?? _doc?.supplierName)
            : null,
        externalInvoiceNumber: _invoiceCtrl.text.trim().isEmpty ? null : _invoiceCtrl.text.trim(),
        lines: _lines,
        totalQuantity: totalQty,
        totalMoney: totalMoney,
        globalDiscountMoney: 0,
        totalTaxMoney: 0,
        totalNetMoney: totalMoney,
        paidMoney: 0,
        debtMoney: _currentDocType == 'PURCHASE_RECEIPT' ? totalMoney : 0,
        note: _noteCtrl.text.trim(),
        reason: _reasonCtrl.text.trim().isEmpty ? null : _reasonCtrl.text.trim(),
        createdBy: _doc?.createdBy ?? _auth.currentUser?.username ?? 'system',
        createdByName: _doc?.createdByName ?? _auth.currentUser?.fullName ?? 'Người dùng',
        createdAt: _doc?.createdAt ?? now,
        idempotencyKey: _doc?.idempotencyKey ?? now.toString(),
      );

      await _inventoryService.saveInventoryDocumentDraft(docToSave);
      if (complete) {
        await _inventoryService.completeInventoryDocument(docToSave);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(complete ? '$_docTypeName hoàn thành & cập nhật kho' : 'Đã lưu phiếu tạm (DRAFT)'),
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

  Future<void> _cancelDoc() async {
    if (_doc == null || _doc!.status != 'DRAFT') return;

    final reasonCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy phiếu nháp'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Lý do hủy phiếu *'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Đóng')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận hủy', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && reasonCtrl.text.trim().isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await _inventoryService.cancelInventoryDocument(
          _doc!.documentId,
          reasonCtrl.text.trim(),
          _auth.currentUser?.username ?? 'system',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã hủy phiếu nháp thành công')),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi hủy phiếu: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = _doc?.status == 'COMPLETED';
    final isCancelled = _doc?.status == 'CANCELLED';
    final isDraft = _doc == null || _doc?.status == 'DRAFT';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.documentId == null ? 'Tạo $_docTypeName' : '$_docTypeName: ${_doc?.documentCode ?? ""}'),
        backgroundColor: _currentDocType == 'WASTE'
            ? Colors.deepOrange
            : (_currentDocType == 'INTERNAL_USE' ? Colors.blueGrey.shade700 : context.tc.primary),
        foregroundColor: Colors.white,
        actions: [
          if (isDraft) ...[
            IconButton(
              icon: const Icon(Icons.save_outlined),
              onPressed: () => _save(complete: false),
              tooltip: 'Lưu tạm DRAFT',
            ),
            if (_canCompleteDoc())
              IconButton(
                icon: const Icon(Icons.check_circle_outline),
                onPressed: () => _save(complete: true),
                tooltip: 'Duyệt & Hoàn thành',
              ),
            if (_doc != null)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _cancelDoc,
                tooltip: 'Hủy phiếu',
              ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildHeader(isCompleted || isCancelled),
                Expanded(child: _buildLines(isCompleted || isCancelled)),
                _buildFooter(isCompleted || isCancelled),
              ],
            ),
    );
  }

  Widget _buildHeader(bool isReadOnly) {
    final status = _doc?.status ?? 'DRAFT';
    Color statusColor = Colors.amber.shade800;
    if (status == 'COMPLETED') statusColor = Colors.green;
    if (status == 'CANCELLED') statusColor = Colors.red;

    final reasonsList = _currentDocType == 'INTERNAL_USE'
        ? _internalUseReasons
        : (_currentDocType == 'WASTE' ? _wasteReasons : <String>[]);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Loại phiếu: $_docTypeName',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // If PURCHASE_RECEIPT: Supplier Selector & Invoice Number
            if (_currentDocType == 'PURCHASE_RECEIPT') ...[
              if (!isReadOnly)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedSupplier?.name ?? _doc?.supplierName ?? 'Chưa chọn nhà cung cấp',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: _selectedSupplier != null || _doc?.supplierName != null
                              ? context.tc.textPrimary
                              : Colors.red,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(minimumSize: const Size(64, AppSpacing.minTapTarget)),
                      onPressed: () async {
                        final sups = await _inventoryService.getSuppliers();
                        if (sups.isNotEmpty && mounted) {
                          final selected = await showDialog<SupplierModel>(
                            context: context,
                            builder: (ctx) => SimpleDialog(
                              title: const Text('Chọn nhà cung cấp'),
                              children: sups.map((s) => SimpleDialogOption(
                                onPressed: () => Navigator.pop(ctx, s),
                                child: Text('${s.name} (${s.supplierCode})'),
                              )).toList(),
                            ),
                          );
                          if (selected != null) {
                            setState(() => _selectedSupplier = selected);
                          }
                        }
                      },
                      icon: const Icon(Icons.business, size: 16),
                      label: const Text('Chọn NCC'),
                    ),
                  ],
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.business, color: context.tc.primary),
                  title: Text(_doc?.supplierName ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Nhà cung cấp'),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _invoiceCtrl,
                decoration: const InputDecoration(labelText: 'Số hóa đơn VAT / Chứng từ gốc'),
                readOnly: isReadOnly,
              ),
            ] else ...[
              // If INTERNAL_USE or WASTE: Reason selector & text
              if (!isReadOnly && reasonsList.isNotEmpty) ...[
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: reasonsList.map((r) => ActionChip(
                    label: Text(r, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      if (r != 'Khác...') {
                        setState(() => _reasonCtrl.text = r);
                      } else {
                        _reasonCtrl.clear();
                      }
                    },
                  )).toList(),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: _reasonCtrl,
                decoration: InputDecoration(
                  labelText: _currentDocType == 'INTERNAL_USE' ? 'Lý do xuất kho *' : 'Lý do xuất hủy *',
                  hintText: 'Nhập hoặc chọn lý do ở trên...',
                ),
                readOnly: isReadOnly,
              ),
            ],

            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú bổ sung'),
              readOnly: isReadOnly,
            ),

            if (isReadOnly && _doc?.completedByName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Duyệt bởi: ${_doc!.completedByName} lúc ${FormatUtils.dateTime(_doc!.completedAt ?? 0)}',
                style: TextStyle(fontSize: 12, color: context.tc.textHint, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLines(bool isReadOnly) {
    if (_lines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: context.tc.textHint),
            const SizedBox(height: 8),
            Text(
              'Chưa có mặt hàng nào trong $_docTypeName',
              style: TextStyle(color: context.tc.textHint),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _lines.length,
      itemBuilder: (context, index) {
        final line = _lines[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            title: Text(line.itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'SL: ${line.quantity} ${line.unitId} • Đơn giá: ${FormatUtils.currency(line.unitPrice)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  FormatUtils.currency(line.lineNetMoney),
                  style: TextStyle(fontWeight: FontWeight.bold, color: context.tc.primary),
                ),
                if (!isReadOnly)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () {
                      setState(() {
                        _lines.removeAt(index);
                      });
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooter(bool isReadOnly) {
    int totalQty = _lines.fold(0, (sum, line) => sum + line.quantity);
    int totalMoney = _lines.fold(0, (sum, line) => sum + line.lineNetMoney);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.tc.surface,
        border: Border(top: BorderSide(color: context.tc.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isReadOnly)
            ElevatedButton.icon(
              onPressed: _showAddItemDialog,
              icon: const Icon(Icons.add),
              label: const Text('Thêm hàng vào phiếu'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.tc.primary,
                minimumSize: const Size.fromHeight(44),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng số lượng mặt hàng:'),
              Text('$totalQty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tổng giá trị phiếu:'),
              Text(
                FormatUtils.currency(totalMoney),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: context.tc.primary,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
