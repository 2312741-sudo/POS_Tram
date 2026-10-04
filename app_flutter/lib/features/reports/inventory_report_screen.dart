import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../widgets/common_widgets.dart';
import '../../data/models/inventory_models.dart';
import '../../data/services/inventory_service.dart';

class InventoryReportScreen extends StatefulWidget {
  const InventoryReportScreen({Key? key}) : super(key: key);

  @override
  State<InventoryReportScreen> createState() => _InventoryReportScreenState();
}

class _InventoryReportScreenState extends State<InventoryReportScreen> {
  final InventoryService _inventoryService = InventoryService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: TramColors.brandPrimary,
        title: const Text('Báo cáo Kho hàng', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<List<CatalogItemModel>>(
        stream: _inventoryService.catalogItemsStream(),
        builder: (context, catalogSnapshot) {
          if (!catalogSnapshot.hasData) return const Center(child: CircularProgressIndicator());
          final catalogItems = catalogSnapshot.data ?? [];
          final catalogMap = {for (var item in catalogItems) item.itemId: item};

          return StreamBuilder<List<StockBalanceModel>>(
            stream: _inventoryService.stockBalancesStream(),
            builder: (context, balanceSnapshot) {
              if (!balanceSnapshot.hasData) return const Center(child: CircularProgressIndicator());
              final balances = balanceSnapshot.data ?? [];

              return StreamBuilder<List<StockEventModel>>(
                stream: _inventoryService.stockEventsStream(limit: 50),
                builder: (context, eventsSnapshot) {
                  if (!eventsSnapshot.hasData) return const Center(child: CircularProgressIndicator());
                  final events = eventsSnapshot.data ?? [];

                  return _buildContent(catalogMap, balances, events);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(
    Map<String, CatalogItemModel> catalogMap,
    List<StockBalanceModel> balances,
    List<StockEventModel> events,
  ) {
    // Analytics
    int totalValue = 0;
    int trackedItems = 0;
    int lowStockCount = 0;
    int outOfStockCount = 0;

    final List<Map<String, dynamic>> alerts = [];

    for (final balance in balances) {
      final item = catalogMap[balance.itemId];
      if (item == null || !item.trackStock) continue;

      totalValue += balance.inventoryValue;
      trackedItems++;

      if (balance.onHandQty <= 0) {
        outOfStockCount++;
        alerts.add({
          'item': item,
          'balance': balance,
          'ratio': 0.0,
          'missing': item.minStock - balance.onHandQty,
        });
      } else if (balance.onHandQty < item.minStock) {
        lowStockCount++;
        alerts.add({
          'item': item,
          'balance': balance,
          'ratio': balance.onHandQty / (item.minStock > 0 ? item.minStock : 1),
          'missing': item.minStock - balance.onHandQty,
        });
      }
    }

    alerts.sort((a, b) => (a['ratio'] as double).compareTo(b['ratio'] as double));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Tổng quan tồn kho'),
          const SizedBox(height: 12),
          _buildOverviewSection(totalValue, trackedItems, lowStockCount, outOfStockCount),
          const SizedBox(height: 24),
          _buildSectionTitle('Danh sách cảnh báo tồn kho'),
          const SizedBox(height: 12),
          _buildAlertsSection(alerts),
          const SizedBox(height: 24),
          _buildSectionTitle('Biến động kho gần đây'),
          const SizedBox(height: 12),
          _buildRecentEventsSection(events, catalogMap),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildOverviewSection(int totalValue, int trackedItems, int lowStockCount, int outOfStockCount) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.5,
      children: [
        _buildMetricCard('Tổng giá trị tồn kho', FormatUtils.currency(totalValue), TramColors.brandPrimary),
        _buildMetricCard('Số mặt hàng theo dõi', trackedItems.toString(), Colors.blue),
        _buildMetricCard('Dưới mức tối thiểu', lowStockCount.toString(), Colors.orange),
        _buildMetricCard('Hết hàng', outOfStockCount.toString(), Colors.red),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildAlertsSection(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Không có cảnh báo tồn kho.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        final CatalogItemModel item = alert['item'];
        final StockBalanceModel balance = alert['balance'];
        final int missing = alert['missing'];
        
        final isOutOfStock = balance.onHandQty <= 0;
        final color = isOutOfStock ? Colors.red : Colors.orange;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(isOutOfStock ? Icons.error : Icons.warning, color: color),
            title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('SKU: ${item.sku ?? 'N/A'} | Tồn: ${balance.onHandQty} | Tối thiểu: ${item.minStock}'),
            trailing: Text('Thiếu: $missing', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  Widget _buildRecentEventsSection(List<StockEventModel> events, Map<String, CatalogItemModel> catalogMap) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Không có biến động kho gần đây.'),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final item = catalogMap[event.itemId];
        final itemName = item?.name ?? 'Sản phẩm không xác định';
        
        final isPositive = event.qtyDeltaBase > 0;
        final color = isPositive ? Colors.green : Colors.red;
        final sign = isPositive ? '+' : '';

        // Extract time from eventId if no explicit timestamp exists (assuming eventId starts with timestamp)
        // Adjust this depending on how events are structured. For now using current date or event creation if available.
        // Assuming there is no explicit date field except implied or from command.
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(itemName),
            subtitle: Text('Loại: ${event.documentType} | Giá vốn: ${FormatUtils.currency(event.unitCostSnapshot)}'),
            trailing: Text('$sign${event.qtyDeltaBase}', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        );
      },
    );
  }
}
