"use client";
/**
 * Nhập khách hàng từ file Excel KiotViet (DanhSachKhachHang_KV...xlsx, chọn được nhiều file).
 * - Xem trước: khách mới / đã có trong POS (bỏ qua, không đè điểm) / trùng giữa các file / dòng lỗi.
 * - Tạo khách như nút "Thêm khách" (cùng các chi nhánh), rồi chuyển "Điểm hiện tại" KiotViet qua Cloud Function
 *   adjustLoyaltyPoints (sổ điểm + nhật ký; khóa chống trùng theo SĐT → bấm lại không cộng lần 2).
 */
import { useState } from "react";
import { FileUp } from "lucide-react";
import { ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { buildNewCustomerNode } from "@/lib/loyalty";
import { adjustLoyaltyPoints } from "@/lib/loyalty-client";
import { kvPointsOpId, parseKvSheet, planKvImport, type KvCustomer, type KvImportPlan } from "@/lib/kiotviet-customers";
import { errorMessage } from "@/lib/errors";
import ModalShell, { btnGhost, btnPrimary, errorBox } from "@/components/ModalShell";

interface Props {
  /** Chi nhánh ghi khách (giống "Thêm khách") — chi nhánh đầu dùng để chỉnh điểm */
  targetStores: string[];
  existingPhones: string[];
  /** Có quyền chỉnh điểm (ADJUST_POINTS) → được chuyển điểm KiotViet */
  canTransferPoints: boolean;
  actor: { username: string; fullName?: string; role?: string };
  onClose: () => void;
  onDone: (message: string) => void;
}

export default function KiotVietImportDialog({ targetStores, existingPhones, canTransferPoints, actor, onClose, onDone }: Props) {
  const [plan, setPlan] = useState<KvImportPlan | null>(null);
  const [files, setFiles] = useState<string[]>([]);
  const [wantPoints, setWithPoints] = useState(true);
  const withPoints = wantPoints && canTransferPoints;
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const [error, setError] = useState("");
  const [failed, setFailed] = useState<{ c: KvCustomer; id: string; err: string }[]>([]);

  const readFiles = async (list: FileList | null) => {
    if (!list || list.length === 0) return;
    setError("");
    setPlan(null);
    try {
      const XLSX = await import("xlsx");
      const sheets = [];
      for (const f of Array.from(list)) {
        const wb = XLSX.read(await f.arrayBuffer(), { cellDates: true });
        const ws = wb.Sheets[wb.SheetNames[0]];
        const rows = XLSX.utils.sheet_to_json(ws, { header: 1, raw: true, defval: null }) as unknown[][];
        sheets.push(parseKvSheet(rows, f.name));
      }
      setFiles(Array.from(list).map((f) => f.name));
      setPlan(planKvImport(sheets, existingPhones));
    } catch (e) {
      setError(errorMessage(e, "Không đọc được file Excel"));
    }
  };

  /** Chuyển điểm (4 luồng song song); trả về các khách chưa chuyển được */
  const transferPoints = async (items: { c: KvCustomer; id: string }[]) => {
    const bad: { c: KvCustomer; id: string; err: string }[] = [];
    let done = 0;
    const queue = [...items];
    const worker = async () => {
      for (let x = queue.shift(); x; x = queue.shift()) {
        try {
          await adjustLoyaltyPoints(targetStores[0], { customerId: x.id }, "ADD", x.c.points, "Chuyển điểm từ KiotViet (nhập Excel)", kvPointsOpId(x.c.phone));
        } catch (e) {
          bad.push({ ...x, err: errorMessage(e, "lỗi") });
        }
        done++;
        setProgress(`Đang chuyển điểm ${done}/${items.length}…`);
      }
    };
    await Promise.all([worker(), worker(), worker(), worker()]);
    setFailed(bad);
    return bad;
  };

  const retryPoints = async () => {
    setBusy(true);
    try {
      const bad = await transferPoints(failed);
      setProgress(bad.length ? `Còn ${bad.length} khách chưa chuyển được điểm` : "Đã chuyển điểm xong cho các khách còn lại");
    } finally {
      setBusy(false);
    }
  };

  const run = async () => {
    if (!plan || plan.toCreate.length === 0 || targetStores.length === 0) return;
    setBusy(true);
    setError("");
    setFailed([]);
    const now = Date.now();
    const created: { c: KvCustomer; id: string }[] = [];
    try {
      // 1. Tạo khách (từng nhóm 50 khách / lần ghi)
      for (let i = 0; i < plan.toCreate.length; i += 50) {
        const chunk = plan.toCreate.slice(i, i + 50);
        const updates: Record<string, unknown> = {};
        chunk.forEach((c, k) => {
          const id = `CUST_${now}_${i + k}`;
          for (const st of targetStores) {
            updates[`stores/${st}/customers/${id}`] = {
              ...buildNewCustomerNode(id, { name: c.name, phone: c.phone, gender: c.gender, birthday: c.birthday }, now),
              ...(c.kvCode ? { kiotVietCode: c.kvCode } : {}),
              importedFrom: "kiotviet_excel",
            };
          }
          created.push({ c, id });
        });
        setProgress(`Đang tạo khách ${Math.min(i + 50, plan.toCreate.length)}/${plan.toCreate.length}…`);
        await update(ref(db), updates);
      }
      const log = {
        timestamp: now,
        username: actor.username,
        userFullName: actor.fullName || actor.username,
        userRole: actor.role || "",
        action: "CUSTOMER_IMPORT_KIOTVIET",
        targetType: "CUSTOMER",
        targetId: files.join(", ").slice(0, 200),
        details: `Nhập ${created.length} khách từ Excel KiotViet (${files.join(", ")}) qua Web Admin`,
      };
      await update(ref(db), Object.fromEntries(targetStores.map((st) => [`stores/${st}/audit_logs/log_${now}_kvimport`, { ...log, storeCode: st }])));

      // 2. Chuyển điểm KiotViet (máy chủ ghi sổ điểm; khóa theo SĐT nên chạy lại không cộng 2 lần)
      const bad = withPoints ? await transferPoints(created.filter((x) => x.c.points > 0)) : [];
      const pts = created.reduce((s, x) => s + (withPoints ? x.c.points : 0), 0);
      const msg = `Đã nhập ${created.length} khách từ KiotViet${withPoints ? ` (chuyển ${pts.toLocaleString("vi-VN")} điểm)` : ""}${bad.length ? ` — ${bad.length} khách chưa chuyển được điểm` : ""}`;
      setProgress(msg);
      if (bad.length === 0) onDone(msg);
    } catch (e) {
      setError(`${errorMessage(e, "Nhập khách bị lỗi")}${created.length ? ` (đã tạo ${created.length} khách trước khi lỗi)` : ""}`);
    } finally {
      setBusy(false);
    }
  };

  const stat = (label: string, n: number, color?: string) => (
    <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, padding: "4px 0" }}>
      <span>{label}</span>
      <b style={{ color }}>{n}</b>
    </div>
  );
  const totalPts = plan?.toCreate.reduce((s, c) => s + c.points, 0) ?? 0;

  return (
    <ModalShell
      title="Nhập khách hàng từ KiotViet"
      subtitle={`File Excel "Danh sách khách hàng" xuất từ KiotViet • ghi vào ${targetStores.join(", ")}`}
      icon={<FileUp size={18} />}
      maxWidth={560}
      onClose={busy ? () => {} : onClose}
      footer={
        <>
          <button type="button" style={btnGhost} onClick={onClose} disabled={busy}>
            Đóng
          </button>
          <button type="button" style={btnPrimary} onClick={run} disabled={busy || !plan || plan.toCreate.length === 0}>
            {busy ? "Đang nhập…" : `Nhập ${plan?.toCreate.length ?? 0} khách`}
          </button>
        </>
      }
    >
      <input type="file" accept=".xlsx,.xls" multiple disabled={busy} onChange={(e) => readFiles(e.target.files)} style={{ fontSize: 13, marginBottom: 12 }} />
      {error && <div style={errorBox}>{error}</div>}
      {plan && (
        <div style={{ border: "1px solid var(--border)", borderRadius: 10, padding: "8px 12px", marginBottom: 12 }}>
          {stat("Khách mới sẽ tạo", plan.toCreate.length, "var(--success, #137333)")}
          {stat("Đã có trong POS (theo SĐT) — bỏ qua, giữ nguyên điểm", plan.existing.length)}
          {stat("Trùng SĐT giữa các dòng / file — đã gộp", plan.duplicates.length)}
          {stat("Dòng lỗi (thiếu tên / SĐT sai) — bỏ qua", plan.invalid.length, plan.invalid.length ? "var(--danger)" : undefined)}
          {stat("Tổng điểm KiotViet của khách mới", totalPts)}
        </div>
      )}
      {plan && plan.invalid.length > 0 && (
        <div style={{ fontSize: 12, color: "var(--danger)", marginBottom: 12 }}>
          {plan.invalid.map((x, i) => (
            <div key={i}>
              {x.file} dòng {x.row}: {x.name || "(không tên)"} — {x.reason}
            </div>
          ))}
        </div>
      )}
      {canTransferPoints ? (
        <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <input type="checkbox" checked={wantPoints} disabled={busy} onChange={(e) => setWithPoints(e.target.checked)} />
          Chuyển &quot;Điểm hiện tại&quot; từ KiotViet sang POS (ghi sổ điểm, lý do &quot;Chuyển điểm từ KiotViet&quot;)
        </label>
      ) : (
        <div style={{ fontSize: 12, color: "var(--subtext)" }}>Tài khoản không có quyền chỉnh điểm: chỉ tạo khách (0 điểm), không chuyển điểm KiotViet.</div>
      )}
      {progress && <div style={{ fontSize: 13, fontWeight: 600, marginTop: 12 }}>{progress}</div>}
      {failed.length > 0 && (
        <div style={{ fontSize: 12, color: "var(--danger)", marginTop: 8 }}>
          Chưa chuyển được điểm (khách đã được tạo):
          {failed.map((f) => (
            <div key={f.id}>
              {f.c.name} ({f.c.phone}, {f.c.points} điểm): {f.err}
            </div>
          ))}
          <button type="button" style={{ ...btnGhost, marginTop: 8 }} onClick={retryPoints} disabled={busy}>
            Thử lại chuyển điểm
          </button>
        </div>
      )}
    </ModalShell>
  );
}
