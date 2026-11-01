"use client";
import { useEffect, useState } from "react";
import { get, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { errorMessage } from "@/lib/errors";
import { nowMs } from "@/lib/kitchen";
import { menuDedupeUpdates, planMenuDedupe, type DupGroup } from "@/lib/menu-dedupe";
import ModalShell, { btnGhost, errorBox } from "./ModalShell";

const fmt = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

/** Xem trước & dọn món trùng mã của MỘT chi nhánh (đọc dữ liệu tươi từ RTDB khi mở) */
export default function MenuDedupeDialog({
  storeCode,
  actor,
  onClose,
}: {
  storeCode: string;
  actor: { username?: string; fullName?: string };
  onClose: () => void;
}) {
  const [groups, setGroups] = useState<DupGroup[] | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState("");

  useEffect(() => {
    let alive = true;
    Promise.all([get(ref(db, `stores/${storeCode}/products`)), get(ref(db, `stores/${storeCode}/catalog_items`)).catch(() => null)])
      .then(([p, c]) => {
        if (!alive) return;
        const g = planMenuDedupe(p.val(), c?.val() ?? null);
        setGroups(g);
        setPicked(new Set(g.map((x) => x.code)));
      })
      .catch((e) => alive && setError(`Không đọc được thực đơn: ${errorMessage(e)}`));
    return () => {
      alive = false;
    };
  }, [storeCode]);

  const run = async () => {
    if (!groups) return;
    const chosen = groups.filter((g) => picked.has(g.code));
    if (chosen.length === 0) return;
    setBusy(true);
    setError("");
    try {
      const now = nowMs();
      const removed = chosen.reduce((s, g) => s + g.remove.length, 0);
      await update(ref(db), {
        ...menuDedupeUpdates(storeCode, chosen),
        [`stores/${storeCode}/audit_logs/log_${now}_dedupe`]: {
          timestamp: now,
          username: actor.username || "admin_web",
          userFullName: actor.fullName || actor.username || "Quản trị viên Web",
          action: "DEDUPE_MENU",
          targetType: "PRODUCT",
          targetId: storeCode,
          storeCode,
          details: `Dọn ${removed} món trùng mã: ${chosen.map((g) => `${g.code} ${g.name}`).join(", ")}`,
        },
      });
      setDone(`Đã xóa ${removed} bản trùng của ${chosen.length} món. Trên máy POS mở lại màn gọi món để làm mới thực đơn.`);
      setGroups(groups.filter((g) => !picked.has(g.code)));
    } catch (e) {
      setError(`Không dọn được: ${errorMessage(e)}`);
    } finally {
      setBusy(false);
    }
  };

  return (
    <ModalShell title={`Dọn món trùng — ${storeCode}`} onClose={onClose} maxWidth={720}>
      <p style={{ fontSize: "13px", color: "var(--subtext)", margin: "0 0 10px" }}>
        Mỗi mã món chỉ giữ MỘT bản: ưu tiên bản đang nối kho, rồi bản có nhóm hàng thật, rồi bản đã gắn topping / note.
        Bản giữ lại được chép thêm nhóm hàng, nhóm topping / note, size còn thiếu. Hóa đơn cũ không bị ảnh hưởng.
      </p>
      {error && <div style={errorBox}>{error}</div>}
      {done && <div style={{ ...errorBox, color: "var(--success)", borderColor: "var(--success)", background: "transparent" }}>{done}</div>}
      {!groups && !error && <div style={{ fontSize: "13px" }}>Đang đọc thực đơn…</div>}
      {groups && groups.length === 0 && !done && <div style={{ fontSize: "13px" }}>Không có món trùng mã.</div>}
      {groups && groups.length > 0 && (
        <div style={{ display: "flex", flexDirection: "column", gap: "8px", maxHeight: "55vh", overflowY: "auto" }}>
          {groups.map((g) => (
            <label key={g.code} style={{ display: "flex", gap: "10px", alignItems: "flex-start", border: "1px solid var(--border)", borderRadius: "10px", padding: "10px", fontSize: "13px", cursor: "pointer" }}>
              <input
                type="checkbox"
                checked={picked.has(g.code)}
                onChange={(e) => {
                  const next = new Set(picked);
                  if (e.target.checked) next.add(g.code);
                  else next.delete(g.code);
                  setPicked(next);
                }}
                style={{ marginTop: "3px" }}
              />
              <div style={{ minWidth: 0, flex: 1 }}>
                <div style={{ fontWeight: 700 }}>
                  {g.code} • {g.name}
                </div>
                <div style={{ color: "var(--success)" }}>
                  Giữ: nhóm {g.keep.category || "—"} • {fmt(g.keep.price)}
                  {g.keep.linkedStock ? " • đang nối kho" : ""}
                  {Object.keys(g.patch).length > 0 ? ` • bổ sung: ${Object.keys(g.patch).map((f) => (f === "category" ? `nhóm ${String(g.patch.category)}` : f)).join(", ")}` : ""}
                </div>
                {g.remove.map((r) => (
                  <div key={r.key} style={{ color: "var(--danger)" }}>
                    Xóa: nhóm {r.category || "—"} • {fmt(r.price)}
                    {r.price !== g.keep.price ? " (khác giá!)" : ""}
                    {r.linkedStock ? " • cũng nối kho" : ""}
                  </div>
                ))}
              </div>
            </label>
          ))}
        </div>
      )}
      <div style={{ display: "flex", justifyContent: "flex-end", gap: "8px", marginTop: "12px", flexWrap: "wrap" }}>
        <button type="button" style={btnGhost} onClick={onClose}>
          Đóng
        </button>
        {groups && groups.length > 0 && (
          <button type="button" className="btn-primary" style={{ background: "var(--danger)" }} disabled={busy || picked.size === 0} onClick={run}>
            {busy ? "Đang dọn…" : `Dọn ${picked.size} món đã chọn`}
          </button>
        )}
      </div>
    </ModalShell>
  );
}
