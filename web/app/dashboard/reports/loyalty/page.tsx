"use client";
import { Suspense, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Download, History, RefreshCw, Search } from "lucide-react";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { canReadCustomers } from "@/lib/customers";
import {
  LEDGER_KINDS,
  LEDGER_KIND_LABEL,
  buildLedgerCsv,
  dayEndMs,
  dayStartMs,
  ledgerErrorMessage,
  ledgerKindLabel,
  listLoyaltyLedger,
  type LoyaltyLedgerEntry,
  type LoyaltyLedgerTotals,
} from "@/lib/loyalty-ledger-client";
import { formatNumber } from "@/lib/reports";

const th = { padding: "10px 12px", textAlign: "left", fontSize: 12, color: "var(--subtext)", whiteSpace: "nowrap" } as const;
const td = { padding: "9px 12px", fontSize: 13, borderTop: "1px solid var(--border)" } as const;
const PAGE_SIZE = 200;
const EMPTY_TOTALS: LoyaltyLedgerTotals = { earned: 0, redeemed: 0, manual: 0, count: 0 };

const fmtTime = (ms: number) => (ms > 0 ? new Date(ms).toLocaleString("vi-VN") : "—");

export default function LoyaltyHistoryPage() {
  // useSearchParams cần Suspense để trang vẫn build tĩnh được
  return (
    <Suspense fallback={null}>
      <LoyaltyHistoryContent />
    </Suspense>
  );
}

function LoyaltyHistoryContent() {
  const params = useSearchParams();
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();
  const canRead = canReadCustomers(user?.roleId || user?.role, user?.isRootOwner);

  // Mở từ nút "Lịch sử" ở trang Khách hàng: ?store=...&customer=...
  const [customerId, setCustomerId] = useState(params.get("customer") || "");
  const [storeSel, setStoreSel] = useState(params.get("store") || currentStoreCode || "ALL");
  const [search, setSearch] = useState("");
  const [debouncedSearch, setDebouncedSearch] = useState("");
  const [type, setType] = useState<"ALL" | string>("ALL");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  const [entries, setEntries] = useState<LoyaltyLedgerEntry[]>([]);
  const [totals, setTotals] = useState<LoyaltyLedgerTotals>(EMPTY_TOTALS);
  const [nextCursor, setNextCursor] = useState<string | undefined>();
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState("");
  const reqId = useRef(0);

  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search.trim()), 350);
    return () => clearTimeout(t);
  }, [search]);

  const buildQuery = useCallback(
    (cursor?: string) => ({
      storeCode: storeSel || "ALL",
      from: dayStartMs(from),
      to: dayEndMs(to),
      types: type === "ALL" ? undefined : [type],
      search: debouncedSearch || undefined,
      customerId: customerId && storeSel !== "ALL" ? customerId : undefined,
      cursor,
      limit: PAGE_SIZE,
    }),
    [storeSel, from, to, type, debouncedSearch, customerId]
  );

  const load = useCallback(async () => {
    if (!canRead) return;
    const id = ++reqId.current;
    setLoading(true);
    setError("");
    try {
      const page = await listLoyaltyLedger(buildQuery());
      if (id !== reqId.current) return;
      setEntries(page.entries);
      setTotals(page.totals);
      setNextCursor(page.nextCursor);
    } catch (e) {
      if (id !== reqId.current) return;
      setEntries([]);
      setTotals(EMPTY_TOTALS);
      setNextCursor(undefined);
      setError(ledgerErrorMessage(e));
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  }, [canRead, buildQuery]);

  useEffect(() => {
    // Tải lại từ máy chủ mỗi khi bộ lọc đổi (setState nằm trong hàm async)
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  const loadMore = async () => {
    if (!nextCursor || loadingMore) return;
    const id = reqId.current;
    setLoadingMore(true);
    try {
      const page = await listLoyaltyLedger(buildQuery(nextCursor));
      if (id !== reqId.current) return;
      setEntries((prev) => [...prev, ...page.entries]);
      setNextCursor(page.nextCursor);
    } catch (e) {
      setError(ledgerErrorMessage(e));
    } finally {
      setLoadingMore(false);
    }
  };

  const showBranch = storeSel === "ALL" && stores.length > 1;

  const exportCsv = () => {
    const blob = new Blob([buildLedgerCsv(entries, fmtTime)], { type: "text/csv;charset=utf-8" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `lich-su-diem-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(a.href);
  };

  const input = { padding: "7px 10px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)", fontSize: 13 } as const;
  const kpi = (label: string, value: string, color: string) => (
    <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px" }}>
      <div style={{ fontSize: 12, color: "var(--subtext)" }}>{label}</div>
      <div style={{ fontSize: 22, fontWeight: 800, color }}>{value}</div>
    </div>
  );
  const cols = showBranch ? 8 : 7;

  return (
    <div style={{ padding: "24px 28px", maxWidth: 1280, margin: "0 auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "center", marginBottom: 14 }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0, display: "flex", gap: 8, alignItems: "center" }}>
            <History size={22} /> Lịch sử sử dụng điểm khách hàng
          </h1>
          <p style={{ fontSize: 13, color: "var(--subtext)", margin: "4px 0 0" }}>
            Tích điểm, đổi điểm, hoàn điểm theo hóa đơn và các lần Chủ/Quản lý chỉnh điểm (điểm dùng chung toàn chuỗi).
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <button
            onClick={() => void load()}
            disabled={loading || !canRead}
            style={{ display: "flex", gap: 6, alignItems: "center", padding: "8px 14px", background: "var(--surface)", color: "var(--text)", border: "1px solid var(--border)", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer" }}
          >
            <RefreshCw size={15} /> Làm mới
          </button>
          <button
            onClick={exportCsv}
            disabled={entries.length === 0}
            style={{ display: "flex", gap: 6, alignItems: "center", padding: "8px 14px", background: "#137333", color: "#fff", border: "none", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer", opacity: entries.length ? 1 : 0.5 }}
          >
            <Download size={15} /> Xuất CSV
          </button>
        </div>
      </div>

      {error && canRead && (
        <div role="alert" style={{ background: "#FEF7E0", color: "#8A5B00", borderRadius: 12, padding: "10px 14px", fontSize: 13, marginBottom: 14 }}>
          {error}
        </div>
      )}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 12, marginBottom: 14 }}>
        {kpi("Điểm đã tích / hoàn", `+${formatNumber(totals.earned)}`, "#137333")}
        {kpi("Điểm đã đổi", `−${formatNumber(totals.redeemed)}`, "#B3261E")}
        {kpi("Điểm chỉnh tay (ròng)", `${totals.manual > 0 ? "+" : ""}${formatNumber(totals.manual)}`, "#1877F2")}
        {kpi("Số giao dịch", formatNumber(totals.count), "var(--text)")}
      </div>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center", marginBottom: 14, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px" }}>
        <select value={storeSel} onChange={(e) => setStoreSel(e.target.value)} style={input} aria-label="Chi nhánh">
          <option value="ALL">Tất cả chi nhánh</option>
          {stores.map((s) => (
            <option key={s.storeCode} value={s.storeCode}>{s.storeName || s.storeCode}</option>
          ))}
        </select>
        <div style={{ display: "flex", alignItems: "center", gap: 6, ...input, minWidth: 220 }}>
          <Search size={14} />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Khách, SĐT, mã HĐ, lý do..." style={{ border: "none", background: "transparent", outline: "none", width: "100%", fontSize: 13 }} />
        </div>
        <select value={type} onChange={(e) => setType(e.target.value)} style={input} aria-label="Loại">
          <option value="ALL">Tất cả loại</option>
          {LEDGER_KINDS.map((t) => (
            <option key={t} value={t}>{LEDGER_KIND_LABEL[t]}</option>
          ))}
        </select>
        <label style={{ fontSize: 12, color: "var(--subtext)" }}>Từ <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} style={input} /></label>
        <label style={{ fontSize: 12, color: "var(--subtext)" }}>Đến <input type="date" value={to} onChange={(e) => setTo(e.target.value)} style={input} /></label>
        {customerId && (
          <button onClick={() => setCustomerId("")} style={{ ...input, cursor: "pointer", color: "var(--primary)", fontWeight: 600 }}>
            Bỏ lọc khách: {entries.find((e) => e.customerId === customerId)?.memberName || customerId} ✕
          </button>
        )}
      </div>

      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ background: "var(--bg)" }}>
              <th style={th}>Thời gian</th>
              {showBranch && <th style={th}>Chi nhánh</th>}
              <th style={th}>Khách hàng</th>
              <th style={th}>Loại</th>
              <th style={{ ...th, textAlign: "right" }}>Biến động</th>
              <th style={{ ...th, textAlign: "right" }}>Số dư</th>
              <th style={th}>Hóa đơn / Lý do</th>
              <th style={th}>Người thực hiện</th>
            </tr>
          </thead>
          <tbody>
            {!canRead ? (
              <tr><td colSpan={cols + 1} style={{ ...td, textAlign: "center", padding: 32 }}>Vai trò của bạn không có quyền xem lịch sử điểm. Chỉ Quản lý/Chủ quán xem được.</td></tr>
            ) : loading ? (
              <tr><td colSpan={cols + 1} style={{ ...td, textAlign: "center", padding: 32 }}>Đang tải...</td></tr>
            ) : entries.length === 0 ? (
              <tr><td colSpan={cols + 1} style={{ ...td, textAlign: "center", padding: 32 }}>{error ? "Không có dữ liệu để hiển thị" : "Chưa có lịch sử điểm phù hợp"}</td></tr>
            ) : (
              entries.map((r) => (
                <tr key={`${r.memberKey}~${r.opId}`}>
                  <td style={{ ...td, whiteSpace: "nowrap" }}>{fmtTime(r.at)}</td>
                  {showBranch && <td style={{ ...td, fontFamily: "monospace" }}>{r.storeCode}</td>}
                  <td style={{ ...td, fontWeight: 600 }}>
                    {r.memberName || r.customerId || "—"}
                    {r.memberPhone && <div style={{ fontSize: 11, fontWeight: 400, color: "var(--subtext)" }}>{r.memberPhone}</div>}
                  </td>
                  <td style={td}>{ledgerKindLabel(r.type)}</td>
                  <td style={{ ...td, textAlign: "right", fontWeight: 800, color: r.points < 0 ? "#B3261E" : "#137333" }}>
                    {r.points > 0 ? "+" : ""}{formatNumber(r.points)}
                  </td>
                  <td style={{ ...td, textAlign: "right", color: "var(--subtext)" }}>{formatNumber(r.balanceAfter)}</td>
                  <td style={td}>
                    {r.billCode || r.billId ? <span style={{ fontFamily: "monospace" }}>{r.billCode || r.billId}</span> : r.note || "—"}
                    {(r.billCode || r.billId) && r.note ? <div style={{ fontSize: 11, color: "var(--subtext)" }}>{r.note}</div> : null}
                  </td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{r.staff || "—"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      {canRead && entries.length > 0 && (
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginTop: 10, fontSize: 12, color: "var(--subtext)" }}>
          <span>Đang hiển thị {formatNumber(entries.length)} / {formatNumber(totals.count)} giao dịch</span>
          {nextCursor && (
            <button onClick={() => void loadMore()} disabled={loadingMore} style={{ ...input, cursor: "pointer", fontWeight: 600 }}>
              {loadingMore ? "Đang tải..." : "Tải thêm"}
            </button>
          )}
        </div>
      )}
    </div>
  );
}
