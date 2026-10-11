#!/usr/bin/env node
/**
 * Gộp điểm khách hàng của MỌI chi nhánh thành một bản ghi dùng chung:
 *   stores/{s}/customers/{id}  --(cùng SĐT chuẩn hóa)-->  loyalty_members/{SĐT}  (+ loyalty_ledger số dư đầu kỳ)
 *
 * An toàn:
 *  - Mặc định DRY-RUN: chỉ in báo cáo. Chỉ ghi khi có --apply.
 *  - Sao lưu toàn bộ node khách các chi nhánh vào migration_output/ trước khi ghi.
 *  - Idempotent: marker loyalty_migration/shared_v1; có marker thì dừng (trừ khi --force, khi đó bản ghi loyalty_members
 *    đã tồn tại luôn được BỎ QUA, không bao giờ ghi đè).
 *  - Không xóa/sửa dữ liệu khác của node khách (chỉ cập nhật 3 trường điểm = cache của số dư chung).
 *  - Khách không có SĐT hợp lệ: KHÔNG gộp, mỗi người một bản ghi cục bộ L_{chi nhánh}_{mã khách}.
 *  - Kiểm tra cuối: tổng điểm các chi nhánh trước == tổng điểm loyalty_members sau.
 *
 * Chạy khi cửa hàng đóng cửa, TRƯỚC khi deploy rules/functions/app mới (xem docs/RULES_NOTES.md §3c).
 */
const fs = require("fs");
const path = require("path");
const { readSource, planMigration, buildWrites } = require("./plan");

const args = process.argv.slice(2);
const isApply = args.includes("--apply");
const force = args.includes("--force");
const arg = (p) => {
  const a = args.find((x) => x.startsWith(p));
  return a ? a.slice(p.length) : null;
};
const onlyStores = (arg("--stores=") || "").split(",").map((s) => s.trim()).filter(Boolean);
const MARKER = "loyalty_migration/shared_v1";

function findKey() {
  const explicit = arg("--service-account=");
  if (explicit && fs.existsSync(explicit)) return path.resolve(explicit);
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) return path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS);
  for (const dir of [__dirname, path.resolve(__dirname, "../.."), process.cwd()]) {
    const f = fs.readdirSync(dir).find((n) => (n.startsWith("service-account") || n.includes("firebase-adminsdk")) && n.endsWith(".json"));
    if (f) return path.join(dir, f);
  }
  return null;
}

function report(plan, header) {
  console.log(header);
  const t = plan.totals;
  console.log(`  Nhóm gộp theo SĐT:           ${plan.groups.length} (trong đó trùng SĐT >= 2 node: ${plan.groups.filter((g) => g.duplicate).length})`);
  console.log(`  Khách KHÔNG có SĐT hợp lệ:   ${plan.localOnly.length} (giữ riêng theo chi nhánh, không gộp)`);
  console.log(`  Tổng điểm hiện tại:          chi nhánh ${t.branchPoints}  ->  dùng chung ${t.sharedPoints}  ${t.branchPoints === t.sharedPoints ? "OK" : "LỆCH!"}`);
  console.log(`  Tổng điểm tích lũy (hạng):   chi nhánh ${t.branchTotalPoints}  ->  dùng chung ${t.sharedTotalPoints}  ${t.branchTotalPoints === t.sharedTotalPoints ? "OK" : "LỆCH!"}`);
  for (const g of plan.groups.filter((x) => x.duplicate).slice(0, 30)) {
    console.log(`    * ${g.memberKey}: ${g.sources.map((s) => `${s.storeCode}/${s.customerId}=${s.points}`).join(" + ")} = ${g.points}`);
  }
  for (const g of plan.localOnly.slice(0, 30)) console.log(`    - không SĐT: ${g.memberKey} (${g.name || "?"}) ${g.points} điểm`);
}

async function main() {
  const keyPath = findKey();
  const emulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST);
  if (!keyPath && !emulator) {
    console.log("Chưa có service account. Dùng --service-account=<file.json> hoặc GOOGLE_APPLICATION_CREDENTIALS. (Không làm gì.)");
    return;
  }
  const admin = require("firebase-admin");
  let projectId = "tramapp-36f53";
  const opts = {};
  if (keyPath) {
    const sa = JSON.parse(fs.readFileSync(keyPath, "utf8"));
    projectId = sa.project_id || projectId;
    opts.credential = admin.credential.cert(sa);
  } else opts.projectId = "demo-tram-pos";
  const databaseURL = arg("--database-url=") || process.env.DATABASE_URL || `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`;
  opts.databaseURL = databaseURL;
  admin.initializeApp(opts);
  const db = admin.database();

  console.log(`POS Trạm - gộp điểm dùng chung | ${projectId} | ${databaseURL} | ${isApply ? "APPLY (GHI THẬT)" : "DRY-RUN (không ghi)"}`);

  const marker = (await db.ref(MARKER).get()).val();
  if (marker && !force) {
    console.log(`Đã di trú trước đó (${JSON.stringify(marker)}). Dừng. Dùng --force để chạy bù (bản ghi đã có luôn được giữ nguyên).`);
    return;
  }

  // Danh sách chi nhánh: REST shallow để không tải toàn bộ stores/
  const token = (await admin.app().options.credential.getAccessToken()).access_token;
  const shallow = await (await fetch(`${databaseURL}/stores.json?shallow=true&access_token=${token}`)).json();
  let stores = Object.keys(shallow || {});
  if (onlyStores.length) stores = stores.filter((s) => onlyStores.includes(s));
  console.log(`Chi nhánh (${stores.length}): ${stores.join(", ")}`);

  const raw = {};
  const sources = [];
  for (const s of stores) {
    const v = (await db.ref(`stores/${s}/customers`).get()).val() || {};
    raw[s] = v;
    for (const [id, node] of Object.entries(v)) {
      const src = readSource(s, id, node);
      if (src) sources.push(src);
    }
  }
  const plan = planMigration(sources);
  report(plan, `\nKế hoạch (${sources.length} node khách):`);
  if (plan.totals.branchPoints !== plan.totals.sharedPoints || plan.totals.branchTotalPoints !== plan.totals.sharedTotalPoints) {
    console.log("TỔNG KHÔNG KHỚP - dừng, cần kiểm tra thủ công.");
    process.exitCode = 1;
    return;
  }
  if (!isApply) {
    console.log("\nDry-run xong. Thêm --apply để ghi.");
    return;
  }

  const outDir = path.resolve(__dirname, "../../migration_output");
  fs.mkdirSync(outDir, { recursive: true });
  const backup = path.join(outDir, `backup_branch_customers_${Date.now()}.json`);
  fs.writeFileSync(backup, JSON.stringify(raw));
  console.log(`\nĐã sao lưu node khách các chi nhánh: ${backup}`);

  const existing = (await (await fetch(`${databaseURL}/loyalty_members.json?shallow=true&access_token=${token}`)).json()) || {};
  const now = Date.now();
  let created = 0;
  let skipped = 0;
  const sharedSum = { points: 0, total: 0 };
  for (const g of plan.groups.concat(plan.localOnly)) {
    if (existing[g.memberKey]) {
      skipped++;
      console.log(`  bỏ qua (đã có bản ghi dùng chung): ${g.memberKey}`);
      continue;
    }
    await db.ref().update(buildWrites(g, now, "migration"));
    created++;
  }
  await db.ref(MARKER).set({ at: now, by: "migrate_shared_loyalty", groups: plan.groups.length, local: plan.localOnly.length, points: plan.totals.sharedPoints });

  // Kiểm tra sau ghi: tổng điểm loyalty_members == tổng điểm chi nhánh trước đó
  const members = (await db.ref("loyalty_members").get()).val() || {};
  for (const m of Object.values(members)) {
    sharedSum.points += Number(m.points) || 0;
    sharedSum.total += Number(m.totalPoints) || 0;
  }
  console.log(`\nĐã tạo ${created} bản ghi, bỏ qua ${skipped}.`);
  console.log(`KIỂM TRA: điểm chi nhánh trước = ${plan.totals.branchPoints}, điểm dùng chung sau = ${sharedSum.points} -> ${plan.totals.branchPoints === sharedSum.points ? "KHỚP" : "LỆCH (có bản ghi cũ trước đó hoặc đã bỏ qua)"}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
