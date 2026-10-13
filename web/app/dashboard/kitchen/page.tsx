"use client";
import { useEffect, useMemo, useState } from "react";
import { Ban, CheckCircle2, ChefHat, Clock, Search } from "lucide-react";
import { onValue, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { hasPermission, useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { buildMarkDoneUpdates, nowMs, parseKitchenTickets, waitingMinutes } from "@/lib/kitchen";
import { errorMessage } from "@/lib/errors";
import { isProductAvailable, soldOutNote } from "@/lib/product-availability";
import { writeSoldOut } from "@/lib/product-availability-run";

/** Màn hình Bếp trên Web: phiếu bếp chưa xong theo thời gian thực, bấm "Xong" khi làm xong */
export default function KitchenPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, products } = useDashboardData();
  // Đang xem "Tất cả chi nhánh" → dùng chi nhánh của tài khoản
  const storeCode = currentStoreCode !== "ALL" && currentStoreCode ? currentStoreCode : user?.storeCode || stores[0]?.storeCode || "";

  const [raw, setRaw] = useState<Record<string, unknown>>({});
  const [error, setError] = useState("");
  const [busyKey, setBusyKey] = useState("");
  const [now, setNow] = useState(0);

  useEffect(() => {
    if (!storeCode) return;
    return onValue(
      ref(db, `stores/${storeCode}/kitchen_orders`),
      (snap) => {
        setRaw((p) => ({ ...p, [storeCode]: snap.val() }));
        setError("");
      },
      (e) => setError(e.message || "Không đọc được phiếu bếp")
    );
  }, [storeCode]);

  useEffect(() => {
    const tick = () => setNow(nowMs());
    const first = setTimeout(tick, 0);
    const t = setInterval(tick, 30_000);
    return () => {
      clearTimeout(first);
      clearInterval(t);
    };
  }, []);

  const tickets = useMemo(() => parseKitchenTickets(storeCode, raw[storeCode]), [storeCode, raw]);

  // ===== Báo hết món (quyền TOGGLE_ITEM_AVAILABILITY) =====
  const canToggle = hasPermission(user, "TOGGLE_ITEM_AVAILABILITY");
  const [showSoldOut, setShowSoldOut] = useState(false);
  const [search, setSearch] = useState("");
  const [untilTomorrow, setUntilTomorrow] = useState(true);
  const [availBusy, setAvailBusy] = useState("");
  const menu = useMemo(() => {
    const q = search.trim().toLowerCase();
    return products
      .filter((p) => (p.storeCode || storeCode) === storeCode && !p.isTopping && (!q || p.name.toLowerCase().includes(q)))
      .sort((a, b) => a.name.localeCompare(b.name, "vi"));
  }, [products, storeCode, search]);
  const soldOutCount = useMemo(() => products.filter((p) => (p.storeCode || storeCode) === storeCode && !isProductAvailable(p, now || undefined)).length, [products, storeCode, now]);

  const toggleSoldOut = async (id: string, name: string, soldOut: boolean) => {
    setAvailBusy(id);
    setError("");
    try {
      await writeSoldOut(db, {
        storeCode,
        productKey: id,
        productName: name,
        soldOut,
        untilNextReset: soldOut && untilTomorrow,
        actor: { username: user?.username || "bep", fullName: user?.fullName, role: user?.roleId || user?.role },
      });
    } catch (e) {
      setError(errorMessage(e, `Không cập nhật được ${name}`));
    } finally {
      setAvailBusy("");
    }
  };

  const markDone = async (key: string) => {
    setBusyKey(key);
    try {
      await update(ref(db), buildMarkDoneUpdates(storeCode, key, nowMs()));
    } catch (e) {
      setError(errorMessage(e, "Không cập nhật được phiếu bếp"));
    } finally {
      setBusyKey("");
    }
  };

  return (
    <div style={{ padding: "24px 28px", maxWidth: 1280, margin: "0 auto" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
        <ChefHat size={26} color="var(--primary)" />
        <div>
          <h1 style={{ fontSize: 22, fontWeight: 800, margin: 0 }}>Màn hình Bếp</h1>
          <div style={{ fontSize: 13, color: "var(--subtext)" }}>
            Chi nhánh {storeCode || "—"} • {tickets.length} phiếu đang chờ
          </div>
        </div>
      </div>

      {canToggle && (
        <div style={{ marginBottom: 16 }}>
          <button className={showSoldOut ? "btn-primary" : "btn-secondary"} onClick={() => setShowSoldOut((v) => !v)}>
            <Ban size={16} /> Hết món{soldOutCount > 0 ? ` (${soldOutCount} món đang hết)` : ""}
          </button>
          {showSoldOut && (
            <div style={{ marginTop: 12, background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 14, padding: 14 }}>
              <div style={{ display: "flex", gap: 12, flexWrap: "wrap", alignItems: "center", marginBottom: 10 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6, padding: "7px 12px", border: "1px solid var(--border)", borderRadius: 8, background: "var(--bg)", flex: 1, minWidth: 200 }}>
                  <Search size={14} />
                  <input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Tìm món..." style={{ border: "none", background: "transparent", outline: "none", width: "100%", fontSize: 13, color: "var(--text)" }} />
                </div>
                <label style={{ fontSize: 13, display: "flex", gap: 6, alignItems: "center" }}>
                  <input type="checkbox" checked={untilTomorrow} onChange={(e) => setUntilTomorrow(e.target.checked)} />
                  Tự bật lại sáng mai (5:00)
                </label>
              </div>
              <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(260px, 100%), 1fr))", gap: 8, maxHeight: 360, overflowY: "auto" }}>
                {menu.map((p) => {
                  const available = isProductAvailable(p, now || undefined);
                  return (
                    <div key={p.id} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, padding: "8px 10px", border: `1px solid ${available ? "var(--border)" : "#B3261E"}`, borderRadius: 10, background: available ? "var(--surface)" : "#FDECEA" }}>
                      <div style={{ minWidth: 0 }}>
                        <div style={{ fontSize: 13, fontWeight: 700, textDecoration: available ? "none" : "line-through" }}>{p.name}</div>
                        {!available && <div style={{ fontSize: 11, color: "#B3261E" }}>{soldOutNote(p)}</div>}
                      </div>
                      <button
                        className={available ? "btn-secondary" : "btn-primary"}
                        style={{ padding: "5px 10px", fontSize: 12, whiteSpace: "nowrap", opacity: availBusy === p.id ? 0.6 : 1 }}
                        disabled={availBusy === p.id}
                        onClick={() => toggleSoldOut(p.id, p.name, available)}
                      >
                        {available ? "Báo hết" : "Bật lại"}
                      </button>
                    </div>
                  );
                })}
                {menu.length === 0 && <div style={{ fontSize: 13, color: "var(--subtext)" }}>Không có món phù hợp</div>}
              </div>
            </div>
          )}
        </div>
      )}

      {error && <div style={{ background: "#FDECEA", color: "#B3261E", padding: "10px 14px", borderRadius: 10, marginBottom: 14, fontSize: 13 }}>{error}</div>}

      {tickets.length === 0 ? (
        <div style={{ textAlign: "center", padding: "70px 20px", color: "var(--subtext)" }}>
          <CheckCircle2 size={56} color="var(--success)" style={{ marginBottom: 12 }} />
          <div style={{ fontSize: 18, fontWeight: 800, color: "var(--text)" }}>Tất cả đơn đã xong!</div>
          <div>Đang chờ đơn mới...</div>
        </div>
      ) : (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(min(300px, 100%), 1fr))", gap: 14 }}>
          {tickets.map((t) => {
            const wait = now > 0 ? waitingMinutes(t, now) : 0;
            return (
              <div key={t.key} style={{ background: "var(--surface)", border: `2px solid ${wait >= 10 ? "#B3261E" : "var(--border)"}`, borderRadius: 14, padding: 14, display: "flex", flexDirection: "column", gap: 8 }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                  <strong style={{ fontSize: 18 }}>{t.tableName}</strong>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 4, fontSize: 12, fontWeight: 700, color: wait >= 10 ? "#B3261E" : "var(--subtext)" }}>
                    <Clock size={13} /> {wait} phút
                  </span>
                </div>
                {(t.orderCode || t.orderedByName) && (
                  <div style={{ fontSize: 11, color: "var(--subtext)" }}>
                    {t.orderCode}{t.orderCode && t.orderedByName ? " • " : ""}{t.orderedByName}
                  </div>
                )}
                <div style={{ display: "grid", gap: 6 }}>
                  {t.lines.map((l, i) => (
                    <div key={i} style={{ fontSize: 14 }}>
                      <strong>{l.quantity} ×</strong> {l.name}
                      {l.options && <div style={{ fontSize: 12, color: "var(--subtext)" }}>{l.options}</div>}
                      {l.note && <div style={{ fontSize: 12, color: "#B06000", fontWeight: 600 }}>Ghi chú: {l.note}</div>}
                    </div>
                  ))}
                </div>
                {t.note && <div style={{ background: "#FEF7E0", color: "#8A5B00", borderRadius: 8, padding: "6px 10px", fontSize: 12 }}>Bếp: {t.note}</div>}
                <button
                  className="btn-primary"
                  style={{ justifyContent: "center", marginTop: "auto", opacity: busyKey === t.key ? 0.6 : 1 }}
                  disabled={busyKey === t.key}
                  onClick={() => markDone(t.key)}
                >
                  <CheckCircle2 size={16} /> Xong
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
