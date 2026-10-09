// lib/features/zone_management/zone_management_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class ZoneManagementScreen extends StatefulWidget {
  const ZoneManagementScreen({super.key});

  @override
  State<ZoneManagementScreen> createState() => _ZoneManagementScreenState();
}

class _ZoneManagementScreenState extends State<ZoneManagementScreen> {
  final _fb = FirebaseService();
  List<ZoneModel> _zones = [];

  @override
  void initState() {
    super.initState();
    _fb.zonesStream().listen((z) { if (mounted) setState(() => _zones = z); });
  }

  void _showAddDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.tc.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Thêm khu vực', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          style: TextStyle(color: context.tc.textPrimary),
          decoration: InputDecoration(
            labelText: 'Tên khu vực (VD: Khu A, Tầng 2)',
            prefixIcon: Icon(Icons.map_outlined, color: context.tc.textSecondary),
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
            child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: context.tc.textSecondary))),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isNotEmpty) {
                await _fb.saveZone(ZoneModel(name: ctrl.text.trim()));
                if (mounted) Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteZone(ZoneModel zone) async {
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa khu vực',
      message: 'Xóa khu vực "${zone.name}"?\nCác bàn trong khu vực này sẽ không bị ảnh hưởng.',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) await _fb.deleteZone(zone);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.tc.background,
      appBar: AppBar(
        backgroundColor: context.tc.surface,
        foregroundColor: context.tc.textPrimary, // nền sáng => icon/chữ tối (tránh trắng trên nền kem)
        title: Text('Quản lý khu vực', style: GoogleFonts.beVietnamPro(
          color: context.tc.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: _zones.isEmpty
        ? EmptyState(
            icon: Icons.map_outlined,
            title: 'Chưa có khu vực',
            subtitle: 'Thêm khu vực để phân loại bàn',
            action: ElevatedButton.icon(
              onPressed: _showAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Thêm khu vực'),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: _zones.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => Container(
              decoration: BoxDecoration(
                color: context.tc.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.tc.border),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_on_outlined, color: AppColors.secondary, size: 18),
                ),
                title: Text(_zones[i].name, style: GoogleFonts.beVietnamPro(
                  color: context.tc.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: StreamBuilder<List<TableModel>>(
                  stream: _fb.tablesStream(),
                  builder: (_, snap) {
                    final tables = (snap.data ?? []).where((t) => t.zone == _zones[i].name).length;
                    return Text('$tables bàn', style: GoogleFonts.beVietnamPro(
                      color: context.tc.textSecondary, fontSize: 12));
                  },
                ),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: context.tc.danger, size: 20),
                  onPressed: () => _deleteZone(_zones[i]),
                ),
              ),
            ),
          ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('Thêm', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
      ),
    );
  }
}
