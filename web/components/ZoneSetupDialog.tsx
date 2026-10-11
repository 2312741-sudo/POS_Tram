"use client";
import { useEffect, useMemo, useState } from "react";
import { LayoutGrid, Trash2 } from "lucide-react";
import { onValue, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "./ModalShell";
import { errorMessage } from "@/lib/errors";
import {
  buildZoneCreateUpdates,
  buildZoneDeleteUpdates,
  mergeZoneNames,
  nextTableNames,
  parseZones,
  validateZoneName,
} from "@/lib/zones";

interface Props {
  storeCode: string;
  /** Bàn hiện có của chi nhánh (để đếm bàn theo khu và tránh trùng tên) */
  tables: { name: string; zone?: string }[];
  actor: { username: string; fullName?: string; role?: string };
  onClose: () => void;
}

/** Thiết lập khu vực: thêm khu (kèm tạo nhanh N bàn) và xóa khu trống — Chủ quán / Quản lý */
export default function ZoneSetupDialog({ storeCode, tables, actor, onClose }: Props) {
  const [declared, setDeclared] = useState<string[]>([]);
  const [name, setName] = useState("");
  const [count, setCount] = useState("5");
  const [prefix, setPrefix] = useState("Bàn");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(
    () =>
      onValue(
        ref(db, `stores/${storeCode}/zones`),
        (snap) => setDeclared(parseZones(snap.val())),
        () => setError("Không đọc được danh sách khu vực")
      ),
    [storeCode]
  );

  const zones = useMemo(() => mergeZoneNames(declared, tables.map((t) => t.zone)), [declared, tables]);
  const countIn = (z: string) => tables.filter((t) => t.zone === z).length;

  const audit = (action: string, details: string, now: number) => ({
    [`stores/${storeCode}/audit_logs/log_${now}_zone_${Math.floor(Math.random() * 1e5)}`]: {
      timestamp: now,
      username: actor.username,
      userFullName: actor.fullName || actor.username,
      userRole: actor.role || "",
      action,
      targetType: "ZONE",
      targetId: details.split('"')[1] || "",
      storeCode,
      details,
    },
  });

  const add = async () => {
    const err = validateZoneName(name, zones);
    if (err) return setError(err);
    const n = Math.trunc(Number(count));
    if (!Number.isFinite(n) || n < 0 || n > 100) return setError("Số bàn tạo nhanh từ 0 đến 100");
    setBusy(true);
    setError("");
    try {
      const now = Date.now();
      const zone = name.trim();
      const tableNames = nextTableNames(prefix, n, []);
      await update(ref(db), {
        ...buildZoneCreateUpdates({ storeCode, zoneName: zone, tableNames }),
        ...audit("ZONE_SAVE", `Thêm khu vực "${zone}" kèm ${tableNames.length} bàn qua Web Admin`, now),
      });
      setName("");
    } catch (e) {
      setError(errorMessage(e, "Không thêm được khu vực"));
    } finally {
      setBusy(false);
    }
  };

  const remove = async (zone: string) => {
    const r = buildZoneDeleteUpdates({ storeCode, zoneName: zone, tablesInZone: countIn(zone) });
    if ("error" in r) return setError(r.error);
    if (!confirm(`Xóa khu vực "${zone}"?`)) return;
    setBusy(true);
    setError("");
    try {
      await update(ref(db), { ...r.updates, ...audit("ZONE_DELETE", `Xóa khu vực "${zone}" qua Web Admin`, Date.now()) });
    } catch (e) {
      setError(errorMessage(e, "Không xóa được khu vực"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <ModalShell
      title="Thiết lập khu vực bàn"
      subtitle={`Chi nhánh ${storeCode}`}
      icon={<LayoutGrid size={18} color="var(--primary)" />}
      maxWidth={520}
      onClose={onClose}
      footer={<button type="button" style={btnGhost} onClick={onClose}>Đóng</button>}
    >
      {error && <div style={errorBox}>{error}</div>}
      <div style={{ display: "grid", gap: 8, marginBottom: 16 }}>
        {zones.length === 0 && <div style={{ fontSize: 13, color: "var(--subtext)" }}>Chưa có khu vực nào.</div>}
        {zones.map((z) => (
          <div key={z} style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "8px 12px", border: "1px solid var(--border)", borderRadius: 8 }}>
            <div>
              <strong>{z}</strong>
              <span style={{ marginLeft: 8, fontSize: 12, color: "var(--subtext)" }}>{countIn(z)} bàn</span>
            </div>
            <button
              type="button"
              aria-label={`Xóa khu ${z}`}
              disabled={busy || countIn(z) > 0}
              title={countIn(z) > 0 ? "Khu còn bàn — không thể xóa" : "Xóa khu"}
              onClick={() => remove(z)}
              style={{ background: "none", border: "none", cursor: countIn(z) > 0 ? "not-allowed" : "pointer", color: "var(--danger, #B3261E)", opacity: countIn(z) > 0 ? 0.35 : 1 }}
            >
              <Trash2 size={16} />
            </button>
          </div>
        ))}
      </div>

      <div style={{ borderTop: "1px solid var(--border)", paddingTop: 14, display: "grid", gap: 10 }}>
        <div style={{ fontWeight: 700, fontSize: 13 }}>Thêm khu vực mới</div>
        <div>
          <label style={fieldLabel}>Tên khu *</label>
          <input style={fieldInput} value={name} onChange={(e) => setName(e.target.value)} placeholder="VD: Tầng 2, Sân vườn" />
        </div>
        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10 }}>
          <div>
            <label style={fieldLabel}>Tạo nhanh số bàn</label>
            <input style={fieldInput} type="number" min={0} max={100} value={count} onChange={(e) => setCount(e.target.value)} />
          </div>
          <div>
            <label style={fieldLabel}>Tiền tố tên bàn</label>
            <input style={fieldInput} value={prefix} onChange={(e) => setPrefix(e.target.value)} />
          </div>
        </div>
        <button type="button" style={{ ...btnPrimary, opacity: busy ? 0.6 : 1 }} disabled={busy} onClick={add}>
          {busy ? "Đang lưu..." : "Thêm khu vực"}
        </button>
      </div>
    </ModalShell>
  );
}
