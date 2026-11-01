"use client";
import { useState } from "react";
import Link from "next/link";
import { AlertTriangle, ArrowLeft, CheckCircle2, Download, RotateCcw, Search } from "lucide-react";
import { get, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { useDashboardData } from "@/lib/data-context";
import { useAuth, normalizeRoleId, ROLE_OWNER } from "@/lib/auth";
import { errorMessage } from "@/lib/errors";
import { nowMs } from "@/lib/kitchen";
import { RESET_GROUPS, buildResetPlan, orderedChunks, type ResetPlan } from "@/lib/sales-reset";

type Loaded = { storeCode: string; data: Record<string, Record<string, unknown> | null>; tables: Record<string, unknown> | null; at: number };

const box = { background: "var(--surface)", border: "1px solid var(--border)", borderRadius: "14px", padding: "16px", marginBottom: "14px" } as const;

/** Reset dữ liệu bán hàng (bắt đầu vận hành lại) — chỉ Chủ quán. Bắt buộc tải bản sao lưu trước khi xóa. */
export default function ResetSalesDataPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();
  const [groups, setGroups] = useState<string[]>(RESET_GROUPS.filter((g) => g.defaultOn).map((g) => g.key));
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [backedUp, setBackedUp] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [done, setDone] = useState<ResetPlan | null>(null);

  const isOwner = !!user && (user.isRootOwner || normalizeRoleId(user.roleId || user.role || "") === ROLE_OWNER);
  if (!isOwner) {
    return <div style={{ ...box, padding: 24 }}>Chỉ Chủ quán được reset dữ liệu bán hàng.</div>;
  }
  if (!currentStoreCode || currentStoreCode === "ALL") {
    return <div style={{ ...box, padding: 24 }}>Chọn MỘT cửa hàng ở thanh trên cùng trước khi reset dữ liệu.</div>;
  }
  const storeCode = currentStoreCode;
  const storeName = stores.find((s) => s.storeCode === storeCode)?.storeName || storeCode;
  const fresh = loaded?.storeCode === storeCode ? loaded : null;
  const plan = fresh ? buildResetPlan(storeCode, groups, fresh.data, fresh.tables) : null;
  const totalDeleted = plan ? Object.values(plan.counts).reduce((s, n) => s + n, 0) : 0;

  const reset = () => {
    setBackedUp(false);
    setConfirmText("");
    setDone(null);
  };

  const scan = async () => {
    setBusy("Đang đọc dữ liệu…");
    setError("");
    reset();
    try {
      const nodes = [...new Set(RESET_GROUPS.flatMap((g) => g.nodes))];
      const snaps = await Promise.all(nodes.map((n) => get(ref(db, `stores/${storeCode}/${n}`)).then((s) => [n, s.val()] as const).catch(() => [n, null] as const)));
      const tables = (await get(ref(db, `stores/${storeCode}/tables`))).val();
      setLoaded({ storeCode, data: Object.fromEntries(snaps), tables, at: nowMs() });
    } catch (e) {
      setError(`Không đọc được dữ liệu: ${errorMessage(e)}`);
    } finally {
      setBusy("");
    }
  };

  const downloadBackup = () => {
    if (!fresh) return;
    const nodes = RESET_GROUPS.filter((g) => groups.includes(g.key)).flatMap((g) => g.nodes);
    const payload = {
      storeCode,
      storeName,
      exportedAt: new Date().toISOString(),
      note: "Bản sao lưu trước khi reset dữ liệu bán hàng (POS Trạm). Giữ file này để đối soát hoặc khôi phục.",
      data: Object.fromEntries(nodes.map((n) => [n, fresh.data[n] ?? null])),
      tables: fresh.tables,
    };
    const blob = new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    const d = new Date();
    a.download = `saoluu_${storeCode}_${d.getFullYear()}${String(d.getMonth() + 1).padStart(2, "0")}${String(d.getDate()).padStart(2, "0")}_${String(d.getHours()).padStart(2, "0")}${String(d.getMinutes()).padStart(2, "0")}.json`;
    a.click();
    URL.revokeObjectURL(a.href);
    setBackedUp(true);
  };

  const run = async () => {
    if (!plan || !user || confirmText.trim().toUpperCase() !== storeCode.toUpperCase()) return;
    setError("");
    const chunks = orderedChunks(plan.updates);
    try {
      for (let i = 0; i < chunks.length; i++) {
        setBusy(`Đang xóa… ${i + 1}/${chunks.length}`);
        await update(ref(db), chunks[i]);
      }
      const now = nowMs();
      await update(ref(db), {
        [`stores/${storeCode}/audit_logs/log_${now}_reset`]: {
          timestamp: now,
          username: user.username || "owner",
          userFullName: user.fullName || user.username || "Chủ quán",
          userRole: normalizeRoleId(user.roleId || user.role || "") || "OWNER",
          action: "RESET_SALES_DATA",
          targetType: "STORE",
          targetId: storeCode,
          storeCode,
          isSuspicious: true,
          details: `Reset dữ liệu bán hàng cửa hàng ${storeCode}: ${Object.entries(plan.counts).map(([n, c]) => `${n} ${c}`).join(", ")}; trả ${plan.tablesCleared} bàn về trống, xóa ${plan.tablesRemoved} bàn tách.`,
        },
      }).catch(() => undefined);
      setDone(plan);
      setLoaded(null);
    } catch (e) {
      setError(`Dừng giữa chừng: ${errorMessage(e)}. Bấm "Kiểm tra dữ liệu" lại để xem phần còn lại rồi chạy tiếp.`);
    } finally {
      setBusy("");
    }
  };

  return (
    <div style={{ maxWidth: "860px", margin: "0 auto" }}>
      <Link href="/dashboard/settings" style={{ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: "13px", color: "var(--subtext)", marginBottom: "10px" }}>
        <ArrowLeft size={14} /> Cài đặt cửa hàng
      </Link>
      <h1 style={{ fontSize: "22px", fontWeight: 800, margin: "0 0 4px", color: "var(--text)" }}>Reset dữ liệu bán hàng</h1>
      <p style={{ fontSize: "13px", color: "var(--subtext)", margin: "0 0 14px" }}>
        Cửa hàng <b>{storeCode} - {storeName}</b>. Dùng khi bắt đầu vận hành lại từ đầu (xóa đơn bấm thử / dữ liệu cũ).
      </p>

      <div style={{ ...box, borderColor: "var(--danger)", display: "flex", gap: "10px", color: "var(--danger)", fontSize: "13px", fontWeight: 600 }}>
        <AlertTriangle size={18} style={{ flexShrink: 0 }} />
        <div>
          Xóa VĨNH VIỄN, không hoàn tác được. Doanh thu, báo cáo, ca két của những ngày đã qua sẽ mất. Làm lúc quán chưa bán
          (không ai đang bấm đơn trên app). Bắt buộc tải bản sao lưu trước khi xóa.
        </div>
      </div>

      <div style={box}>
        <div style={{ fontWeight: 800, fontSize: "14px", marginBottom: "8px" }}>1. Chọn dữ liệu cần xóa</div>
        {RESET_GROUPS.map((g) => (
          <label key={g.key} style={{ display: "flex", alignItems: "center", gap: "8px", padding: "5px 0", fontSize: "13px" }}>
            <input
              type="checkbox"
              checked={groups.includes(g.key)}
              onChange={(e) => {
                reset();
                setGroups((prev) => (e.target.checked ? [...prev, g.key] : prev.filter((k) => k !== g.key)));
              }}
            />
            <span>
              {g.label}
              {plan && <span style={{ color: "var(--subtext)" }}> — {g.nodes.reduce((s, n) => s + (plan.counts[n] ?? 0), 0) || (groups.includes(g.key) ? 0 : "")}</span>}
            </span>
          </label>
        ))}
        <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "6px" }}>
          Luôn kèm: đưa mọi bàn về <b>trống</b> (bỏ món đang gọi, đặt trước, khách gắn bàn); bàn tách tạm như &quot;Bàn 01 (2)&quot; bị xóa.
          <br />
          Giữ nguyên: thực đơn, bàn & khu vực, nhân viên, khách hàng & điểm, kho & tồn kho, chương trình khuyến mãi, nhật ký kiểm soát.
        </div>
      </div>

      <div style={box}>
        <div style={{ fontWeight: 800, fontSize: "14px", marginBottom: "8px" }}>2. Kiểm tra & sao lưu</div>
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
          <button className="btn-secondary" onClick={scan} disabled={!!busy}>
            <Search size={15} /> Kiểm tra dữ liệu
          </button>
          <button className="btn-secondary" onClick={downloadBackup} disabled={!plan || !!busy}>
            <Download size={15} /> Tải bản sao lưu (.json)
          </button>
        </div>
        {plan && (
          <div style={{ marginTop: "10px", fontSize: "13px" }}>
            Sẽ xóa <b>{totalDeleted.toLocaleString("vi-VN")}</b> mục ({Object.entries(plan.counts).filter(([, c]) => c > 0).map(([n, c]) => `${n}: ${c}`).join(", ") || "không có"}),
            trả <b>{plan.tablesCleared}</b> bàn về trống{plan.tablesRemoved ? `, xóa ${plan.tablesRemoved} bàn tách` : ""}.
            {backedUp && <span style={{ color: "var(--success)", fontWeight: 700 }}> • Đã tải bản sao lưu</span>}
          </div>
        )}
      </div>

      <div style={box}>
        <div style={{ fontWeight: 800, fontSize: "14px", marginBottom: "8px" }}>3. Xác nhận</div>
        <label style={{ display: "block", fontSize: "13px", marginBottom: "6px" }}>
          Gõ mã cửa hàng <b>{storeCode}</b> để xác nhận:
        </label>
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
          <input className="input-field" style={{ flex: "1 1 180px" }} value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder={storeCode} disabled={!backedUp} />
          <button
            className="btn-primary"
            style={{ background: "var(--danger)" }}
            disabled={!plan || !backedUp || !!busy || confirmText.trim().toUpperCase() !== storeCode.toUpperCase()}
            onClick={run}
          >
            <RotateCcw size={15} /> Xóa & bắt đầu lại
          </button>
        </div>
        {!backedUp && <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "6px" }}>Kiểm tra dữ liệu và tải bản sao lưu trước.</div>}
      </div>

      {busy && <div style={{ ...box, fontSize: "13px" }}>{busy}</div>}
      {error && <div style={{ ...box, color: "var(--danger)", fontSize: "13px", fontWeight: 600 }}>{error}</div>}
      {done && (
        <div style={{ ...box, borderColor: "var(--success)", color: "var(--success)", fontSize: "13px", fontWeight: 600, display: "flex", gap: "8px" }}>
          <CheckCircle2 size={18} style={{ flexShrink: 0 }} />
          <div>
            Đã reset xong: xóa {Object.values(done.counts).reduce((s, n) => s + n, 0).toLocaleString("vi-VN")} mục, trả {done.tablesCleared} bàn về trống.
            Trên máy POS, thoát ra vào lại màn bàn (hoặc mở lại app) để làm mới. Ca mới mở như bình thường.
          </div>
        </div>
      )}
    </div>
  );
}
