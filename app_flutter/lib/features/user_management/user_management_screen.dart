// lib/features/user_management/user_management_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format_utils.dart';
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
    setState(() => _isLoading = true);
    try {
      final users = await _fb.getUsers();
      final roles = await _fb.getRoles();
      if (mounted) {
        setState(() {
          _users = users;
          _roles = roles.isNotEmpty
              ? roles
              : [
                  RoleModel(
                    id: 'ROLE_OWNER',
                    name: 'Chủ Quán (Toàn quyền)',
                    permissions: AppPermissions.allPermissions.map((p) => p.key).toList(),
                    isSystemRole: true,
                  ),
                  RoleModel(
                    id: 'ROLE_MANAGER_1',
                    name: 'Quản Lý 1 (Điều hành & Kho)',
                    permissions: [
                      AppPermissions.viewMenu,
                      AppPermissions.editMenu,
                      AppPermissions.changePrice,
                      AppPermissions.openTable,
                      AppPermissions.changeTable,
                      AppPermissions.mergeSplitTable,
                      AppPermissions.sendKitchen,
                      AppPermissions.cancelKitchenItem,
                      AppPermissions.createBill,
                      AppPermissions.editBill,
                      AppPermissions.applyPromotion,
                      AppPermissions.manualDiscount,
                      AppPermissions.cancelBill,
                      AppPermissions.printBill,
                      AppPermissions.reprintBill,
                      AppPermissions.manageCashShift,
                      AppPermissions.viewReports,
                      AppPermissions.viewAuditLogs,
                      AppPermissions.viewInventory,
                    ],
                    isSystemRole: true,
                  ),
                  RoleModel(
                    id: 'ROLE_MANAGER_2',
                    name: 'Quản Lý 2 (Giám sát ca)',
                    permissions: [
                      AppPermissions.viewMenu,
                      AppPermissions.openTable,
                      AppPermissions.changeTable,
                      AppPermissions.mergeSplitTable,
                      AppPermissions.sendKitchen,
                      AppPermissions.createBill,
                      AppPermissions.applyPromotion,
                      AppPermissions.printBill,
                      AppPermissions.manageCashShift,
                      AppPermissions.viewReports,
                    ],
                    isSystemRole: true,
                  ),
                  RoleModel(
                    id: 'ROLE_CASHIER',
                    name: 'Thu Ngân / Phục Vụ',
                    permissions: [
                      AppPermissions.viewMenu,
                      AppPermissions.openTable,
                      AppPermissions.changeTable,
                      AppPermissions.sendKitchen,
                      AppPermissions.createBill,
                      AppPermissions.applyPromotion,
                      AppPermissions.printBill,
                    ],
                    isSystemRole: true,
                  ),
                ];
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Hộp thoại chọn quyền riêng (Custom Permissions)
  Future<List<String>?> _showPermissionsPickerDialog(List<String> currentPerms) async {
    final selected = List<String>.from(currentPerms);

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = math.min(500.0, screenWidth * 0.9);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Cấp Quyền Riêng Biệt (Custom Permissions)',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(500.0, screenWidth * 0.9),
              ),
              child: SizedBox(
                width: dialogWidth,
                height: 400,
                child: ListView.builder(
                  itemCount: AppPermissions.allPermissions.length,
                  itemBuilder: (context, i) {
                    final p = AppPermissions.allPermissions[i];
                    final isChecked = selected.contains(p.key);

                    return CheckboxListTile(
                      dense: true,
                      title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text('${p.category} • ${p.key}', style: const TextStyle(fontSize: 11)),
                      value: isChecked,
                      activeColor: context.tc.primary,
                      onChanged: (val) {
                        setDlgState(() {
                          if (val == true) {
                            selected.add(p.key);
                          } else {
                            selected.remove(p.key);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: context.tc.border),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Hủy', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, color: context.tc.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        backgroundColor: context.tc.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () => Navigator.pop(ctx, selected),
                      child: Text('Xác Nhận', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Hộp thoại Thêm hoặc Sửa Nhân Viên
  Future<void> _showAddEditUserDialog([UserModel? userToEdit]) async {
    final isEditing = userToEdit != null;
    final fullNameCtrl = TextEditingController(text: userToEdit?.fullName ?? '');
    final usernameCtrl = TextEditingController(text: userToEdit?.username ?? '');
    final passCtrl = TextEditingController();
    final phoneCtrl = TextEditingController(text: userToEdit?.phone ?? '');

    String selectedRole = userToEdit?.roleId ?? (_roles.isNotEmpty ? _roles.last.id : 'ROLE_CASHIER');
    List<String> customPerms = List<String>.from(userToEdit?.customPermissions ?? []);
    bool obscure = true;
    String? dlgError;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isRoot = userToEdit?.isRootOwner ?? false;
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = math.min(480.0, screenWidth < 480 ? (screenWidth - 32) : screenWidth * 0.9);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              isEditing ? 'Sửa Thông Tin Nhân Viên' : 'Thêm Nhân Viên Mới',
              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(480.0, screenWidth < 480 ? (screenWidth - 32) : screenWidth * 0.9),
              ),
              child: SizedBox(
                width: dialogWidth,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (dlgError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: context.tc.dangerLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.tc.danger.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: context.tc.danger, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  dlgError!,
                                  style: GoogleFonts.beVietnamPro(color: context.tc.danger, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (isRoot) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: context.bg(Colors.amber.shade50),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.workspace_premium, color: context.ink(Colors.brown), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '👑 Tài khoản Chủ Quán Tối Cao (Sovereign Owner). Không thể thay đổi vai trò hoặc hạ quyền.',
                                  style: TextStyle(color: context.ink(Colors.brown), fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      TextField(
                        controller: fullNameCtrl,
                        decoration: const InputDecoration(labelText: 'Họ và tên *', prefixIcon: Icon(Icons.person_outline)),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: usernameCtrl,
                        decoration: InputDecoration(
                          labelText: 'Tên đăng nhập *',
                          prefixIcon: const Icon(Icons.badge_outlined),
                          hintText: 'VD: thungan1, ql_kho (3-30 ký tự)',
                          helperText: isEditing ? 'Không thể thay đổi tên đăng nhập đã tạo' : null,
                        ),
                        enabled: !isEditing,
                      ),
                      const SizedBox(height: 12),

                      if (!isEditing) ...[
                        TextField(
                          controller: passCtrl,
                          obscureText: obscure,
                          decoration: InputDecoration(
                            labelText: 'Mật khẩu khởi tạo *',
                            prefixIcon: const Icon(Icons.lock_outline),
                            hintText: 'Tối thiểu 6 ký tự',
                            helperText: 'Nhân viên sẽ được yêu cầu đổi mật khẩu ở lần đăng nhập đầu tiên',
                            suffixIcon: IconButton(
                              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                              onPressed: () => setDlgState(() => obscure = !obscure),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
                      ),
                      const SizedBox(height: 12),

                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: selectedRole,
                        decoration: const InputDecoration(labelText: 'Vai trò mặc định *'),
                        items: _roles.map((r) {
                          return DropdownMenuItem(
                            value: r.id,
                            child: Text(r.name, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: isRoot
                            ? null
                            : (v) {
                                if (v != null) setDlgState(() => selectedRole = v);
                              },
                      ),
                      const SizedBox(height: 14),

                      // Khối phân quyền riêng lẻ bổ sung (Container card gọn gàng, co giãn linh hoạt)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: context.tc.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.tc.border),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 280;
                            if (isCompact) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Quyền riêng lẻ bổ sung',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: context.tc.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    customPerms.isEmpty
                                        ? 'Không có quyền bổ sung'
                                        : '${customPerms.length} quyền riêng biệt đã cấp thêm',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      color: customPerms.isEmpty
                                          ? context.tc.textSecondary
                                          : context.tc.primary,
                                      fontWeight: customPerms.isEmpty
                                          ? FontWeight.normal
                                          : FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 36),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                        side: BorderSide(color: context.tc.primary.withValues(alpha: 0.5)),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        backgroundColor: context.tc.primaryLight.withValues(alpha: 0.15),
                                      ),
                                      icon: Icon(Icons.tune, size: 16, color: context.tc.primary),
                                      label: Text(
                                        'Tùy chỉnh quyền',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: context.tc.primary,
                                        ),
                                      ),
                                      onPressed: () async {
                                        final res = await _showPermissionsPickerDialog(customPerms);
                                        if (res != null) {
                                          setDlgState(() => customPerms = res);
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Quyền riêng lẻ bổ sung',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: context.tc.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        customPerms.isEmpty
                                            ? 'Không có quyền bổ sung'
                                            : '${customPerms.length} quyền riêng biệt đã cấp thêm',
                                        style: GoogleFonts.beVietnamPro(
                                          fontSize: 12,
                                          color: customPerms.isEmpty
                                              ? context.tc.textSecondary
                                              : context.tc.primary,
                                          fontWeight: customPerms.isEmpty
                                              ? FontWeight.normal
                                              : FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    side: BorderSide(color: context.tc.primary.withValues(alpha: 0.5)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    backgroundColor: context.tc.primaryLight.withValues(alpha: 0.15),
                                  ),
                                  icon: Icon(Icons.tune, size: 16, color: context.tc.primary),
                                  label: Text(
                                    'Tùy chỉnh quyền',
                                    style: GoogleFonts.beVietnamPro(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: context.tc.primary,
                                    ),
                                  ),
                                  onPressed: () async {
                                    final res = await _showPermissionsPickerDialog(customPerms);
                                    if (res != null) {
                                      setDlgState(() => customPerms = res);
                                    }
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: context.tc.border),
                      ),
                      onPressed: isSaving ? null : () => Navigator.pop(ctx),
                      child: Text(
                        'Hủy',
                        style: GoogleFonts.beVietnamPro(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: context.tc.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: context.tc.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final fullName = fullNameCtrl.text.trim();
                              final username = AuthUtils.normalizeUsername(usernameCtrl.text);
                              final rawPass = passCtrl.text;
                              final phone = phoneCtrl.text.trim();

                              if (fullName.isEmpty) {
                                setDlgState(() => dlgError = 'Vui lòng nhập họ và tên nhân viên.');
                                return;
                              }

                              if (!isEditing) {
                                if (!AuthUtils.isValidUsername(username)) {
                                  setDlgState(() => dlgError = 'Tên đăng nhập không hợp lệ. Chỉ chấp nhận chữ thường không dấu, số, gạch dưới hoặc gạch ngang (3-30 ký tự).');
                                  return;
                                }
                                if (rawPass.length < 6) {
                                  setDlgState(() => dlgError = 'Mật khẩu khởi tạo phải có tối thiểu 6 ký tự.');
                                  return;
                                }
                                // Kiểm tra trùng username
                                final exists = _users.any((u) => u.username.toLowerCase() == username);
                                if (exists) {
                                  setDlgState(() => dlgError = 'Tên đăng nhập "$username" đã tồn tại tại cửa hàng này.');
                                  return;
                                }
                              }

                              setDlgState(() {
                                isSaving = true;
                                dlgError = null;
                              });

                              final storeCode = _auth.currentStoreCode;

                              if (!isEditing) {
                                // TẠO MỚI QUA CLOUD FUNCTIONS (An toàn tuyệt đối, không dùng secondary app)
                                try {
                                  final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
                                  final callable = functions.httpsCallable('createStaffAccount');
                                  await callable.call({
                                    'storeCode': storeCode,
                                    'username': username,
                                    'fullName': fullName,
                                    'roleId': selectedRole,
                                    'tempPassword': rawPass,
                                    'phone': phone,
                                    'customPermissions': customPerms,
                                  });

                                  if (mounted && ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    _loadData();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Đã tạo nhân viên @$username thành công!'),
                                        backgroundColor: AppColors.success,
                                      ),
                                    );
                                  }
                                } on FirebaseFunctionsException catch (e) {
                                  String msg = e.message ?? 'Lỗi tạo tài khoản nhân viên.';
                                  if (e.code == 'already-exists') {
                                    msg = 'Tên đăng nhập này đã được sử dụng trong chi nhánh.';
                                  }
                                  setDlgState(() {
                                    dlgError = msg;
                                    isSaving = false;
                                  });
                                } catch (e) {
                                  setDlgState(() {
                                    dlgError = 'Lỗi hệ thống: $e';
                                    isSaving = false;
                                  });
                                }
                              } else {
                                // CẬP NHẬT HỒ SƠ NGƯỜI DÙNG HIỆN CÓ
                                try {
                                  final updatedUser = userToEdit.copyWith(
                                    fullName: fullName,
                                    phone: phone,
                                    roleId: isRoot ? userToEdit.roleId : selectedRole,
                                    customPermissions: customPerms,
                                  );

                                  await _fb.saveUser(updatedUser);

                                  await _fb.logAction(AuditLogModel(
                                    timestamp: DateTime.now().millisecondsSinceEpoch,
                                    username: _auth.currentUser?.username ?? 'admin',
                                    userFullName: _auth.currentUser?.fullName ?? 'Chủ Quán',
                                    userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
                                    action: 'USER_UPDATE',
                                    targetType: 'USER',
                                    targetId: updatedUser.username,
                                    details: 'Sửa thông tin nhân viên @${updatedUser.username} (${updatedUser.fullName})',
                                  ));

                                  if (mounted && ctx.mounted) {
                                    Navigator.of(ctx).pop();
                                    _loadData();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Cập nhật thông tin thành công!'), backgroundColor: AppColors.success),
                                    );
                                  }
                                } catch (e) {
                                  setDlgState(() {
                                    dlgError = 'Lỗi lưu thông tin: $e';
                                    isSaving = false;
                                  });
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(
                              isEditing ? 'LƯU THAY ĐỔI' : 'TẠO NHÂN VIÊN',
                              style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Khóa hoặc Mở khóa tài khoản nhân viên (Sovereign Owner Rule bảo vệ Chủ quán)
  Future<void> _toggleUserActiveStatus(UserModel user) async {
    if (user.isRootOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('👑 Không thể khóa tài khoản Chủ Quán Tối Cao!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final willDeactivate = user.isActive;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(willDeactivate ? 'Xác nhận khóa tài khoản' : 'Xác nhận mở khóa tài khoản'),
        content: Text(
          willDeactivate
              ? 'Bạn có chắc chắn muốn TẠM KHÓA tài khoản của "${user.fullName}" (@${user.username})? Nhân viên này sẽ không thể đăng nhập.'
              : 'Bạn có chắc chắn muốn MỞ KHÓA tài khoản cho "${user.fullName}" (@${user.username})?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: willDeactivate ? context.tc.danger : context.tc.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(willDeactivate ? 'Khóa Tài Khoản' : 'Mở Khóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
        final callable = functions.httpsCallable('setStaffDisabled');
        await callable.call({
          'storeCode': _auth.currentStoreCode,
          'targetUid': user.uid.isNotEmpty ? user.uid : user.username,
          'disabled': willDeactivate,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(willDeactivate ? 'Đã tạm khóa tài khoản @${user.username}' : 'Đã mở khóa tài khoản @${user.username}'),
              backgroundColor: willDeactivate ? AppColors.warningInk : AppColors.success,
            ),
          );
        }
        _loadData();
      } on FirebaseFunctionsException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e.message ?? 'Lỗi khi cập nhật trạng thái tài khoản.'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lỗi hệ thống: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
        }
      }
    }
  }

  /// Đặt lại mật khẩu nhân viên qua Cloud Functions (Bật mustChangePassword)
  Future<void> _showResetPasswordDialog(UserModel user) async {
    final passwordCtrl = TextEditingController();
    bool isSaving = false;
    String? dlgError;
    bool obscure = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final screenWidth = MediaQuery.of(context).size.width;
          final dialogWidth = math.min(380.0, screenWidth * 0.9);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.bg(Colors.purple.shade50),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.key_outlined, color: Colors.purple),
                ),
                const SizedBox(width: 10),
                const Text('Đặt lại mật khẩu', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(380.0, screenWidth * 0.9),
              ),
              child: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.tc.cardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.tc.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Tài khoản nhân viên:', style: TextStyle(fontSize: 12, color: context.tc.textSecondary)),
                          const SizedBox(height: 2),
                          Text('${user.fullName} (@${user.username})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordCtrl,
                      obscureText: obscure,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới *',
                        hintText: 'Tối thiểu 6 ký tự',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        suffixIcon: IconButton(
                          icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                          onPressed: () => setDlgState(() => obscure = !obscure),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '* Nhân viên sẽ bắt buộc đổi mật khẩu ở lần đăng nhập tiếp theo.',
                      style: TextStyle(fontSize: 11, color: context.tc.textSecondary),
                    ),
                    if (dlgError != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.tc.dangerLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(dlgError!, style: TextStyle(color: context.tc.danger, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: context.tc.border),
                      ),
                      onPressed: isSaving ? null : () => Navigator.pop(ctx),
                      child: Text('Hủy', style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600, color: context.tc.textSecondary)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final newPass = passwordCtrl.text.trim();
                              if (newPass.length < 6) {
                                setDlgState(() => dlgError = 'Mật khẩu mới phải có tối thiểu 6 ký tự.');
                                return;
                              }

                              setDlgState(() {
                                isSaving = true;
                                dlgError = null;
                              });

                              try {
                                final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
                                final callable = functions.httpsCallable('resetStaffPassword');
                                await callable.call({
                                  'storeCode': _auth.currentStoreCode,
                                  'targetUid': user.uid.isNotEmpty ? user.uid : user.username,
                                  'newPassword': newPass,
                                });

                                if (mounted && ctx.mounted) {
                                  Navigator.of(ctx).pop();
                                  _loadData();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Đã đặt lại mật khẩu cho @${user.username} thành công!'),
                                      backgroundColor: AppColors.success,
                                    ),
                                  );
                                }
                              } on FirebaseFunctionsException catch (e) {
                                setDlgState(() {
                                  dlgError = e.message ?? 'Lỗi khi đặt lại mật khẩu.';
                                  isSaving = false;
                                });
                              } catch (e) {
                                setDlgState(() {
                                  dlgError = 'Lỗi hệ thống: $e';
                                  isSaving = false;
                                });
                              }
                            },
                      child: isSaving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Xác nhận đặt lại', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Xóa tài khoản nhân viên (Sovereign Owner Rule bảo vệ Chủ quán)
  Future<void> _deleteUser(UserModel user) async {
    if (user.isRootOwner) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('👑 Không thể xóa tài khoản Chủ Quán Tối Cao!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa nhân viên'),
        content: Text('Bạn có chắc muốn xóa hồ sơ nhân viên "${user.fullName}" (@${user.username}) khỏi chi nhánh? Thao tác này không thể hoàn tác.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.tc.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _fb.deleteUser(user.uid.isNotEmpty ? user.uid : user.username);

      await _fb.logAction(AuditLogModel(
        timestamp: DateTime.now().millisecondsSinceEpoch,
        username: _auth.currentUser?.username ?? 'admin',
        userFullName: _auth.currentUser?.fullName ?? 'Chủ Quán',
        userRole: _auth.currentUser?.roleId ?? 'ROLE_OWNER',
        action: 'USER_DELETE',
        targetType: 'USER',
        targetId: user.username,
        details: 'Xóa hồ sơ nhân viên @${user.username} (${user.fullName})',
      ));

      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản Lý Tài Khoản Nhân Viên'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _loadData,
          ),
          IconButton(
            icon: const Icon(Icons.grid_on),
            tooltip: 'Ma trận phân quyền',
            onPressed: () => context.push('/permissions-matrix'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditUserDialog(),
        icon: const Icon(Icons.person_add_outlined, color: Colors.white),
        label: Text('Thêm Nhân Viên', style: GoogleFonts.beVietnamPro(color: Colors.white, fontWeight: FontWeight.w600)),
        backgroundColor: context.tc.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _users.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline, size: 64, color: context.tc.textHint),
                      const SizedBox(height: 12),
                      Text(
                        'Chưa có tài khoản nhân viên nào',
                        style: GoogleFonts.beVietnamPro(fontSize: 16, color: context.tc.textSecondary, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Bấm "Thêm Nhân Viên" để tạo tài khoản đầu tiên',
                        style: GoogleFonts.beVietnamPro(fontSize: 13, color: context.tc.textSecondary),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final role = _roles.where((r) => r.id == user.roleId).firstOrNull;

                    return Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: user.isRootOwner
                              ? Colors.amber.shade300
                              : (!user.isActive ? context.tc.danger.withValues(alpha: 0.3) : context.tc.border),
                          width: user.isRootOwner ? 1.5 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Avatar
                            CircleAvatar(
                              radius: 22,
                              backgroundColor: user.isRootOwner
                                  ? Colors.amber.shade400
                                  : (user.isActive ? context.tc.primaryLight : context.tc.border),
                              child: Text(
                                user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : 'U',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: user.isRootOwner
                                      ? Colors.white
                                      : (user.isActive ? context.tc.primary : context.tc.textSecondary),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Main Content
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Name and Badges
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      Text(
                                        user.fullName,
                                        style: GoogleFonts.beVietnamPro(fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                      if (user.isRootOwner)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: context.bg(Colors.amber.shade100),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.shade400, width: 0.8),
                                          ),
                                          child: Text(
                                            '👑 Chủ Quán Tối Cao',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: context.ink(Colors.brown)),
                                          ),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: user.isActive ? context.tc.successLight : context.tc.dangerLight,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          user.isActive ? 'Hoạt động' : 'Đã khóa',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: user.isActive ? context.tc.success : context.tc.danger,
                                          ),
                                        ),
                                      ),
                                      if (user.mustChangePassword)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: context.tc.warningLight,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '⚠️ Chưa đổi MK',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.tc.warningInk),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),

                                  // Username & Role
                                  Text(
                                    '@${user.username} • Vai trò: ${role?.name ?? user.roleId}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 12, color: context.tc.textSecondary),
                                  ),

                                  // Phone & Last login
                                  const SizedBox(height: 2),
                                  Text(
                                    '${user.phone.isNotEmpty ? "SĐT: ${user.phone} • " : ""}Đăng nhập cuối: ${user.lastLoginAt != null ? FormatUtils.dateTime(user.lastLoginAt!) : "Chưa từng đăng nhập"}',
                                    style: GoogleFonts.beVietnamPro(fontSize: 11, color: context.tc.textSecondary),
                                  ),

                                  // Custom Permissions Chip
                                  if (user.customPermissions.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: context.tc.primaryLight.withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '🌟 ${user.customPermissions.length} quyền riêng biệt',
                                            style: GoogleFonts.beVietnamPro(
                                              fontSize: 10,
                                              color: context.tc.primaryDark,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            // Actions
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Lock / Unlock Action
                                if (!user.isRootOwner)
                                  IconButton(
                                    icon: Icon(
                                      user.isActive ? Icons.lock_open_outlined : Icons.lock_outlined,
                                      color: user.isActive ? context.tc.textSecondary : context.tc.danger,
                                      size: 20,
                                    ),
                                    tooltip: user.isActive ? 'Khóa tài khoản' : 'Mở khóa tài khoản',
                                    onPressed: () => _toggleUserActiveStatus(user),
                                  ),

                                // Edit Action
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 20),
                                  tooltip: 'Sửa thông tin',
                                  onPressed: () => _showAddEditUserDialog(user),
                                ),

                                // Reset Password Action (Qua Cloud Function)
                                if (!user.isRootOwner || (_auth.currentUser?.isRootOwner ?? false))
                                  IconButton(
                                    icon: const Icon(Icons.key_outlined, size: 20, color: Colors.purple),
                                    tooltip: 'Đặt lại mật khẩu',
                                    onPressed: () => _showResetPasswordDialog(user),
                                  ),

                                // Delete Action (Hidden for Root Owner)
                                if (!user.isRootOwner)
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: context.tc.danger, size: 20),
                                    tooltip: 'Xóa tài khoản',
                                    onPressed: () => _deleteUser(user),
                                  ),
                              ],
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
