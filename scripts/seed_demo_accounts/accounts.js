// Danh sách tài khoản MẪU theo bộ phận + hàm dựng hồ sơ (thuần, không gọi Firebase → dễ kiểm thử).

const DEMO_ACCOUNTS = [
  { username: "chu_demo", fullName: "Chủ quán (mẫu)", roleId: "ROLE_OWNER", department: "Chủ" },
  { username: "quanly_demo", fullName: "Quản lý (mẫu)", roleId: "ROLE_MANAGER", department: "Quản lý" },
  { username: "banhang_demo", fullName: "Nhân viên bán hàng (mẫu)", roleId: "ROLE_STAFF", department: "Nhân viên bán hàng" },
  { username: "bep_demo", fullName: "Nhân viên bếp (mẫu)", roleId: "ROLE_KITCHEN", department: "Nhân viên bếp" },
];

function normalizeUsername(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/đ/g, "d")
    .replace(/[^a-z0-9_.-]/g, "");
}

// Khớp functions/src/permissions.ts → buildSyntheticEmail
function buildSyntheticEmail(username, storeCode) {
  const cleanStore = String(storeCode).trim().toLowerCase().replace(/[^a-z0-9]/g, "");
  return `${normalizeUsername(username)}.${cleanStore}@tram.local`;
}

// Khớp createStaffAccount (functions/src/index.ts) + cờ isDemo để nhận biết / gỡ sạch
function buildProfile(account, uid, now) {
  return {
    uid,
    username: normalizeUsername(account.username),
    fullName: account.fullName,
    roleId: account.roleId,
    isRootOwner: false,
    isActive: true,
    phone: "",
    customPermissions: [],
    createdAt: now,
    mustChangePassword: false,
    isDemo: true,
  };
}

function validatePassword(p) {
  return typeof p === "string" && p.length >= 8;
}

module.exports = { DEMO_ACCOUNTS, normalizeUsername, buildSyntheticEmail, buildProfile, validatePassword };
