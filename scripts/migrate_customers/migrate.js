#!/usr/bin/env node

/**
 * Script di chuyển khách hàng tích điểm từ node gốc /kmt_customers
 * sang nhánh multi-tenant: stores/{storeCode}/customers
 *
 * Tính chất an toàn:
 * - Mặc định chạy thử (dry-run). Chỉ ghi khi có cờ --apply.
 * - Tự động sao lưu JSON trước khi ghi vào thư mục migration_output/ (đã được .gitignore).
 * - Hoàn toàn lũy kế / idempotent: kiểm tra key đã tồn tại, không tạo trùng hay ghi đè sai lệch.
 * - Không bao giờ xóa node gốc /kmt_customers.
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

// -----------------------------------------------------------------------------
// 1. Phân tích tham số dòng lệnh
// -----------------------------------------------------------------------------
const args = process.argv.slice(2);
const isApply = args.includes("--apply");
const isDryRun = !isApply;

function getArgValue(prefix) {
  const arg = args.find((a) => a.startsWith(prefix));
  return arg ? arg.split("=")[1] : null;
}

const customStore = getArgValue("--store=") || "TRAM01";
const customSaPath = getArgValue("--service-account=");
const customDbUrl = getArgValue("--database-url=");

// Thư mục lưu trữ bản sao lưu
const outputDir = path.resolve(__dirname, "../../migration_output");
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

// -----------------------------------------------------------------------------
// 2. Nạp Service Account Key & Khởi tạo Admin SDK
// -----------------------------------------------------------------------------
function findServiceAccountKey() {
  if (customSaPath && fs.existsSync(customSaPath)) {
    return path.resolve(customSaPath);
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS && fs.existsSync(process.env.GOOGLE_APPLICATION_CREDENTIALS)) {
    return path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS);
  }

  const searchDirs = [
    path.resolve(__dirname),
    path.resolve(__dirname, "../.."),
    process.cwd(),
  ];

  for (const dir of searchDirs) {
    if (!fs.existsSync(dir)) continue;
    const files = fs.readdirSync(dir);
    const saFile = files.find(
      (f) => (f.startsWith("service-account") || f.includes("firebase-adminsdk")) && f.endsWith(".json")
    );
    if (saFile) {
      return path.join(dir, saFile);
    }
  }

  return null;
}

const isEmulator = Boolean(process.env.FIREBASE_DATABASE_EMULATOR_HOST);
const saKeyPath = findServiceAccountKey();

if (!saKeyPath && !isEmulator) {
  console.log("================================================================================");
  console.log(`🛡️  POS TRẠM - SCRIPT MIGRATE KHÁCH HÀNG CRM (DRY-RUN / HƯỚNG DẪN)`);
  console.log(`Chế độ: ${isApply ? "⚠️  --apply" : "🛡️  DRY-RUN (Mặc định)"}`);
  console.log("================================================================================");
  console.log("ℹ️  CHƯA PHÁT HIỆN SERVICE ACCOUNT KEY.");
  console.log("   Để kết nối database (chạy thử hoặc áp dụng), cung cấp khóa theo 1 trong các cách:");
  console.log("   1. Tải key từ Firebase Console (tramapp-36f53 -> Project settings -> Service accounts -> Generate new private key)");
  console.log("   2. Lưu file với tên 'service-account.json' ở thư mục gốc repo");
  console.log("   3. Hoặc truyền cờ: node migrate.js --service-account=path/to/key.json");
  console.log("   4. Hoặc xuất biến môi trường: export GOOGLE_APPLICATION_CREDENTIALS=path/to/key.json");
  console.log("\n✅ Cú pháp và tệp script đã sẵn sàng, an toàn 100%.");
  process.exit(0);
}

let projectId = "tramapp-36f53";
let appOptions = {};

if (saKeyPath) {
  const serviceAccount = JSON.parse(fs.readFileSync(saKeyPath, "utf-8"));
  projectId = serviceAccount.project_id || projectId;
  appOptions.credential = admin.credential.cert(serviceAccount);
} else if (isEmulator) {
  appOptions.projectId = "demo-tram-pos";
}

const databaseURL =
  customDbUrl ||
  process.env.DATABASE_URL ||
  `https://${projectId}-default-rtdb.asia-southeast1.firebasedatabase.app`;

appOptions.databaseURL = databaseURL;

admin.initializeApp(appOptions);
const db = admin.database();

// -----------------------------------------------------------------------------
// 3. Tiến trình Di chuyển
// -----------------------------------------------------------------------------
async function runMigration() {
  console.log("================================================================================");
  console.log(`🚀 POS TRẠM - SCRIPT MIGRATE KHÁCH HÀNG CRM: /kmt_customers -> stores/${customStore}/customers`);
  console.log(`Dự án Firebase:  ${projectId}`);
  console.log(`Database URL:    ${databaseURL}`);
  console.log(`Chi nhánh đích:  ${customStore}`);
  console.log(`Chế độ:          ${isApply ? "⚠️  --apply (GHI DỮ LIỆU THẬT)" : "🛡️  DRY-RUN (CHỈ KIỂM TRA, KHÔNG GHI)"}`);
  console.log("================================================================================\n");

  // 1. Đọc node gốc /kmt_customers
  console.log(`[1/4] Đọc dữ liệu từ /kmt_customers...`);
  const sourceSnap = await db.ref("kmt_customers").get();

  if (!sourceSnap.exists() || !sourceSnap.val()) {
    console.log(`[THÔNG BÁO] Node /kmt_customers trống hoặc không tồn tại. Không có dữ liệu cần migrate.`);
    return;
  }

  const sourceData = sourceSnap.val();
  const sourceKeys = Object.keys(sourceData);
  console.log(`      Tìm thấy ${sourceKeys.length} khách hàng trong /kmt_customers.`);

  // 2. Đọc dữ liệu hiện tại trong stores/{customStore}/customers để bảo đảm tính lũy kế
  console.log(`[2/4] Kiểm tra dữ liệu hiện tại tại stores/${customStore}/customers...`);
  const targetSnap = await db.ref(`stores/${customStore}/customers`).get();
  const existingTargetData = targetSnap.exists() ? targetSnap.val() : {};
  const existingTargetKeys = Object.keys(existingTargetData);
  console.log(`      Đã có ${existingTargetKeys.length} khách hàng trong stores/${customStore}/customers.`);

  // 3. Chuẩn bị danh sách bản ghi cần migrate
  console.log(`[3/4] So khớp và lập kế hoạch copy...`);
  const toInsert = [];
  const alreadySynced = [];

  for (const key of sourceKeys) {
    const rawCustomer = sourceData[key];
    if (!rawCustomer || typeof rawCustomer !== "object") continue;

    const normalizedCustomer = {
      ...rawCustomer,
      id: rawCustomer.id || key,
      storeCode: rawCustomer.storeCode || customStore,
      updatedAt: rawCustomer.updatedAt || Date.now(),
    };

    if (existingTargetData[key]) {
      alreadySynced.push({ key, name: normalizedCustomer.name || "N/A" });
    } else {
      toInsert.push({ key, data: normalizedCustomer });
    }
  }

  console.log(`      - Đã tồn tại (bỏ qua): ${alreadySynced.length}`);
  console.log(`      - Cần copy mới:        ${toInsert.length}`);

  // 4. Sao lưu dữ liệu JSON trước khi ghi
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupFilePath = path.join(outputDir, `backup_customers_${timestamp}.json`);

  const backupData = {
    exportedAt: new Date().toISOString(),
    sourceNode: "/kmt_customers",
    targetStore: customStore,
    sourceTotal: sourceKeys.length,
    sourceRecords: sourceData,
    targetExistingTotal: existingTargetKeys.length,
    targetExistingRecords: existingTargetData,
  };

  fs.writeFileSync(backupFilePath, JSON.stringify(backupData, null, 2), "utf8");
  console.log(`\n[SAO LƯU] Đã xuất bản sao lưu trước khi migrate tại:`);
  console.log(`          ${backupFilePath}`);

  // 5. Ghi dữ liệu nếu có cờ --apply
  if (isDryRun) {
    console.log(`\n================================================================================`);
    console.log(`[DRY-RUN TỔNG KẾT]`);
    console.log(`  Số khách hàng dự kiến copy: ${toInsert.length}`);
    console.log(`  Số khách hàng đã có sẵn:    ${alreadySynced.length}`);
    console.log(`  KHÔNG CÓ DỮ LIỆU NÀO ĐƯỢC GHI TRONG CHẾ ĐỘ CHẠY THỬ.`);
    console.log(`  Để thực hiện ghi vào database, chạy lại với:`);
    console.log(`    node migrate.js --apply --store=${customStore}`);
    console.log(`================================================================================\n`);
    return;
  }

  console.log(`\n[4/4] Bắt đầu ghi ${toInsert.length} khách hàng vào stores/${customStore}/customers...`);
  let successCount = 0;
  let failCount = 0;

  for (const item of toInsert) {
    try {
      await db.ref(`stores/${customStore}/customers/${item.key}`).set(item.data);
      successCount++;
    } catch (err) {
      console.error(`      [THẤT BẠI] Key ${item.key}: ${err.message}`);
      failCount++;
    }
  }

  console.log(`\n================================================================================`);
  console.log(`[HOÀN TẤT MIGRATE KHÁCH HÀNG]`);
  console.log(`  Thành công:  ${successCount}/${toInsert.length}`);
  console.log(`  Thất bại:   ${failCount}`);
  console.log(`  Đã tồn tại:  ${alreadySynced.length}`);
  console.log(`  Node gốc /kmt_customers: NGUYÊN VẸN (Không bị xóa)`);
  console.log(`  Bản sao lưu: ${backupFilePath}`);
  console.log(`================================================================================\n`);
}

runMigration()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(`[FATAL] Ngoại lệ không xác định: ${err.message}`);
    process.exit(1);
  });
