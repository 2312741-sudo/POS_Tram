"use strict";
/**
 * Logic THUẦN gom khách các chi nhánh theo SĐT (bản sao có chủ đích của planMigration trong
 * functions/src/sharedLoyalty.ts - functions/src/migrationParity.test.ts kiểm tra hai bản cho kết quả giống nhau).
 */

function normalizePhone(raw) {
  let p = String(raw == null ? "" : raw).replace(/[\s.\-()]/g, "");
  if (p.startsWith("+84")) p = "0" + p.slice(3);
  else if (p.startsWith("84") && p.length === 11) p = "0" + p.slice(2);
  return /^0\d{9}$/.test(p) ? p : null;
}

function sanitizeKey(s) {
  return String(s).replace(/[.#$[\]/\u0000-\u001f\u007f\s]/g, "_");
}

function memberKeyFor(phoneRaw, storeCode, customerId) {
  return normalizePhone(phoneRaw) || `L_${sanitizeKey(storeCode)}_${sanitizeKey(customerId)}`;
}

function num(v) {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

/** Đọc 1 node khách chi nhánh thành SourceCustomer (null nếu không phải object) */
function readSource(storeCode, customerId, v) {
  if (!v || typeof v !== "object") return null;
  const pts = Math.max(0, Math.trunc(num(v.diem_hien_tai) ?? num(v.diemHienTai) ?? num(v.currentPoints) ?? 0));
  const total = Math.max(0, Math.trunc(num(v.tongDiem) ?? num(v.totalPoints) ?? pts));
  const created = num(v.ngay_tao) ?? num(v.createdAt);
  return {
    storeCode,
    customerId,
    name: String(v.ho_ten ?? v.name ?? ""),
    phone: v.so_dien_thoai ?? v.phone ?? "",
    points: pts,
    totalPoints: Math.max(total, pts),
    createdAt: created,
  };
}

function planMigration(customers) {
  const byKey = new Map();
  for (const c of customers) {
    const key = memberKeyFor(c.phone, c.storeCode, c.customerId);
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(c);
  }
  const groups = [];
  const localOnly = [];
  const keys = [...byKey.keys()].sort((a, b) => a.localeCompare(b));
  for (const key of keys) {
    const list = byKey.get(key);
    const isLocal = key.startsWith("L_");
    const sorted = [...list].sort(
      (a, b) =>
        b.totalPoints - a.totalPoints ||
        (a.createdAt ?? Infinity) - (b.createdAt ?? Infinity) ||
        a.storeCode.localeCompare(b.storeCode) ||
        a.customerId.localeCompare(b.customerId)
    );
    const created = list.map((c) => c.createdAt).filter((x) => typeof x === "number" && x > 0);
    const g = {
      memberKey: key,
      phone: isLocal ? "" : key,
      name: sorted[0].name,
      points: list.reduce((s, c) => s + Math.max(0, c.points), 0),
      totalPoints: list.reduce((s, c) => s + Math.max(c.totalPoints, c.points, 0), 0),
      joinedAt: created.length ? Math.min(...created) : 0,
      lastStoreCode: sorted[0].storeCode,
      sources: sorted,
      duplicate: list.length > 1,
    };
    (isLocal ? localOnly : groups).push(g);
  }
  const all = groups.concat(localOnly);
  return {
    groups,
    localOnly,
    totals: {
      branchPoints: customers.reduce((s, c) => s + Math.max(0, c.points), 0),
      sharedPoints: all.reduce((s, g) => s + g.points, 0),
      branchTotalPoints: customers.reduce((s, c) => s + Math.max(c.totalPoints, c.points, 0), 0),
      sharedTotalPoints: all.reduce((s, g) => s + g.totalPoints, 0),
    },
  };
}

/** Các đường dẫn RTDB (multi-path update) cần ghi cho 1 nhóm. Create-only được đảm bảo ở migrate.js */
function buildWrites(g, now, by) {
  const ops = {};
  const branches = {};
  const writes = {};
  let running = 0;
  for (const s of g.sources) {
    const opId = `opening_${sanitizeKey(s.storeCode)}_${sanitizeKey(s.customerId)}`;
    running += s.points;
    ops[opId] = { p: s.points, t: "opening", at: now };
    (branches[s.storeCode] = branches[s.storeCode] || {})[s.customerId] = true;
    writes[`loyalty_ledger/${g.memberKey}/${opId}`] = {
      type: "opening",
      points: s.points,
      balanceAfter: running,
      storeCode: s.storeCode,
      customerId: s.customerId,
      staff: by,
      note: `Số dư đầu kỳ gộp từ chi nhánh ${s.storeCode} (khách ${s.customerId})`,
      at: now,
    };
  }
  writes[`loyalty_members/${g.memberKey}`] = {
    name: g.name,
    phone: g.phone,
    points: g.points,
    totalPoints: g.totalPoints,
    joinedAt: g.joinedAt || now,
    updatedAt: now,
    lastStoreCode: g.lastStoreCode,
    branches,
    ops,
  };
  // Cache trên node khách chi nhánh (client chỉ đọc)
  for (const s of g.sources) {
    const base = `stores/${s.storeCode}/customers/${s.customerId}`;
    writes[`${base}/diem_hien_tai`] = g.points;
    writes[`${base}/currentPoints`] = g.points;
    writes[`${base}/totalPoints`] = g.totalPoints;
  }
  return writes;
}

module.exports = { normalizePhone, memberKeyFor, readSource, planMigration, buildWrites, sanitizeKey };
