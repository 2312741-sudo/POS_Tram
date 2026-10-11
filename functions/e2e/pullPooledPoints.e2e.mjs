// E2E pullPooledPoints trên emulator (Functions + Database + Auth). Chạy từ thư mục gốc repo:
//   printf "WEB_API_KEY=test\n" > functions/.env.local
//   DATABASE_URL=https://demo-tram-pos-default-rtdb.firebaseio.com firebase emulators:exec --config firebase.json --only functions,database,auth --project demo-tram-pos "node functions/e2e/pullPooledPoints.e2e.mjs"
//   rm functions/.env.local
import { createRequire } from "module";
const require = createRequire(new URL("../", import.meta.url).pathname);
const admin = require("firebase-admin");
const PROJECT = "demo-tram-pos";
admin.initializeApp({ projectId: PROJECT, databaseURL: `http://127.0.0.1:9000/?ns=demo-tram-pos-default-rtdb` });
const db = admin.database();
const auth = admin.auth();
const fn = "http://127.0.0.1:5001/" + PROJECT + "/asia-southeast1/pullPooledPoints";

let fails = 0;
const ok = (c, m) => { console.log((c ? "PASS " : "FAIL ") + m); if (!c) fails++; };
const val = async (p) => (await db.ref(p).get()).val();

async function user(uid, store, roleId) {
  await auth.createUser({ uid, email: `${uid}@tram.local`, password: "secret123" });
  await db.ref(`stores/${store}/users/${uid}`).set({ username: uid, fullName: uid, roleId, isActive: true });
  await db.ref(`userIndex/${uid}/${store}`).set(true);
  const r = await fetch(`http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=x`, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: `${uid}@tram.local`, password: "secret123", returnSecureToken: true }),
  });
  return (await r.json()).idToken;
}
async function call(token, data) {
  const r = await fetch(fn, { method: "POST", headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify({ data }) });
  return { status: r.status, body: await r.json() };
}
const cust = (id, pts, total, phone = "0912345678") => ({ id, ho_ten: "An", so_dien_thoai: phone, diem_hien_tai: pts, currentPoints: pts, totalPoints: total });

const cashier = await user("cashierA", "AAA", "ROLE_CASHIER");
const waiter = await user("waiterA", "AAA", "waiter");
for (const s of ["AAA", "BBB", "CCC"]) await db.ref(`stores/${s}/storeInfo`).set({ storeName: s });
await db.ref("stores/AAA/storeInfo/sharedLoyalty").set({ enabled: true, deductOrder: "HOME_FIRST", storeCodes: ["AAA", "BBB", "CCC"] });
await db.ref("stores/AAA/customers/a1").set(cust("a1", 20, 100));
await db.ref("stores/BBB/customers/b1").set(cust("b1", 80, 500));
await db.ref("stores/CCC/customers/c1").set(cust("c1", 30, 60));
await db.ref("stores/CCC/customers/other").set(cust("other", 999, 999, "0999999999"));

let r = await call(null, { storeCode: "AAA", customerId: "a1", billId: "x", points: 5 });
ok(r.status === 401, "không đăng nhập bị từ chối (" + r.status + ")");
r = await call(waiter, { storeCode: "AAA", customerId: "a1", billId: "x", points: 5 });
ok(r.status === 403, "phục vụ bị từ chối (" + r.status + ")");

r = await call(cashier, { storeCode: "AAA", customerId: "a1", balanceOnly: true });
ok(r.body.result?.othersPoints === 110, "tra số dư chi nhánh khác = 110 (" + JSON.stringify(r.body) + ")");

r = await call(cashier, { storeCode: "AAA", customerId: "a1", billId: "BILL1", points: 100 });
ok(r.body.result?.pulled === 100 && r.body.result?.alreadyApplied === false, "kéo 100 điểm: " + JSON.stringify(r.body));
ok((await val("stores/AAA/customers/a1/diem_hien_tai")) === 120, "chi nhánh bán: 20 → 120");
ok((await val("stores/AAA/customers/a1/totalPoints")) === 100, "totalPoints chi nhánh bán không đổi");
ok((await val("stores/BBB/customers/b1/diem_hien_tai")) === 0, "BBB bị trừ hết 80 → 0");
ok((await val("stores/CCC/customers/c1/diem_hien_tai")) === 10, "CCC bị trừ 20 → 10");
ok((await val("stores/CCC/customers/other/diem_hien_tai")) === 999, "khách khác SĐT không bị đụng");
ok((await val("stores/BBB/customers/b1/totalPoints")) === 500, "totalPoints chi nhánh nguồn không đổi");
ok((await val("stores/AAA/point_history/pull_BILL1"))?.type === "POOL_TRANSFER", "có lịch sử POOL_TRANSFER");

r = await call(cashier, { storeCode: "AAA", customerId: "a1", billId: "BILL1", points: 100 });
ok(r.body.result?.alreadyApplied === true && (await val("stores/AAA/customers/a1/diem_hien_tai")) === 120, "gọi lại cùng hóa đơn không kéo thêm (idempotent)");

r = await call(cashier, { storeCode: "AAA", customerId: "a1", billId: "BILL2", points: 50 });
ok(r.status === 400 || r.status === 412 || r.body.error, "không đủ điểm bị từ chối: " + JSON.stringify(r.body.error?.status));
ok((await val("stores/AAA/customers/a1/diem_hien_tai")) === 120 && (await val("stores/CCC/customers/c1/diem_hien_tai")) === 10, "từ chối thì số dư không đổi");

await db.ref("stores/AAA/storeInfo/sharedLoyalty/enabled").set(false);
r = await call(cashier, { storeCode: "AAA", customerId: "a1", billId: "BILL3", points: 1 });
ok(r.body.error?.status === "FAILED_PRECONDITION", "chưa bật dùng chung bị từ chối: " + r.body.error?.status);

console.log(fails === 0 ? "ALL PASS" : fails + " FAILED");
process.exit(fails === 0 ? 0 : 1);
