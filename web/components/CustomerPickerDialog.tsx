"use client";
import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Search, UserPlus, Users } from "lucide-react";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput } from "./ModalShell";
import { maskPhone, type MatchRange } from "@/lib/customer-search";
import { rankPickerCustomers, type PickerCustomer } from "@/lib/loyalty-checkout";
import { normalizePhone, tierForTotalPoints, validateNewCustomer, type LoyaltyTier } from "@/lib/loyalty";
import { lookupMember } from "@/lib/loyalty-client";
import { errorMessage } from "@/lib/errors";

interface Props {
  storeCode: string;
  customers: PickerCustomer[];
  tiers: LoyaltyTier[];
  loading?: boolean;
  /** Hiện SĐT đầy đủ (VIEW_CUSTOMERS / MANAGE_CUSTOMERS); ngược lại che giữa */
  showFullPhone: boolean;
  /** Được tạo khách mới (MANAGE_CUSTOMERS) */
  canCreate: boolean;
  /** Chọn khách; trả thông báo lỗi để hiện trong hộp thoại, null = thành công (đóng hộp) */
  onSelect: (c: PickerCustomer) => Promise<string | null>;
  onCreate: (name: string, phone: string) => Promise<string | null>;
  onClose: () => void;
}

const fmtPts = (n: number) => new Intl.NumberFormat("vi-VN").format(n);

function highlight(text: string, ranges: MatchRange[] | undefined): ReactNode {
  if (!ranges || ranges.length === 0) return text;
  const out: ReactNode[] = [];
  let pos = 0;
  ranges.forEach((r, i) => {
    if (r.start > pos) out.push(text.slice(pos, r.start));
    out.push(
      <mark key={i} style={{ background: "var(--primary-light)", color: "var(--primary)", borderRadius: 3, padding: "0 1px" }}>
        {text.slice(r.start, r.end)}
      </mark>
    );
    pos = r.end;
  });
  if (pos < text.length) out.push(text.slice(pos));
  return out;
}

/** Chọn khách cho bàn: mở ra là có ~10 khách ngay (gần đây / nhiều điểm), gõ để lọc (debounce 150ms) */
export default function CustomerPickerDialog({ storeCode, customers, tiers, loading, showFullPhone, canCreate, onSelect, onCreate, onClose }: Props) {
  const [text, setText] = useState("");
  const [query, setQuery] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [adding, setAdding] = useState(false);
  const [newName, setNewName] = useState("");
  const [newPhone, setNewPhone] = useState("");
  const [remote, setRemote] = useState<{ phone: string; state: "loading" | "found" | "none"; customer?: PickerCustomer } | null>(null);
  const reqId = useRef(0);

  useEffect(() => {
    const t = setTimeout(() => setQuery(text), 150);
    return () => clearTimeout(t);
  }, [text]);

  const results = useMemo(() => rankPickerCustomers(customers, query, 10), [customers, query]);

  // Số điện thoại đầy đủ không có trong chi nhánh → hỏi máy chủ (khách ở chi nhánh khác)
  const fullPhone = useMemo(() => (/^[0-9\s.\-+()]+$/.test(query.trim()) ? normalizePhone(query) : null), [query]);
  const localHasPhone = !!fullPhone && customers.some((c) => normalizePhone(c.phone) === fullPhone);
  useEffect(() => {
    if (!fullPhone || localHasPhone || loading) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setRemote(null);
      return;
    }
    const id = ++reqId.current;
    setRemote({ phone: fullPhone, state: "loading" });
    lookupMember(storeCode, { phone: fullPhone })
      .then((m) => {
        if (id !== reqId.current) return;
        setRemote(
          m.found
            ? {
                phone: fullPhone,
                state: "found",
                customer: { id: "", name: m.name || "Khách hàng", phone: m.phone || fullPhone, points: m.points ?? 0, totalPoints: m.totalPoints ?? m.points ?? 0, lastVisitAt: 0, remote: true },
              }
            : { phone: fullPhone, state: "none" }
        );
      })
      .catch(() => id === reqId.current && setRemote({ phone: fullPhone, state: "none" }));
  }, [fullPhone, localHasPhone, loading, storeCode]);

  const phoneOf = (p: string) => (showFullPhone ? p : maskPhone(p));

  const pick = async (c: PickerCustomer) => {
    setBusy(true);
    setError("");
    try {
      const err = await onSelect(c);
      if (err) setError(err);
    } catch (e) {
      setError(errorMessage(e, "Không gắn được khách vào bàn"));
    }
    setBusy(false);
  };

  const create = async () => {
    const v = validateNewCustomer({ name: newName, phone: newPhone }, customers.map((c) => ({ soDienThoai: c.phone })));
    if ("error" in v) {
      setError(v.error);
      return;
    }
    setBusy(true);
    setError("");
    try {
      const err = await onCreate(v.name, v.phone);
      if (err) setError(err);
    } catch (e) {
      setError(errorMessage(e, "Không tạo được khách hàng"));
    }
    setBusy(false);
  };

  const row = (c: PickerCustomer, nameRanges?: MatchRange[], phoneRange?: MatchRange) => {
    const phone = phoneOf(c.phone);
    return (
      <button
        key={c.remote ? `remote:${c.phone}` : c.id}
        type="button"
        disabled={busy}
        onClick={() => pick(c)}
        style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10, width: "100%", textAlign: "left", padding: "10px 12px", borderRadius: 10, border: "1px solid var(--border)", background: "var(--surface)", color: "var(--text)", cursor: "pointer" }}
      >
        <span style={{ minWidth: 0 }}>
          <span style={{ display: "block", fontWeight: 700, fontSize: 14 }}>{highlight(c.name, nameRanges)}</span>
          <span style={{ display: "block", fontSize: 12, color: "var(--subtext)" }}>
            {showFullPhone && phoneRange ? highlight(phone, [phoneRange]) : phone || "Chưa có SĐT"}
            {c.remote ? " • chi nhánh khác" : ""}
          </span>
        </span>
        <span style={{ textAlign: "right", flexShrink: 0 }}>
          <span style={{ display: "block", fontWeight: 800, fontSize: 13, color: "var(--primary)" }}>{fmtPts(c.points)} điểm</span>
          <span style={{ display: "block", fontSize: 11, color: "var(--subtext)" }}>{tierForTotalPoints(c.totalPoints, tiers)}</span>
        </span>
      </button>
    );
  };

  return (
    <ModalShell
      title={adding ? "Thêm khách mới" : "Chọn khách hàng"}
      subtitle={`Chi nhánh ${storeCode}`}
      icon={adding ? <UserPlus size={18} color="var(--primary)" /> : <Users size={18} color="var(--primary)" />}
      maxWidth={480}
      onClose={onClose}
      footer={
        adding ? (
          <>
            <button type="button" style={btnGhost} onClick={() => { setAdding(false); setError(""); }}>Quay lại</button>
            <button type="button" style={{ ...btnPrimary, opacity: busy ? 0.6 : 1 }} disabled={busy} onClick={create}>
              {busy ? "Đang lưu..." : "Lưu & chọn khách"}
            </button>
          </>
        ) : (
          <>
            {canCreate && (
              <button type="button" style={{ ...btnGhost, marginRight: "auto" }} onClick={() => { setAdding(true); setError(""); setNewPhone(fullPhone ?? ""); }}>
                <UserPlus size={14} style={{ verticalAlign: -2, marginRight: 4 }} />
                Thêm khách mới
              </button>
            )}
            <button type="button" style={btnGhost} onClick={onClose}>Đóng</button>
          </>
        )
      }
    >
      {error && <div style={errorBox}>{error}</div>}
      {adding ? (
        <div style={{ display: "grid", gap: 10 }}>
          <input style={fieldInput} placeholder="Họ và tên *" value={newName} onChange={(e) => setNewName(e.target.value)} autoFocus />
          <input style={fieldInput} placeholder="Số điện thoại *" inputMode="tel" value={newPhone} onChange={(e) => setNewPhone(e.target.value)} />
          <div style={{ fontSize: 12, color: "var(--subtext)" }}>Khách mới bắt đầu với 0 điểm. Nếu SĐT đã có điểm ở chi nhánh khác, điểm dùng chung sẽ tự gắn vào.</div>
        </div>
      ) : (
        <>
          <div style={{ position: "relative", marginBottom: 10 }}>
            <Search size={15} style={{ position: "absolute", left: 10, top: 12, color: "var(--subtext)" }} />
            <input
              style={{ ...fieldInput, paddingLeft: 32 }}
              placeholder="Tìm theo SĐT (3-4 số cuối) hoặc tên"
              value={text}
              onChange={(e) => setText(e.target.value)}
              autoFocus
              aria-label="Tìm khách hàng"
            />
          </div>
          <div style={{ display: "grid", gap: 8, maxHeight: "50vh", overflowY: "auto" }}>
            {loading && <div style={{ fontSize: 13, color: "var(--subtext)" }}>Đang tải khách hàng...</div>}
            {results.map((m) => row(m.customer, m.nameRanges, m.phoneRange))}
            {remote?.state === "found" && remote.customer && row(remote.customer)}
            {remote?.state === "loading" && <div style={{ fontSize: 12, color: "var(--subtext)" }}>Đang tra số điện thoại ở chi nhánh khác...</div>}
            {!loading && results.length === 0 && (!remote || remote.state === "none") && (
              <div style={{ fontSize: 13, color: "var(--subtext)", textAlign: "center", padding: 12 }}>
                {query.trim() ? "Không tìm thấy khách phù hợp." : "Chi nhánh chưa có khách hàng."}
                {canCreate ? " Bấm “Thêm khách mới” để tạo." : ""}
              </div>
            )}
          </div>
        </>
      )}
    </ModalShell>
  );
}
