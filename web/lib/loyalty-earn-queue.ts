/**
 * Hàng đợi thử lại tích điểm (giống LoyaltyEarnQueue của Flutter): tích điểm lỗi KHÔNG được im lặng.
 * applyLoyaltyEarn idempotent theo hóa đơn nên thử lại nhiều lần là an toàn.
 * Lưu ở localStorage theo người dùng + chi nhánh; các hàm nhận `storage` để test.
 */
export interface EarnQueueEntry {
  billId: string;
  billCode?: string;
  at: number;
  attempts: number;
  error?: string;
}

export interface KeyValueStorage {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
}

export const EARN_QUEUE_MAX = 200;

export const earnQueueKey = (username: string, storeCode: string) => `loyalty_earn_retry:${username || "anon"}:${storeCode}`;

export function readEarnQueue(storage: KeyValueStorage | null, key: string): EarnQueueEntry[] {
  if (!storage) return [];
  try {
    const raw = JSON.parse(storage.getItem(key) || "[]");
    if (!Array.isArray(raw)) return [];
    return raw
      .filter((e): e is Record<string, unknown> => !!e && typeof e === "object" && typeof (e as Record<string, unknown>).billId === "string")
      .map((e) => ({
        billId: String(e.billId),
        billCode: typeof e.billCode === "string" ? e.billCode : undefined,
        at: Number(e.at) || 0,
        attempts: Number(e.attempts) || 0,
        error: typeof e.error === "string" ? e.error : undefined,
      }));
  } catch {
    return [];
  }
}

function write(storage: KeyValueStorage | null, key: string, list: EarnQueueEntry[]) {
  if (!storage) return;
  try {
    storage.setItem(key, JSON.stringify(list.slice(-EARN_QUEUE_MAX)));
  } catch {
    // localStorage đầy / bị chặn: bỏ qua, người dùng vẫn được báo lỗi bằng toast
  }
}

/** Thêm hóa đơn vào hàng đợi (trùng billId → gộp, giữ lần thử cũ) */
export function addToEarnQueue(storage: KeyValueStorage | null, key: string, entry: { billId: string; billCode?: string; error?: string }, now = Date.now()): EarnQueueEntry[] {
  const list = readEarnQueue(storage, key);
  const i = list.findIndex((e) => e.billId === entry.billId);
  if (i >= 0) list[i] = { ...list[i], error: entry.error ?? list[i].error };
  else list.push({ billId: entry.billId, billCode: entry.billCode, at: now, attempts: 0, error: entry.error });
  write(storage, key, list);
  return list;
}

export function removeFromEarnQueue(storage: KeyValueStorage | null, key: string, billId: string): EarnQueueEntry[] {
  const list = readEarnQueue(storage, key).filter((e) => e.billId !== billId);
  write(storage, key, list);
  return list;
}

/**
 * Thử lại toàn bộ hàng đợi. `apply` trả về khi thành công (kể cả đã tích rồi), ném lỗi khi thất bại.
 * Thành công → bỏ khỏi hàng đợi; thất bại → giữ lại, tăng số lần thử.
 */
export async function processEarnQueue(
  storage: KeyValueStorage | null,
  key: string,
  apply: (billId: string) => Promise<unknown>
): Promise<{ done: string[]; failed: string[] }> {
  const done: string[] = [];
  const failed: string[] = [];
  for (const e of readEarnQueue(storage, key)) {
    try {
      await apply(e.billId);
      done.push(e.billId);
      removeFromEarnQueue(storage, key, e.billId);
    } catch (err) {
      failed.push(e.billId);
      const list = readEarnQueue(storage, key).map((x) =>
        x.billId === e.billId ? { ...x, attempts: x.attempts + 1, error: err instanceof Error ? err.message : String(err) } : x
      );
      write(storage, key, list);
    }
  }
  return { done, failed };
}

/** Tích điểm ngay sau khi hóa đơn PAID; lỗi → vào hàng đợi. Trả `ok=false` để UI báo "sẽ thử lại". */
export async function earnWithRetry(
  storage: KeyValueStorage | null,
  key: string,
  bill: { billId: string; billCode?: string },
  apply: (billId: string) => Promise<unknown>
): Promise<{ ok: boolean }> {
  try {
    await apply(bill.billId);
    return { ok: true };
  } catch (err) {
    addToEarnQueue(storage, key, { ...bill, error: err instanceof Error ? err.message : String(err) });
    return { ok: false };
  }
}

const KEY_PREFIX = "loyalty_earn_retry:";

/** Mọi hàng đợi của một người dùng (mỗi chi nhánh một khóa) → [{ key, storeCode }] */
export function listEarnQueueKeys(storage: { length: number; key(i: number): string | null } | null, username: string): { key: string; storeCode: string }[] {
  if (!storage) return [];
  const prefix = `${KEY_PREFIX}${username || "anon"}:`;
  const out: { key: string; storeCode: string }[] = [];
  for (let i = 0; i < storage.length; i++) {
    const k = storage.key(i);
    if (k && k.startsWith(prefix) && k.length > prefix.length) out.push({ key: k, storeCode: k.slice(prefix.length) });
  }
  return out;
}
