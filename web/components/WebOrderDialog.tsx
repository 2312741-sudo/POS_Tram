"use client";
import { useMemo, useState, type ReactNode } from "react";
import { ChefHat, Minus, Plus, Save, Search, StickyNote, Trash2 } from "lucide-react";
import ModalShell, { btnGhost, errorBox } from "./ModalShell";
import { lineQuantity, lineUnitPrice, setLineQuantity, summarizeOrderLines, type RawOrderLine } from "@/lib/order-math";
import { addLineToOrder, makeOrderLine, type OrderActor } from "@/lib/web-order";
import { isProductAvailable, type AvailabilityFields } from "@/lib/product-availability";
import { toggleTopping, type ItemCatalog } from "@/lib/item-options";
import {
  ICE_OPTIONS,
  SUGAR_OPTIONS,
  defaultSelection,
  describeSelection,
  getProductOptions,
  makeConfiguredLine,
  type OptionCategory,
  type OptionProduct,
  type OptionSelection,
  type ProductOptions,
} from "@/lib/product-options";

/** Món kèm trạng thái báo hết (isAvailable / soldOutUntil) */
type DialogProduct = OptionProduct & AvailabilityFields;

const fmt = (n: number) => `${new Intl.NumberFormat("vi-VN").format(n)}đ`;

interface Props {
  tableName: string;
  zone?: string;
  /** Bàn chưa mở → hỏi số khách */
  opening: boolean;
  /** Món đã có trên bàn (để người gọi biết đang thêm vào đơn nào) */
  existingCount: number;
  /** Toàn bộ món của chi nhánh (kể cả topping — để tính giá topping) */
  products: DialogProduct[];
  categories: OptionCategory[];
  /** Danh mục note & topping của chi nhánh (chưa cấu hình/không truyền = cách hiển thị cũ) */
  catalog?: ItemCatalog;
  actor: OrderActor;
  canSendKitchen: boolean;
  saving?: boolean;
  error?: string;
  onCancel: () => void;
  onSubmit: (lines: RawOrderLine[], opts: { sendKitchen: boolean; guestCount: number; kitchenNote: string }) => void;
}

/**
 * Gọi món trên Web (dự phòng khi app POS sự cố): chọn món → lưu đơn hoặc lưu & gửi phiếu bếp.
 * Món có size / topping / đường / đá sẽ mở bảng chọn tùy chọn (cùng quy tắc với POS).
 */
export default function WebOrderDialog({
  tableName, zone, opening, existingCount, products, categories: optionCategories, catalog, actor, canSendKitchen, saving, error, onCancel, onSubmit,
}: Props) {
  const [search, setSearch] = useState("");
  const [category, setCategory] = useState("ALL");
  const [lines, setLines] = useState<RawOrderLine[]>([]);
  const [guests, setGuests] = useState("1");
  const [kitchenNote, setKitchenNote] = useState("");
  const [localError, setLocalError] = useState("");

  const sellable = useMemo(() => products.filter((p) => !p.isTopping), [products]);
  const categories = useMemo(() => {
    const set = new Set<string>();
    sellable.forEach((p) => p.category && set.add(p.category));
    return [...set].sort((a, b) => a.localeCompare(b, "vi"));
  }, [sellable]);

  const shown = useMemo(() => {
    const q = search.trim().toLowerCase();
    return sellable.filter((p) => (category === "ALL" || p.category === category) && (!q || p.name.toLowerCase().includes(q)));
  }, [sellable, search, category]);

  // Món đã có trong giỏ nhưng vừa bị báo hết: chỉ cảnh báo, không tự xóa
  const soldOutNames = useMemo(() => new Set(products.filter((p) => !isProductAvailable(p)).map((p) => p.name)), [products]);

  const { subTotal } = summarizeOrderLines(lines);
  const totalQty = lines.reduce((s, l) => s + lineQuantity(l), 0);

  const [picking, setPicking] = useState<{ product: OptionProduct; opts: ProductOptions; sel: OptionSelection; qty: number; note: string } | null>(null);

  const add = (p: DialogProduct) => {
    if (!isProductAvailable(p)) return; // món đã báo hết: không cho thêm
    const opts = getProductOptions(p, optionCategories, products, catalog);
    if (!opts.hasAny) {
      setLines((prev) => addLineToOrder(prev, makeOrderLine(p, 1, "", actor, Date.now())));
      return;
    }
    setPicking({ product: p, opts, sel: defaultSelection(opts), qty: 1, note: "" });
  };

  const confirmPicking = () => {
    if (!picking) return;
    const line = makeConfiguredLine(picking.product, picking.opts, picking.sel, picking.qty, picking.note, actor, Date.now());
    setLines((prev) => addLineToOrder(prev, line));
    setPicking(null);
  };
  const changeQty = (i: number, delta: number) =>
    setLines((prev) =>
      prev.flatMap((l, idx) => {
        if (idx !== i) return [l];
        const q = lineQuantity(l) + delta;
        return q <= 0 ? [] : [setLineQuantity(l, q)];
      })
    );
  const setNote = (i: number, note: string) => setLines((prev) => prev.map((l, idx) => (idx === i ? { ...l, note } : l)));

  const submit = (sendKitchen: boolean) => {
    if (lines.length === 0) return setLocalError("Chưa chọn món nào");
    const g = Math.trunc(Number(guests));
    if (opening && (!Number.isFinite(g) || g < 1 || g > 99)) return setLocalError("Số khách từ 1 đến 99");
    setLocalError("");
    onSubmit(lines, { sendKitchen, guestCount: opening ? g : 1, kitchenNote });
  };

  const err = localError || error;
  const chip = (active: boolean) =>
    ({
      padding: "5px 12px", borderRadius: 16, fontSize: 12, fontWeight: active ? 700 : 500, cursor: "pointer", whiteSpace: "nowrap",
      border: active ? "1px solid var(--primary)" : "1px solid var(--border)",
      background: active ? "var(--primary)" : "var(--surface)", color: active ? "#fff" : "var(--subtext)",
    }) as const;

  return (
    <ModalShell
      title={`${opening ? "Mở bàn & gọi món" : "Thêm món"} — ${tableName}`}
      subtitle={`${zone ? zone + " • " : ""}${opening ? "Bàn đang trống" : `Đơn hiện có ${existingCount} dòng món`} • Gọi món dự phòng trên Web`}
      icon={<ChefHat size={18} color="var(--primary)" />}
      maxWidth={940}
      onClose={onCancel}
    >
      {err && <div style={errorBox}>{err}</div>}
      <div style={{ display: "grid", gridTemplateColumns: "minmax(0, 1.5fr) minmax(0, 1fr)", gap: 16 }} className="grid-stack-sm">
        {/* Thực đơn */}
        <div style={{ minWidth: 0 }}>
          {picking && (
            <div style={{ border: "2px solid var(--primary)", borderRadius: 12, padding: 14, marginBottom: 12, background: "var(--surface)" }}>
              <div style={{ fontWeight: 800, fontSize: 14 }}>
                {picking.product.name} <span style={{ color: "var(--primary)", fontWeight: 600 }}>{fmt(picking.product.price)}</span>
              </div>
              {picking.opts.sizes.length > 0 && (
                <OptionGroup label="Size">
                  {picking.opts.sizes.map((z) => (
                    <button key={z.name} type="button" style={chip(picking.sel.size === z.name)} onClick={() => setPicking({ ...picking, sel: { ...picking.sel, size: z.name } })}>
                      {z.name}{z.extra > 0 ? ` +${fmt(z.extra)}` : ""}
                    </button>
                  ))}
                </OptionGroup>
              )}
              {picking.opts.iceSugar && (
                <>
                  <OptionGroup label="Đường">
                    {SUGAR_OPTIONS.map((o) => (
                      <button key={o} type="button" style={chip(picking.sel.sugar === o)} onClick={() => setPicking({ ...picking, sel: { ...picking.sel, sugar: o } })}>{o}</button>
                    ))}
                  </OptionGroup>
                  <OptionGroup label="Đá">
                    {ICE_OPTIONS.map((o) => (
                      <button key={o} type="button" style={chip(picking.sel.ice === o)} onClick={() => setPicking({ ...picking, sel: { ...picking.sel, ice: o } })}>{o}</button>
                    ))}
                  </OptionGroup>
                </>
              )}
              {picking.opts.catalogMode
                ? picking.opts.toppingGroups.map((g) => (
                    <OptionGroup key={g.id} label={`${g.name}${!g.multi ? " (chọn 1)" : g.max > 0 ? ` (tối đa ${g.max})` : ""}`}>
                      {g.items.map((t) => {
                        const on = picking.sel.toppings.includes(t.name);
                        return (
                          <button
                            key={t.id}
                            type="button"
                            style={chip(on)}
                            onClick={() => setPicking({ ...picking, sel: { ...picking.sel, toppings: toggleTopping(picking.sel.toppings, g, t.name) } })}
                          >
                            {t.name}{t.price > 0 ? ` +${fmt(t.price)}` : ""}
                          </button>
                        );
                      })}
                    </OptionGroup>
                  ))
                : null}
              {!picking.opts.catalogMode && picking.opts.toppings.length > 0 && (
                <OptionGroup label="Topping (chọn nhiều)">
                  {picking.opts.toppings.map((t) => {
                    const on = picking.sel.toppings.includes(t.name);
                    return (
                      <button
                        key={t.name}
                        type="button"
                        style={chip(on)}
                        onClick={() =>
                          setPicking({
                            ...picking,
                            sel: { ...picking.sel, toppings: on ? picking.sel.toppings.filter((x) => x !== t.name) : [...picking.sel.toppings, t.name] },
                          })
                        }
                      >
                        {t.name} +{fmt(t.price)}
                      </button>
                    );
                  })}
                </OptionGroup>
              )}
              <div style={{ display: "flex", gap: 8, alignItems: "center", marginTop: 12, flexWrap: "wrap" }}>
                <button type="button" aria-label="Giảm" style={{ ...btnGhost, padding: "4px 10px" }} onClick={() => setPicking({ ...picking, qty: Math.max(1, picking.qty - 1) })}><Minus size={13} /></button>
                <strong>{picking.qty}</strong>
                <button type="button" aria-label="Tăng" style={{ ...btnGhost, padding: "4px 10px" }} onClick={() => setPicking({ ...picking, qty: picking.qty + 1 })}><Plus size={13} /></button>
                <input
                  value={picking.note} onChange={(e) => setPicking({ ...picking, note: e.target.value })} placeholder="Ghi chú" maxLength={80}
                  style={{ flex: 1, minWidth: 120, padding: "6px 10px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)", fontSize: 12 }}
                />
                <button type="button" style={btnGhost} onClick={() => setPicking(null)}>Hủy</button>
                <button type="button" className="btn-primary" onClick={confirmPicking}>Thêm vào đơn</button>
              </div>
              {picking.opts.noteChips.length > 0 && (
                <OptionGroup label="Ghi chú nhanh">
                  {picking.opts.noteChips.map((n) => {
                    const on = picking.note.includes(n);
                    return (
                      <button
                        key={n}
                        type="button"
                        style={chip(on)}
                        onClick={() => {
                          const parts = picking.note.split(",").map((x) => x.trim()).filter(Boolean);
                          const next = on ? parts.filter((x) => x !== n) : [...parts, n];
                          setPicking({ ...picking, note: next.join(", ").slice(0, 80) });
                        }}
                      >
                        {n}
                      </button>
                    );
                  })}
                </OptionGroup>
              )}
            </div>
          )}
          <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "8px 12px", border: "1px solid var(--border)", borderRadius: 8, background: "var(--bg)", marginBottom: 8 }}>
            <Search size={14} />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Tìm món..."
              style={{ border: "none", background: "transparent", outline: "none", width: "100%", fontSize: 13, color: "var(--text)" }}
            />
          </div>
          <div style={{ display: "flex", gap: 6, overflowX: "auto", paddingBottom: 6, marginBottom: 8 }}>
            <button type="button" style={chip(category === "ALL")} onClick={() => setCategory("ALL")}>Tất cả</button>
            {categories.map((c) => (
              <button key={c} type="button" style={chip(category === c)} onClick={() => setCategory(c)}>{c}</button>
            ))}
          </div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))", gap: 8, maxHeight: 380, overflowY: "auto", paddingRight: 4 }}>
            {shown.length === 0 && <div style={{ fontSize: 13, color: "var(--subtext)", gridColumn: "1 / -1" }}>Không có món phù hợp</div>}
            {shown.map((p) => {
              const out = !isProductAvailable(p);
              return (
                <button
                  key={p.id}
                  type="button"
                  disabled={out}
                  aria-label={out ? `${p.name} (hết hàng)` : p.name}
                  onClick={() => add(p)}
                  style={{ textAlign: "left", padding: "10px 12px", borderRadius: 10, border: "1px solid var(--border)", background: "var(--surface)", color: "var(--text)", cursor: out ? "not-allowed" : "pointer", opacity: out ? 0.55 : 1 }}
                >
                  <div style={{ fontSize: 13, fontWeight: 700, lineHeight: 1.25 }}>{p.name}</div>
                  <div style={{ fontSize: 12, color: "var(--primary)", marginTop: 4, fontWeight: 600 }}>{fmt(p.price)}</div>
                  {out && (
                    <span style={{ display: "inline-block", marginTop: 4, padding: "1px 6px", borderRadius: 6, background: "var(--danger, #b4232c)", color: "#fff", fontSize: 10, fontWeight: 700 }}>
                      Hết hàng
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Giỏ */}
        <div style={{ minWidth: 0, display: "flex", flexDirection: "column", border: "1px solid var(--border)", borderRadius: 12, padding: 12, background: "var(--surface-muted)" }}>
          <div style={{ fontSize: 13, fontWeight: 800, marginBottom: 8 }}>Món vừa chọn ({totalQty})</div>
          <div style={{ flex: 1, maxHeight: 250, overflowY: "auto", display: "grid", gap: 8, alignContent: "start" }}>
            {lines.length === 0 && <div style={{ fontSize: 12, color: "var(--subtext)" }}>Chạm vào món bên trái để thêm.</div>}
            {lines.map((l, i) => (
              <div key={i} style={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 8, padding: 8 }}>
                <div style={{ display: "flex", justifyContent: "space-between", gap: 8, fontSize: 13, fontWeight: 600 }}>
                  <span>
                    {String(l.name ?? "")}
                    {soldOutNames.has(String(l.name ?? "")) && (
                      <span style={{ display: "inline-block", marginLeft: 6, padding: "1px 6px", borderRadius: 6, background: "var(--danger, #b4232c)", color: "#fff", fontSize: 10, fontWeight: 700 }}>
                        Món đã hết hàng
                      </span>
                    )}
                    {describeSelection(l) && <span style={{ display: "block", fontSize: 11, fontWeight: 400, color: "var(--subtext)" }}>{describeSelection(l)}</span>}
                  </span>
                  <span>{fmt(lineUnitPrice(l) * lineQuantity(l))}</span>
                </div>
                <div style={{ display: "flex", alignItems: "center", gap: 6, marginTop: 6 }}>
                  <button type="button" aria-label="Giảm" onClick={() => changeQty(i, -1)} style={{ ...btnGhost, padding: "4px 8px" }}>
                    {lineQuantity(l) === 1 ? <Trash2 size={13} /> : <Minus size={13} />}
                  </button>
                  <strong style={{ minWidth: 20, textAlign: "center" }}>{lineQuantity(l)}</strong>
                  <button type="button" aria-label="Tăng" onClick={() => changeQty(i, 1)} style={{ ...btnGhost, padding: "4px 8px" }}>
                    <Plus size={13} />
                  </button>
                  <StickyNote size={13} color="var(--subtext)" style={{ marginLeft: 6 }} />
                  <input
                    value={String(l.note ?? "")}
                    onChange={(e) => setNote(i, e.target.value)}
                    placeholder="Ghi chú (ít đá...)"
                    maxLength={80}
                    style={{ flex: 1, minWidth: 0, border: "none", borderBottom: "1px dashed var(--border)", background: "transparent", fontSize: 12, outline: "none", color: "var(--text)" }}
                  />
                </div>
              </div>
            ))}
          </div>

          {opening && (
            <label style={{ fontSize: 12, fontWeight: 600, marginTop: 10, display: "flex", alignItems: "center", justifyContent: "space-between" }}>
              Số khách
              <input
                type="number" min={1} max={99} value={guests} onChange={(e) => setGuests(e.target.value)}
                style={{ width: 70, padding: "6px 8px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)" }}
              />
            </label>
          )}
          {canSendKitchen && (
            <input
              value={kitchenNote} onChange={(e) => setKitchenNote(e.target.value)} placeholder="Ghi chú cho bếp (tùy chọn)" maxLength={100}
              style={{ marginTop: 8, padding: "7px 10px", borderRadius: 6, border: "1px solid var(--border)", background: "var(--bg)", color: "var(--text)", fontSize: 12 }}
            />
          )}

          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 15, fontWeight: 800, margin: "12px 0 8px" }}>
            <span>Tạm tính</span>
            <span style={{ color: "var(--primary)" }}>{fmt(subTotal)}</span>
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            {canSendKitchen && (
              <button
                type="button" disabled={saving || lines.length === 0} onClick={() => submit(true)}
                className="btn-primary" style={{ justifyContent: "center", opacity: saving || lines.length === 0 ? 0.6 : 1 }}
              >
                <ChefHat size={15} /> {saving ? "Đang lưu..." : "Lưu & gửi bếp"}
              </button>
            )}
            <button
              type="button" disabled={saving || lines.length === 0} onClick={() => submit(false)}
              className="btn-secondary" style={{ justifyContent: "center", opacity: saving || lines.length === 0 ? 0.6 : 1 }}
            >
              <Save size={15} /> Chỉ lưu đơn (chưa gửi bếp)
            </button>
          </div>
        </div>
      </div>
    </ModalShell>
  );
}

function OptionGroup({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div style={{ marginTop: 10 }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: "var(--subtext)", marginBottom: 4 }}>{label}</div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>{children}</div>
    </div>
  );
}
