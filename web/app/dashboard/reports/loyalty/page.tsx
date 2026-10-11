"use client";
import { Suspense, useEffect, useMemo, useState } from "react";
import { useSearchParams } from "next/navigation";
import { Download, History, Search } from "lucide-react";
import { ref, onValue } from "firebase/database";
import { db } from "@/lib/firebase";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { canReadCustomers, parseStoreCustomers } from "@/lib/customers";
import {
  POINT_TYPE_LABEL,
  parseLoyaltyLedger,
  parsePointHistory,
  sortHistoryDesc,
  summarizeHistory,
  type PointHistoryRow,
} from "@/lib/loyalty";
import { formatNumber } from "@/lib/reports";

const th = { padding: "10px 12px", textAlign: "left", fontSize: 12, color: "var(--subtext)", whiteSpace: "nowrap" } as const;
const td = { padding: "9px 12px", fontSize: 13, borderTop: "1px solid var(--border)" } as const;

const fmtTime = (ms: number) => (ms > 0 ? new Date(ms).toLocaleString("vi-VN") : "—");
const dayStart = (v: string) => (v ? new Date(`${v}T00:00:00`).getTime() : 0);
const dayEnd = (v: string) => (v ? new Date(`${v}T23:59:59.999`).getTime() : Infinity);

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

  const codes = useMemo(
    () => (currentStoreCode !== "ALL" && currentStoreCode ? [currentStoreCode] : stores.map((s) => s.storeCode).filter(Boolean)),
    [stores, currentStoreCode]
  );
  const codesKey = codes.join(",");

  const [ledger, setLedger] = useState<Record<string, unknown>>({});
  const [manual, setManual] = useState<Record<string, unknown>>({});
  const [custRaw, setCustRaw] = useState<Record<string, unknown>>({});
  const [loaded, setLoaded] = useState(false);
  const [denied, setDenied] = useState<string[]>([]);

  const [search, setSearch] = useState("");
  const [type, setType] = useState<"ALL" | PointHistoryRow["type"]>("ALL");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  // Mở từ nút "Lịch sử" ở trang Khách hàng: ?store=...&customer=...
  const [customerId, setCustomerId] = useState(params.get("customer") || "");
  const [storeFilter, setStoreFilter] = useState(params.get("store") || "");

  useEffect(() => {
    if (!canRead || !codesKey) return;
    const list = codesKey.split(",");
    let pending = list.length * 3;
    const done = () => {
      pending -= 1;
      if (pending <= 0) setLoaded(true);
    };
    const unsubs: (() => void)[] = [];
    const listen = (path: string, set: (v: (p: Record<string, unknown>) => Record<string, unknown>) => void, code: string) => {
      let first = true;
      unsubs.push(
        onValue(
          ref(db, `stores/${code}/${path}`),
          (snap) => {
            set((p) => ({ ...p, [code]: snap.val() }));
            if (first) { first = false; done(); }
          },
          () => {
            setDenied((d) => (d.includes(code) ? d : [...d, code]));
            if (first) { first = false; done(); }
          }
        )
      );
    };
    list.forEach((code) => {
      listen("loyalty_applied", setLedger, code);
      listen("point_history", setManual, code);
      listen("customers", setCustRaw, code);
    });
    return () => unsubs.forEach((u) => u());
  }, [canRead, codesKey]);

  const names = useMemo(() => {
    const map = new Map<string, string>();
    codes.forEach((code) => parseStoreCustomers(code, custRaw[code]).forEach((c) => map.set(`${code}:${c.id}`, c.hoTen)));
    return map;
  }, [codes, custRaw]);

  const rows = useMemo(() => {
    const all: PointHistoryRow[] = [];
    codes.forEach((code) => {
      all.push(...parseLoyaltyLedger(code, ledger[code]), ...parsePointHistory(code, manual[code]));
    });
    return sortHistoryDesc(all);
  }, [codes, ledger, manual]);

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    const f = dayStart(from);
    const t = dayEnd(to);
    return rows.filter((r) => {
      if (storeFilter && r.storeCode !== storeFilter) return false;
      if (customerId && r.customerId !== customerId) return false;
      if (type !== "ALL" && r.type !== type) return false;
      if (r.at < f || r.at > t) return false;
      if (q) {
        const name = names.get(`${r.storeCode}:${r.customerId}`) || "";
        if (!`${name} ${r.customerId} ${r.billId ?? ""} ${r.reason ?? ""} ${r.by}`.toLowerCase().includes(q)) return false;
      }
      return true;
    });
  }, [rows, search, type, from, to, customerId, storeFilter, names]);

  const sum = useMemo(() => summarizeHistory(filtered), [filtered]);

  const exportCsv = () => {
    const esc = (v: unknown) => `"${String(v ?? "").replace(/"/g, '""')}"`;
    const head = ["Thời gian", "Chi nhánh", "Khách hàng", "Loại", "Biến động", "Trước", "Sau", "Hóa đơn", "Lý do", "Người thực hiện"];
    const lines = filtered.map((r) =>
      [fmtTime(r.at), r.storeCode, names.get(`${r.storeCode}:${r.customerId}`) || r.customerId, POINT_TYPE_LABEL[r.type], r.delta, r.before, r.after, r.billId, r.reason, r.by]
        .map(esc)
        .join(",")
    );
    const blob = new Blob(["﻿" + [head.map(esc).join(","), ...lines].join("\n")], { type: "text/csv;charset=utf-8" });
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

  return (
    <div style={{ padding: "24px 28px", maxWidth: 1280, margin: "0 auto" }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "center", marginBottom: 14 }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0, display: "flex", gap: 8, alignItems: "center" }}>
            <History size={22} /> Lịch sử sử dụng điểm khách hàng
          </h1>
          <p style={{ fontSize: 13, color: "var(--subtext)", margin: "4px 0 0" }}>
            Đổi điểm, tích điểm, hoàn điểm theo hóa đơn (từ POS) và các lần Chủ/Quản lý chỉnh điểm.
          </p>
        </div>
        <button
          onClick={exportCsv}
          disabled={filtered.length === 0}
          style={{ display: "flex", gap: 6, alignItems: "center", padding: "8px 14px", background: "#137333", color: "#fff", border: "none", borderRadius: 8, fontSize: 13, fontWeight: 600, cursor: "pointer", opacity: filtered.length ? 1 : 0.5 }}
        >
          <Download size={15} /> Xuất CSV
        </button>
      </div>

      {denied.length > 0 && (
        <div style={{ background: "#FEF7E0", color: "#8A5B00", borderRadius: 12, padding: "10px 14px", fontSize: 13, marginBottom: 14 }}>
          Không đọc được dữ liệu điểm của chi nhánh: {denied.join(", ")}
        </div>
      )}

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: 12, marginBottom: 14 }}>
        {kpi("Điểm đã tích / hoàn", `+${formatNumber(sum.earned)}`, "#137333")}
        {kpi("Điểm đã đổi", `−${formatNumber(sum.redeemed)}`, "#B3261E")}
        {kpi("Điểm chỉnh tay (ròng)", `${sum.adjusted > 0 ? "+" : ""}${formatNumber(sum.adjusted)}`, "#1877F2")}
        {kpi("Số giao dịch", formatNumber(filtered.length), "var(--text)")}
      </div>

      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "center", marginBottom: 14, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 12, padding: "12px 16px" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 6, ...input, minWidth: 220 }}>
          <Search size={14} />
          <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Khách, mã HĐ, lý do..." style={{ border: "none", background: "transparent", outline: "none", width: "100%", fontSize: 13 }} />
        </div>
        <select value={type} onChange={(e) => setType(e.target.value as typeof type)} style={input}>
          <option value="ALL">Tất cả loại</option>
          {(Object.keys(POINT_TYPE_LABEL) as PointHistoryRow["type"][]).map((t) => (
            <option key={t} value={t}>{POINT_TYPE_LABEL[t]}</option>
          ))}
        </select>
        <label style={{ fontSize: 12, color: "var(--subtext)" }}>Từ <input type="date" value={from} onChange={(e) => setFrom(e.target.value)} style={input} /></label>
        <label style={{ fontSize: 12, color: "var(--subtext)" }}>Đến <input type="date" value={to} onChange={(e) => setTo(e.target.value)} style={input} /></label>
        {(customerId || storeFilter) && (
          <button
            onClick={() => { setCustomerId(""); setStoreFilter(""); }}
            style={{ ...input, cursor: "pointer", color: "var(--primary)", fontWeight: 600 }}
          >
            Bỏ lọc khách: {names.get(`${storeFilter}:${customerId}`) || customerId} ✕
          </button>
        )}
      </div>

      <div style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead>
            <tr style={{ background: "var(--bg)" }}>
              <th style={th}>Thời gian</th>
              {codes.length > 1 && <th style={th}>Chi nhánh</th>}
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
              <tr><td colSpan={8} style={{ ...td, textAlign: "center", padding: 32 }}>Vai trò của bạn không có quyền xem dữ liệu khách hàng</td></tr>
            ) : !loaded ? (
              <tr><td colSpan={8} style={{ ...td, textAlign: "center", padding: 32 }}>Đang tải...</td></tr>
            ) : filtered.length === 0 ? (
              <tr><td colSpan={8} style={{ ...td, textAlign: "center", padding: 32 }}>Chưa có lịch sử điểm phù hợp</td></tr>
            ) : (
              filtered.slice(0, 1000).map((r) => (
                <tr key={r.key}>
                  <td style={{ ...td, whiteSpace: "nowrap" }}>{fmtTime(r.at)}</td>
                  {codes.length > 1 && <td style={{ ...td, fontFamily: "monospace" }}>{r.storeCode}</td>}
                  <td style={{ ...td, fontWeight: 600 }}>{names.get(`${r.storeCode}:${r.customerId}`) || r.customerId || "—"}</td>
                  <td style={td}>{POINT_TYPE_LABEL[r.type]}</td>
                  <td style={{ ...td, textAlign: "right", fontWeight: 800, color: r.delta < 0 ? "#B3261E" : "#137333" }}>
                    {r.delta > 0 ? "+" : ""}{formatNumber(r.delta)}
                  </td>
                  <td style={{ ...td, textAlign: "right", color: "var(--subtext)" }}>{formatNumber(r.before)} → {formatNumber(r.after)}</td>
                  <td style={td}>{r.billId ? <span style={{ fontFamily: "monospace" }}>{r.billId}</span> : r.reason || "—"}</td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{r.by || "—"}</td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
      {filtered.length > 1000 && (
        <p style={{ fontSize: 12, color: "var(--subtext)", marginTop: 8 }}>Hiển thị 1.000 dòng mới nhất — dùng bộ lọc hoặc xuất CSV để xem đủ.</p>
      )}
    </div>
  );
}
