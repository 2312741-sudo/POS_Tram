import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _fb = FirebaseService();
  final _auth = AuthService();

  List<UserModel> _users = [];
  List<RoleModel> _roles = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final users = await _fb.getUsers();
    final roles = await _fb.getRoles();
    if (mounted) {
      setState(() {
        _users = users.isNotEmpty ? users : [
          UserModel(username: 'admin', fullName: 'Chủ Quán (Admin)', password: 'admin', roleId: 'ROLE_OWNER', isRootOwner: true),
          UserModel(username: 'thungan', fullName: 'Nguyễn Thu Ngân', password: '123', roleId: 'ROLE_CASHIER'),
          UserModel(username: 'phucvu', fullName: 'Trần Phục Vụ', password: '123', roleId: 'ROLE_WAITER'),
          UserModel(username: 'daubep', fullName: 'Lê Đầu Bếp', password: '123', roleId: 'ROLE_KITCHEN'),
        ];
        _roles = roles.isNotEmpty ? roles : [
          RoleModel(id: 'ROLE_OWNER', name: 'Chủ Quán (Toàn quyền)', permissions: AppPermissions.allPermissions.map((p) => p.key).toList(), isSystemRole: true),
          RoleModel(id: 'ROLE_MANAGER', name: 'Quản Lý Ca', permissions: [AppPermissions.viewMenu, AppPermissions.editMenu, AppPermissions.openTable, AppPermissions.createBill, AppPermissions.printBill, AppPermissions.viewReports], isSystemRole: true),
          RoleModel(id: 'ROLE_CASHIER', name: 'Thu Ngân', permissions: [AppPermissions.viewMenu, AppPermissions.openTable, AppPermissions.createBill, AppPermissions.applyPromotion, AppPermissions.printBill], isSystemRole: true),
          RoleModel(id: 'ROLE_WAITER', name: 'Nhân Viên Phục Vụ', permissions: [AppPermissions.viewMenu, AppPermissions.openTable, AppPermissions.sendKitchen], isSystemRole: true),
          RoleModel(id: 'ROLE_KITCHEN', name: 'Bếp / Pha Chế', permissions: [], isSystemRole: true),
        ];
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddEditUserDialog([UserModel? userToEdit]) async {
    final fullNameCtrl = TextEditingController(text: userToEdit?.fullName ?? '');
    final usernameCtrl = TextEditingController(text: userToEdit?.username ?? '');
    final passCtrl = TextEditingController(text: userToEdit?.password ?? '');
    final phoneCtrl = TextEditingController(text: userToEdit?.phone ?? '');
    String selectedRole = userToEdit?.roleId ?? (_roles.isNotEmpty ? _roles.first.id : 'ROLE_STAFF');
    bool obscure = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: Text(
              userToEdit == null ? 'Thêm Nhân Viên Mới' : 'Sửa Thông Tin Nhân Viên',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: fullNameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên *', prefixIcon: Icon(Icons.person_outline)),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: usernameCtrl,
                      decoration: const InputDecoration(labelText: 'Tên đăng nhập *', prefixIcon: Icon(Icons.badge_outlined)),
                      enabled: userToEdit == null,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu *',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDlgState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedRole,
                      decoration: const InputDecoration(labelText: 'Vai trò mặc định *'),
                      items: _roles.map((r) {
                        return DropdownMenuItem(value: r.id, child: Text(r.name));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedRole = v);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () async {
                  if (fullNameCtrl.text.trim().isEmpty || usernameCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) return;

                  final u = UserModel(
                    username: usernameCtrl.text.trim(),
                    fullName: fullNameCtrl.text.trim(),
                    password: passCtrl.text,
                    roleId: selectedRole,
                    phone: phoneCtrl.text.trim(),
                    isRootOwner: userToEdit?.isRootOwner ?? false,
                    customPermissions: userToEdit?.customPermissions ?? [],
                    isActive: userToEdit?.isActive ?? true,
                  );

                  await _fb.saveUser(u);

                  // Audit log
                  await _fb.logAction(AuditLogModel(
                    timestamp: DateTime.now().millisecondsSinceEpoch,
                    username: _auth.currentUser?.username ?? 'admin',
                    userFullName: _auth.currentUser?.fullName ?? 'Chủ Quán',
                    userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
                    action: userToEdit == null ? 'CREATE_USER' : 'EDIT_USER',
                    targetType: 'USER',
                    targetId: u.username,
                    details: '${userToEdit == null ? "Tạo" : "Sửa"} nhân viên ${u.fullName} (@${u.username}) vai trò $selectedRole',
                  ));

                  Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text('Lưu Nhân Viên'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Tài Khoản Nhân Viên'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Ma trận phân quyền',
            onPressed: () => context.push('/permissions-matrix'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditUserDialog(),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Thêm Nhân Viên'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final user = _users[index];
                final role = _roles.where((r) => r.id == user.roleId).firstOrNull;

                return Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: user.isRootOwner ? Colors.amber : AppColors.primaryLight,
                      child: Text(
                        user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: user.isRootOwner ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(user.fullName, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 8),
                        if (user.isRootOwner)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(4)),
                            child: const Text('👑 Chủ Quán', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.brown)),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 2),
                        Text(
                          '@${user.username} • Vai trò: ${role?.name ?? user.roleId}',
                          style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (user.customPermissions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '🌟 ${user.customPermissions.length} quyền riêng biệt được cấp thêm',
                            style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.primaryDark, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          onPressed: () => _showAddEditUserDialog(user),
                        ),
                        if (!user.isRootOwner)
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Xác nhận xóa tài khoản'),
                                  content: Text('Bạn có chắc muốn xóa tài khoản "${user.fullName}"?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Xóa'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _fb.deleteUser(user.username);
                                _loadData();
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
