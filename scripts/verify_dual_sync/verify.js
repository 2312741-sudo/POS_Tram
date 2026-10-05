#!/usr/bin/env node

/**
 * Script kiểm tra và so sánh đối chiếu dữ liệu giữa các nút gốc cũ và stores/{storeCode}.
 * CHỈ ĐỌC (READ-ONLY) - Tuyệt đối không thực hiện bất kỳ lệnh ghi nào.
 *
 * Cách chạy:
 *   1. Dùng file xuất database (Export JSON):
 *      node verify.js --file path/to/database_export.json [--store TRAM01]
 *
 *   2. Dùng Emulator (nếu đang bật emulator):
 *      FIREBASE_DATABASE_EMULATOR_HOST="127.0.0.1:9000" node verify.js [--store TRAM01]
 *
 *   3. Dùng Service Account (với database thật, chỉ đọc):
 *      GOOGLE_APPLICATION_CREDENTIALS="serviceAccount.json" node verify.js [--store TRAM01]
 */

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
let exportFilePath = null;
let targetStore = "TRAM01";

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--file" && args[i + 1]) {
    exportFilePath = args[i + 1];
    i++;
  } else if (args[i] === "--store" && args[i + 1]) {
    targetStore = args[i + 1];
    i++;
  }
}

const NODES_TO_CHECK = [
  { root: "tables", store: "tables", name: "Bàn (tables)" },
  { root: "products", store: "products", name: "Món ăn/sản phẩm (products)" },
  { root: "categories", store: "categories", name: "Danh mục (categories)" },
  { root: "zones", store: "zones", name: "Khu vực (zones)" },
  { root: "history", store: "bills", name: "Hóa đơn (history -> bills)" },
  { root: "audit_logs", store: "audit_logs", name: "Nhật ký hệ thống (audit_logs)" },
  { root: "users", store: "users", name: "Người dùng (users)" },
  { root: "kitchen_orders", store: "kitchen_orders", name: "Đơn bếp (kitchen_orders)" },
  { root: "online_orders", store: "online_orders", name: "Đơn online (online_orders)" },
];

function printTable(rows) {
  const colWidths = [30, 15, 18, 15, 20];
  const headers = ["Nút Dữ Liệu", "Số lượng Gốc", `Số lượng ${targetStore}`, "Chênh lệch", "Đánh giá"];

  const formatLine = (cols) =>
    cols.map((col, idx) => String(col !== undefined && col !== null ? col : "").padEnd(colWidths[idx])).join(" | ");

  const separator = colWidths.map((w) => "-".repeat(w)).join("-+-");

  console.log(formatLine(headers));
  console.log(separator);
  for (const row of rows) {
    console.log(formatLine(row));
  }
  console.log(separator);
}

function analyzeData(dbData) {
  console.log(`\n======================================================`);
  console.log(`BÁO CÁO ĐỐI CHIẾU DỮ LIỆU: Nút Gốc vs stores/${targetStore}`);
  console.log(`Thời gian: ${new Date().toISOString()}`);
  console.log(`======================================================\n`);

  const storeBranch = (dbData.stores && dbData.stores[targetStore]) || {};
  const reportRows = [];
  const detailedMismatches = [];

  for (const item of NODES_TO_CHECK) {
    const rootData = dbData[item.root] || {};
    let storeData = storeBranch[item.store] || {};

    // Fallback nếu hóa đơn trong store lưu ở history thay vì bills
    if (item.store === "bills" && (!storeBranch.bills || Object.keys(storeBranch.bills).length === 0)) {
      if (storeBranch.history) {
        storeData = storeBranch.history;
      }
    }

    const rootKeys = typeof rootData === "object" ? Object.keys(rootData) : [];
    const storeKeys = typeof storeData === "object" ? Object.keys(storeData) : [];

    const rootCount = rootKeys.length;
    const storeCount = storeKeys.length;
    const diff = storeCount - rootCount;

    let status = "Khớp số lượng";
    if (rootCount === 0 && storeCount === 0) {
      status = "Không có dữ liệu";
    } else if (diff === 0) {
      status = "Đồng bộ hoàn toàn";
    } else if (storeCount > rootCount) {
      status = `stores nhiều hơn (+${diff})`;
    } else {
      status = `gốc nhiều hơn (${diff})`;
    }

    reportRows.push([
      item.name,
      rootCount,
      storeCount,
      diff > 0 ? `+${diff}` : `${diff}`,
      status,
    ]);

    // Tìm các key chỉ có ở 1 bên (giới hạn tối đa 5 mẫu ví dụ)
    const onlyInRoot = rootKeys.filter((k) => !storeKeys.includes(k));
    const onlyInStore = storeKeys.filter((k) => !rootKeys.includes(k));

    if (onlyInRoot.length > 0 || onlyInStore.length > 0) {
      detailedMismatches.push({
        node: item.name,
        onlyInRootCount: onlyInRoot.length,
        onlyInRootSample: onlyInRoot.slice(0, 5),
        onlyInStoreCount: onlyInStore.length,
        onlyInStoreSample: onlyInStore.slice(0, 5),
      });
    }
  }

  printTable(reportRows);

  if (detailedMismatches.length > 0) {
    console.log(`\nCHI TIẾT MẪU KHÓA (KEYS) LỆCH NHAU:`);
    for (const m of detailedMismatches) {
      console.log(`\n- ${m.node}:`);
      if (m.onlyInRootCount > 0) {
        console.log(`  * Chỉ có ở nút gốc (${m.onlyInRootCount}): ${m.onlyInRootSample.join(", ")}${m.onlyInRootCount > 5 ? "..." : ""}`);
      }
      if (m.onlyInStoreCount > 0) {
        console.log(`  * Chỉ có ở stores/${targetStore} (${m.onlyInStoreCount}): ${m.onlyInStoreSample.join(", ")}${m.onlyInStoreCount > 5 ? "..." : ""}`);
      }
    }
  } else {
    console.log(`\nToàn bộ danh sách khóa dữ liệu giữa nút gốc và stores/${targetStore} trùng khớp 100%!`);
  }

  console.log(`\nKẾT LUẬN & KHUYẾN NGHỊ:`);
  console.log(`- Nếu stores/${targetStore} đã có đầy đủ hoặc nhiều hơn nút gốc: An toàn để cắt hoàn toàn dual-sync ghi vào nút gốc.`);
  console.log(`- Dữ liệu lịch sử cũ ở nút gốc có thể lưu trữ dự phòng (backup) trước khi tắt quyền ghi.\n`);
}

async function run() {
  if (exportFilePath) {
    const fullPath = path.resolve(process.cwd(), exportFilePath);
    console.log(`Đang đọc file export: ${fullPath}...`);
    if (!fs.existsSync(fullPath)) {
      console.error(`Lỗi: Không tìm thấy file "${fullPath}"`);
      process.exit(1);
    }
    try {
      const content = fs.readFileSync(fullPath, "utf8");
      const dbData = JSON.parse(content);
      analyzeData(dbData);
    } catch (err) {
      console.error(`Lỗi phân tích cú pháp JSON:`, err.message);
      process.exit(1);
    }
    return;
  }

  // Kết nối Firebase Admin SDK
  try {
    const admin = require("firebase-admin");
    if (!admin.apps.length) {
      admin.initializeApp({
        databaseURL:
          process.env.DATABASE_URL ||
          "https://tramapp-36f53-default-rtdb.asia-southeast1.firebasedatabase.app",
      });
    }
    const db = admin.database();
    console.log(`Đang kết nối Realtime Database để kiểm tra dữ liệu...`);

    const snapshot = await db.ref("/").once("value");
    const dbData = snapshot.val() || {};
    analyzeData(dbData);
    process.exit(0);
  } catch (err) {
    console.error(`Lỗi khi đọc Realtime Database:`, err.message);
    console.log(`\nGợi ý: Bạn có thể chạy với file sao lưu JSON qua tham số:`);
    console.log(`  node verify.js --file path/to/database_export.json\n`);
    process.exit(1);
  }
}

run();
