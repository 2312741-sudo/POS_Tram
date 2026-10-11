/**
 * Chạy sao chép thực đơn trên Firebase (phần có I/O của lib/menu-copy.ts).
 * Mỗi chi nhánh đích: đọc đích → dựng kế hoạch → ghi theo lô update() đa đường dẫn → ghi nhật ký COPY_MENU.
 * KHÔNG xóa gì ở chi nhánh đích.
 */
import { get, ref, set, update, type Database } from "firebase/database";
import {
  buildCopyAuditEntry,
  buildCopyPlan,
  chunkUpdates,
  summarizePlan,
  type CopyAuditActor,
  type CopyOptions,
  type CopyPlan,
  type CopySelection,
  type MenuSnapshot,
} from "./menu-copy";
import { errorMessage } from "./errors";

export const COPY_CHUNK_PATHS = 400;

export async function loadMenuSnapshot(db: Database, storeCode: string): Promise<MenuSnapshot> {
  const [p, c, n] = await Promise.all([
    get(ref(db, `stores/${storeCode}/products`)),
    get(ref(db, `stores/${storeCode}/categories`)),
    get(ref(db, `stores/${storeCode}/product_notes`)),
  ]);
  return {
    products: (p.val() as Record<string, unknown>) || {},
    categories: (c.val() as Record<string, unknown>) || {},
    notes: (n.val() as Record<string, unknown>) || {},
  };
}

export interface TargetPlan {
  targetStore: string;
  plan: CopyPlan;
  error?: string;
}

/** Dựng kế hoạch (xem trước) cho từng đích */
export async function planForTargets(
  db: Database,
  source: MenuSnapshot,
  targets: string[],
  selection: CopySelection,
  options: Partial<CopyOptions>
): Promise<TargetPlan[]> {
  const out: TargetPlan[] = [];
  for (const t of targets) {
    try {
      const target = await loadMenuSnapshot(db, t);
      out.push({ targetStore: t, plan: buildCopyPlan({ source, target, selection, options }) });
    } catch (e) {
      out.push({ targetStore: t, plan: buildCopyPlan({ source: { products: {}, categories: {}, notes: {} }, target: { products: {}, categories: {}, notes: {} } }), error: errorMessage(e) });
    }
  }
  return out;
}

export interface TargetResult {
  targetStore: string;
  ok: boolean;
  created: number;
  overwritten: number;
  skipped: number;
  error?: string;
}

export interface RunProgress {
  targetStore: string;
  doneChunks: number;
  totalChunks: number;
  targetIndex: number;
  targetCount: number;
}

export async function applyPlan(
  db: Database,
  args: {
    sourceStore: string;
    targetStore: string;
    plan: CopyPlan;
    actor: CopyAuditActor;
    onChunk?: (done: number, total: number) => void;
  }
): Promise<TargetResult> {
  const { sourceStore, targetStore, plan, actor } = args;
  const summary = summarizePlan(plan);
  const chunks = chunkUpdates(plan.updates, COPY_CHUNK_PATHS);
  let done = 0;
  try {
    for (const part of chunks) {
      await update(ref(db, `stores/${targetStore}`), part);
      done++;
      args.onChunk?.(done, chunks.length);
    }
  } catch (e) {
    const msg = errorMessage(e);
    await writeAudit(db, { sourceStore, targetStore, summary: { created: 0, overwritten: 0, skipped: summary.skipped }, actor, failed: true });
    return { targetStore, ok: false, created: 0, overwritten: 0, skipped: summary.skipped, error: `${msg} (đã ghi ${done}/${chunks.length} lô)` };
  }
  await writeAudit(db, { sourceStore, targetStore, summary, actor });
  return { targetStore, ok: true, ...summary };
}

async function writeAudit(
  db: Database,
  a: { sourceStore: string; targetStore: string; summary: { created: number; overwritten: number; skipped: number }; actor: CopyAuditActor; failed?: boolean }
) {
  try {
    const now = Date.now();
    const entry = buildCopyAuditEntry({ ...a, now });
    await set(ref(db, `stores/${a.targetStore}/audit_logs/LOG_${now}_${Math.random().toString(36).slice(2, 6)}`), entry);
  } catch {
    // nhật ký lỗi không làm hỏng kết quả sao chép
  }
}

/** Sao chép nguyên thực đơn sang chi nhánh mới (tạo chi nhánh): tất cả món, giữ id nguồn khi đích trống */
export async function copyWholeMenu(db: Database, sourceStore: string, targetStore: string, actor: CopyAuditActor): Promise<TargetResult> {
  const [source, target] = await Promise.all([loadMenuSnapshot(db, sourceStore), loadMenuSnapshot(db, targetStore)]);
  const plan = buildCopyPlan({ source, target, selection: { all: true }, options: { conflict: "skip" } });
  return applyPlan(db, { sourceStore, targetStore, plan, actor });
}
