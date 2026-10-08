import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/app_permissions.dart';
import '../../data/models/app_models.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';
import '../../widgets/common_widgets.dart';
import 'catalog_item_dialog.dart';
import 'supplier_dialog.dart';
import 'purchase_receipt_screen.dart';
import 'stock_card_screen.dart';
import 'excel_import_dialog.dart';
import 'inventory_excel_service.dart';
import '../../core/utils/format_utils.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _inventoryService = InventoryService();
  final _auth = AuthService();

  String _catalogSearch = '';
  String _catalogFilterKind = 'ALL';
  List<CatalogItemModel> _lastLoadedItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.can(AppPermissions.viewInventory)) {
      return const AppScreen(
        title: 'Quản lý kho',
        body: Center(child: Text('Bạn không có quyền xem kho hàng')),
      );
    }

    return AppScreen(
      title: 'Quản lý kho',
      actions: [
        IconButton(
          icon: const Icon(Icons.file_download_outlined),
          tooltip: 'Xuất file Excel',
          onPressed: _exportCatalogExcel,
        ),
        IconButton(
          icon: const Icon(Icons.upload_file_rounded),
          tooltip: 'Nhập từ file Excel',
          onPressed: () => _showImportExcelDialog(_lastLoadedItems),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (val) {
            if (val == 'template') {
              _downloadSampleExcel();
            } else if (val == 'export') {
              _exportCatalogExcel();
            } else if (val == 'import') {
              _showImportExcelDialog(_lastLoadedItems);
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'import',
              child: Row(
                children: [
                  Icon(Icons.upload_file_rounded, size: 18, color: AppColors.primary),
                  SizedBox(width: 8),
                  Text('Nhập file Excel'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.file_download_outlined, size: 18, color: AppColors.managerAccent),
                  SizedBox(width: 8),
                  Text('Xuất file Excel'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'template',
              child: Row(
                children: [
                  Icon(Icons.description_outlined, size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 8),
                  Text('Tải file mẫu Excel'),
                ],
              ),
            ),
          ],
        ),
      ],
      body: Column(
        children: [
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Danh sách hàng'),
                Tab(text: 'Tồn kho'),
                Tab(text: 'Phiếu kho'),
                Tab(text: 'Nhà cung cấp'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCatalogTab(),
                _buildStockTab(),
                _buildDocumentsTab(),
                _buildSuppliersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCatalogTab() {
    return StreamBuilder<List<CatalogItemModel>>(
      stream: _inventoryService.catalogItemsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        }

        final items = snapshot.data ?? [];
        _lastLoadedItems = items;

        if (items.isEmpty) {
          return EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Chưa có hàng hóa',
            action: _auth.can(AppPermissions.editCatalogItem)
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => _showCatalogDialog(null),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Thêm hàng'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: () => _showImportExcelDialog(items),
                        icon: const Icon(Icons.upload_file_rounded, size: 18),
                        label: const Text('Nhập Excel'),
                      ),
                    ],
                  )
                : null,
          );
        }

        final filteredItems = items.where((i) {
          final matchSearch = _catalogSearch.isEmpty ||
              i.name.toLowerCase().contains(_catalogSearch.toLowerCase()) ||
              (i.sku?.toLowerCase().contains(_catalogSearch.toLowerCase()) ?? false) ||
              (i.managementGroup?.toLowerCase().contains(_catalogSearch.toLowerCase()) ?? false);
          final matchKind = _catalogFilterKind == 'ALL' ||
              (_catalogFilterKind == 'RAW_MATERIAL' && (i.kind == 'RAW_MATERIAL' || i.kind == null)) ||
              (_catalogFilterKind == 'TOOL' && i.kind == 'TOOL');
          return matchSearch && matchKind;
        }).toList();

        return Scaffold(
          body: Column(
            children: [
              // Thanh tìm kiếm & thao tác nhanh
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                color: AppColors.card,
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (val) => setState(() => _catalogSearch = val.trim()),
                            decoration: InputDecoration(
                              hintText: 'Tìm theo tên, mã SKU, nhóm hàng...',
                              hintStyle: GoogleFonts.beVietnamPro(fontSize: 13, color: AppColors.textSecondary),
                              prefixIcon: const Icon(Icons.search, size: 20),
                              isDense: true,
                              filled: true,
                              fillColor: AppColors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: () => _showImportExcelDialog(items),
                          icon: const Icon(Icons.upload_file_rounded, size: 20),
                          tooltip: 'Nhập Excel',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.primary.withAlpha(25),
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton.filledTonal(
                          onPressed: _exportCatalogExcel,
                          icon: const Icon(Icons.file_download_outlined, size: 20),
                          tooltip: 'Xuất Excel',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.managerAccent.withAlpha(25),
                            foregroundColor: AppColors.managerAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('Tất cả (${items.length})', 'ALL'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Nguyên vật liệu', 'RAW_MATERIAL'),
                          const SizedBox(width: 8),
                          _buildFilterChip('Công cụ dụng cụ', 'TOOL'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: filteredItems.isEmpty
                    ? const Center(child: Text('Không tìm thấy mặt hàng phù hợp'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('SKU: ${item.sku ?? ''} | ${item.managementGroup ?? item.kind ?? ''}'),
                              trailing: Text('${FormatUtils.currency(item.costPrice)} / ${item.baseUnitId}'),
                              onTap: () => _showCatalogDialog(item),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: _auth.can(AppPermissions.editCatalogItem)
              ? FloatingActionButton(
                  onPressed: () => _showCatalogDialog(null),
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        );
      },
    );
  }

  Widget _buildStockTab() {
    return StreamBuilder<List<StockBalanceModel>>(
      stream: _inventoryService.stockBalancesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: \${snapshot.error}'));
        }

        final stocks = snapshot.data ?? [];
        if (stocks.isEmpty) {
          return const EmptyState(
            icon: Icons.inventory_outlined,
            title: 'Không có dữ liệu tồn kho',
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: stocks.length,
          itemBuilder: (context, index) {
            final stock = stocks[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text('Hàng ID: \${stock.itemId}'),
                subtitle: Text('Tồn: \${stock.onHandQty} | Khả dụng: \${stock.availableQty}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => StockCardScreen(itemId: stock.itemId, branchId: stock.branchId),
                  ));
                },
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateDocSheet(BuildContext context) {
    final canStockIn = _auth.currentUser?.role == UserRole.owner ||
        _auth.can(AppPermissions.inventoryStockIn) ||
        _auth.can(AppPermissions.createReceipt);
    final canStockOut = _auth.currentUser?.role == UserRole.owner ||
        _auth.can(AppPermissions.inventoryStockOut) ||
        _auth.can(AppPermissions.createInternalUse);
    final canWaste = _auth.currentUser?.role == UserRole.owner ||
        _auth.can(AppPermissions.inventoryWaste) ||
        _auth.can(AppPermissions.createWaste);

    final options = <Widget>[];

    if (canStockIn) {
      options.add(
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.login_rounded, color: AppColors.primary),
          ),
          title: const Text('Phiếu nhập hàng (Stock In)', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Nhập nguyên vật liệu từ nhà cung cấp, cập nhật giá vốn'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'PURCHASE_RECEIPT')),
            );
          },
        ),
      );
    }

    if (canStockOut) {
      options.add(
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.warningLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.logout_rounded, color: AppColors.warningLight),
          ),
          title: const Text('Phiếu xuất kho (Stock Out)', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Xuất nguyên vật liệu cho quầy bar, bếp, pha chế nội bộ'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'INTERNAL_USE')),
            );
          },
        ),
      );
    }

    if (canWaste) {
      options.add(
        ListTile(
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.dangerLight.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_sweep_outlined, color: AppColors.dangerLight),
          ),
          title: const Text('Phiếu xuất hủy (Waste)', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Ghi nhận hàng hết hạn, đổ vỡ, hư hỏng không sử dụng được'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'WASTE')),
            );
          },
        ),
      );
    }

    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bạn không có quyền tạo phiếu kho')),
      );
      return;
    }

    if (options.length == 1) {
      if (canStockIn) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'PURCHASE_RECEIPT')));
      } else if (canStockOut) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'INTERNAL_USE')));
      } else if (canWaste) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReceiptScreen(docType: 'WASTE')));
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text('Chọn loại nghiệp vụ kho', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(),
              ...options,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    final canAnyCreate = _auth.currentUser?.role == UserRole.owner ||
        _auth.can(AppPermissions.inventoryStockIn) ||
        _auth.can(AppPermissions.createReceipt) ||
        _auth.can(AppPermissions.inventoryStockOut) ||
        _auth.can(AppPermissions.createInternalUse) ||
        _auth.can(AppPermissions.inventoryWaste) ||
        _auth.can(AppPermissions.createWaste);

    return StreamBuilder<List<InventoryDocumentModel>>(
      stream: _inventoryService.inventoryDocumentsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: ${snapshot.error}'));
        }

        final docs = snapshot.data ?? [];
        if (docs.isEmpty) {
          return EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Chưa có phiếu kho nào',
            action: canAnyCreate
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    onPressed: () => _showCreateDocSheet(context),
                    label: const Text('Tạo phiếu kho'),
                  )
                : null,
          );
        }

        return Scaffold(
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              String typeLabel;
              Color typeColor;
              switch (doc.docType) {
                case 'INTERNAL_USE':
                  typeLabel = 'Xuất kho';
                  typeColor = AppColors.warningLight;
                  break;
                case 'WASTE':
                  typeLabel = 'Xuất hủy';
                  typeColor = AppColors.dangerLight;
                  break;
                case 'PURCHASE_RECEIPT':
                default:
                  typeLabel = 'Nhập hàng';
                  typeColor = AppColors.primary;
              }

              final subInfo = doc.docType == 'PURCHASE_RECEIPT'
                  ? (doc.supplierName?.isNotEmpty == true ? doc.supplierName! : 'Nhập hàng NCC')
                  : (doc.reason?.isNotEmpty == true ? doc.reason! : (doc.note?.isNotEmpty == true ? doc.note! : 'Nội bộ'));

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      doc.docType == 'PURCHASE_RECEIPT'
                          ? Icons.login_rounded
                          : (doc.docType == 'INTERNAL_USE' ? Icons.logout_rounded : Icons.delete_outline_rounded),
                      color: typeColor,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(doc.documentCode, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          typeLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typeColor),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(subInfo, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(FormatUtils.currency(doc.totalMoney), style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        doc.status == 'COMPLETED' ? 'Đã duyệt' : 'Bản nháp',
                        style: TextStyle(
                          fontSize: 12,
                          color: doc.status == 'COMPLETED' ? AppColors.successLight : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PurchaseReceiptScreen(
                          documentId: doc.documentId,
                          docType: doc.docType,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
          floatingActionButton: canAnyCreate
              ? FloatingActionButton.extended(
                  onPressed: () => _showCreateDocSheet(context),
                  backgroundColor: AppColors.primary,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Tạo phiếu', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                )
              : null,
        );
      },
    );
  }

  Widget _buildSuppliersTab() {
    return StreamBuilder<List<SupplierModel>>(
      stream: _inventoryService.suppliersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Lỗi: \${snapshot.error}'));
        }

        final suppliers = snapshot.data ?? [];
        if (suppliers.isEmpty) {
          return EmptyState(
            icon: Icons.business_outlined,
            title: 'Chưa có nhà cung cấp',
            action: _auth.can(AppPermissions.editSuppliers)
                ? ElevatedButton(
                    onPressed: () => _showSupplierDialog(null),
                    child: const Text('Thêm nhà cung cấp'),
                  )
                : null,
          );
        }

        return Scaffold(
          body: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: suppliers.length,
            itemBuilder: (context, index) {
              final sup = suppliers[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  title: Text(sup.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('\${sup.supplierCode} | SĐT: \${sup.phone ?? ''}'),
                  onTap: () => _showSupplierDialog(sup),
                ),
              );
            },
          ),
          floatingActionButton: _auth.can(AppPermissions.editSuppliers)
              ? FloatingActionButton(
                  onPressed: () => _showSupplierDialog(null),
                  backgroundColor: AppColors.primary,
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        );
      },
    );
  }

  void _showCatalogDialog(CatalogItemModel? item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CatalogItemDialog(item: item),
    );
  }

  void _showSupplierDialog(SupplierModel? sup) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SupplierDialog(supplier: sup),
    );
  }

  Widget _buildFilterChip(String label, String kindKey) {
    final isSelected = _catalogFilterKind == kindKey;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      labelStyle: GoogleFonts.beVietnamPro(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        color: isSelected ? Colors.white : AppColors.textPrimary,
      ),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surface,
      side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
      onSelected: (_) => setState(() => _catalogFilterKind = kindKey),
    );
  }

  void _showImportExcelDialog(List<CatalogItemModel> currentItems) {
    ExcelImportDialog.show(
      context,
      existingItems: currentItems,
      onImportCompleted: () {
        setState(() {});
      },
    );
  }

  Future<void> _exportCatalogExcel() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      final items = await _inventoryService.getCatalogItems();
      final balances = await _inventoryService.getStockBalances();
      final currentStore = _auth.currentStoreInfo ?? StoreInfoModel(storeCode: _auth.currentStoreCode, storeName: 'POS Trạm - ${_auth.currentStoreCode}');
      if (mounted) Navigator.of(context).pop();

      await InventoryExcelService.exportInventoryExcel(
        items: items,
        balances: balances,
        storeCode: currentStore.storeCode,
        storeName: currentStore.storeName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã xuất file Excel danh sách hàng hóa kho thành công!'),
            backgroundColor: Color(0xFF146A65),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất file Excel: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _downloadSampleExcel() async {
    try {
      await InventoryExcelService.downloadSampleTemplate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã tạo và mở file mẫu Excel thành công!'),
            backgroundColor: Color(0xFF146A65),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải file mẫu: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}
