// Gộp vai trò: Quản lý 1 + Quản lý 2 -> ROLE_MANAGER; Thu ngân + Phục vụ -> ROLE_STAFF.
// Logic thuần (không gọi Firebase) → có test. Khớp functions/src/permissions.ts → normalizeRoleId.

const ROLE_MANAGER = "ROLE_MANAGER";
const ROLE_STAFF = "ROLE_STAFF";

const clean = (raw) => String(raw == null ? "" : raw).trim().toLowerCase().replace(/[-\s]+/g, "_");

const MANAGER_ALIASES = new Set([
  "manager", "role_manager", "manager_1", "manager_2", "role_manager_1", "role_manager_2",
  "manager1", "manager2", "legacymanager", "legacy_manager",
  "ql", "ql1", "ql2", "ql_1", "ql_2", "quan_ly", "quan_ly_1", "quan_ly_2",
]);
const STAFF_ALIASES = new Set([
  "role_staff", "staff", "employee", "role_employee", "cashier", "role_cashier",
  "waiter", "role_waiter", "nhan_vien", "nv", "thu_ngan", "phuc_vu",
]);

/** Mã chuẩn của một vai trò; vai trò khác (owner, ROLE_KITCHEN, tự tạo...) giữ nguyên. */
function normalizeRoleId(raw) {
  const trimmed = String(raw == null ? "" : raw).trim();
  const c = clean(trimmed);
  if (MANAGER_ALIASES.has(c)) return ROLE_MANAGER;
  if (STAFF_ALIASES.has(c)) return ROLE_STAFF;
  return trimmed;
}

/**
 * Kế hoạch cập nhật một hồ sơ nhân viên: trả về { updates } (chỉ các trường đổi) hoặc null nếu không cần đổi.
 * Không đụng chủ quán gốc (isRootOwner) và không đổi các vai trò khác.
 */
function planUserUpdate(profile) {
  if (!profile || typeof profile !== "object" || profile.isRootOwner === true) return null;
  const updates = {};
  for (const field of ["roleId", "role"]) {
    if (typeof profile[field] !== "string" || !profile[field].trim()) continue;
    const next = normalizeRoleId(profile[field]);
    if (next !== profile[field] && (next === ROLE_MANAGER || next === ROLE_STAFF)) updates[field] = next;
  }
  return Object.keys(updates).length ? updates : null;
}

/**
 * Kế hoạch gộp bản ghi vai trò (stores/{s}/roles/{id}): quyền của các bản ghi cũ gộp thành HỢP vào bản ghi chuẩn.
 * roles: { [id]: { name, permissions } } → { writes: { [id]: roleRecord }, removes: [id] }
 */
function planRolesMerge(roles) {
  const writes = {};
  const removes = [];
  if (!roles || typeof roles !== "object") return { writes, removes };
  const toPerms = (r) => (Array.isArray(r && r.permissions) ? r.permissions : r && r.permissions && typeof r.permissions === "object" ? Object.keys(r.permissions) : []);
  const groups = {};
  for (const [id, rec] of Object.entries(roles)) {
    const target = normalizeRoleId(id);
    if (target !== ROLE_MANAGER && target !== ROLE_STAFF) continue;
    (groups[target] = groups[target] || []).push([id, rec]);
  }
  for (const [target, list] of Object.entries(groups)) {
    const perms = new Set();
    list.forEach(([, rec]) => toPerms(rec).forEach((p) => perms.add(p)));
    const base = (list.find(([id]) => id === target) || list[0])[1] || {};
    writes[target] = {
      ...base,
      id: target,
      name: target === ROLE_MANAGER ? "Quản lý" : "Nhân viên (Thu ngân / Phục vụ)",
      permissions: Array.from(perms).sort(),
      isSystemRole: true,
    };
    list.forEach(([id]) => { if (id !== target) removes.push(id); });
  }
  return { writes, removes };
}

module.exports = { ROLE_MANAGER, ROLE_STAFF, normalizeRoleId, planUserUpdate, planRolesMerge };
