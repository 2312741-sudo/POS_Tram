#!/usr/bin/env node
/**
 * Nhập topping / ghi chú mẫu cũ vào danh mục note & topping mới (docs/NOTE_CATALOG.md):
 *   stores/{s}/product_notes + topping hiện có  -->  note_groups / topping_groups + categories|products.{noteGroupIds,toppingGroupIds}
 *
 * An toàn:
 *  - Mặc định DRY-RUN: chỉ in kế hoạch. Chỉ ghi khi có --apply.
 *  - Sao lưu các node liên quan vào migration_output/ trước khi ghi.
 *  - Idempotent: nhóm đã có không bị ghi đè; trường gắn đã có (kể cả "không có") không bị đổi. Chạy lại an toàn.
 *  - Chỉ THÊM đường dẫn mới; không xóa/sửa dữ liệu khác.
 *
 * Dùng:  node migrate.js [--stores=TRAM01,TRAM02] [--service-account=file.json] [--apply]
 * (Dùng được với Database Emulator qua FIREBASE_DATABASE_EMULATOR_HOST.)
 */
const fs = require("fs");
const path = require("path");
const { planNoteCatalogMigration } = require("./plan");

const args = process.argv.slice(2);
const isApply = args.includes("--apply");
const arg = (p) => {
  const a = args.find((x) => x.startsWith(p));
  return a ? a.slice(p.length) : null;
};
const onlyStores = (arg("--stores=") || "").split(",").map((s) => s.trim().toUpperCase()).filter(Boolean);

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
  opts.databaseURL = arg("--database-url=") || process.env.DATABASE_URL || `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`;
  admin.initializeApp(opts);
  const db = admin.database();

  console.log(`POS Trạm - nhập danh mục note & topping | ${projectId} | ${opts.databaseURL} | ${isApply ? "APPLY (GHI THẬT)" : "DRY-RUN (không ghi)"}`);

  const stores = onlyStores.length ? onlyStores : Object.keys((await db.ref("stores").get({ shallow: true })).val() || {});
  const backup = {};
  let total = 0;
  for (const code of stores) {
    const read = async (n) => (await db.ref(`stores/${code}/${n}`).get()).val();
    const raw = {
      products: await read("products"),
      categories: await read("categories"),
      productNotes: await read("product_notes"),
      noteGroups: await read("note_groups"),
      toppingGroups: await read("topping_groups"),
    };
    const plan = planNoteCatalogMigration(raw);
    const n = Object.keys(plan.updates).length;
    console.log(`\n[${code}] ${n === 0 ? "không có gì để nhập" : `${n} đường dẫn sẽ ghi`}`);
    for (const line of plan.summary) console.log(`  - ${line}`);
    if (n === 0) continue;
    total += n;
    backup[code] = { categories: raw.categories, products: raw.products, note_groups: raw.noteGroups, topping_groups: raw.toppingGroups };
    if (isApply) {
      const dir = path.join(__dirname, "migration_output");
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `backup_${code}_${Date.now()}.json`), JSON.stringify(backup[code]));
      await db.ref(`stores/${code}`).update(plan.updates);
      console.log(`  Đã ghi ${n} đường dẫn.`);
    }
  }
  console.log(isApply ? `\nXong. Tổng ${total} đường dẫn.` : `\nDRY-RUN xong (${total} đường dẫn). Thêm --apply để ghi thật.`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
