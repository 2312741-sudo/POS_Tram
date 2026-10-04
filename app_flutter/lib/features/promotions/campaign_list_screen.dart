import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/campaign_models.dart';
import '../../data/services/campaign_service.dart';
import '../../core/services/auth_service.dart';
import '../../widgets/common_widgets.dart';
import 'campaign_form_screen.dart';
import 'voucher_management_screen.dart';

class CampaignListScreen extends StatefulWidget {
  const CampaignListScreen({Key? key}) : super(key: key);

  @override
  State<CampaignListScreen> createState() => _CampaignListScreenState();
}

class _CampaignListScreenState extends State<CampaignListScreen> {
  final CampaignService _campaignService = CampaignService();
  final AuthService _auth = AuthService();
  
  String _searchQuery = '';
  String _statusFilter = 'Tất cả'; // Tất cả, Đang chạy, Sắp tới, Đã kết thúc, Tạm dừng
  CampaignType? _typeFilter;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TramColors.brandSurface,
      appBar: AppBar(
        title: const Text('Quản lý Khuyến mãi'),
        backgroundColor: TramColors.brandPrimary,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: _buildFilters(),
        ),
      ),
      body: StreamBuilder<List<CampaignModel>>(
        stream: _campaignService.campaignsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: \${snapshot.error}'));
          }

          var campaigns = snapshot.data ?? [];
          campaigns = _filterCampaigns(campaigns);

          if (campaigns.isEmpty) {
            return EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'Không tìm thấy khuyến mãi nào',
              action: _auth.can(AppPermissions.createCampaign)
                  ? ElevatedButton(
                      onPressed: _goToCreateCampaign,
                      style: ElevatedButton.styleFrom(backgroundColor: TramColors.brandPrimary),
                      child: const Text('Tạo khuyến mãi mới', style: TextStyle(color: Colors.white)),
                    )
                  : null,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: campaigns.length,
            itemBuilder: (context, index) {
              return _buildCampaignCard(campaigns[index]);
            },
          );
        },
      ),
      floatingActionButton: _auth.can(AppPermissions.createCampaign)
          ? FloatingActionButton(
              onPressed: _goToCreateCampaign,
              backgroundColor: TramColors.brandPrimary,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Column(
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: 'Tìm theo tên, mã chương trình...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey[200],
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              isDense: true,
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('Tất cả'),
                const SizedBox(width: 8),
                _buildStatusChip('Đang chạy'),
                const SizedBox(width: 8),
                _buildStatusChip('Sắp tới'),
                const SizedBox(width: 8),
                _buildStatusChip('Đã kết thúc'),
                const SizedBox(width: 8),
                _buildStatusChip('Tạm dừng'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label) {
    final isSelected = _statusFilter == label;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _statusFilter = label;
          });
        }
      },
      selectedColor: TramColors.brandPrimary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? TramColors.brandPrimary : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  List<CampaignModel> _filterCampaigns(List<CampaignModel> campaigns) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return campaigns.where((c) {
      // Search text
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        if (!c.name.toLowerCase().contains(query) &&
            !c.programCode.toLowerCase().contains(query)) {
          return false;
        }
      }

      // Status filter
      final isUpcoming = c.isUpcoming;
      final isEnded = c.schedule.absoluteEnd != null && now > c.schedule.absoluteEnd!;
      final isActive = c.active;

      if (_statusFilter == 'Đang chạy' && (!isActive || isUpcoming || isEnded)) return false;
      if (_statusFilter == 'Sắp tới' && (!isActive || !isUpcoming)) return false;
      if (_statusFilter == 'Đã kết thúc' && (!isActive || !isEnded)) return false;
      if (_statusFilter == 'Tạm dừng' && isActive) return false;

      // Type filter
      if (_typeFilter != null && CampaignType.fromMap(c.campaignType) != _typeFilter) {
        return false;
      }

      return true;
    }).toList();
  }

  Widget _buildCampaignCard(CampaignModel campaign) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final isUpcoming = campaign.isUpcoming;
    final isEnded = campaign.schedule.absoluteEnd != null && now > campaign.schedule.absoluteEnd!;
    
    String statusText = 'Tạm dừng';
    Color statusColor = Colors.orange;
    
    if (campaign.active) {
      if (isEnded) {
        statusText = 'Đã kết thúc';
        statusColor = Colors.grey;
      } else if (isUpcoming) {
        statusText = 'Sắp tới';
        statusColor = Colors.blue;
      } else {
        statusText = 'Đang chạy';
        statusColor = Colors.green;
      }
    }

    final startDateStr = campaign.schedule.absoluteStart != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(campaign.schedule.absoluteStart!))
        : 'Không giới hạn';
    final endDateStr = campaign.schedule.absoluteEnd != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(campaign.schedule.absoluteEnd!))
        : 'Không giới hạn';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _goToEditCampaign(campaign),
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: TramColors.brandPrimary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    campaign.programCode,
                    style: const TextStyle(
                      color: TramColors.brandPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: (statusColor).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor)), child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              campaign.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(_getTypeIcon(CampaignType.fromMap(campaign.campaignType)), size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  _getTypeName(CampaignType.fromMap(campaign.campaignType)),
                  style: TextStyle(color: Colors.grey[700], fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '\$startDateStr - \$endDateStr',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: StreamBuilder<CampaignCountersModel?>(
                    stream: _campaignService.campaignCountersStream(campaign.campaignId),
                    builder: (context, snapshot) {
                      final counters = snapshot.data;
                      if (counters == null) {
                        return const SizedBox.shrink();
                      }
                      
                      final spent = counters.spentMoney;
                      final uses = counters.committedUseCount;
                      
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (campaign.budgetMoney != null) ...[
                            Text('Ngân sách: \${FormatUtils.currency(spent)} / \${FormatUtils.currency(campaign.budgetMoney!)}', style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 4),
                            LinearProgressIndicator(
                              value: spent / campaign.budgetMoney!,
                              backgroundColor: Colors.grey[200],
                              valueColor: AlwaysStoppedAnimation<Color>(
                                (spent / campaign.budgetMoney!) > 0.9 ? Colors.red : TramColors.brandPrimary
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (campaign.maxUses != null) ...[
                            Text('Lượt dùng: \$uses / \${campaign.maxUses}', style: const TextStyle(fontSize: 12)),
                          ] else ...[
                            Text('Lượt dùng: \$uses', style: const TextStyle(fontSize: 12)),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Switch(
                      value: campaign.active,
                      activeColor: TramColors.brandPrimary,
                      onChanged: (val) async {
                        try {
                          await _campaignService.toggleCampaignActive(campaign.campaignId, val);
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lỗi: \$e')));
                          }
                        }
                      },
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => VoucherManagementScreen(campaign: campaign),
                        ));
                      },
                      icon: const Icon(Icons.qr_code, size: 16),
                      label: Text(campaign.hasCodes ? 'Mã KM' : '+ Mã KM'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  IconData _getTypeIcon(CampaignType type) {
    switch (type) {
      case CampaignType.billDiscount:
        return Icons.request_quote_outlined;
      case CampaignType.orderValueItemBenefit:
        return Icons.card_giftcard_outlined;
      case CampaignType.buyXGetY:
        return Icons.shopping_basket_outlined;
      case CampaignType.itemPriceRule:
        return Icons.sell_outlined;
    }
  }

  String _getTypeName(CampaignType type) {
    switch (type) {
      case CampaignType.billDiscount:
        return 'Giảm giá đơn hàng';
      case CampaignType.orderValueItemBenefit:
        return 'Tặng món theo giá trị đơn';
      case CampaignType.buyXGetY:
        return 'Mua X tặng Y';
      case CampaignType.itemPriceRule:
        return 'Đồng giá/Đồng giảm giá';
    }
  }

  void _goToCreateCampaign() {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => const CampaignFormScreen(),
    ));
  }

  void _goToEditCampaign(CampaignModel campaign) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CampaignFormScreen(campaign: campaign),
    ));
  }
}
