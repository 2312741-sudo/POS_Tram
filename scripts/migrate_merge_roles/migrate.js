#!/usr/bin/env node
/**
 * Gộp vai trò trong Realtime Database của MỌI cửa hàng:
 *   Quản lý 1 / Quản lý 2 (manager_1, manager_2, ROLE_MANAGER_1/2, manager...) -> ROLE_MANAGER
 *   Thu ngân / Phục vụ (cashier, waiter, employee, ROLE_CASHIER, ROLE_WAITER...) -> ROLE_STAFF
 * Ghi lại roleId + role của hồ sơ nhân viên (stores/{s}/users/*) và gộp bản ghi vai trò (stores/{s}/roles/*)
 * theo HỢP quyền. Không đụng chủ quán gốc (isRootOwner), Bếp, vai trò tự tạo. Mã cũ vẫn được rules/ứng dụng chấp nhận,
 * nên chạy hay không chạy script đều không làm ai mất quyền; script chỉ dọn dữ liệu về mã chuẩn.
 *
 *   node migrate.js                                    # DRY-RUN (mặc định): chỉ in những gì SẼ đổi
 *   node migrate.js --store=TRAM01                     # giới hạn 1 cửa hàng
 *   node migrate.js --apply                            # GHI THẬT (ghi nhật ký vào audit_logs của từng quán)
 *   node migrate.js --service-account=./service-account.json --database-url=https://...firebasedatabase.app
 *
 * Cần service account (xem ../migrate_legacy_users/README.md). KHÔNG chạy --apply trên production khi chưa sao lưu
 * (Firebase Console → Realtime Database → Export JSON) và chưa kiểm tra bản dry-run.
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { planUserUpdate, planRolesMerge } = require("./roles");

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const val = (p) => (args.find((a) => a.startsWith(p)) || "").split("=").slice(1).join("=");

const apply = flag("--apply");
const onlyStore = val("--store=").trim().toUpperCase();

function findKey() {
  const explicit = val("--service-account=") || process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (explicit && fs.existsSync(explicit)) return path.resolve(explicit);
  for (const dir of [__dirname, path.resolve(__dirname, "../.."), process.cwd()]) {
    const f = fs.existsSync(dir) && fs.readdirSync(dir).find((x) => x.startsWith("service-account") && x.endsWith(".json"));
    if (f) return path.join(dir, f);
  }
  return null;
}

async function main() {
  const keyPath = findKey();
  if (!keyPath) throw new Error("Không tìm thấy service-account*.json (hoặc --service-account=...)");
  const sa = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    databaseURL: val("--database-url=") || `https://${sa.project_id}-default-rtdb.asia-southeast1.firebasedatabase.app`,
  });
  const db = admin.database();

  console.log(`Gộp vai trò • ${apply ? "--apply (GHI THẬT)" : "DRY-RUN (không ghi gì)"}${onlyStore ? ` • chỉ ${onlyStore}` : ""}`);
  const storesSnap = await db.ref("stores").get();
  const stores = storesSnap.exists() ? Object.keys(storesSnap.val()) : [];

  const summary = { stores: 0, usersScanned: 0, usersChanged: 0, rolesMerged: 0, rolesRemoved: 0 };
  for (const storeCode of stores) {
    if (onlyStore && storeCode !== onlyStore) continue;
    summary.stores++;
    const usersSnap = await db.ref(`stores/${storeCode}/users`).get();
    const users = usersSnap.exists() ? usersSnap.val() : {};
    const multi = {};
    let changedHere = 0;

    for (const [key, profile] of Object.entries(users)) {
      summary.usersScanned++;
      const updates = planUserUpdate(profile);
      if (!updates) continue;
      changedHere++;
      summary.usersChanged++;
      console.log(`  [${storeCode}] ${profile.username || key}: ${profile.roleId || profile.role} -> ${updates.roleId || updates.role}`);
      for (const [f, v] of Object.entries(updates)) multi[`stores/${storeCode}/users/${key}/${f}`] = v;
    }

    const rolesSnap = await db.ref(`stores/${storeCode}/roles`).get();
    const { writes, removes } = planRolesMerge(rolesSnap.exists() ? rolesSnap.val() : null);
    for (const [id, rec] of Object.entries(writes)) {
      summary.rolesMerged++;
      console.log(`  [${storeCode}] vai trò ${id}: gộp ${rec.permissions.length} quyền`);
      multi[`stores/${storeCode}/roles/${id}`] = rec;
    }
    for (const id of removes) {
      summary.rolesRemoved++;
      console.log(`  [${storeCode}] bản ghi vai trò cũ ${id}: sẽ xóa (đã gộp)`);
      multi[`stores/${storeCode}/roles/${id}`] = null;
    }

    if (apply && Object.keys(multi).length) {
      const logId = `LOG_${Date.now()}_merge_roles`;
      multi[`stores/${storeCode}/audit_logs/${logId}`] = {
        timestamp: Date.now(),
        action: "MIGRATE_MERGE_ROLES",
        staffUsername: "system",
        staffFullName: "Script gộp vai trò",
        details: `Gộp vai trò: ${changedHere} hồ sơ, ${Object.keys(writes).length} vai trò`,
      };
      await db.ref().update(multi);
      console.log(`  [${storeCode}] ĐÃ GHI`);
    }
  }

  console.log("\nTổng kết:", JSON.stringify(summary));
  if (!apply) console.log("Đây là DRY-RUN. Thêm --apply để ghi thật.");
}

main().then(() => process.exit(0)).catch((e) => { console.error("LỖI:", e.message); process.exit(1); });
