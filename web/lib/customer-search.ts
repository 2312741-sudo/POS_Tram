/**
 * Tìm / xếp hạng khách hàng (bản web của app_flutter/lib/core/domain/customer_search.dart - giữ cùng quy tắc):
 *  - Rỗng: khách gần đây trước, rồi nhiều điểm nhất.
 *  - Số điện thoại: đủ số, 3+ số CUỐI, hoặc một phần bất kỳ (từ 3 số).
 *  - Tên: không phân biệt dấu/hoa thường, thứ tự từ bất kỳ.
 */
export interface CustomerCandidate {
  id: string;
  name: string;
  phone: string;
  points: number;
  lastVisitAt?: number;
}

export interface MatchRange {
  start: number;
  end: number;
}

export interface CustomerMatch<T extends CustomerCandidate = CustomerCandidate> {
  customer: T;
  score: number;
  nameRanges: MatchRange[];
  phoneRange?: MatchRange;
}

const FROM = "àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ";
const TO = "aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd";

/** Bỏ dấu tiếng Việt + chữ thường, giữ nguyên độ dài chuỗi (để tô sáng đúng vị trí) */
export function foldVi(s: string): string {
  let out = "";
  for (const ch of s.toLowerCase()) {
    const i = FROM.indexOf(ch);
    out += i >= 0 ? TO[i] : ch;
  }
  return out;
}

export const digitsOf = (s: string): string => s.replace(/\D/g, "");

/** 0901234567 → 090****567 */
export function maskPhone(phone: string): string {
  const p = phone.trim();
  return p.length < 7 ? p : `${p.slice(0, 3)}${"*".repeat(p.length - 6)}${p.slice(-3)}`;
}

function phoneRange(phone: string, digitIdx: number, len: number): MatchRange | undefined {
  let seen = 0;
  let start = -1;
  for (let i = 0; i < phone.length; i++) {
    if (/\d/.test(phone[i])) {
      if (seen === digitIdx) start = i;
      if (seen === digitIdx + len - 1 && start >= 0) return { start, end: i + 1 };
      seen++;
    }
  }
  return undefined;
}

function mergeRanges(r: MatchRange[]): MatchRange[] {
  const s = [...r].sort((a, b) => a.start - b.start);
  const out: MatchRange[] = [];
  for (const x of s) {
    const last = out[out.length - 1];
    if (last && x.start <= last.end) last.end = Math.max(last.end, x.end);
    else out.push({ ...x });
  }
  return out;
}

export function searchCustomers<T extends CustomerCandidate>(all: T[], query: string, limit = 10): CustomerMatch<T>[] {
  const q = query.trim();
  const visit = (c: T) => c.lastVisitAt ?? 0;
  if (!q) {
    return [...all]
      .sort((a, b) => visit(b) - visit(a) || b.points - a.points)
      .slice(0, limit)
      .map((customer) => ({ customer, score: 0, nameRanges: [] }));
  }
  const onlyDigits = /^[0-9\s.\-+()]+$/.test(q);
  const qd = digitsOf(q);
  const tokens = foldVi(q).split(/\s+/).filter(Boolean);
  const out: CustomerMatch<T>[] = [];
  for (const c of all) {
    if (onlyDigits) {
      if (qd.length < 3) continue;
      const p = digitsOf(c.phone);
      const idx = p.indexOf(qd);
      if (idx < 0) continue;
      out.push({ customer: c, score: p === qd ? 100 : p.endsWith(qd) ? 90 : 70, nameRanges: [], phoneRange: phoneRange(c.phone, idx, qd.length) });
    } else {
      const name = foldVi(c.name);
      const ranges: MatchRange[] = [];
      let ok = tokens.length > 0;
      for (const t of tokens) {
        const i = name.indexOf(t);
        if (i < 0) {
          ok = false;
          break;
        }
        ranges.push({ start: i, end: i + t.length });
      }
      if (!ok) continue;
      const startsWord = tokens.every((t) => name.startsWith(t) || name.includes(` ${t}`));
      out.push({ customer: c, score: startsWord ? 60 : 40, nameRanges: mergeRanges(ranges) });
    }
  }
  out.sort((a, b) => b.score - a.score || visit(b.customer) - visit(a.customer) || b.customer.points - a.customer.points);
  return out.slice(0, limit);
}
