/**
 * Sinh mã hóa đơn tuần tự dùng chung định dạng với ứng dụng Flutter POS:
 *   HD-yyMMdd-NNNN
 * Bộ đếm theo ngày (giờ Việt Nam UTC+7) nằm ở stores/{storeCode}/counters/bill_seq/{yyMMdd}
 * và được tăng +1 bằng runTransaction để hai thiết bị không bao giờ cấp trùng số.
 * Nếu transaction thất bại (mất mạng, bị rules từ chối...) thì dùng mã dự phòng
 * HD-yyMMdd-HHmmss-XXXX để không chặn thao tác thanh toán.
 */
import { ref, runTransaction, type Database } from "firebase/database";

const VN_OFFSET_MS = 7 * 60 * 60 * 1000;

/** Khóa ngày yyMMdd theo giờ Việt Nam (UTC+7) */
export function billDayKey(timestamp: number): string {
  const d = new Date(timestamp + VN_OFFSET_MS);
  const yy = String(d.getUTCFullYear() % 100).padStart(2, "0");
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(d.getUTCDate()).padStart(2, "0");
  return `${yy}${mm}${dd}`;
}

/** HD-yyMMdd-NNNN (tối thiểu 4 chữ số, vượt 9999 thì giữ nguyên độ dài) */
export function formatBillCode(dayKey: string, seq: number): string {
  return `HD-${dayKey}-${String(seq).padStart(4, "0")}`;
}

/**
 * Mã dự phòng khi không lấy được số tuần tự — cùng định dạng với Flutter (BillCodeGenerator.fallback):
 *   HD-yyMMdd-HHmmss-XXXX (hậu tố 4 ký tự ngẫu nhiên)
 * Có thêm một đoạn nên không bao giờ trùng định dạng với mã tuần tự.
 */
const FALLBACK_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export function fallbackBillCode(timestamp: number, random: () => number = Math.random): string {
  const d = new Date(timestamp + VN_OFFSET_MS);
  const hh = String(d.getUTCHours()).padStart(2, "0");
  const mi = String(d.getUTCMinutes()).padStart(2, "0");
  const ss = String(d.getUTCSeconds()).padStart(2, "0");
  let suffix = "";
  for (let i = 0; i < 4; i++) {
    suffix += FALLBACK_CHARS[Math.floor(random() * FALLBACK_CHARS.length) % FALLBACK_CHARS.length];
  }
  return `HD-${billDayKey(timestamp)}-${hh}${mi}${ss}-${suffix}`;
}

/** Mã tuần tự chính thức HD-yyMMdd-NNNN */
export function isSequentialBillCode(code: string): boolean {
  return /^[A-Z]+-\d{6}-\d{4,}$/.test(code);
}

/** Cấp mã hóa đơn tuần tự qua RTDB transaction, có fallback timestamp+random */
export async function generateBillCode(
  database: Database,
  storeCode: string,
  timestamp: number = Date.now()
): Promise<string> {
  const dayKey = billDayKey(timestamp);
  try {
    const counterRef = ref(database, `stores/${storeCode}/counters/bill_seq/${dayKey}`);
    const result = await runTransaction(counterRef, (current) => {
      const n = typeof current === "number" && Number.isFinite(current) ? current : 0;
      return n + 1;
    });
    const seq = result.snapshot.val();
    if (result.committed && typeof seq === "number" && seq > 0) {
      return formatBillCode(dayKey, seq);
    }
    console.warn("generateBillCode: transaction không commit, dùng mã dự phòng");
  } catch (e) {
    console.warn("generateBillCode: lỗi transaction, dùng mã dự phòng:", e);
  }
  return fallbackBillCode(timestamp);
}
