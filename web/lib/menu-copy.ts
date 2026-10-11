/**
 * Sao chép thực đơn giữa các chi nhánh — LOGIC THUẦN (không đụng Firebase), có test.
 * Bản Dart song song: app_flutter/lib/core/domain/menu_copy.dart (giữ hai bản cùng quy tắc).
 *
 * Dữ liệu mỗi chi nhánh:
 *  - stores/{s}/products/{key}   : món. `key` là khóa RTDB (Flutter: tên món; Web: push id), trường `id` là số.
 *  - stores/{s}/categories/{tên} : nhóm món (món tham chiếu nhóm BẰNG TÊN).
 *  - stores/{s}/product_notes/{id}: ghi chú mẫu.
 *
 * Quy tắc cấp mã món ở chi nhánh đích (không bao giờ trùng):
 *  - Chi nhánh đích CHƯA có món nào (preserveIds) → giữ nguyên id/khóa nguồn khi còn trống.
 *  - Ngược lại mỗi món mới nhận id = (id số lớn nhất ở đích + các id đã cấp) + 1.
 *  - Ghi đè giữ nguyên khóa và id của món đang có ở đích (không đổi id → không lệch lịch sử/công thức).
 *  - `idMap` (id nguồn → id đích) được trả về để nối công thức/kho nếu cần.
 * Không bao giờ xóa gì ở đích: kế hoạch chỉ có các đường dẫn ghi.
 */

import { normalizeRoleId, ROLE_MANAGER, ROLE_OWNER } from "./roles";

export type RawNode = Record<string, unknown>;
export type ConflictPolicy = "skip" | "overwrite" | "duplicate";

export interface MenuSnapshot {
  products: Record<string, unknown>;
  categories: Record<string, unknown>;
  notes: Record<string, unknown>;
}

export interface CopyOptions {
  /** Tạo nhóm còn thiếu ở đích (theo tên) */
  copyCategories: boolean;
  /** size / topping / đường-đá */
  copyOptions: boolean;
  copyNotes: boolean;
  /** imageBase64 / imageResourceName (URL hoặc tên ảnh) */
  copyImages: boolean;
  conflict: ConflictPolicy;
  /** Giữ id/khóa nguồn khi còn trống. Mặc định: chỉ khi đích chưa có món nào */
  preserveIds?: boolean;
  /** Hậu tố khi chọn "Tạo bản sao" */
  duplicateSuffix?: string;
}

export const DEFAULT_COPY_OPTIONS: CopyOptions = {
  copyCategories: true,
  copyOptions: true,
  copyNotes: true,
  copyImages: true,
  conflict: "skip",
};

export interface CopySelection {
  /** true (hoặc bỏ trống mọi trường) = tất cả món */
  all?: boolean;
  /** Tên nhóm ở nguồn (so khớp chuẩn hóa) */
  categories?: string[];
  /** Khóa món ở nguồn */
  productKeys?: string[];
}

export type ProductAction = "create" | "overwrite" | "skip" | "duplicate";

export interface ProductOp {
  action: ProductAction;
  sourceKey: string;
  sourceId: number | null;
  name: string;
  category: string;
  targetKey: string | null;
  targetId: number | null;
  /** Lý do bỏ qua (chỉ khi skip) */
  reason?: string;
}

export interface CategoryOp {
  name: string;
  action: "create" | "exists";
}

export interface CopyPlan {
  productOps: ProductOp[];
  categoryOps: CategoryOp[];
  notesToAdd: number;
  /** Đường dẫn ghi, tương đối theo stores/{đích} */
  updates: Record<string, unknown>;
  /** id nguồn → id đích (nối công thức/kho) */
  idMap: Record<string, number>;
  counts: { create: number; overwrite: number; skip: number; duplicate: number; categories: number; notes: number };
}

const IMAGE_FIELDS = ["imageBase64", "imageResourceName", "imageUrl", "image"];
const OPTION_FIELDS = ["sizes", "allowedToppings", "hasIceSugarOptions"];

/** Chuẩn hóa tên để so khớp: bỏ dấu tiếng Việt, đ→d, thường hóa, gộp khoảng trắng/ký tự lạ */
export function normalizeName(s: unknown): string {
  return String(s ?? "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/đ/g, "d")
    .replace(/Đ/g, "d")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Khóa RTDB hợp lệ (cấm . # $ [ ] / và ký tự điều khiển) — cùng cách Flutter đặt khóa món */
export function sanitizeKey(s: string): string {
  return String(s).replace(/[.#$[\]/\u0000-\u001f\u007f]/g, "_").trim();
}

function isObj(v: unknown): v is RawNode {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function positiveInt(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" && v.trim() !== "" ? Number(v) : NaN;
  return Number.isInteger(n) && n > 0 ? n : null;
}

/** RTDB có thể trả mảng (khóa số liên tiếp) thay vì object */
export function toRecord(v: unknown): Record<string, unknown> {
  if (Array.isArray(v)) {
    const out: Record<string, unknown> = {};
    v.forEach((x, i) => {
      if (x != null) out[String(i)] = x;
    });
    return out;
  }
  return isObj(v) ? v : {};
}

function productName(node: unknown, key: string): string {
  return isObj(node) && node.name != null && String(node.name).trim() ? String(node.name).trim() : key;
}

function productCategory(node: unknown): string {
  return isObj(node) && node.category != null ? String(node.category).trim() : "";
}

function categoryName(node: unknown, key: string): string {
  if (typeof node === "string") return node.trim() || key;
  return isObj(node) && node.name != null && String(node.name).trim() ? String(node.name).trim() : key;
}

function noteText(node: unknown): string {
  if (typeof node === "string") return node.trim();
  if (isObj(node)) return String(node.text ?? node.name ?? "").trim();
  return "";
}

/** Bỏ undefined/null (RTDB không nhận undefined) */
function cleanNode(o: RawNode): RawNode {
  const out: RawNode = {};
  for (const [k, v] of Object.entries(o)) {
    if (v === undefined) continue;
    out[k] = v;
  }
  return out;
}

export interface BuildPlanInput {
  source: MenuSnapshot;
  target: MenuSnapshot;
  selection?: CopySelection;
  options?: Partial<CopyOptions>;
  /** Sinh khóa ghi chú (mặc định theo thời gian) — tiêm vào để test */
  noteKey?: (index: number) => string;
}

/** Món nguồn nằm trong phạm vi chọn? */
export function matchesSelection(sel: CopySelection | undefined, key: string, node: unknown): boolean {
  if (!sel || sel.all || (!sel.categories?.length && !sel.productKeys?.length)) return true;
  if (sel.productKeys?.includes(key)) return true;
  if (sel.categories?.length) {
    const cat = normalizeName(productCategory(node));
    return sel.categories.some((c) => normalizeName(c) === cat);
  }
  return false;
}

export function buildCopyPlan(input: BuildPlanInput): CopyPlan {
  const opt: CopyOptions = { ...DEFAULT_COPY_OPTIONS, ...(input.options || {}) };
  const srcProducts = toRecord(input.source.products);
  const tgtProducts = toRecord(input.target.products);
  const srcCats = toRecord(input.source.categories);
  const tgtCats = toRecord(input.target.categories);
  const preserveIds = opt.preserveIds ?? Object.keys(tgtProducts).length === 0;
  const suffix = opt.duplicateSuffix ?? " (bản sao)";

  // ---- Chỉ mục phía đích
  const usedKeys = new Set(Object.keys(tgtProducts));
  const usedIds = new Set<number>();
  let maxId = 0;
  for (const [k, node] of Object.entries(tgtProducts)) {
    const fromNode = isObj(node) ? positiveInt(node.id) : null;
    const fromKey = positiveInt(k);
    for (const n of [fromNode, fromKey]) {
      if (n != null) {
        usedIds.add(n);
        if (n > maxId) maxId = n;
      }
    }
  }
  const allocId = (): number => {
    let n = maxId + 1;
    while (usedIds.has(n)) n++;
    maxId = n;
    usedIds.add(n);
    return n;
  };

  // Nhóm đích: tên chuẩn hóa → tên thật + khóa
  const tgtCatByNorm = new Map<string, string>();
  for (const [k, node] of Object.entries(tgtCats)) tgtCatByNorm.set(normalizeName(categoryName(node, k)), categoryName(node, k));
  for (const node of Object.values(tgtProducts)) {
    const c = productCategory(node);
    if (c && !tgtCatByNorm.has(normalizeName(c))) tgtCatByNorm.set(normalizeName(c), c);
  }
  // Nhóm nguồn: tên chuẩn hóa → node
  const srcCatNodeByNorm = new Map<string, { name: string; node: unknown }>();
  for (const [k, node] of Object.entries(srcCats)) srcCatNodeByNorm.set(normalizeName(categoryName(node, k)), { name: categoryName(node, k), node });

  // Món đích: (tên + nhóm chuẩn hóa) → khóa
  const tgtByIdentity = new Map<string, string>();
  for (const [k, node] of Object.entries(tgtProducts)) {
    const id = `${normalizeName(productName(node, k))}|${normalizeName(productCategory(node))}`;
    if (!tgtByIdentity.has(id)) tgtByIdentity.set(id, k);
  }

  const updates: Record<string, unknown> = {};
  const idMap: Record<string, number> = {};
  const productOps: ProductOp[] = [];
  const categoryOps: CategoryOp[] = [];
  const plannedCats = new Set<string>();
  const seenIdentity = new Set<string>();

  const ensureCategory = (srcCatName: string): string => {
    if (!srcCatName) return "";
    const norm = normalizeName(srcCatName);
    const existing = tgtCatByNorm.get(norm);
    if (existing) {
      if (!plannedCats.has(norm) && !categoryOps.some((c) => normalizeName(c.name) === norm)) categoryOps.push({ name: existing, action: "exists" });
      return existing;
    }
    if (!opt.copyCategories) return srcCatName;
    const srcNode = srcCatNodeByNorm.get(norm);
    const name = srcNode?.name || srcCatName;
    const payload: RawNode = { name };
    if (srcNode && isObj(srcNode.node) && srcNode.node.allowedToppingIds != null) payload.allowedToppingIds = srcNode.node.allowedToppingIds;
    updates[`categories/${sanitizeKey(name)}`] = cleanNode(payload);
    plannedCats.add(norm);
    tgtCatByNorm.set(norm, name);
    categoryOps.push({ name, action: "create" });
    return name;
  };

  // Giữ thứ tự ổn định theo tên để kết quả dự đoán được
  const entries = Object.entries(srcProducts)
    .filter(([k, n]) => isObj(n) && matchesSelection(input.selection, k, n))
    .sort((a, b) => productName(a[1], a[0]).localeCompare(productName(b[1], b[0]), "vi"));

  const buildPayload = (key: string, node: RawNode, name: string, category: string, targetId: number): RawNode => {
    const out: RawNode = { ...node };
    delete out.storeCode;
    delete out.storeName;
    if (!opt.copyImages) for (const f of IMAGE_FIELDS) delete out[f];
    if (!opt.copyOptions) for (const f of OPTION_FIELDS) delete out[f];
    out.id = targetId;
    out.name = name;
    out.category = category;
    void key;
    return cleanNode(out);
  };

  for (const [key, raw] of entries) {
    const node = raw as RawNode;
    const name = productName(node, key);
    const srcCat = productCategory(node);
    const sourceId = positiveInt(node.id) ?? positiveInt(key);
    const identityNorm = `${normalizeName(name)}|${normalizeName(srcCat)}`;
    const mappedCat = srcCat ? tgtCatByNorm.get(normalizeName(srcCat)) ?? null : null;
    // Danh tính ở đích dùng tên nhóm đã quy đổi (khớp bỏ dấu)
    const identity = `${normalizeName(name)}|${normalizeName(mappedCat ?? srcCat)}`;
    const existingKey = tgtByIdentity.get(identity) ?? tgtByIdentity.get(identityNorm) ?? null;
    const base: Omit<ProductOp, "action" | "targetKey" | "targetId"> = { sourceKey: key, sourceId, name, category: srcCat };

    // Trùng ngay trong phạm vi sao chép (hai món nguồn cùng tên+nhóm) → chỉ lấy món đầu
    if (seenIdentity.has(identity)) {
      productOps.push({ ...base, action: "skip", targetKey: null, targetId: null, reason: "Trùng món khác trong danh sách chọn" });
      continue;
    }
    seenIdentity.add(identity);

    if (existingKey && opt.conflict === "skip") {
      const tNode = tgtProducts[existingKey];
      productOps.push({ ...base, action: "skip", targetKey: existingKey, targetId: isObj(tNode) ? positiveInt(tNode.id) ?? positiveInt(existingKey) : null, reason: "Đã có ở chi nhánh đích" });
      continue;
    }

    if (existingKey && opt.conflict === "overwrite") {
      const tNode = tgtProducts[existingKey];
      const tId = (isObj(tNode) ? positiveInt(tNode.id) : null) ?? positiveInt(existingKey) ?? allocId();
      const cat = ensureCategory(srcCat);
      const payload = buildPayload(key, node, isObj(tNode) && tNode.name ? String(tNode.name) : name, cat, tId);
      // Ghi từng trường: giữ nguyên các trường đích có mà nguồn không có (vd. tồn nội bộ)
      for (const [f, v] of Object.entries(payload)) updates[`products/${existingKey}/${f}`] = v;
      if (sourceId != null) idMap[String(sourceId)] = tId;
      productOps.push({ ...base, action: "overwrite", targetKey: existingKey, targetId: tId });
      continue;
    }

    // Tạo mới (hoặc bản sao khi trùng)
    const isDup = Boolean(existingKey);
    let finalName = name;
    if (isDup) {
      let n = 1;
      const taken = (candidate: string) => tgtByIdentity.has(`${normalizeName(candidate)}|${normalizeName(mappedCat ?? srcCat)}`);
      finalName = `${name}${suffix}`;
      while (taken(finalName)) {
        n++;
        finalName = `${name}${suffix.replace(/\)$/, "")} ${n})`;
      }
    }
    const cat = ensureCategory(srcCat);

    let targetId: number;
    if (preserveIds && !isDup && sourceId != null && !usedIds.has(sourceId)) {
      targetId = sourceId;
      usedIds.add(sourceId);
      if (sourceId > maxId) maxId = sourceId;
    } else {
      targetId = allocId();
    }

    let targetKey: string;
    if (isDup) targetKey = sanitizeKey(finalName);
    else if (positiveInt(key) != null) targetKey = String(targetId); // khóa số = id
    else targetKey = sanitizeKey(key) || sanitizeKey(finalName);
    if (!targetKey || usedKeys.has(targetKey)) {
      const alt = `${targetKey || sanitizeKey(finalName) || "mon"}_${targetId}`;
      targetKey = usedKeys.has(alt) ? `${alt}_${usedKeys.size}` : alt;
    }
    usedKeys.add(targetKey);
    tgtByIdentity.set(`${normalizeName(finalName)}|${normalizeName(cat)}`, targetKey);

    const payload = buildPayload(key, node, finalName, cat, targetId);
    if (isDup && payload.code) payload.code = ""; // tránh trùng mã SKU
    updates[`products/${targetKey}`] = payload;
    if (sourceId != null) idMap[String(sourceId)] = targetId;
    productOps.push({ ...base, action: isDup ? "duplicate" : "create", targetKey, targetId });
  }

  // ---- Ghi chú mẫu (không trùng nội dung đã có)
  let notesToAdd = 0;
  if (opt.copyNotes) {
    const have = new Set(Object.values(toRecord(input.target.notes)).map((n) => normalizeName(noteText(n))));
    const usedNoteKeys = new Set(Object.keys(toRecord(input.target.notes)));
    const gen = input.noteKey ?? ((i: number) => `note_${Date.now()}_${i}`);
    let i = 0;
    for (const n of Object.values(toRecord(input.source.notes))) {
      const text = noteText(n);
      const norm = normalizeName(text);
      if (!text || have.has(norm)) continue;
      have.add(norm);
      let k = gen(i++);
      while (usedNoteKeys.has(k)) k = gen(i++);
      usedNoteKeys.add(k);
      updates[`product_notes/${sanitizeKey(k)}`] = { text };
      notesToAdd++;
    }
  }

  const count = (a: ProductAction) => productOps.filter((p) => p.action === a).length;
  return {
    productOps,
    categoryOps,
    notesToAdd,
    updates,
    idMap,
    counts: {
      create: count("create"),
      overwrite: count("overwrite"),
      skip: count("skip"),
      duplicate: count("duplicate"),
      categories: categoryOps.filter((c) => c.action === "create").length,
      notes: notesToAdd,
    },
  };
}

/** Số mục ghi thực sự thay đổi (để biết có gì cần chạy) */
export function planWriteCount(plan: CopyPlan): number {
  return Object.keys(plan.updates).length;
}

/** Chia các đường dẫn thành lô ≤ maxPaths (mỗi đường dẫn đã phẳng 1 lá hoặc 1 object nhỏ) */
export function chunkUpdates(updates: Record<string, unknown>, maxPaths = 400): Array<Record<string, unknown>> {
  const keys = Object.keys(updates);
  const out: Array<Record<string, unknown>> = [];
  for (let i = 0; i < keys.length; i += Math.max(1, maxPaths)) {
    const part: Record<string, unknown> = {};
    for (const k of keys.slice(i, i + maxPaths)) part[k] = updates[k];
    out.push(part);
  }
  return out;
}

export interface CopyAuditActor {
  username: string;
  fullName?: string;
  role?: string;
}

export interface CopyAuditSummary {
  created: number;
  overwritten: number;
  skipped: number;
}

/** Bản ghi nhật ký cho chi nhánh đích (khớp rules audit_logs: timestamp/action/username) */
export function buildCopyAuditEntry(args: {
  sourceStore: string;
  targetStore: string;
  summary: CopyAuditSummary;
  actor: CopyAuditActor;
  now: number;
  failed?: boolean;
}): Record<string, unknown> {
  const { sourceStore, targetStore, summary, actor, now } = args;
  const n = summary.created + summary.overwritten;
  return {
    timestamp: now,
    action: "COPY_MENU",
    targetType: "MENU",
    targetId: targetStore,
    username: actor.username || "unknown",
    userFullName: actor.fullName || actor.username || "",
    userRole: actor.role || "",
    details: `Sao chép ${n} món từ ${sourceStore} sang ${targetStore}${args.failed ? " (có lỗi, chưa hoàn tất)" : ""}`,
    sourceStore,
    targetStore,
    created: summary.created,
    overwritten: summary.overwritten,
    skipped: summary.skipped,
  };
}

export function summarizePlan(plan: CopyPlan): CopyAuditSummary {
  return {
    created: plan.counts.create + plan.counts.duplicate,
    overwritten: plan.counts.overwrite,
    skipped: plan.counts.skip,
  };
}

/**
 * Ai được sao chép thực đơn: Chủ / Quản lý (khớp rules — chỉ họ ghi được products/categories)
 * VÀ có mã quyền COPY_MENU (Chủ: mặc định; Quản lý: mặc định có, bỏ được qua phân quyền).
 */
export function canCopyMenu(
  user: { roleId?: string; role?: string; isRootOwner?: boolean } | null | undefined,
  hasPerm: (permission: string) => boolean
): boolean {
  if (!user) return false;
  if (user.isRootOwner) return true;
  const r = normalizeRoleId(user.roleId || user.role || "");
  if (r !== ROLE_OWNER && r !== ROLE_MANAGER) return false;
  return hasPerm("COPY_MENU");
}
