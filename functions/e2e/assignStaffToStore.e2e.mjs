// E2E assignStaffToStore + khóa theo cửa hàng trên emulator. Chạy từ thư mục gốc repo:
//   printf "WEB_API_KEY=test\n" > functions/.env.local
//   DATABASE_URL=https://demo-tram-pos-default-rtdb.firebaseio.com firebase emulators:exec --config firebase.json --only functions,database,auth --project demo-tram-pos "node functions/e2e/assignStaffToStore.e2e.mjs"
//   rm functions/.env.local
import { createRequire } from "module";
const require = createRequire(new URL("../", import.meta.url).pathname);
const admin = require("firebase-admin");
const PROJECT = "demo-tram-pos";
admin.initializeApp({ projectId: PROJECT, databaseURL: `http://127.0.0.1:9000/?ns=demo-tram-pos-default-rtdb` });
const db = admin.database();
const auth = admin.auth();
const url = (fn) => `http://127.0.0.1:5001/${PROJECT}/asia-southeast1/${fn}`;
let fails = 0;
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) fails++; };
const val = async (p) => (await db.ref(p).get()).val();

async function user(uid, store, roleId, extra = {}) {
  await auth.createUser({ uid, email: `${uid}@tram.local`, password: "secret123" });
  await db.ref(`stores/${store}/users/${uid}`).set({ uid, username: uid, fullName: uid, roleId, isActive: true, ...extra });
  await db.ref(`userIndex/${uid}/${store}`).set(true);
  const r = await fetch(`http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=x`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: `${uid}@tram.local`, password: "secret123", returnSecureToken: true }),
  });
  return (await r.json()).idToken;
}
async function call(fn, token, data) {
  const r = await fetch(url(fn), { method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  return { status: r.status, body: await r.json() };
}

for (const s of ["AAA", "BBB"]) await db.ref(`stores/${s}/storeInfo`).set({ storeName: s });
const owner = await user("ownerX", "AAA", "ROLE_OWNER");
await db.ref("stores/BBB/users/ownerX").set({ uid: "ownerX", username: "ownerX", fullName: "Chu", roleId: "ROLE_OWNER", isActive: true });
await db.ref("userIndex/ownerX/BBB").set(true);
const mgr = await user("mgrA", "AAA", "ROLE_MANAGER");
await user("staffA", "AAA", "ROLE_STAFF", { phone: "0900", customPermissions: ["MANAGE_USERS"] });

const base = { sourceStoreCode: "AAA", targetStoreCode: "BBB", targetUid: "staffA", roleId: "ROLE_MANAGER" };
let r = await call("assignStaffToStore", null, base);
ok(r.status === 401, "chưa đăng nhập bị từ chối");
r = await call("assignStaffToStore", mgr, base);
ok(r.status === 403, "Quản lý không được gán (" + r.status + ")");
r = await call("assignStaffToStore", owner, { ...base, roleId: "ROLE_OWNER" });
ok(r.status === 400, "không gán vai trò Chủ (" + r.status + ")");
r = await call("assignStaffToStore", owner, { ...base, targetStoreCode: "AAA" });
ok(r.status === 400, "đích phải khác nguồn");
r = await call("assignStaffToStore", owner, base);
ok(r.body.result?.success === true, "Chủ gán thành công: " + JSON.stringify(r.body));
const p = await val("stores/BBB/users/staffA");
ok(p?.roleId === "ROLE_MANAGER" && p.username === "staffA" && p.isActive === true, "hồ sơ ở BBB có vai trò riêng ROLE_MANAGER");
ok((await val("stores/AAA/users/staffA")).roleId === "ROLE_STAFF", "vai trò ở AAA không đổi (ROLE_STAFF)");
ok(Array.isArray(p?.customPermissions) ? p.customPermissions.length === 0 : !p?.customPermissions, "quyền riêng không sao chép sang BBB");
ok((await val("userIndex/staffA/BBB")) === true, "userIndex BBB = true");
r = await call("assignStaffToStore", owner, base);
ok(r.body.error?.status === "ALREADY_EXISTS", "gán lần hai bị từ chối (đã có hồ sơ)");

// khóa ở BBB không khóa tài khoản đăng nhập (vì thuộc 2 cửa hàng)
r = await call("setStaffDisabled", owner, { storeCode: "BBB", targetUid: "staffA", disabled: true });
ok(r.body.result?.success === true, "khóa staffA ở BBB: " + JSON.stringify(r.body));
ok((await val("stores/BBB/users/staffA/isActive")) === false, "BBB: isActive=false");
ok((await val("stores/AAA/users/staffA/isActive")) === true, "AAA: vẫn hoạt động");
ok((await auth.getUser("staffA")).disabled === false, "tài khoản đăng nhập (Auth) vẫn bật");

// nhân viên chỉ 1 cửa hàng: khóa thì khóa luôn Auth
await user("soloA", "AAA", "ROLE_STAFF");
r = await call("setStaffDisabled", owner, { storeCode: "AAA", targetUid: "soloA", disabled: true });
ok((await auth.getUser("soloA")).disabled === true, "nhân viên 1 cửa hàng: khóa Auth như cũ");

console.log(fails === 0 ? "ALL PASS" : fails + " FAILED");
process.exit(fails === 0 ? 0 : 1);
