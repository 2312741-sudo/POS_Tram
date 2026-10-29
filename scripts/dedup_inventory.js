// scripts/dedup_inventory.js
const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

async function deduplicateBranch(branch) {
  console.log(`\n========================================`);
  console.log(`  Bắt đầu xử lý dọn dẹp kho: ${branch}`);
  console.log(`========================================`);

  const raw = execSync(`firebase database:get /stores/${branch}/catalog_items`, {
    maxBuffer: 50 * 1024 * 1024,
  }).toString();

  const items = JSON.parse(raw);
  if (!items) {
    console.log(`${branch}: Không tìm thấy danh mục hàng hóa nào.`);
    return;
  }

  const bySku = new Map();
  for (const [id, item] of Object.entries(items)) {
    const key =
      (item.sku || "").trim().toUpperCase() ||
      (item.name || "").trim().toLowerCase();
    if (!bySku.has(key)) bySku.set(key, []);
    bySku.get(key).push({ id, ...item });
  }

  const toDelete = [];
  const keptItems = [];

  for (const [key, list] of bySku.entries()) {
    if (list.length > 1) {
      // Sắp xếp: Ưu tiên bản ghi có updatedAt mới nhất / createdAt mới nhất
      list.sort(
        (a, b) =>
          (b.updatedAt || b.createdAt || 0) - (a.updatedAt || a.createdAt || 0)
      );
      const keep = list[0];
      const dups = list.slice(1);
      keptItems.push(keep);
      dups.forEach((d) => toDelete.push(d.id));
    } else {
      keptItems.push(list[0]);
    }
  }

  console.log(
    `${branch}: Tổng số bản ghi ban đầu = ${Object.keys(items).length}`
  );
  console.log(`${branch}: Số mặt hàng duy nhất = ${bySku.size}`);
  console.log(`${branch}: Số bản ghi dư thừa cần xóa = ${toDelete.length}`);

  if (toDelete.length === 0) {
    console.log(`${branch}: Không có hàng trùng lặp.`);
    return;
  }

  // Chia nhỏ thành các batch 50 items và dùng file JSON tạm để tránh vượt quá giới hạn CLI argument
  const batchSize = 50;
  const tmpFile = path.join(__dirname, `tmp_dedup_${branch}.json`);

  for (let i = 0; i < toDelete.length; i += batchSize) {
    const chunk = toDelete.slice(i, i + batchSize);
    const updateObj = {};
    for (const id of chunk) {
      updateObj[id] = null;
    }
    fs.writeFileSync(tmpFile, JSON.stringify(updateObj));

    execSync(
      `firebase database:update /stores/${branch}/catalog_items "${tmpFile}" -f`
    );
    console.log(
      `${branch}: Đã xóa thành công ${Math.min(
        i + batchSize,
        toDelete.length
      )}/${toDelete.length} mục trùng...`
    );
  }

  if (fs.existsSync(tmpFile)) {
    fs.unlinkSync(tmpFile);
  }

  console.log(`✅ ${branch}: Hoàn tất dọn dẹp hàng trùng! Còn lại đúng ${bySku.size} mặt hàng.`);
}

async function main() {
  const branches = ["TRAM01", "TRAM02", "TRAM03", "TRAM04"];
  for (const branch of branches) {
    await deduplicateBranch(branch);
  }
}

main().catch((err) => {
  console.error("Lỗi:", err);
  process.exit(1);
});
