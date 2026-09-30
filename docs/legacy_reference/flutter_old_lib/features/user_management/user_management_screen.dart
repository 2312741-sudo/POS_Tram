// lib/features/user_management/user_management_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_constants.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';
import '../../widgets/common_widgets.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();
  List<UserModel> _users = [];
  List<OrderHistoryModel> _history = [];
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _fb.usersStream().listen((u) { if (mounted) setState(() => _users = u); });
    _fb.historyStream().listen((h) { if (mounted) setState(() => _history = h); });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // Calculate revenue per staff from order history (today)
  Map<String, int> get _staffRevenue {
    final now = DateTime.now();
    final todayHistory = _history.where((h) {
      final dt = h.dateTime;
      return dt.year == now.year && dt.month == now.month && dt.day == now.day;
    }).toList();
    
    final map = <String, int>{};
    for (final order in todayHistory) {
      if (order.staffUsername != null) {
        map[order.staffUsername!] = (map[order.staffUsername!] ?? 0) + order.totalAmount;
      }
    }
    return map;
  }

  void _showUserDialog({UserModel? existing}) {
    final fullNameCtrl = TextEditingController(text: existing?.fullName ?? '');
    final usernameCtrl = TextEditingController(text: existing?.username ?? '');
    final passCtrl = TextEditingController(text: existing?.password ?? '');
    String selectedRole = existing?.role ?? AppConstants.roleStaff;
    bool obscure = true;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(existing == null ? 'Thêm nhân viên' : 'Sửa nhân viên',
            style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fullNameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Họ và tên *',
                    prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usernameCtrl,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Tên đăng nhập *',
                    prefixIcon: Icon(Icons.account_circle_outlined, color: AppColors.textSecondary),
                  ),
                  enabled: existing == null, // Không sửa username
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu *',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: AppColors.textSecondary, size: 18),
                      onPressed: () => setSt(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Vai trò',
                    prefixIcon: Icon(Icons.badge_outlined, color: AppColors.textSecondary),
                  ),
                  items: [
                    DropdownMenuItem(value: AppConstants.roleStaff, child: Text('Nhân viên')),
                    DropdownMenuItem(value: AppConstants.roleKitchen, child: Text('Đầu bếp')),
                    DropdownMenuItem(value: AppConstants.roleManager, child: Text('Quản lý')),
                  ],
                  onChanged: (v) => setSt(() => selectedRole = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Hủy', style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary))),
            ElevatedButton(
              onPressed: () async {
                if (fullNameCtrl.text.trim().isEmpty ||
                    usernameCtrl.text.trim().isEmpty ||
                    passCtrl.text.trim().isEmpty) return;
                
                final user = UserModel(
                  fullName: fullNameCtrl.text.trim(),
                  username: usernameCtrl.text.trim(),
                  password: passCtrl.text.trim(),
                  role: selectedRole,
                );
                await _fb.saveUser(user);
                await _fb.logAction(AuditLogModel(
                  action: existing == null ? AppConstants.actionAddUser : 'EDIT_USER',
                  username: _auth.currentUser?.username ?? '',
                  userRole: _auth.currentUser?.role ?? '',
                  timestamp: DateTime.now().millisecondsSinceEpoch,
                  details: '${existing == null ? "Thêm" : "Sửa"} nhân viên: ${user.fullName} (${user.role})',
                  targetId: user.username,
                ));
                if (mounted) Navigator.pop(ctx);
              },
              child: Text(existing == null ? 'Thêm' : 'Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteUser(UserModel user) async {
    if (user.username == _auth.currentUser?.username) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Không thể xóa tài khoản đang đăng nhập!'),
        backgroundColor: AppColors.danger,
      ));
      return;
    }
    
    final confirm = await showConfirmDialog(
      context,
      title: 'Xóa nhân viên',
      message: 'Xóa nhân viên "${user.fullName}"?',
      confirmText: 'Xóa',
      isDanger: true,
    );
    if (confirm == true) {
      await _fb.deleteUser(user.username);
      await _fb.logAction(AuditLogModel(
        action: AppConstants.actionDeleteUser,
        username: _auth.currentUser?.username ?? '',
        userRole: _auth.currentUser?.role ?? '',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        details: 'Xóa nhân viên: ${user.fullName}',
        targetId: user.username,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Text('Quản lý nhân viên', style: GoogleFonts.beVietnamPro(
          color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [Tab(text: 'Danh sách'), Tab(text: 'Xếp hạng')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [_buildUserList(), _buildLeaderboard()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        icon: const Icon(Icons.person_add_outlined),
        label: Text('Thêm NV', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  Widget _buildUserList() {
    if (_users.isEmpty) {
      return const EmptyState(
        icon: Icons.people_outline,
        title: 'Chưa có nhân viên',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final user = _users[i];
        final isSelf = user.username == _auth.currentUser?.username;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelf ? AppColors.primary.withAlpha(100) : AppColors.border,
              width: isSelf ? 1.5 : 1,
            ),
          ),
          child: ListTile(
            leading: Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: user.isManager
                    ? [AppColors.primary, AppColors.secondary]
                    : user.isKitchen
                      ? [AppColors.warning, AppColors.kitchenAccent]
                      : [AppColors.info, const Color(0xFF60A5FA)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                  style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18),
                ),
              ),
            ),
            title: Row(
              children: [
                Text(user.fullName, style: GoogleFonts.beVietnamPro(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                if (isSelf) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(30),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('Bạn', style: GoogleFonts.beVietnamPro(
                      color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            ),
            subtitle: Text('@${user.username}', style: GoogleFonts.beVietnamPro(
              color: AppColors.textSecondary, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                RoleBadge(role: user.role),
                const SizedBox(width: 4),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 20),
                  color: AppColors.surface,
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      onTap: () => _showUserDialog(existing: user),
                      child: Row(children: [
                        const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 18),
                        const SizedBox(width: 8),
                        Text('Sửa', style: GoogleFonts.beVietnamPro(color: AppColors.textPrimary)),
                      ]),
                    ),
                    if (!isSelf) PopupMenuItem(
                      onTap: () => _deleteUser(user),
                      child: Row(children: [
                        const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                        const SizedBox(width: 8),
                        Text('Xóa', style: GoogleFonts.beVietnamPro(color: AppColors.danger)),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ).animate(delay: (i * 50).ms).fadeIn(duration: 200.ms);
      },
    );
  }

  Widget _buildLeaderboard() {
    final revenue = _staffRevenue;
    final staffUsers = _users.where((u) => u.isStaff).toList();
    staffUsers.sort((a, b) => (revenue[b.username] ?? 0).compareTo(revenue[a.username] ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.white, size: 32),
                const SizedBox(width: 12),
                Text('Bảng xếp hạng hôm nay', style: GoogleFonts.beVietnamPro(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (staffUsers.isEmpty)
            const EmptyState(icon: Icons.people_outline, title: 'Chưa có nhân viên')
          else
            ...staffUsers.asMap().entries.map((e) {
              final rank = e.key + 1;
              final user = e.value;
              final rev = revenue[user.username] ?? 0;
              final maxRev = revenue.isEmpty ? 1 : revenue.values.reduce((a, b) => a > b ? a : b);
              
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: rank <= 3
                    ? [AppColors.kitchenAccent, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][rank - 1].withAlpha(20)
                    : AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: rank <= 3
                      ? [AppColors.kitchenAccent, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][rank - 1].withAlpha(70)
                      : AppColors.border,
                    width: rank <= 3 ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text('$rank', style: GoogleFonts.beVietnamPro(
                          color: rank <= 3
                            ? [AppColors.kitchenAccent, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][rank - 1]
                            : AppColors.textSecondary,
                          fontWeight: FontWeight.w800, fontSize: 18,
                        )),
                        const SizedBox(width: 14),
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.info.withAlpha(40),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text(
                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?',
                            style: GoogleFonts.beVietnamPro(
                              color: AppColors.info, fontWeight: FontWeight.w700, fontSize: 16),
                          )),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(user.fullName, style: GoogleFonts.beVietnamPro(
                            color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                        ),
                        Text(FormatUtils.currency(rev), style: GoogleFonts.beVietnamPro(
                          color: AppColors.success, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: maxRev > 0 ? rev / maxRev : 0,
                      backgroundColor: AppColors.cardElevated,
                      color: rank <= 3
                        ? [AppColors.kitchenAccent, const Color(0xFFC0C0C0), const Color(0xFFCD7F32)][rank - 1]
                        : AppColors.info,
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 4,
                    ),
                  ],
                ),
              ).animate(delay: (e.key * 80).ms).fadeIn(duration: 300.ms).slideX(begin: 0.1, end: 0);
            }),
        ],
      ),
    );
  }
}
