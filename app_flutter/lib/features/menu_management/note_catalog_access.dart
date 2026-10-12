// lib/features/menu_management/note_catalog_access.dart
import '../../core/permissions/app_permissions.dart';
import '../../core/services/auth_service.dart';

/// Quyền quản lý danh mục note & topping (MANAGE_NOTE_CATALOG: chủ, quản lý). Một chỗ duy nhất để đổi quy tắc.
bool canManageNoteCatalog(AuthService auth) => auth.can(AppPermissions.manageNoteCatalog);
