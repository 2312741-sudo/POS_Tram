"use client";
import { useEffect, useMemo, useState } from "react";
import { Copy, X, Search, AlertCircle, Check } from "lucide-react";
import { db } from "@/lib/firebase";
import { useAuth } from "@/lib/auth";
import { errorMessage } from "@/lib/errors";
import {
  DEFAULT_COPY_OPTIONS,
  normalizeName,
  toRecord,
  type ConflictPolicy,
  type CopyOptions,
  type MenuSnapshot,
} from "@/lib/menu-copy";
import { applyPlan, loadMenuSnapshot, planForTargets, type TargetPlan, type TargetResult } from "@/lib/menu-copy-run";

interface StoreLite {
  storeCode: string;
  storeName?: string;
}

type Step = "config" | "preview" | "running" | "done";
type Scope = "all" | "pick";

const CONFLICT_LABELS: Record<ConflictPolicy, string> = {
  skip: "Bỏ qua (giữ món đang có ở chi nhánh đích)",
  overwrite: "Ghi đè giá & thông tin (giữ mã món của đích)",
  duplicate: "Tạo bản sao (thêm hậu tố \"(bản sao)\")",
};

export default function CopyMenuDialog({
  stores,
  defaultSource,
  onClose,
}: {
  stores: StoreLite[];
  defaultSource: string;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const [step, setStep] = useState<Step>("config");
  const [source, setSource] = useState(defaultSource || stores[0]?.storeCode || "");
  const [targets, setTargets] = useState<string[]>([]);
  const [scope, setScope] = useState<Scope>("all");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [search, setSearch] = useState("");
  const [opts, setOpts] = useState<CopyOptions>({ ...DEFAULT_COPY_OPTIONS });
  const [plans, setPlans] = useState<TargetPlan[]>([]);
  const [progress, setProgress] = useState("");
  const [results, setResults] = useState<TargetResult[]>([]);
  const [busy, setBusy] = useState(false);

  // Đọc thực đơn nguồn mỗi khi đổi chi nhánh nguồn (kết quả gắn với mã nguồn để bỏ kết quả cũ)
  const [loaded, setLoaded] = useState<{ source: string; data?: MenuSnapshot; error?: string } | null>(null);
  useEffect(() => {
    if (!source) return;
    let cancelled = false;
    loadMenuSnapshot(db, source)
      .then((data) => !cancelled && setLoaded({ source, data }))
      .catch((e) => !cancelled && setLoaded({ source, error: errorMessage(e) || "Không đọc được thực đơn chi nhánh nguồn." }));
    return () => {
      cancelled = true;
    };
  }, [source]);
  const snapshot = loaded?.source === source ? loaded.data ?? null : null;
  const loadError = loaded?.source === source ? loaded.error ?? "" : "";

  const changeSource = (code: string) => {
    setSource(code);
    setPicked(new Set());
    setTargets((t) => t.filter((c) => c !== code));
  };

  const sourceProducts = useMemo(() => {
    const list = Object.entries(toRecord(snapshot?.products)).map(([key, v]) => {
      const n = (v || {}) as { name?: string; category?: string; price?: number };
      return { key, name: String(n.name || key), category: String(n.category || "").trim() || "Chưa phân loại", price: Number(n.price || 0) };
    });
    return list.sort((a, b) => a.category.localeCompare(b.category, "vi") || a.name.localeCompare(b.name, "vi"));
  }, [snapshot]);

  const visible = useMemo(() => {
    const q = normalizeName(search);
    return q ? sourceProducts.filter((p) => normalizeName(`${p.name} ${p.category}`).includes(q)) : sourceProducts;
  }, [sourceProducts, search]);

  const groups = useMemo(() => {
    const m = new Map<string, typeof visible>();
    for (const p of visible) m.set(p.category, [...(m.get(p.category) || []), p]);
    return [...m.entries()];
  }, [visible]);

  const toggleKey = (k: string) =>
    setPicked((prev) => {
      const n = new Set(prev);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });

  const toggleGroup = (items: { key: string }[]) =>
    setPicked((prev) => {
      const n = new Set(prev);
      const all = items.every((i) => n.has(i.key));
      items.forEach((i) => (all ? n.delete(i.key) : n.add(i.key)));
      return n;
    });

  const selectedCount = scope === "all" ? sourceProducts.length : picked.size;
  const canPreview = Boolean(snapshot) && targets.length > 0 && selectedCount > 0 && !busy;
  const selection = useMemo(() => (scope === "all" ? { all: true } : { productKeys: [...picked] }), [scope, picked]);

  const doPreview = async () => {
    if (!snapshot) return;
    setBusy(true);
    try {
      setPlans(await planForTargets(db, snapshot, targets, selection, opts));
      setStep("preview");
    } finally {
      setBusy(false);
    }
  };

  const doRun = async () => {
    if (!snapshot) return;
    setStep("running");
    setBusy(true);
    const out: TargetResult[] = [];
    const actor = { username: user?.username || "unknown", fullName: user?.fullName, role: user?.roleId || user?.role };
    for (let i = 0; i < plans.length; i++) {
      const tp = plans[i];
      if (tp.error) {
        out.push({ targetStore: tp.targetStore, ok: false, created: 0, overwritten: 0, skipped: 0, error: tp.error });
        continue;
      }
      setProgress(`Đang sao chép sang ${tp.targetStore} (${i + 1}/${plans.length})...`);
      const r = await applyPlan(db, {
        sourceStore: source,
        targetStore: tp.targetStore,
        plan: tp.plan,
        actor,
        onChunk: (d, t) => setProgress(`Đang sao chép sang ${tp.targetStore} (${i + 1}/${plans.length}) — lô ${d}/${t}`),
      });
      out.push(r);
    }
    setResults(out);
    setBusy(false);
    setStep("done");
  };

  const storeLabel = (c: string) => {
    const s = stores.find((x) => x.storeCode === c);
    return s?.storeName ? `${c} - ${s.storeName}` : c;
  };

  const setOpt = <K extends keyof CopyOptions>(k: K, v: CopyOptions[K]) => setOpts((o) => ({ ...o, [k]: v }));
  const labelStyle = { display: "flex", alignItems: "center", gap: "8px", fontSize: "13px", cursor: "pointer" } as const;
  const sectionTitle = { fontSize: "13px", fontWeight: 700, color: "var(--muted)", marginBottom: "6px", display: "block" } as const;

  return (
    <div className="modal-overlay" onClick={() => !busy && onClose()}>
      <div className="modal-content" style={{ maxWidth: "760px", width: "100%" }} onClick={(e) => e.stopPropagation()}>
        <div style={{ padding: "22px 24px 0", display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: "14px" }}>
          <h2 style={{ fontSize: "18px", fontWeight: 700, color: "var(--text)", display: "flex", gap: "8px", alignItems: "center" }}>
            <Copy size={18} /> Sao chép thực đơn
          </h2>
          <button aria-label="Đóng" onClick={() => !busy && onClose()} style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer" }}>
            <X size={20} />
          </button>
        </div>

        <div style={{ padding: "0 24px 24px", display: "flex", flexDirection: "column", gap: "16px", maxHeight: "75vh", overflowY: "auto" }}>
          {step === "config" && (
            <>
              <div>
                <span style={sectionTitle}>1. Chi nhánh nguồn</span>
                <select className="input-field" value={source} onChange={(e) => changeSource(e.target.value)}>
                  {stores.map((s) => (
                    <option key={s.storeCode} value={s.storeCode}>
                      {storeLabel(s.storeCode)}
                    </option>
                  ))}
                </select>
                {loadError && <div style={{ color: "var(--danger)", fontSize: "12px", marginTop: "4px" }}>{loadError}</div>}
                {!snapshot && !loadError && <div style={{ fontSize: "12px", color: "var(--muted)", marginTop: "4px" }}>Đang đọc thực đơn...</div>}
                {snapshot && <div style={{ fontSize: "12px", color: "var(--muted)", marginTop: "4px" }}>{sourceProducts.length} món • {Object.keys(toRecord(snapshot.categories)).length} nhóm • {Object.keys(toRecord(snapshot.notes)).length} ghi chú mẫu</div>}
              </div>

              <div>
                <span style={sectionTitle}>2. Chi nhánh đích (chọn nhiều)</span>
                <div style={{ display: "flex", flexWrap: "wrap", gap: "8px" }}>
                  {stores.filter((s) => s.storeCode !== source).map((s) => (
                    <label key={s.storeCode} style={{ ...labelStyle, padding: "6px 12px", border: "1px solid var(--border)", borderRadius: "10px" }}>
                      <input
                        type="checkbox"
                        checked={targets.includes(s.storeCode)}
                        onChange={(e) => setTargets((t) => (e.target.checked ? [...t, s.storeCode] : t.filter((c) => c !== s.storeCode)))}
                      />
                      {storeLabel(s.storeCode)}
                    </label>
                  ))}
                  {stores.length < 2 && <span style={{ fontSize: "12px", color: "var(--muted)" }}>Cần có ít nhất 2 chi nhánh.</span>}
                </div>
              </div>

              <div>
                <span style={sectionTitle}>3. Món cần sao chép</span>
                <div style={{ display: "flex", gap: "16px", marginBottom: "8px" }}>
                  <label style={labelStyle}>
                    <input type="radio" checked={scope === "all"} onChange={() => setScope("all")} /> Tất cả món ({sourceProducts.length})
                  </label>
                  <label style={labelStyle}>
                    <input type="radio" checked={scope === "pick"} onChange={() => setScope("pick")} /> Chọn nhóm / món cụ thể ({picked.size})
                  </label>
                </div>
                {scope === "pick" && (
                  <div style={{ border: "1px solid var(--border)", borderRadius: "10px", padding: "10px" }}>
                    <div style={{ position: "relative", marginBottom: "8px" }}>
                      <Search size={14} style={{ position: "absolute", left: "10px", top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }} />
                      <input className="input-field" placeholder="Tìm món hoặc nhóm..." value={search} onChange={(e) => setSearch(e.target.value)} style={{ paddingLeft: "32px" }} />
                    </div>
                    <div style={{ maxHeight: "240px", overflowY: "auto", display: "flex", flexDirection: "column", gap: "8px" }}>
                      {groups.length === 0 && <span style={{ fontSize: "12px", color: "var(--muted)" }}>Không có món phù hợp.</span>}
                      {groups.map(([cat, items]) => (
                        <div key={cat}>
                          <label style={{ ...labelStyle, fontWeight: 700 }}>
                            <input type="checkbox" checked={items.every((i) => picked.has(i.key))} onChange={() => toggleGroup(items)} />
                            📂 {cat} ({items.length})
                          </label>
                          <div style={{ marginLeft: "24px", display: "flex", flexDirection: "column", gap: "2px" }}>
                            {items.map((p) => (
                              <label key={p.key} style={labelStyle}>
                                <input type="checkbox" checked={picked.has(p.key)} onChange={() => toggleKey(p.key)} />
                                <span style={{ flex: 1 }}>{p.name}</span>
                                <span style={{ color: "var(--muted)", fontSize: "12px" }}>{new Intl.NumberFormat("vi-VN").format(p.price)}đ</span>
                              </label>
                            ))}
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>

              <div>
                <span style={sectionTitle}>4. Sao chép kèm</span>
                <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: "6px" }}>
                  <label style={labelStyle}><input type="checkbox" checked disabled /> Giá bán, tên, đơn vị (luôn sao chép)</label>
                  <label style={labelStyle}><input type="checkbox" checked={opts.copyCategories} onChange={(e) => setOpt("copyCategories", e.target.checked)} /> Tạo nhóm còn thiếu ở đích (theo tên)</label>
                  <label style={labelStyle}><input type="checkbox" checked={opts.copyOptions} onChange={(e) => setOpt("copyOptions", e.target.checked)} /> Size, topping, đường/đá</label>
                  <label style={labelStyle}><input type="checkbox" checked={opts.copyNotes} onChange={(e) => setOpt("copyNotes", e.target.checked)} /> Ghi chú mẫu</label>
                  <label style={labelStyle}><input type="checkbox" checked={opts.copyImages} onChange={(e) => setOpt("copyImages", e.target.checked)} /> Hình ảnh</label>
                </div>
              </div>

              <div>
                <span style={sectionTitle}>5. Món đã có ở chi nhánh đích (trùng tên + nhóm)</span>
                <div style={{ display: "flex", flexDirection: "column", gap: "6px" }}>
                  {(Object.keys(CONFLICT_LABELS) as ConflictPolicy[]).map((c) => (
                    <label key={c} style={labelStyle}>
                      <input type="radio" checked={opts.conflict === c} onChange={() => setOpt("conflict", c)} /> {CONFLICT_LABELS[c]}
                    </label>
                  ))}
                </div>
                <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "6px" }}>Không có thao tác nào xóa dữ liệu ở chi nhánh đích. Mã món ở đích được cấp mới, không trùng.</div>
              </div>

              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px" }}>
                <button className="btn-secondary" onClick={onClose}>Hủy</button>
                <button className="btn-primary" disabled={!canPreview} onClick={doPreview}>{busy ? "Đang tính..." : "Xem trước"}</button>
              </div>
            </>
          )}

          {step === "preview" && (
            <>
              <div style={{ fontSize: "13px", color: "var(--subtext)" }}>
                Nguồn <b>{source}</b> • {selectedCount} món được chọn • Xem lại rồi bấm Xác nhận.
              </div>
              <div style={{ display: "flex", flexDirection: "column", gap: "10px" }}>
                {plans.map((tp) => (
                  <div key={tp.targetStore} style={{ border: "1px solid var(--border)", borderRadius: "10px", padding: "12px" }}>
                    <div style={{ fontWeight: 700, marginBottom: "6px" }}>🏪 {storeLabel(tp.targetStore)}</div>
                    {tp.error ? (
                      <div style={{ color: "var(--danger)", fontSize: "13px" }}>Không đọc được chi nhánh đích: {tp.error}</div>
                    ) : (
                      <div style={{ fontSize: "13px", display: "flex", gap: "16px", flexWrap: "wrap" }}>
                        <span>Tạo mới: <b>{tp.plan.counts.create}</b></span>
                        {opts.conflict === "overwrite" && <span>Ghi đè: <b>{tp.plan.counts.overwrite}</b></span>}
                        {opts.conflict === "duplicate" && <span>Tạo bản sao: <b>{tp.plan.counts.duplicate}</b></span>}
                        <span>Bỏ qua: <b>{tp.plan.counts.skip}</b></span>
                        <span>Nhóm mới: <b>{tp.plan.counts.categories}</b></span>
                        <span>Ghi chú mới: <b>{tp.plan.counts.notes}</b></span>
                      </div>
                    )}
                  </div>
                ))}
              </div>
              <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px" }}>
                <button className="btn-secondary" onClick={() => setStep("config")}>Quay lại</button>
                <button className="btn-primary" onClick={doRun} disabled={plans.every((p) => p.error || Object.keys(p.plan.updates).length === 0)}>
                  <Check size={16} /> Xác nhận sao chép
                </button>
              </div>
            </>
          )}

          {step === "running" && (
            <div style={{ display: "flex", alignItems: "center", gap: "12px", padding: "20px 0" }}>
              <div className="spinner" />
              <span>{progress || "Đang sao chép..."}</span>
            </div>
          )}

          {step === "done" && (
            <>
              <div style={{ display: "flex", flexDirection: "column", gap: "8px" }}>
                {results.map((r) => (
                  <div key={r.targetStore} style={{ border: `1px solid ${r.ok ? "var(--border)" : "var(--danger)"}`, borderRadius: "10px", padding: "12px", fontSize: "13px" }}>
                    <div style={{ fontWeight: 700 }}>
                      {r.ok ? "✅" : <AlertCircle size={14} style={{ display: "inline", color: "var(--danger)" }} />} {storeLabel(r.targetStore)}
                    </div>
                    {r.ok ? (
                      <div>Đã tạo/bản sao {r.created} • ghi đè {r.overwritten} • bỏ qua {r.skipped}</div>
                    ) : (
                      <div style={{ color: "var(--danger)" }}>Lỗi: {r.error}</div>
                    )}
                  </div>
                ))}
              </div>
              <div style={{ display: "flex", justifyContent: "flex-end" }}>
                <button className="btn-primary" onClick={onClose}>Đóng</button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

