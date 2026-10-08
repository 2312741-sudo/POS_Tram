// lib/features/permissions/permissions_matrix_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/app_models.dart';
import '../../data/services/firebase_service.dart';

class PermissionsMatrixScreen extends StatefulWidget {
  const PermissionsMatrixScreen({super.key});

  @override
  State<PermissionsMatrixScreen> createState() => _PermissionsMatrixScreenState();
}

class _PermissionsMatrixScreenState extends State<PermissionsMatrixScreen> with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();
  final _auth = AuthService();
  late TabController _tabController;

  List<UserModel> _users = [];
  List<RoleModel> _roles = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedCategory = 'Tất cả';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final users = await _fb.getUsers();
    final roles = await _fb.getRoles();
    if (mounted) {
      setState(() {
        _users = users;
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

  List<AppPermission> get _filteredPermissions {
    if (_selectedCategory == 'Tất cả') {
      return AppPermissions.allPermissions;
    }
    return AppPermissions.allPermissions.where((p) => p.category == _selectedCategory).toList();
  }

  List<UserModel> get _filteredUsers {
    if (_searchQuery.trim().isEmpty) return _users;
    final q = _searchQuery.toLowerCase().trim();
    return _users.where((u) => u.fullName.toLowerCase().contains(q) || u.username.toLowerCase().contains(q)).toList();
  }

  Future<void> _toggleUserPermission(UserModel user, String permKey, bool newValue) async {
    if (user.isRootOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chủ quán (Root Owner) luôn có toàn quyền và không thể sửa.')),
      );
      return;
    }

    List<String> newCustom = List.from(user.customPermissions);

    if (newValue) {
      // Bật quyền
      if (!newCustom.contains(permKey)) {
        newCustom.add(permKey);
      }
    } else {
      // Tắt quyền
      newCustom.remove(permKey);
      // Nếu vai trò gốc có quyền này nhưng chủ quán muốn tắt riêng cho NV này:
      // Trong mô hình override, ta có thể đánh dấu quyền bị cấm hoặc sửa vai trò.
    }

    final updatedUser = UserModel(
      username: user.username,
      fullName: user.fullName,
      password: user.password,
      roleId: user.roleId,
      isRootOwner: user.isRootOwner,
      customPermissions: newCustom,
      isActive: user.isActive,
      phone: user.phone,
    );

    await _fb.saveUser(updatedUser);

    // Audit Log
    await _fb.logAction(AuditLogModel(
      timestamp: DateTime.now().millisecondsSinceEpoch,
      username: _auth.currentUser?.username ?? 'admin',
      userFullName: _auth.currentUser?.fullName ?? 'Chủ Quán',
      userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
      action: 'CHANGE_PERMISSION',
      targetType: 'USER',
      targetId: user.username,
      details: '${newValue ? "Cấp thêm" : "Hủy"} quyền $permKey cho ${user.fullName}',
      isSuspicious: AppPermissions.isSensitive(permKey),
    ));

    setState(() {
      final idx = _users.indexWhere((u) => u.username == user.username);
      if (idx != -1) _users[idx] = updatedUser;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã cập nhật quyền cho ${user.fullName}!'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showAddEditRoleDialog([RoleModel? roleToEdit]) async {
    final nameCtrl = TextEditingController(text: roleToEdit?.name ?? '');
    final descCtrl = TextEditingController(text: roleToEdit?.description ?? '');
    final selectedPerms = Set<String>.from(roleToEdit?.permissions ?? []);

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: Text(
              roleToEdit == null ? 'Thêm Vai Trò Mới' : 'Sửa Vai Trò',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: 500,
              height: 500,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Tên vai trò * (vd: Trưởng ca tối)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Mô tả công việc'),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Tích chọn quyền hạn cho vai trò:',
                      style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ...AppPermissions.allPermissions.map((perm) {
                      final isChecked = selectedPerms.contains(perm.key);
                      final isSensitive = AppPermissions.isSensitive(perm.key);
                      return CheckboxListTile(
                        title: Row(
                          children: [
                            Text(perm.label, style: GoogleFonts.beVietnamPro(fontSize: 14)),
                            if (isSensitive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.dangerLight,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('Nhạy cảm', style: GoogleFonts.beVietnamPro(fontSize: 10, color: AppColors.danger, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(perm.description, style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary)),
                        value: isChecked,
                        dense: true,
                        onChanged: (val) {
                          setDlgState(() {
                            if (val == true) {
                              selectedPerms.add(perm.key);
                            } else {
                              selectedPerms.remove(perm.key);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final roleId = roleToEdit?.id ?? 'ROLE_${DateTime.now().millisecondsSinceEpoch}';
                  final newRole = RoleModel(
                    id: roleId,
                    name: nameCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    permissions: selectedPerms.toList(),
                    isSystemRole: roleToEdit?.isSystemRole ?? false,
                  );
                  await _fb.saveRole(newRole);
                  Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text('Lưu Vai Trò'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['Tất cả', AppPermissions.catMenu, AppPermissions.catTableOrder, AppPermissions.catBilling, AppPermissions.catReports, AppPermissions.catAdmin];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiểm Soát & Ma Trận Phân Quyền'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(icon: Icon(Icons.grid_on), text: 'Ma Trận Quyền Nhân Viên'),
            Tab(icon: Icon(Icons.badge_outlined), text: 'Danh Sách Vai Trò'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: MA TRẬN PHÂN QUYỀN NHÂN VIÊN
                Column(
                  children: [
                    // Toolbar Filter
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Tìm kiếm nhân viên...',
                                    prefixIcon: const Icon(Icons.search, size: 20),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: DropdownButtonFormField<String>(
                                  value: _selectedCategory,
                                  isDense: true,
                                  decoration: InputDecoration(
                                    labelText: 'Nhóm quyền',
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c, style: GoogleFonts.beVietnamPro(fontSize: 13)))).toList(),
                                  onChanged: (v) {
                                    if (v != null) setState(() => _selectedCategory = v);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Chủ quán tick chọn trực tiếp quyền hạn cho từng nhân viên. Thay đổi có hiệu lực ngay lập tức.',
                                  style: GoogleFonts.beVietnamPro(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // Interactive Matrix Table or Empty State
                    Expanded(
                      child: _filteredUsers.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty ? 'Chưa có tài khoản nhân viên nào' : 'Không tìm thấy tài khoản phù hợp',
                                    style: GoogleFonts.beVietnamPro(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Vui lòng vào Quản lý tài khoản để thêm nhân viên vào quán.',
                                    style: GoogleFonts.beVietnamPro(fontSize: 13, color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            )
                          : SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                            headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                            dataRowMinHeight: 48,
                            dataRowMaxHeight: 56,
                            columns: [
                              const DataColumn(
                                label: Text('Nhân Viên', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              const DataColumn(
                                label: Text('Vai Trò Gốc', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                              ..._filteredPermissions.map((perm) {
                                final isSens = AppPermissions.isSensitive(perm.key);
                                return DataColumn(
                                  label: Tooltip(
                                    message: '${perm.label}\n${perm.description}',
                                    child: Row(
                                      children: [
                                        Text(perm.label, style: TextStyle(fontWeight: FontWeight.bold, color: isSens ? AppColors.danger : null)),
                                        if (isSens) ...[
                                          const SizedBox(width: 4),
                                          const Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.danger),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ],
                            rows: _filteredUsers.map((user) {
                              final role = _roles.where((r) => r.id == user.roleId).firstOrNull;
                              return DataRow(
                                cells: [
                                  // User name & phone
                                  DataCell(
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 14,
                                          backgroundColor: user.isRootOwner ? Colors.amber : AppColors.primaryLight,
                                          child: Text(
                                            user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: user.isRootOwner ? Colors.white : AppColors.primary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(user.fullName, style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, fontSize: 13)),
                                            Text('@${user.username}', style: GoogleFonts.beVietnamPro(fontSize: 11, color: AppColors.textSecondary)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Role
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: user.isRootOwner ? Colors.amber.shade100 : Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        user.isRootOwner ? '👑 Chủ Quán' : (role?.name ?? user.roleId),
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: user.isRootOwner ? Colors.amber.shade900 : Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Permission Checkboxes
                                  ..._filteredPermissions.map((perm) {
                                    final hasPerm = user.can(perm.key, _roles);
                                    return DataCell(
                                      Center(
                                        child: Checkbox(
                                          value: hasPerm,
                                          activeColor: user.isRootOwner ? Colors.amber.shade700 : AppColors.primary,
                                          onChanged: user.isRootOwner
                                              ? null
                                              : (val) {
                                                  _toggleUserPermission(user, perm.key, val ?? false);
                                                },
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // TAB 2: QUẢN LÝ VAI TRÒ (ROLES)
                Scaffold(
                  floatingActionButton: FloatingActionButton.extended(
                    onPressed: () => _showAddEditRoleDialog(),
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: Text('Thêm Vai Trò Tùy Chỉnh', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  body: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _roles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final role = _roles[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      role.name,
                                      style: GoogleFonts.beVietnamPro(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (role.isSystemRole)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                                      child: const Text('Mặc định hệ thống', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 20),
                                    onPressed: () => _showAddEditRoleDialog(role),
                                  ),
                                  if (!role.isSystemRole)
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
                                      onPressed: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text('Xác nhận xóa'),
                                            content: Text('Bạn có chắc muốn xóa vai trò "${role.name}"?'),
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
                                          await _fb.deleteRole(role.id);
                                          _loadData();
                                        }
                                      },
                                    ),
                                ],
                              ),
                              if (role.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(role.description, style: GoogleFonts.beVietnamPro(color: AppColors.textSecondary, fontSize: 13)),
                              ],
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: role.permissions.map((pKey) {
                                  final pObj = AppPermissions.allPermissions.where((p) => p.key == pKey).firstOrNull;
                                  return Chip(
                                    label: Text(pObj?.label ?? pKey, style: const TextStyle(fontSize: 11)),
                                    backgroundColor: AppColors.primaryLight,
                                    visualDensity: VisualDensity.compact,
                                    padding: EdgeInsets.zero,
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
