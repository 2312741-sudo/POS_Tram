"use client";
import { useEffect, useMemo, useState } from "react";
import { CheckCircle2, ChefHat, Clock } from "lucide-react";
import { onValue, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { useAuth } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import { buildMarkDoneUpdates, nowMs, parseKitchenTickets, waitingMinutes } from "@/lib/kitchen";
import { errorMessage } from "@/lib/errors";

/** Màn hình Bếp trên Web: phiếu bếp chưa xong theo thời gian thực, bấm "Xong" khi làm xong */
export default function KitchenPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();
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
