"use client";
import { useMemo, useState } from "react";
import { Lock, Unlock, Wallet } from "lucide-react";
import { ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { hasPermission, useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { buildCloseShift, buildOpenShift, expectedCash, findOwnOpenShift, isShiftOpen, totalRevenue, type ShiftActor, type ShiftLike } from "@/lib/cash-shift";
import { shiftOwnedBy } from "@/lib/shift-scope";
import { errorMessage } from "@/lib/errors";
import { formatVND } from "@/lib/reports";
import { nowMs } from "@/lib/kitchen";
import { fetchOwnOpenShift } from "@/lib/cash-shift-run";

const card = { background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, padding: 18 } as const;
const input = { width: "100%", padding: "10px 12px", borderRadius: 8, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)", fontSize: 15 } as const;
const fmtTime = (ms?: number) => (ms ? new Date(ms).toLocaleString("vi-VN") : "—");

/** Ca / két của tài khoản đang đăng nhập: mở ca (tiền đầu ca) và chốt két cuối ca */
export default function MyShiftPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, cashShifts } = useDashboardData();
  const storeCode = currentStoreCode !== "ALL" && currentStoreCode ? currentStoreCode : user?.storeCode || stores[0]?.storeCode || "";
  const actor: ShiftActor = { uid: user?.uid || "", username: user?.username || "", fullName: user?.fullName, role: user?.roleId || user?.role };
  const canManage = hasPermission(user, "MANAGE_CASH_SHIFT");
  // Tổng quan két / số kỳ vọng / chênh lệch: chỉ Chủ/Quản lý (hoặc được cấp quyền); Nhân viên kiểm đếm mù
  const canViewOverview = hasPermission(user, "VIEW_SHIFT_HANDOVER") || hasPermission(user, "VIEW_ALL_SHIFTS") || hasPermission(user, "VIEW_REPORTS");

  const mine = useMemo(
    () => cashShifts.filter((s) => (s.storeCode || storeCode) === storeCode && shiftOwnedBy(s, { uid: actor.uid, username: actor.username })),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [cashShifts, storeCode, actor.uid, actor.username]
  );
  const open = findOwnOpenShift(mine, { uid: actor.uid, username: actor.username }, storeCode);
  const history = useMemo(() => mine.filter((s) => !isShiftOpen(s)).sort((a, b) => (b.openedAt || 0) - (a.openedAt || 0)).slice(0, 10), [mine]);

  const [initialCash, setInitialCash] = useState("");
  const [actualCash, setActualCash] = useState("");
  const [notes, setNotes] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");

  const run = async (build: () => { error: string } | { updates: Record<string, unknown> }, okMsg: string) => {
    setError("");
    setMessage("");
    const r = build();
    if ("error" in r) return setError(r.error);
    setBusy(true);
    try {
      await update(ref(db), r.updates);
      setMessage(okMsg);
      setInitialCash("");
      setActualCash("");
      setNotes("");
    } catch (e) {
      setError(errorMessage(e, "Không lưu được ca"));
    } finally {
      setBusy(false);
    }
  };

  const doOpen = async () => {
    const v = initialCash.trim() === "" ? 0 : Number(initialCash.replace(/[^0-9]/g, ""));
    setError("");
    setBusy(true);
    // Xoay ca nhiều cửa hàng: tra ca đang mở của chính mình ở MỌI cửa hàng có quyền
    const others: ShiftLike[] = [];
    try {
      for (const s of stores) {
        if (s.storeCode === storeCode) continue;
        try {
          const o = await fetchOwnOpenShift(db, s.storeCode, { uid: actor.uid, username: actor.username });
          if (o) others.push({ ...o, storeCode: s.storeCode });
        } catch {
          // cửa hàng không đọc được (không thuộc tài khoản) → bỏ qua
        }
      }
    } finally {
      setBusy(false);
    }
    return run(() => buildOpenShift({ storeCode, actor, initialCash: v, existing: [...mine, ...others], now: nowMs() }), "Đã mở ca. Chúc bạn bán hàng tốt!");
  };

  const doClose = () => {
    if (!open) return;
    if (actualCash.trim() === "") return setError("Vui lòng nhập số tiền mặt kiểm đếm thực tế trong két");
    const v = Number(actualCash.replace(/[^0-9]/g, ""));
    if (!confirm(`Chốt ca với ${formatVND(v)} tiền mặt thực tế ${canViewOverview ? `(hệ thống ghi nhận ${formatVND(expectedCash(open))})` : ""}?`)) return;
    return run(() => buildCloseShift({ storeCode, actor, shift: open, actualCash: v, notes, now: nowMs() }), "Đã chốt ca. Cảm ơn bạn!");
  };

  if (!canManage) {
    return <div style={{ padding: 32, color: "var(--subtext)" }}>Tài khoản của bạn không có quyền mở / chốt ca két.</div>;
  }

  const actualNum = actualCash.trim() === "" ? null : Number(actualCash.replace(/[^0-9]/g, ""));
  const stat = (label: string, value: string, color = "var(--text)") => (
    <div style={{ background: "var(--bg)", borderRadius: 10, padding: "10px 12px" }}>
      <div style={{ fontSize: 12, color: "var(--subtext)" }}>{label}</div>
      <div style={{ fontSize: 17, fontWeight: 800, color }}>{value}</div>
    </div>
  );

  return (
    <div style={{ padding: "24px 28px", maxWidth: 820, margin: "0 auto" }}>
      <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0, display: "flex", alignItems: "center", gap: 8 }}>
        <Wallet size={22} /> Ca / két của tôi
      </h1>
      <p style={{ fontSize: 13, color: "var(--subtext)", margin: "4px 0 16px" }}>
        Chi nhánh {storeCode || "—"} • {actor.fullName || actor.username}. Mỗi tài khoản có ca riêng; doanh số thanh toán trên Web được cộng vào ca đang mở của bạn.
      </p>

      {error && <div style={{ background: "#FDECEA", color: "#B3261E", padding: "10px 14px", borderRadius: 10, marginBottom: 12, fontSize: 13 }}>{error}</div>}
      {message && <div style={{ background: "var(--success-bg)", color: "#137333", padding: "10px 14px", borderRadius: 10, marginBottom: 12, fontSize: 13, fontWeight: 600 }}>{message}</div>}

      {!storeCode ? (
        <div style={card}>Chưa xác định được chi nhánh.</div>
      ) : !open ? (
        <div style={card}>
          <div style={{ fontWeight: 800, fontSize: 16, marginBottom: 4 }}>Bạn chưa mở ca</div>
          <div style={{ fontSize: 13, color: "var(--subtext)", marginBottom: 12 }}>Nhập số tiền mặt có trong két lúc bắt đầu ca.</div>
          <label style={{ fontSize: 13, fontWeight: 700 }}>Tiền đầu ca (VNĐ)</label>
          <input style={{ ...input, margin: "6px 0 12px" }} inputMode="numeric" value={initialCash} onChange={(e) => setInitialCash(e.target.value)} placeholder="0" />
          <button className="btn-primary" disabled={busy} onClick={doOpen} style={{ opacity: busy ? 0.6 : 1 }}>
            <Unlock size={16} /> {busy ? "Đang mở ca..." : "Mở ca"}
          </button>
        </div>
      ) : (
        <div style={card}>
          <div style={{ display: "flex", justifyContent: "space-between", flexWrap: "wrap", gap: 8, marginBottom: 12 }}>
            <div>
              <div style={{ fontWeight: 800, fontSize: 16 }}>Ca đang mở {open.shiftCode}</div>
              <div style={{ fontSize: 12, color: "var(--subtext)" }}>Mở lúc {fmtTime(open.openedAt)}</div>
            </div>
            <span style={{ background: "var(--success-bg)", color: "#137333", borderRadius: 14, padding: "4px 12px", fontSize: 12, fontWeight: 700, alignSelf: "flex-start" }}>ĐANG MỞ</span>
          </div>
          {canViewOverview && <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))", gap: 10, marginBottom: 14 }}>
            {stat("Tiền đầu ca", formatVND(open.initialCash || 0))}
            {stat("Bán tiền mặt", formatVND(open.totalCashSales || 0))}
            {stat("Bán chuyển khoản/QR", formatVND(open.totalQrSales || 0))}
            {stat("Bán thẻ/ví", formatVND(open.totalCardSales || 0))}
            {stat("Thu thêm / Chi vặt", `${formatVND(open.cashIn || 0)} / ${formatVND(open.cashOut || 0)}`)}
            {stat("Tổng doanh số ca", formatVND(totalRevenue(open)), "var(--primary)")}
            {stat("Tiền mặt dự kiến trong két", formatVND(expectedCash(open)), "#137333")}
          </div>}

          <div style={{ borderTop: "1px solid var(--border)", paddingTop: 14 }}>
            <div style={{ fontWeight: 800, marginBottom: 8 }}>Chốt ca / két</div>
            <label style={{ fontSize: 13, fontWeight: 700 }}>Tiền mặt thực tế kiểm đếm (VNĐ)</label>
            <input style={{ ...input, margin: "6px 0 6px" }} inputMode="numeric" value={actualCash} onChange={(e) => setActualCash(e.target.value)} placeholder="0" />
            {canViewOverview && actualNum !== null && (
              <div style={{ fontSize: 13, marginBottom: 8, color: actualNum - expectedCash(open) === 0 ? "#137333" : "#B3261E", fontWeight: 700 }}>
                Chênh lệch: {actualNum - expectedCash(open) > 0 ? "+" : ""}{formatVND(actualNum - expectedCash(open))}
                {actualNum - expectedCash(open) === 0 ? " (khớp)" : actualNum - expectedCash(open) > 0 ? " (thừa)" : " (thiếu)"}
              </div>
            )}
            <label style={{ fontSize: 13, fontWeight: 700 }}>Ghi chú</label>
            <textarea style={{ ...input, margin: "6px 0 12px", minHeight: 60 }} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="VD: thiếu 10k do thối nhầm" />
            <button className="btn-primary" disabled={busy} onClick={doClose} style={{ opacity: busy ? 0.6 : 1 }}>
              <Lock size={16} /> {busy ? "Đang chốt..." : "Chốt ca"}
            </button>
          </div>
        </div>
      )}

      {history.length > 0 && (
        <div style={{ ...card, marginTop: 16, overflowX: "auto" }}>
          <div style={{ fontWeight: 800, marginBottom: 8 }}>Các ca gần đây của bạn</div>
          <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
            <thead>
              <tr style={{ textAlign: "left", color: "var(--subtext)" }}>
                <th style={{ padding: "6px 8px" }}>Ca</th>
                <th style={{ padding: "6px 8px" }}>Mở / Chốt</th>
                <th style={{ padding: "6px 8px", textAlign: "right" }}>Doanh số</th>
                {canViewOverview && <th style={{ padding: "6px 8px", textAlign: "right" }}>Chênh lệch</th>}
              </tr>
            </thead>
            <tbody>
              {history.map((s) => (
                <tr key={s.id} style={{ borderTop: "1px solid var(--border)" }}>
                  <td style={{ padding: "6px 8px", fontFamily: "monospace" }}>{s.shiftCode}</td>
                  <td style={{ padding: "6px 8px" }}>{fmtTime(s.openedAt)} → {fmtTime(s.closedAt)}</td>
                  <td style={{ padding: "6px 8px", textAlign: "right" }}>{formatVND(totalRevenue(s))}</td>
                  {canViewOverview && <td style={{ padding: "6px 8px", textAlign: "right", fontWeight: 700, color: (s.difference || 0) === 0 ? "#137333" : "#B3261E" }}>{formatVND(s.difference || 0)}</td>}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
