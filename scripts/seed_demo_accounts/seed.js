#!/usr/bin/env node
/**
 * Tạo / gỡ tài khoản MẪU theo bộ phận (Chủ, Quản lý, Nhân viên bán hàng, Nhân viên bếp) cho một cửa hàng.
 *
 *   node seed.js --store=TRAM01 --password=MatKhau@123            # dry-run (mặc định)
 *   node seed.js --store=TRAM01 --password=MatKhau@123 --apply    # tạo thật
 *   node seed.js --store=TRAM01 --remove --apply                  # gỡ các tài khoản mẫu (isDemo)
 *
 * Cần service account (xem ../migrate_legacy_users/README.md). Mật khẩu không được hard-code:
 * bắt buộc truyền --password (>= 8 ký tự) hoặc đặt biến DEMO_PASSWORD. Tài khoản mẫu đã tồn tại thì bỏ qua.
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { DEMO_ACCOUNTS, buildSyntheticEmail, buildProfile, normalizeUsername, validatePassword } = require("./accounts");

const args = process.argv.slice(2);
const flag = (n) => args.includes(n);
const val = (p) => (args.find((a) => a.startsWith(p)) || "").split("=").slice(1).join("=");

const apply = flag("--apply");
const remove = flag("--remove");
const storeCode = val("--store=").trim().toUpperCase();
const password = val("--password=") || process.env.DEMO_PASSWORD || "";

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
  if (!storeCode) throw new Error("Thiếu --store=MÃ_CỬA_HÀNG");
  if (!remove && !validatePassword(password)) throw new Error("Cần --password (hoặc DEMO_PASSWORD) tối thiểu 8 ký tự");
  const keyPath = findKey();
  if (!keyPath) throw new Error("Không tìm thấy service-account*.json (hoặc --service-account=...)");
  const sa = JSON.parse(fs.readFileSync(keyPath, "utf8"));
  admin.initializeApp({
    credential: admin.credential.cert(sa),
    databaseURL: val("--database-url=") || `https://${sa.project_id}-default-rtdb.asia-southeast1.firebasedatabase.app`,
  });
  const auth = admin.auth();
  const db = admin.database();

  console.log(`Cửa hàng ${storeCode} • ${remove ? "GỠ" : "TẠO"} tài khoản mẫu • ${apply ? "--apply (GHI THẬT)" : "DRY-RUN"}`);
  const usersSnap = await db.ref(`stores/${storeCode}/users`).get();
  const users = usersSnap.exists() ? usersSnap.val() : {};

  for (const acc of DEMO_ACCOUNTS) {
    const email = buildSyntheticEmail(acc.username, storeCode);
    const existingUid = Object.keys(users).find((uid) => normalizeUsername(users[uid].username) === normalizeUsername(acc.username));
    if (remove) {
      if (!existingUid) { console.log(`- ${acc.username}: không có`); continue; }
      if (users[existingUid].isDemo !== true) { console.log(`- ${acc.username}: KHÔNG phải tài khoản mẫu (không có isDemo) → bỏ qua`); continue; }
      console.log(`- ${acc.username} (${acc.department}): sẽ gỡ`);
      if (apply) {
        await db.ref(`stores/${storeCode}/users/${existingUid}`).remove();
        await db.ref(`userIndex/${existingUid}/${storeCode}`).remove();
        await auth.deleteUser(existingUid).catch(() => {});
      }
      continue;
    }
    if (existingUid) { console.log(`- ${acc.username}: đã tồn tại → bỏ qua`); continue; }
    console.log(`- ${acc.username} (${acc.department}, ${acc.roleId}) → ${email}`);
    if (!apply) continue;
    const rec = await auth.createUser({ email, password, displayName: acc.fullName, disabled: false });
    try {
      await db.ref(`stores/${storeCode}/users/${rec.uid}`).set(buildProfile(acc, rec.uid, Date.now()));
      await db.ref(`userIndex/${rec.uid}/${storeCode}`).set(true);
    } catch (e) {
      await auth.deleteUser(rec.uid).catch(() => {});
      throw e;
    }
  }
  console.log(apply ? "Xong." : "Dry-run xong — thêm --apply để ghi thật.");
  process.exit(0);
}

main().catch((e) => { console.error("Lỗi:", e.message); process.exit(1); });
