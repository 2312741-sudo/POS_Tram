import { hasPermission, type User } from "./auth";

/** Quyền quản lý danh mục note & topping (MANAGE_NOTE_CATALOG: chủ, quản lý). Một chỗ duy nhất để đổi quy tắc. */
export function canManageNoteCatalog(user: User | null | undefined): boolean {
  return !!user && hasPermission(user, "MANAGE_NOTE_CATALOG");
}
