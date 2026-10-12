"use client";
import { useMemo, useState } from "react";
import Link from "next/link";
import { ArrowDown, ArrowUp, DownloadCloud, Edit2, Plus, StickyNote, Trash2, X } from "lucide-react";
import { get, ref } from "firebase/database";
import { db } from "@/lib/firebase";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { canManageNoteCatalog } from "@/lib/note-catalog-access";
import {
  deleteNoteGroup,
  deleteToppingGroup,
  newGroupId,
  saveNoteGroup,
  saveToppingGroup,
  updateStorePaths,
  useItemCatalog,
} from "@/lib/note-catalog";
import { isLegacyCatalog, type NoteGroup, type ToppingGroup } from "@/lib/item-options";
import { planNoteCatalogMigration } from "@/lib/note-catalog-migrate";
import { errorMessage } from "@/lib/errors";
import ModalShell, { btnGhost, btnPrimary, errorBox, fieldInput, fieldLabel } from "@/components/ModalShell";

const fmt = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

type Editing = { kind: "note"; group: NoteGroup | null } | { kind: "topping"; group: ToppingGroup | null } | null;

export default function NoteCatalogPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, setCurrentStoreCode } = useDashboardData();
  const allowed = canManageNoteCatalog(user);
  const storeCode = currentStoreCode !== "ALL" ? currentStoreCode : user?.storeCode || stores[0]?.storeCode || "";
  const { catalog, loaded } = useItemCatalog(allowed ? storeCode : null);
  const [tab, setTab] = useState<"note" | "topping">("note");
  const [editing, setEditing] = useState<Editing>(null);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const legacy = useMemo(() => isLegacyCatalog(catalog), [catalog]);

  if (!allowed) {
    return (
      <div className="card" style={{ padding: 24 }}>
        Bạn không có quyền quản lý danh mục note &amp; topping (MANAGE_NOTE_CATALOG).
      </div>
    );
  }

  const run = async (fn: () => Promise<unknown>, ok = "") => {
    setErr("");
    try {
      await fn();
      if (ok) {
        setMsg(ok);
        setTimeout(() => setMsg(""), 4000);
      }
    } catch (e) {
      setErr(errorMessage(e) || "Không lưu được");
    }
  };

  const importLegacy = () =>
    run(async () => {
      const read = async (n: string) => (await get(ref(db, `stores/${storeCode}/${n}`))).val();
      const [products, categories, productNotes, noteGroups, toppingGroups] = await Promise.all(
        ["products", "categories", "product_notes", "note_groups", "topping_groups"].map(read)
      );
      const plan = planNoteCatalogMigration({ products, categories, productNotes, noteGroups, toppingGroups });
      if (Object.keys(plan.updates).length === 0) {
        setMsg("Không có gì để nhập thêm (đã nhập hoặc chưa có cấu hình cũ).");
        return;
      }
      if (!window.confirm(`${plan.summary.join("\n")}\n\nChỉ THÊM mới, không ghi đè nhóm/gắn kết đã có. Tiếp tục?`)) return;
      await updateStorePaths(storeCode, plan.updates);
      setMsg(`Đã nhập: ${plan.newNoteGroups} nhóm note, ${plan.newToppingGroups} nhóm topping, ${plan.attachments} lượt gắn.`);
    });

  const move = <T extends { id: string; sortOrder: number }>(list: T[], i: number, dir: -1 | 1, save: (g: T) => Promise<unknown>) =>
    run(async () => {
      const j = i + dir;
      if (j < 0 || j >= list.length) return;
      const next = [...list];
      [next[i], next[j]] = [next[j], next[i]];
      await Promise.all(next.map((g, idx) => (g.sortOrder !== idx + 1 ? save({ ...g, sortOrder: idx + 1 }) : Promise.resolve())));
    });

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 16 }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 12, flexWrap: "wrap", alignItems: "flex-start" }}>
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, color: "var(--text)", margin: 0, display: "flex", gap: 8, alignItems: "center" }}>
            <StickyNote size={22} color="var(--primary)" /> Danh mục note &amp; topping
          </h1>
          <div style={{ fontSize: 13, color: "var(--subtext)", marginTop: 4 }}>
            Tạo nhóm rồi gắn vào <Link href="/dashboard/products" style={{ color: "var(--primary)", fontWeight: 700 }}>nhóm món hoặc từng món</Link>. Món/nhóm chưa gắn thì khi gọi món chỉ còn ô ghi chú tự do.
          </div>
        </div>
        <button type="button" style={btnGhost} onClick={importLegacy}>
          <DownloadCloud size={14} style={{ verticalAlign: "-2px" }} /> Nhập từ cấu hình cũ
        </button>
      </div>

      {stores.length > 1 && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {stores.map((s) => (
            <button
              key={s.storeCode}
              type="button"
              onClick={() => setCurrentStoreCode(s.storeCode)}
              style={{
                padding: "7px 16px", borderRadius: 10, fontSize: 13, fontWeight: 700, cursor: "pointer",
                border: "1px solid", borderColor: storeCode === s.storeCode ? "var(--primary)" : "var(--border)",
                background: storeCode === s.storeCode ? "var(--primary)" : "var(--surface)", color: storeCode === s.storeCode ? "#fff" : "var(--subtext)",
              }}
            >
              🏪 {s.storeName}
            </button>
          ))}
        </div>
      )}

      {loaded && legacy && (
        <div style={{ padding: "10px 14px", borderRadius: 10, background: "var(--warning-bg, #FFF4D6)", color: "var(--warning, #7A5200)", fontSize: 13 }}>
          Chưa cấu hình: màn gọi món (POS và Web) vẫn hiện danh sách topping &amp; ghi chú cũ. Tạo nhóm đầu tiên (hoặc bấm “Nhập từ cấu hình cũ”) rồi gắn vào nhóm món/món — từ đó chỉ hiện đúng nhóm đã gắn.
        </div>
      )}
      {msg && <div style={{ padding: "8px 12px", borderRadius: 8, background: "var(--success-bg, #E6F4EA)", color: "var(--success, #1E6B34)", fontSize: 13, whiteSpace: "pre-line" }}>{msg}</div>}
      {err && <div style={errorBox}>{err}</div>}

      <div style={{ display: "flex", borderBottom: "1px solid var(--border)" }}>
        {([["note", `Danh mục note (${catalog.noteGroups.length})`], ["topping", `Nhóm topping (${catalog.toppingGroups.length})`]] as const).map(([k, label]) => (
          <button
            key={k}
            type="button"
            onClick={() => setTab(k)}
            style={{
              padding: "12px 20px", fontSize: 14, fontWeight: 700, cursor: "pointer", background: "none", border: "none",
              borderBottom: tab === k ? "3px solid var(--primary)" : "3px solid transparent", color: tab === k ? "var(--primary)" : "var(--subtext)",
            }}
          >
            {label}
          </button>
        ))}
      </div>

      <div>
        <button type="button" className="btn-primary" onClick={() => setEditing(tab === "note" ? { kind: "note", group: null } : { kind: "topping", group: null })}>
          <Plus size={14} style={{ verticalAlign: "-2px" }} /> {tab === "note" ? "Thêm nhóm note" : "Thêm nhóm topping"}
        </button>
      </div>

      {tab === "note" &&
        (catalog.noteGroups.length === 0 ? (
          <div className="card" style={{ padding: 20, color: "var(--subtext)" }}>Chưa có nhóm note nào.</div>
        ) : (
          catalog.noteGroups.map((g, i, list) => (
            <GroupCard
              key={g.id}
              title={g.name}
              active={g.active}
              body={g.items.map((n) => n.text).join(" • ") || "(chưa có câu note)"}
              onEdit={() => setEditing({ kind: "note", group: g })}
              onDelete={() => window.confirm(`Xóa nhóm note "${g.name}"? Món/nhóm món đang gắn sẽ không còn hiện nhóm này.`) && run(() => deleteNoteGroup(storeCode, g.id), "Đã xóa")}
              onUp={i > 0 ? () => move(list, i, -1, (x) => saveNoteGroup(storeCode, x)) : undefined}
              onDown={i < list.length - 1 ? () => move(list, i, 1, (x) => saveNoteGroup(storeCode, x)) : undefined}
            />
          ))
        ))}

      {tab === "topping" &&
        (catalog.toppingGroups.length === 0 ? (
          <div className="card" style={{ padding: 20, color: "var(--subtext)" }}>Chưa có nhóm topping nào.</div>
        ) : (
          catalog.toppingGroups.map((g, i, list) => (
            <GroupCard
              key={g.id}
              title={`${g.name} — ${!g.multi ? "chọn 1" : g.max > 0 ? `tối đa ${g.max}` : "chọn nhiều"}`}
              active={g.active}
              body={g.items.map((t) => `${t.name} ${fmt(t.price)}`).join(" • ") || "(chưa có topping)"}
              onEdit={() => setEditing({ kind: "topping", group: g })}
              onDelete={() => window.confirm(`Xóa nhóm topping "${g.name}"? Món/nhóm món đang gắn sẽ không còn hiện nhóm này.`) && run(() => deleteToppingGroup(storeCode, g.id), "Đã xóa")}
              onUp={i > 0 ? () => move(list, i, -1, (x) => saveToppingGroup(storeCode, x)) : undefined}
              onDown={i < list.length - 1 ? () => move(list, i, 1, (x) => saveToppingGroup(storeCode, x)) : undefined}
            />
          ))
        ))}

      {editing?.kind === "note" && (
        <NoteGroupEditor
          group={editing.group}
          nextOrder={catalog.noteGroups.length + 1}
          onClose={() => setEditing(null)}
          onSave={(g) => run(() => saveNoteGroup(storeCode, g), "Đã lưu").then(() => setEditing(null))}
        />
      )}
      {editing?.kind === "topping" && (
        <ToppingGroupEditor
          group={editing.group}
          nextOrder={catalog.toppingGroups.length + 1}
          onClose={() => setEditing(null)}
          onSave={(g) => run(() => saveToppingGroup(storeCode, g), "Đã lưu").then(() => setEditing(null))}
        />
      )}
    </div>
  );
}

function GroupCard({
  title, body, active, onEdit, onDelete, onUp, onDown,
}: {
  title: string; body: string; active: boolean; onEdit: () => void; onDelete: () => void; onUp?: () => void; onDown?: () => void;
}) {
  const iconBtn = { background: "none", border: "none", cursor: "pointer", color: "var(--subtext)", padding: 6 } as const;
  return (
    <div className="card" style={{ padding: "12px 16px", display: "flex", gap: 12, alignItems: "center", opacity: active ? 1 : 0.6 }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontWeight: 800, color: "var(--text)" }}>
          {title} {!active && <span style={{ fontSize: 11, color: "var(--subtext)" }}>(đã tắt)</span>}
        </div>
        <div style={{ fontSize: 13, color: "var(--subtext)", marginTop: 2, overflowWrap: "anywhere" }}>{body}</div>
      </div>
      <button type="button" aria-label="Lên" style={{ ...iconBtn, visibility: onUp ? "visible" : "hidden" }} onClick={onUp}><ArrowUp size={16} /></button>
      <button type="button" aria-label="Xuống" style={{ ...iconBtn, visibility: onDown ? "visible" : "hidden" }} onClick={onDown}><ArrowDown size={16} /></button>
      <button type="button" aria-label="Sửa" style={iconBtn} onClick={onEdit}><Edit2 size={16} /></button>
      <button type="button" aria-label="Xóa" style={{ ...iconBtn, color: "var(--danger, #B3261E)" }} onClick={onDelete}><Trash2 size={16} /></button>
    </div>
  );
}

function NoteGroupEditor({ group, nextOrder, onClose, onSave }: { group: NoteGroup | null; nextOrder: number; onClose: () => void; onSave: (g: NoteGroup) => void }) {
  const [name, setName] = useState(group?.name ?? "");
  const [active, setActive] = useState(group?.active ?? true);
  const [items, setItems] = useState(group?.items ?? []);
  const [error, setError] = useState("");
  const submit = () => {
    if (!name.trim()) return setError("Nhập tên nhóm");
    onSave({ id: group?.id ?? newGroupId("ng"), name: name.trim(), sortOrder: group?.sortOrder ?? nextOrder, active, items: items.filter((i) => i.text.trim()) });
  };
  return (
    <ModalShell
      title={group ? "Sửa nhóm note" : "Thêm nhóm note"}
      maxWidth={520}
      onClose={onClose}
      footer={<><button type="button" style={btnGhost} onClick={onClose}>Hủy</button><button type="button" style={btnPrimary} onClick={submit}>Lưu</button></>}
    >
      {error && <div style={errorBox}>{error}</div>}
      <label style={fieldLabel}>Tên nhóm * (VD: Đồ uống, Bánh)</label>
      <input style={fieldInput} value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
      <label style={{ display: "flex", gap: 8, alignItems: "center", margin: "12px 0", fontSize: 13 }}>
        <input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> Đang dùng
      </label>
      <label style={fieldLabel}>Câu note mẫu</label>
      {items.map((it, i) => (
        <div key={it.id} style={{ display: "flex", gap: 6, marginBottom: 6 }}>
          <input style={fieldInput} value={it.text} maxLength={60} onChange={(e) => setItems(items.map((x, idx) => (idx === i ? { ...x, text: e.target.value } : x)))} />
          <button type="button" aria-label="Xóa câu" style={{ ...btnGhost, padding: "6px 10px" }} onClick={() => setItems(items.filter((_, idx) => idx !== i))}><X size={14} /></button>
        </div>
      ))}
      <button type="button" style={btnGhost} onClick={() => setItems([...items, { id: newGroupId("n"), text: "" }])}><Plus size={13} style={{ verticalAlign: "-2px" }} /> Thêm câu note</button>
    </ModalShell>
  );
}

function ToppingGroupEditor({ group, nextOrder, onClose, onSave }: { group: ToppingGroup | null; nextOrder: number; onClose: () => void; onSave: (g: ToppingGroup) => void }) {
  const [name, setName] = useState(group?.name ?? "");
  const [active, setActive] = useState(group?.active ?? true);
  const [multi, setMulti] = useState(group?.multi ?? true);
  const [max, setMax] = useState(group && group.max > 0 ? String(group.max) : "");
  const [items, setItems] = useState(group?.items ?? []);
  const [error, setError] = useState("");
  const submit = () => {
    if (!name.trim()) return setError("Nhập tên nhóm");
    onSave({
      id: group?.id ?? newGroupId("tg"), name: name.trim(), sortOrder: group?.sortOrder ?? nextOrder, active, multi,
      max: multi ? Math.max(0, Math.min(99, Math.trunc(Number(max)) || 0)) : 0,
      items: items.filter((i) => i.name.trim()),
    });
  };
  return (
    <ModalShell
      title={group ? "Sửa nhóm topping" : "Thêm nhóm topping"}
      maxWidth={560}
      onClose={onClose}
      footer={<><button type="button" style={btnGhost} onClick={onClose}>Hủy</button><button type="button" style={btnPrimary} onClick={submit}>Lưu</button></>}
    >
      {error && <div style={errorBox}>{error}</div>}
      <label style={fieldLabel}>Tên nhóm * (VD: Topping trà, Sốt)</label>
      <input style={fieldInput} value={name} onChange={(e) => setName(e.target.value)} maxLength={60} />
      <div style={{ display: "flex", gap: 16, flexWrap: "wrap", margin: "12px 0", fontSize: 13, alignItems: "center" }}>
        <label style={{ display: "flex", gap: 6, alignItems: "center" }}><input type="checkbox" checked={active} onChange={(e) => setActive(e.target.checked)} /> Đang dùng</label>
        <label style={{ display: "flex", gap: 6, alignItems: "center" }}><input type="checkbox" checked={multi} onChange={(e) => setMulti(e.target.checked)} /> Cho chọn nhiều (tắt = chọn 1)</label>
        {multi && (
          <label style={{ display: "flex", gap: 6, alignItems: "center" }}>
            Tối đa <input style={{ ...fieldInput, width: 70 }} inputMode="numeric" value={max} placeholder="∞" onChange={(e) => setMax(e.target.value.replace(/\D/g, "").slice(0, 2))} />
          </label>
        )}
      </div>
      <label style={fieldLabel}>Topping (tên · giá)</label>
      {items.map((it, i) => (
        <div key={it.id} style={{ display: "flex", gap: 6, marginBottom: 6 }}>
          <input style={{ ...fieldInput, flex: 3 }} value={it.name} placeholder="Tên" maxLength={60} onChange={(e) => setItems(items.map((x, idx) => (idx === i ? { ...x, name: e.target.value } : x)))} />
          <input style={{ ...fieldInput, flex: 2 }} inputMode="numeric" value={String(it.price)} placeholder="Giá" onChange={(e) => setItems(items.map((x, idx) => (idx === i ? { ...x, price: Number(e.target.value.replace(/\D/g, "").slice(0, 8)) || 0 } : x)))} />
          <button type="button" aria-label="Xóa topping" style={{ ...btnGhost, padding: "6px 10px" }} onClick={() => setItems(items.filter((_, idx) => idx !== i))}><X size={14} /></button>
        </div>
      ))}
      <button type="button" style={btnGhost} onClick={() => setItems([...items, { id: newGroupId("t"), name: "", price: 0 }])}><Plus size={13} style={{ verticalAlign: "-2px" }} /> Thêm topping</button>
    </ModalShell>
  );
}
