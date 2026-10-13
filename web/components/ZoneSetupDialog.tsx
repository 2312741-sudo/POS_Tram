"use client";
import { useEffect, useMemo, useState, type CSSProperties } from "react";
import { ArrowDown, ArrowUp, LayoutGrid, Pencil, Pin, PinOff, Plus, Trash2 } from "lucide-react";
import { onValue, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "./ModalShell";
import { errorMessage } from "@/lib/errors";
import {
  buildZoneAuditUpdates,
  buildZoneDeleteUpdates,
  buildZoneOrderUpdates,
  buildZonePinUpdates,
  isTableInUse,
  mergeZoneNames,
  parseZoneMeta,
  parseZones,
  planAddTables,
  planZoneCreate,
  planZoneRename,
  sortZoneNames,
  type ZoneMeta,
  type ZoneAuditActor,
  type ZonePlan,
  type ZoneTableRecord,
} from "@/lib/zones";

interface Props {
  /** Mã chi nhánh cụ thể đang chọn. "ALL" = chưa chọn chi nhánh → chỉ hiện hướng dẫn, không ghi gì */
  storeCode: string;
  actor: ZoneAuditActor;
  onClose: () => void;
}

type RowEdit = { zone: string; mode: "rename" | "tables"; value: string; count: string; prefix: string };

/** Thiết lập khu vực: thêm khu (kèm tạo nhanh N bàn), đổi tên khu, thêm bàn vào khu, xóa khu trống — Chủ quán / Quản lý */
export default function ZoneSetupDialog({ storeCode, actor, onClose }: Props) {
  const [declared, setDeclared] = useState<string[]>([]);
  const [meta, setMeta] = useState<ZoneMeta[]>([]);
  const [tables, setTables] = useState<ZoneTableRecord[]>([]);
  const [name, setName] = useState("");
  const [count, setCount] = useState("5");
  const [prefix, setPrefix] = useState("Bàn");
  const [edit, setEdit] = useState<RowEdit | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [info, setInfo] = useState("");

  useEffect(() => {
    if (storeCode === "ALL") return;
    const offZones = onValue(
      ref(db, `stores/${storeCode}/zones`),
      (snap) => {
        setDeclared(parseZones(snap.val()));
        setMeta(parseZoneMeta(snap.val()));
      },
      () => setError("Không đọc được danh sách khu vực")
    );
    const offTables = onValue(
      ref(db, `stores/${storeCode}/tables`),
      (snap) => {
        const raw = (snap.val() || {}) as Record<string, unknown>;
        setTables(
          Object.entries(raw)
            .filter(([, v]) => v && typeof v === "object")
            .map(([key, v]) => ({ key, value: v as Record<string, unknown> }))
        );
      },
      () => setError("Không đọc được danh sách bàn")
    );
    return () => {
      offZones();
      offTables();
    };
  }, [storeCode]);

  const zones = useMemo(
    () => sortZoneNames(mergeZoneNames(declared, tables.map((t) => String(t.value.zone ?? ""))), meta),
    [declared, tables, meta]
  );
  const pinnedSet = useMemo(() => new Set(meta.filter((m) => m.pinned).map((m) => m.name)), [meta]);

  /** Ghim / sắp xếp: ghi trực tiếp (không cần nhật ký), đồng bộ ngay với app */
  const writeOnly = async (updates: Record<string, unknown>, fallback: string) => {
    setBusy(true);
    setError("");
    setInfo("");
    try {
      await update(ref(db), updates);
    } catch (e) {
      setError(`${fallback}: ${errorMessage(e, "lỗi không xác định")}`);
    } finally {
      setBusy(false);
    }
  };
  const togglePin = (z: string) => writeOnly(buildZonePinUpdates(storeCode, z, !pinnedSet.has(z)), "Không ghim được khu vực");
  const move = (z: string, delta: -1 | 1) => {
    const i = zones.indexOf(z);
    const j = i + delta;
    if (i < 0 || j < 0 || j >= zones.length) return;
    // Không cho đổi chỗ khu ghim với khu thường
    if (pinnedSet.has(zones[i]) !== pinnedSet.has(zones[j])) return;
    const next = [...zones];
    [next[i], next[j]] = [next[j], next[i]];
    return writeOnly(buildZoneOrderUpdates(storeCode, next, pinnedSet), "Không lưu được thứ tự khu vực");
  };
  const countIn = (z: string) => tables.filter((t) => String(t.value.zone ?? "") === z).length;
  const busyIn = (z: string) => tables.some((t) => String(t.value.zone ?? "") === z && isTableInUse(t.value));

  /** Ghi các đường dẫn + một bản ghi nhật ký trong cùng một update (nguyên tử) */
  const commit = async (
    plan: { updates: Record<string, unknown> },
    audit: { action: "ZONE_SAVE" | "ZONE_RENAME" | "ZONE_DELETE" | "TABLE_ADD"; targetType: "ZONE" | "TABLE"; targetId: string; details: string }
  ) => {
    const now = Date.now();
    await update(ref(db), {
      ...plan.updates,
      ...buildZoneAuditUpdates({
        storeCode,
        ...audit,
        actor,
        now,
        suffix: Math.floor(Math.random() * 1e5),
      }),
    });
  };

  /** Chạy một thao tác: báo lỗi kế hoạch, hoặc ghi và hiện lỗi Firebase thật nếu thất bại */
  const run = async (plan: ZonePlan, audit: Parameters<typeof commit>[1], fallback: string, onOk?: () => void) => {
    if ("error" in plan) return setError(plan.error);
    setBusy(true);
    setError("");
    setInfo("");
    try {
      await commit(plan, audit);
      onOk?.();
      setInfo("Đã lưu");
    } catch (e) {
      setError(`${fallback}: ${errorMessage(e, "lỗi không xác định")}`);
    } finally {
      setBusy(false);
    }
  };

  const add = () =>
    run(
      planZoneCreate({
        storeCode,
        zoneName: name,
        prefix,
        count: Math.trunc(Number(count)),
        declaredZones: zones,
        tables,
      }),
      {
        action: "ZONE_SAVE",
        targetType: "ZONE",
        targetId: name.trim(),
        details: `Thêm khu vực "${name.trim()}" kèm ${Math.trunc(Number(count)) || 0} bàn qua Web Admin`,
      },
      "Không thêm được khu vực",
      () => setName("")
    );

  const saveRename = () => {
    if (!edit) return;
    const oldName = edit.zone;
    run(
      planZoneRename({ storeCode, oldName, newName: edit.value, declaredZones: zones, tables }),
      {
        action: "ZONE_RENAME",
        targetType: "ZONE",
        targetId: oldName,
        details: `Đổi tên khu vực "${oldName}" thành "${edit.value.trim()}" qua Web Admin`,
      },
      "Không đổi được tên khu",
      () => setEdit(null)
    );
  };

  const saveAddTables = () => {
    if (!edit) return;
    const zone = edit.zone;
    run(
      planAddTables({ storeCode, zoneName: zone, prefix: edit.prefix, count: Math.trunc(Number(edit.count)), declaredZones: zones, tables }),
      {
        action: "TABLE_ADD",
        targetType: "TABLE",
        targetId: zone,
        details: `Thêm ${Math.trunc(Number(edit.count)) || 0} bàn vào khu vực "${zone}" qua Web Admin`,
      },
      "Không thêm được bàn",
      () => setEdit(null)
    );
  };

  const remove = (zone: string) => {
    const r = buildZoneDeleteUpdates({ storeCode, zoneName: zone, tablesInZone: countIn(zone) });
    if ("error" in r) return setError(r.error);
    if (!confirm(`Xóa khu vực "${zone}"?`)) return;
    run({ updates: r.updates, affected: 0 }, {
      action: "ZONE_DELETE",
      targetType: "ZONE",
      targetId: zone,
      details: `Xóa khu vực "${zone}" qua Web Admin`,
    }, "Không xóa được khu vực");
  };

  const iconBtn = (disabled: boolean): CSSProperties => ({
    background: "none",
    border: "none",
    cursor: disabled ? "not-allowed" : "pointer",
    color: "var(--primary)",
    opacity: disabled ? 0.35 : 1,
    padding: 4,
  });

  if (storeCode === "ALL") {
    return (
      <ModalShell
        title="Thiết lập khu vực bàn"
        subtitle="Chưa chọn chi nhánh"
        icon={<LayoutGrid size={18} color="var(--primary)" />}
        maxWidth={520}
        onClose={onClose}
        footer={<button type="button" style={btnGhost} onClick={onClose}>Đóng</button>}
      >
        <div style={{ fontSize: 14, lineHeight: 1.5, color: "var(--text)" }}>
          Đang xem <strong>Tất cả chi nhánh</strong>. Khu vực bàn được thiết lập theo từng chi nhánh — hãy chọn một chi nhánh
          cụ thể ở ô <strong>«Chọn chi nhánh»</strong> phía trên, rồi mở lại «Thiết lập khu vực».
        </div>
      </ModalShell>
    );
  }

  return (
    <ModalShell
      title="Thiết lập khu vực bàn"
      subtitle={`Chi nhánh ${storeCode}`}
      icon={<LayoutGrid size={18} color="var(--primary)" />}
      maxWidth={560}
      onClose={onClose}
      footer={<button type="button" style={btnGhost} onClick={onClose}>Đóng</button>}
    >
      {error && <div style={errorBox}>{error}</div>}
      {info && !error && <div style={{ fontSize: 13, color: "var(--primary)", marginBottom: 10 }}>{info}</div>}

      <div style={{ display: "grid", gap: 8, marginBottom: 16 }}>
        {zones.length === 0 && <div style={{ fontSize: 13, color: "var(--subtext)" }}>Chưa có khu vực nào.</div>}
        {zones.map((z, zi) => {
          const n = countIn(z);
          const isEditing = edit?.zone === z;
          const hasBusy = busyIn(z);
          return (
            <div key={z} style={{ border: "1px solid var(--border)", borderRadius: 8, padding: "8px 12px" }}>
              <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8 }}>
                <div>
                  <strong>{pinnedSet.has(z) ? "📌 " : ""}{z}</strong>
                  <span style={{ marginLeft: 8, fontSize: 12, color: "var(--subtext)" }}>{n} bàn</span>
                  {hasBusy && <span style={{ marginLeft: 8, fontSize: 12, color: "var(--danger, #B3261E)" }}>đang có bàn dùng</span>}
                </div>
                <div style={{ display: "flex", gap: 4 }}>
                  <button type="button" aria-label={pinnedSet.has(z) ? `Bỏ ghim khu ${z}` : `Ghim khu ${z}`}
                    title={pinnedSet.has(z) ? "Bỏ ghim" : "Ghim lên đầu"} disabled={busy} style={iconBtn(busy)}
                    onClick={() => togglePin(z)}>
                    {pinnedSet.has(z) ? <PinOff size={16} /> : <Pin size={16} />}
                  </button>
                  <button type="button" aria-label={`Đưa khu ${z} lên`} title="Đưa lên"
                    disabled={busy || zi === 0 || pinnedSet.has(zones[zi - 1]) !== pinnedSet.has(z)}
                    style={iconBtn(busy || zi === 0 || pinnedSet.has(zones[zi - 1]) !== pinnedSet.has(z))} onClick={() => move(z, -1)}>
                    <ArrowUp size={16} />
                  </button>
                  <button type="button" aria-label={`Đưa khu ${z} xuống`} title="Đưa xuống"
                    disabled={busy || zi === zones.length - 1 || pinnedSet.has(zones[zi + 1]) !== pinnedSet.has(z)}
                    style={iconBtn(busy || zi === zones.length - 1 || pinnedSet.has(zones[zi + 1]) !== pinnedSet.has(z))} onClick={() => move(z, 1)}>
                    <ArrowDown size={16} />
                  </button>
                  <button type="button" aria-label={`Đổi tên khu ${z}`} title={hasBusy ? "Còn bàn đang dùng — không đổi tên" : "Đổi tên khu"}
                    disabled={busy || hasBusy} style={iconBtn(busy || hasBusy)}
                    onClick={() => setEdit({ zone: z, mode: "rename", value: z, count: "5", prefix: "Bàn" })}>
                    <Pencil size={16} />
                  </button>
                  <button type="button" aria-label={`Thêm bàn vào khu ${z}`} title="Thêm bàn vào khu"
                    disabled={busy} style={iconBtn(busy)}
                    onClick={() => setEdit({ zone: z, mode: "tables", value: z, count: "5", prefix: "Bàn" })}>
                    <Plus size={16} />
                  </button>
                  <button type="button" aria-label={`Xóa khu ${z}`} disabled={busy || n > 0}
                    title={n > 0 ? "Khu còn bàn — không thể xóa" : "Xóa khu"} onClick={() => remove(z)}
                    style={{ ...iconBtn(busy || n > 0), color: "var(--danger, #B3261E)" }}>
                    <Trash2 size={16} />
                  </button>
                </div>
              </div>

              {isEditing && edit && edit.mode === "rename" && (
                <div style={{ display: "flex", gap: 8, marginTop: 8 }}>
                  <input style={fieldInput} aria-label="Tên khu mới" value={edit.value}
                    onChange={(e) => setEdit({ ...edit, value: e.target.value })} />
                  <button type="button" style={btnPrimary} disabled={busy} onClick={saveRename}>Lưu</button>
                  <button type="button" style={btnGhost} onClick={() => setEdit(null)}>Hủy</button>
                </div>
              )}
              {isEditing && edit && edit.mode === "tables" && (
                <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr auto auto", gap: 8, marginTop: 8, alignItems: "end" }}>
                  <div>
                    <label style={fieldLabel}>Số bàn thêm</label>
                    <input style={fieldInput} type="number" min={1} max={100} value={edit.count}
                      onChange={(e) => setEdit({ ...edit, count: e.target.value })} />
                  </div>
                  <div>
                    <label style={fieldLabel}>Tiền tố tên bàn</label>
                    <input style={fieldInput} value={edit.prefix}
                      onChange={(e) => setEdit({ ...edit, prefix: e.target.value })} />
                  </div>
                  <button type="button" style={btnPrimary} disabled={busy} onClick={saveAddTables}>Thêm bàn</button>
                  <button type="button" style={btnGhost} onClick={() => setEdit(null)}>Hủy</button>
                </div>
              )}
            </div>
          );
        })}
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
        <button type="button" style={{ ...btnPrimary, opacity: busy ? 0.6 : 1, display: "inline-flex", alignItems: "center", gap: 6, justifyContent: "center" }}
          disabled={busy} onClick={add}>
          <Plus size={14} />
          {busy ? "Đang lưu..." : "Thêm khu vực"}
        </button>
      </div>
    </ModalShell>
  );
}
