"use client";
import { useState, useMemo, useEffect } from "react";
import { ref, onValue } from "firebase/database";
import { db } from "@/lib/firebase";
import { useDashboardData } from "@/lib/data-context";
import { AlertTriangle, TrendingDown, TrendingUp, Package, Box } from "lucide-react";

function formatVND(amount: number) {
  return new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(amount);
}

function formatDate(ts: number) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleDateString("vi-VN", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

interface CatalogItem {
  itemId: string;
  sku: string;
  name: string;
  trackStock: boolean;
  minStock: number;
}

interface StockBalanceItem {
  balanceId: string;
  itemId: string;
  onHandQty: number;
  inventoryValue: number;
}

interface StockEventItem {
  eventId: string;
  documentType: string;
  itemId: string;
  qtyDeltaBase: number;
  unitCostSnapshot: number;
  createdAt: number;
}

const btnPrimary: React.CSSProperties = {
  display: "flex", alignItems: "center", gap: "6px", padding: "10px 18px",
  background: "#7E2930", color: "#fff", border: "none", borderRadius: "10px",
  fontSize: "13px", fontWeight: "700", cursor: "pointer",
};
const thStyle: React.CSSProperties = {
  padding: "12px 14px", textAlign: "left", fontSize: "12px", fontWeight: "700",
  color: "#666", textTransform: "uppercase", letterSpacing: "0.03em",
};
const tdStyle: React.CSSProperties = {
  padding: "12px 14px", fontSize: "13px", color: "#333",
};
const badgeStyle = (color: string): React.CSSProperties => ({
  display: "inline-block", padding: "2px 8px", borderRadius: "6px", fontSize: "11px",
  fontWeight: "700", background: `${color}15`, color: color, whiteSpace: "nowrap",
});

const docTypeLabels: Record<string, string> = {
  PURCHASE_RECEIPT: "Nhập hàng",
  PURCHASE_RETURN: "Trả hàng NCC",
  SALE: "Bán hàng",
  STOCKTAKE_ADJUST: "Kiểm kho",
  TRANSFER_SEND: "Chuyển đi",
  TRANSFER_RECEIVE: "Nhận hàng",
  WASTE: "Xuất hủy",
  INTERNAL_USE: "Dùng nội bộ",
  PRODUCTION_INPUT: "Sản xuất (Xuất)",
  PRODUCTION_OUTPUT: "Sản xuất (Nhập)",
  ADJUSTMENT: "Điều chỉnh",
  OPENING: "Tồn đầu",
};

export default function InventoryReportPage() {
  const { stores, currentStoreCode } = useDashboardData();
  // Ở chế độ "ALL" dùng chi nhánh đầu tiên thực tế (không hardcode TRAM01)
  const targetStoreCode = currentStoreCode === "ALL" ? (stores[0]?.storeCode || "") : currentStoreCode;

  // Mã chi nhánh đã nạp xong catalog — loading được suy ra, không setState đồng bộ trong effect
  const [loadedStoreCode, setLoadedStoreCode] = useState<string | null>(null);
  const loading = !!targetStoreCode && loadedStoreCode !== targetStoreCode;
  const [catalogItems, setCatalogItems] = useState<CatalogItem[]>([]);
  const [stockBalances, setStockBalances] = useState<StockBalanceItem[]>([]);
  const [stockEvents, setStockEvents] = useState<StockEventItem[]>([]);

  useEffect(() => {
    if (!targetStoreCode) return;
    const unsubs: (() => void)[] = [];

    // Catalog Items
    const catRef = ref(db, `stores/${targetStoreCode}/catalog_items`);
    unsubs.push(onValue(catRef, (snap) => {
      const items: CatalogItem[] = [];
      snap.forEach((child) => {
        const v = child.val();
        items.push({
          itemId: child.key!,
          sku: v.sku || "",
          name: v.name || "",
          trackStock: v.trackStock ?? true,
          minStock: v.minStock || 0,
        });
      });
      setCatalogItems(items);
    }));

    // Stock Balances
    const balRef = ref(db, `stores/${targetStoreCode}/stock_balances`);
    unsubs.push(onValue(balRef, (snap) => {
      const bals: StockBalanceItem[] = [];
      snap.forEach((child) => {
        const v = child.val();
        bals.push({
          balanceId: child.key!,
          itemId: v.itemId || "",
          onHandQty: v.onHandQty || 0,
          inventoryValue: v.inventoryValue || 0,
        });
      });
      setStockBalances(bals);
    }));

    // Stock Events
    const evtRef = ref(db, `stores/${targetStoreCode}/stock_events`);
    unsubs.push(onValue(evtRef, (snap) => {
      const evts: StockEventItem[] = [];
      snap.forEach((child) => {
        const v = child.val();
        evts.push({
          eventId: child.key!,
          documentType: v.documentType || "",
          itemId: v.itemId || "",
          qtyDeltaBase: v.qtyDeltaBase || 0,
          unitCostSnapshot: v.unitCostSnapshot || 0,
          createdAt: v.createdAt || 0, // Fallback if exists
        });
      });
      // Sort desc by eventId (which usually contains timestamp) or createdAt
      evts.sort((a, b) => b.eventId.localeCompare(a.eventId));
      setStockEvents(evts.slice(0, 50));
      setLoadedStoreCode(targetStoreCode);
    }));

    return () => unsubs.forEach((u) => u());
  }, [targetStoreCode]);

  const catalogMap = useMemo(() => {
    const m: Record<string, CatalogItem> = {};
    catalogItems.forEach((i) => { m[i.itemId] = i; });
    return m;
  }, [catalogItems]);

  const { totalValue, trackedCount, lowStockCount, outOfStockCount, alerts } = useMemo(() => {
    let tv = 0;
    let tc = 0;
    let lc = 0;
    let oc = 0;
    const alts: { item: CatalogItem; balance: StockBalanceItem; ratio: number; missing: number }[] = [];

    stockBalances.forEach((bal) => {
      const item = catalogMap[bal.itemId];
      if (item && item.trackStock) {
        tv += bal.inventoryValue;
        tc++;
        if (bal.onHandQty <= 0) {
          oc++;
          alts.push({ item, balance: bal, ratio: 0, missing: item.minStock - bal.onHandQty });
        } else if (bal.onHandQty < item.minStock) {
          lc++;
          alts.push({ item, balance: bal, ratio: bal.onHandQty / (item.minStock || 1), missing: item.minStock - bal.onHandQty });
        }
      }
    });

    alts.sort((a, b) => a.ratio - b.ratio);
    return { totalValue: tv, trackedCount: tc, lowStockCount: lc, outOfStockCount: oc, alerts: alts };
  }, [stockBalances, catalogMap]);

  if (loading) {
    return <div style={{ padding: "60px", textAlign: "center", color: "#999" }}>⏳ Đang tải báo cáo...</div>;
  }

  // Chưa có chi nhánh hợp lệ -> không đọc/ghi mặc định vào chi nhánh khác
  if (!targetStoreCode) {
    return (
      <div style={{ padding: "24px", color: "#666" }}>Chưa xác định được chi nhánh. Vui lòng chọn một chi nhánh cụ thể.</div>
    );
  }

  return (
    <div style={{ padding: "24px" }}>
      <div style={{ marginBottom: "24px" }}>
        <h1 style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e", margin: 0 }}>Báo cáo Kho hàng</h1>
        <p style={{ fontSize: "14px", color: "#666", margin: "4px 0 0" }}>Tổng quan và cảnh báo tồn kho chi nhánh {targetStoreCode}</p>
      </div>

      {/* Summary Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(200px, 1fr))", gap: "16px", marginBottom: "32px" }}>
        <div style={{ background: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #eee", boxShadow: "0 2px 8px rgba(0,0,0,0.02)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "8px" }}>
            <div style={{ padding: "8px", background: "#7E293015", borderRadius: "8px", color: "#7E2930" }}><Box size={20} /></div>
            <div style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Tổng giá trị tồn</div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e" }}>{formatVND(totalValue)}</div>
        </div>
        <div style={{ background: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #eee", boxShadow: "0 2px 8px rgba(0,0,0,0.02)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "8px" }}>
            <div style={{ padding: "8px", background: "#3b82f615", borderRadius: "8px", color: "#3b82f6" }}><Package size={20} /></div>
            <div style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Số SKU theo dõi</div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e" }}>{trackedCount}</div>
        </div>
        <div style={{ background: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #eee", boxShadow: "0 2px 8px rgba(0,0,0,0.02)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "8px" }}>
            <div style={{ padding: "8px", background: "#f59e0b15", borderRadius: "8px", color: "#f59e0b" }}><TrendingDown size={20} /></div>
            <div style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Dưới định mức</div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e" }}>{lowStockCount}</div>
        </div>
        <div style={{ background: "#fff", padding: "20px", borderRadius: "12px", border: "1px solid #eee", boxShadow: "0 2px 8px rgba(0,0,0,0.02)" }}>
          <div style={{ display: "flex", alignItems: "center", gap: "12px", marginBottom: "8px" }}>
            <div style={{ padding: "8px", background: "#ef444415", borderRadius: "8px", color: "#ef4444" }}><AlertTriangle size={20} /></div>
            <div style={{ fontSize: "13px", color: "#666", fontWeight: "600" }}>Hết hàng</div>
          </div>
          <div style={{ fontSize: "24px", fontWeight: "800", color: "#1a1a2e" }}>{outOfStockCount}</div>
        </div>
      </div>

      {/* Low Stock Alerts */}
      <h2 style={{ fontSize: "16px", fontWeight: "700", marginBottom: "16px", color: "#1a1a2e" }}>Cảnh báo tồn kho</h2>
      <div style={{ background: "#fff", borderRadius: "12px", border: "1px solid #eee", overflow: "hidden", marginBottom: "32px" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead style={{ background: "#fafafa", borderBottom: "2px solid #eee" }}>
            <tr>
              <th style={thStyle}>SKU</th>
              <th style={thStyle}>Tên hàng</th>
              <th style={thStyle}>Tồn hiện tại</th>
              <th style={thStyle}>Định mức</th>
              <th style={thStyle}>Thiếu</th>
              <th style={thStyle}>Mức độ</th>
            </tr>
          </thead>
          <tbody>
            {alerts.length === 0 ? (
              <tr><td colSpan={6} style={{ ...tdStyle, textAlign: "center", color: "#999", padding: "24px" }}>Không có cảnh báo tồn kho.</td></tr>
            ) : alerts.map((alert, idx) => {
              const isOut = alert.balance.onHandQty <= 0;
              return (
                <tr key={idx} style={{ borderBottom: "1px solid #eee" }}>
                  <td style={tdStyle}>{alert.item.sku || "—"}</td>
                  <td style={{ ...tdStyle, fontWeight: "600" }}>{alert.item.name}</td>
                  <td style={tdStyle}>{alert.balance.onHandQty}</td>
                  <td style={tdStyle}>{alert.item.minStock}</td>
                  <td style={{ ...tdStyle, color: isOut ? "#ef4444" : "#f59e0b", fontWeight: "700" }}>{alert.missing}</td>
                  <td style={tdStyle}>
                    <span style={badgeStyle(isOut ? "#ef4444" : "#f59e0b")}>
                      {isOut ? "Hết hàng" : "Thấp"}
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Recent Events */}
      <h2 style={{ fontSize: "16px", fontWeight: "700", marginBottom: "16px", color: "#1a1a2e" }}>Biến động kho gần đây (50 giao dịch)</h2>
      <div style={{ background: "#fff", borderRadius: "12px", border: "1px solid #eee", overflow: "hidden" }}>
        <table style={{ width: "100%", borderCollapse: "collapse" }}>
          <thead style={{ background: "#fafafa", borderBottom: "2px solid #eee" }}>
            <tr>
              <th style={thStyle}>Thời gian</th>
              <th style={thStyle}>Loại phiếu</th>
              <th style={thStyle}>Sản phẩm</th>
              <th style={thStyle}>SL thay đổi</th>
              <th style={thStyle}>Giá vốn lúc tạo</th>
            </tr>
          </thead>
          <tbody>
            {stockEvents.length === 0 ? (
              <tr><td colSpan={5} style={{ ...tdStyle, textAlign: "center", color: "#999", padding: "24px" }}>Chưa có giao dịch kho.</td></tr>
            ) : stockEvents.map((evt) => {
              const item = catalogMap[evt.itemId];
              const isPos = evt.qtyDeltaBase > 0;
              
              // Extract timestamp from eventId format (e.g. EVT_1679450400000_XXX) or use createdAt
              let ts = evt.createdAt;
              if (!ts) {
                const parts = evt.eventId.split('_');
                if (parts.length > 1) {
                  const parsed = parseInt(parts[1]);
                  if (!isNaN(parsed) && parsed > 1000000000000) ts = parsed;
                }
              }

              return (
                <tr key={evt.eventId} style={{ borderBottom: "1px solid #eee" }}>
                  <td style={tdStyle}>{formatDate(ts)}</td>
                  <td style={tdStyle}>
                    <span style={badgeStyle(isPos ? "#10b981" : "#ef4444")}>
                      {docTypeLabels[evt.documentType] || evt.documentType}
                    </span>
                  </td>
                  <td style={{ ...tdStyle, fontWeight: "600" }}>{item ? item.name : "Sản phẩm xóa/ẩn"}</td>
                  <td style={{ ...tdStyle, color: isPos ? "#10b981" : "#ef4444", fontWeight: "700" }}>
                    {isPos ? "+" : ""}{evt.qtyDeltaBase}
                  </td>
                  <td style={tdStyle}>{formatVND(evt.unitCostSnapshot)}</td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
