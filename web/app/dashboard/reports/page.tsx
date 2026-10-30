"use client";
import React, { useEffect, useMemo, useState } from "react";
import {
  Bar, BarChart, CartesianGrid, Cell as PieCell, Legend, Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import {
  ArrowDownRight,
  ArrowUpRight,
  BadgePercent,
  Ban,
  BarChart3,
  CalendarRange,
  ChartColumn,
  ChartPie,
  ClipboardCheck,
  Clock,
  CreditCard,
  FileSpreadsheet,
  FileText,
  Gift,
  LayoutDashboard,
  ListOrdered,
  Receipt,
  ReceiptText,
  Search,
  Store,
  Tags,
  Trash2,
  TrendingUp,
  UserRound,
  Users,
  UtensilsCrossed,
  Wallet,
  type LucideIcon,
} from "lucide-react";
import { useDashboardData } from "@/lib/data-context";
import { businessDayStartFor } from "@/lib/business-day";
import { buildProductCodeMap } from "@/lib/product-code";
import { buildToppingLookup } from "@/lib/topping-split";
import {
  calculateCategoryReport,
  calculateHourlyReport,
  calculateOverviewReport,
  calculatePaymentMethodsReport,
  calculateRevenueByPeriod,
  formatVND,
  type ProductLookup,
} from "@/lib/reports";
import {
  businessToday,
  formatRangeLabel,
  inReportRange,
  resolveReportRange,
  type ReportRangePreset,
} from "@/lib/staff-sales-report";
import {
  REPORT_KINDS,
  buildHubTable,
  filterHubBills,
  hubStaffOptions,
  paymentLabel,
  percentChange,
  previousRange,
  type BillStatusFilter,
  type Cell,
  type ColType,
  type ProductSort,
  type ReportKind,
} from "@/lib/reports-hub";
import { exportReportsWorkbook, exportStandardReportExcel, printStandardReportPDF } from "@/lib/export";

const PRESETS: { key: ReportRangePreset; label: string }[] = [
  { key: "TODAY", label: "Hôm nay" },
  { key: "YESTERDAY", label: "Hôm qua" },
  { key: "7DAYS", label: "7 ngày qua" },
  { key: "THIS_MONTH", label: "Tháng này" },
  { key: "LAST_MONTH", label: "Tháng trước" },
  { key: "CUSTOM", label: "Tùy chọn" },
];

/** Biểu tượng từng báo cáo — cùng bộ với app */
const KIND_ICONS: Record<ReportKind, LucideIcon> = {
  overview: LayoutDashboard,
  periodRevenue: CalendarRange,
  category: Tags,
  product: UtensilsCrossed,
  staff: Users,
  staffItems: UserRound,
  hourly: Clock,
  paymentMethods: CreditCard,
  promotions: BadgePercent,
  campaigns: Gift,
  bills: Receipt,
  billItems: ListOrdered,
  deletedItems: Trash2,
  cancellations: Ban,
  cashShifts: Wallet,
  grossProfit: TrendingUp,
  endOfDay: ClipboardCheck,
};

const CHART_KINDS: ReportKind[] = ["periodRevenue", "hourly", "category", "paymentMethods"];
const PIE_COLORS = ["#7E2930", "#2563EB", "#16A34A", "#D97706", "#7C3AED", "#0891B2"];
const MAX_ROWS = 500;

const card: React.CSSProperties = {
  background: "var(--surface)",
  borderRadius: "14px",
  border: "1px solid var(--border)",
  padding: "16px",
  marginBottom: "14px",
  boxShadow: "0 2px 10px rgba(0,0,0,0.03)",
};
const fieldBox: React.CSSProperties = {
  display: "flex",
  flexDirection: "column",
  gap: "2px",
  background: "var(--bg)",
  border: "1px solid var(--border)",
  borderRadius: "8px",
  padding: "4px 10px 6px",
  minWidth: 0,
};
const fieldLabel: React.CSSProperties = { fontSize: "11px", color: "var(--subtext)", fontWeight: 600 };
const bare: React.CSSProperties = { background: "transparent", border: "none", outline: "none", fontSize: "13px", fontWeight: 600, color: "var(--text)", width: "100%", minWidth: 0 };
const th: React.CSSProperties = { textAlign: "left", padding: "9px 10px", fontSize: "12px", color: "var(--subtext)", fontWeight: 700, borderBottom: "1px solid var(--border)", whiteSpace: "nowrap", background: "var(--bg)", position: "sticky", top: 0 };
const td: React.CSSProperties = { padding: "8px 10px", fontSize: "13px", borderBottom: "1px solid var(--border)", color: "var(--text)" };
const btn = (bg: string): React.CSSProperties => ({
  display: "flex", alignItems: "center", gap: "6px", padding: "8px 12px", background: bg, color: "#fff",
  border: "none", borderRadius: "8px", fontSize: "13px", fontWeight: 700, cursor: "pointer", whiteSpace: "nowrap",
});

function fmtCell(v: Cell, type: ColType): string {
  if (typeof v !== "number") return v;
  if (type === "money") return formatVND(v);
  if (type === "pct") return `${v}%`;
  return v.toLocaleString("vi-VN");
}

function Field({ label, children, grow = 1 }: { label: string; children: React.ReactNode; grow?: number }) {
  return (
    <label style={{ ...fieldBox, flex: `${grow} 1 160px` }}>
      <span style={fieldLabel}>{label}</span>
      {children}
    </label>
  );
}

function Kpi({ title, value, sub, icon: Icon, color, delta }: { title: string; value: string; sub?: string; icon: LucideIcon; color: string; delta?: number | null }) {
  return (
    <div style={{ flex: "1 1 200px", minWidth: 0, padding: "12px", borderRadius: "10px", background: `${color}0F`, border: `1px solid ${color}33` }}>
      <div style={{ display: "flex", alignItems: "center", gap: "6px", color, fontSize: "12px", fontWeight: 700 }}>
        <Icon size={15} style={{ flexShrink: 0 }} />
        <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{title}</span>
      </div>
      <div style={{ fontSize: "19px", fontWeight: 800, color: "var(--text)", marginTop: "6px", fontVariantNumeric: "tabular-nums", overflowWrap: "anywhere" }}>{value}</div>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "6px", alignItems: "center", marginTop: "2px", fontSize: "12px" }}>
        {sub && <span style={{ color: "var(--subtext)" }}>{sub}</span>}
        {delta !== undefined && (
          delta === null ? (
            <span style={{ color: "var(--subtext)" }}>Kỳ trước: 0</span>
          ) : (
            <span style={{ display: "inline-flex", alignItems: "center", fontWeight: 700, color: delta >= 0 ? "#16A34A" : "#DC2626" }}>
              {delta >= 0 ? <ArrowUpRight size={13} /> : <ArrowDownRight size={13} />}
              {delta >= 0 ? "+" : ""}{delta}% so kỳ trước
            </span>
          )
        )}
      </div>
    </div>
  );
}

export default function ReportsHubPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, historyLoaded, products, cashShifts, tables } = useDashboardData();
  const [kind, setKind] = useState<ReportKind>("overview");
  const [preset, setPreset] = useState<ReportRangePreset>("TODAY");
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [shiftId, setShiftId] = useState("ALL");
  const [staff, setStaff] = useState("ALL");
  const [compare, setCompare] = useState(false);
  const [billStatus, setBillStatus] = useState<BillStatusFilter>("ALL");
  const [productSearch, setProductSearch] = useState("");
  const [productSort, setProductSort] = useState<ProductSort>("REV_DESC");

  // Mốc "hiện tại" giữ trong state (không gọi Date.now() trong render), tự làm mới mỗi phút
  const [nowTs, setNowTs] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNowTs(Date.now()), 60_000);
    return () => clearInterval(t);
  }, []);

  const range = useMemo(
    () => resolveReportRange(preset, nowTs, businessDayStartFor(currentStoreCode), { from: customFrom, to: customTo }),
    [preset, nowTs, currentStoreCode, customFrom, customTo]
  );
  const rangeLabel = formatRangeLabel(range);
  const prevRange = useMemo(() => previousRange(range), [range]);

  const storeBills = useMemo(
    () => historyData.filter((b) => currentStoreCode === "ALL" || !b.storeCode || b.storeCode === currentStoreCode),
    [historyData, currentStoreCode]
  );
  const rangeBills = useMemo(() => storeBills.filter((b) => inReportRange(b, range)), [storeBills, range]);
  const bills = useMemo(() => filterHubBills(rangeBills, shiftId, staff), [rangeBills, shiftId, staff]);
  const prevBills = useMemo(
    () => (compare ? filterHubBills(storeBills.filter((b) => inReportRange(b, prevRange)), shiftId, staff) : []),
    [compare, storeBills, prevRange, shiftId, staff]
  );

  const shifts = useMemo(() => {
    const cutoff = businessDayStartFor(currentStoreCode);
    return cashShifts.filter((s) => {
      if (currentStoreCode !== "ALL" && s.storeCode && s.storeCode !== currentStoreCode) return false;
      const d = businessToday(Number(s.openedAt) || 0, cutoff);
      return d >= range.from && d <= range.to;
    });
  }, [cashShifts, currentStoreCode, range]);
  const staffOptions = useMemo(() => hubStaffOptions(rangeBills), [rangeBills]);

  const productsMap = useMemo(() => {
    const map: Record<string | number, ProductLookup> = {};
    products.forEach((p) => {
      if (p.id != null) map[p.id] = p;
      const pid = (p as { productId?: string | number }).productId;
      if (pid != null) map[pid] = p;
      if (p.name) map[p.name] = p;
    });
    return map;
  }, [products]);
  const codeMap = useMemo(() => buildProductCodeMap(products), [products]);
  const toppingLookup = useMemo(() => buildToppingLookup(products), [products]);

  const storeInfo = useMemo(() => {
    const s = stores.find((x) => x.storeCode === currentStoreCode);
    return { storeCode: currentStoreCode, storeName: s?.storeName || (currentStoreCode === "ALL" ? "Tất cả chi nhánh" : currentStoreCode) };
  }, [stores, currentStoreCode]);

  const overview = useMemo(() => calculateOverviewReport(bills), [bills]);
  const prevOverview = useMemo(() => (compare ? calculateOverviewReport(prevBills) : null), [compare, prevBills]);

  const table = useMemo(
    () => buildHubTable(kind, {
      bills, shifts, tables, productsMap, codeMap, lookupTopping: toppingLookup,
      storeCode: storeInfo.storeCode, storeName: storeInfo.storeName, date: range.to,
      billStatus, productSearch, productSort,
    }),
    [kind, bills, shifts, tables, productsMap, codeMap, toppingLookup, storeInfo, range.to, billStatus, productSearch, productSort]
  );

  const chartData = useMemo(() => {
    switch (kind) {
      case "periodRevenue":
        return calculateRevenueByPeriod(bills, "DAY").map((p) => ({ label: p.periodLabel, value: p.netRevenue }));
      case "hourly":
        return calculateHourlyReport(bills).filter((h) => h.billCount > 0).map((h) => ({ label: h.hourLabel, value: h.netRevenue }));
      case "category":
        return calculateCategoryReport(bills, productsMap).slice(0, 12).map((c) => ({ label: c.category, value: c.netRevenue }));
      case "paymentMethods":
        return Object.entries(calculatePaymentMethodsReport(bills)).map(([m, s]) => ({ label: paymentLabel(m), value: s.finalAmount })).filter((x) => x.value > 0);
      default:
        return [];
    }
  }, [kind, bills, productsMap]);

  const meta = REPORT_KINDS.find((k) => k.kind === kind)!;
  const loading = !historyLoaded && historyData.length === 0;
  const filterNote = [shiftId !== "ALL" ? `Ca ${shifts.find((s) => String(s.shiftId || s.id || "") === shiftId)?.shiftName || shiftId}` : "", staff !== "ALL" ? `NV ${staff}` : ""].filter(Boolean).join(" • ");

  const exportOpts = () => ({
    reportCode: meta.code,
    reportTitle: meta.title.toUpperCase(),
    storeName: storeInfo.storeName,
    storeCode: storeInfo.storeCode,
    dateRangeText: `Kỳ báo cáo: ${rangeLabel}${filterNote ? ` • ${filterNote}` : ""}`,
    headers: table.columns.map((c) => c.label),
    rows: table.rows,
    totalRow: table.total,
  });
  const exportAll = () =>
    exportReportsWorkbook({ bills, productsMap, codeMap, lookupTopping: toppingLookup, storeInfo, rangeLabel, range });

  const changeStore = (code: string) => {
    setCurrentStoreCode(code);
    setShiftId("ALL");
    setStaff("ALL");
  };

  const shownRows = table.rows.slice(0, MAX_ROWS);
  const hasStatusFilter = kind === "bills" || kind === "billItems" || kind === "deletedItems";

  return (
    <div style={{ maxWidth: "1280px", margin: "0 auto" }}>
      {/* Tiêu đề + xuất file */}
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "10px", marginBottom: "12px" }}>
        <div style={{ minWidth: 0 }}>
          <h1 style={{ fontSize: "22px", fontWeight: 800, color: "var(--text)", margin: 0 }}>Trung tâm báo cáo</h1>
          <p style={{ fontSize: "13px", color: "var(--subtext)", margin: "2px 0 0" }}>Tài chính & vận hành theo ngày kinh doanh</p>
        </div>
        <button
          onClick={exportAll}
          disabled={loading}
          title="Một file gồm 12 sheet: tổng quan, doanh thu, thanh toán, hàng hóa, nhóm hàng, nhân viên, NV × món, chi tiết món, hóa đơn, khung giờ, hủy đơn, lợi nhuận"
          style={{ ...btn("#107C41"), cursor: loading ? "wait" : "pointer" }}
        >
          <FileSpreadsheet size={16} /> Xuất Excel tổng hợp
        </button>
      </div>

      {/* Bộ lọc — như app: cửa hàng, khoảng ngày / ca, nhân viên / kỳ + so sánh */}
      <div style={card}>
        <div style={{ display: "flex", flexWrap: "wrap", gap: "8px" }}>
          <Field label="Cửa hàng" grow={2}>
            <span style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <Store size={14} color="var(--primary)" style={{ flexShrink: 0 }} />
              <select aria-label="Cửa hàng" value={currentStoreCode} onChange={(e) => changeStore(e.target.value)} style={{ ...bare, cursor: "pointer" }}>
                <option value="ALL">Tất cả chi nhánh</option>
                {stores.map((s) => (
                  <option key={s.storeCode} value={s.storeCode}>{s.storeCode} - {s.storeName}</option>
                ))}
              </select>
            </span>
          </Field>
          <Field label="Khoảng ngày" grow={2}>
            <span style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <CalendarRange size={14} color="var(--primary)" style={{ flexShrink: 0 }} />
              <select aria-label="Khoảng ngày" value={preset} onChange={(e) => setPreset(e.target.value as ReportRangePreset)} style={{ ...bare, cursor: "pointer" }}>
                {PRESETS.map((p) => <option key={p.key} value={p.key}>{p.label}</option>)}
              </select>
            </span>
          </Field>
          {preset === "CUSTOM" && (
            <Field label="Từ ngày → Đến ngày" grow={2}>
              <span style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <input aria-label="Từ ngày" type="date" value={customFrom} onChange={(e) => setCustomFrom(e.target.value)} style={bare} />
                <span style={{ color: "var(--subtext)" }}>→</span>
                <input aria-label="Đến ngày" type="date" value={customTo} min={customFrom || undefined} onChange={(e) => setCustomTo(e.target.value)} style={bare} />
              </span>
            </Field>
          )}
          <Field label="Ca làm việc">
            <select aria-label="Ca làm việc" value={shiftId} onChange={(e) => setShiftId(e.target.value)} style={{ ...bare, cursor: "pointer" }}>
              <option value="ALL">Tất cả ca</option>
              {shifts.map((s) => {
                const id = String(s.shiftId || s.id || "");
                return <option key={id} value={id}>{s.shiftName || s.shiftCode || id} • {s.staffFullName}</option>;
              })}
            </select>
          </Field>
          <Field label="Nhân viên">
            <select aria-label="Nhân viên" value={staff} onChange={(e) => setStaff(e.target.value)} style={{ ...bare, cursor: "pointer" }}>
              <option value="ALL">Tất cả nhân viên</option>
              {staffOptions.map((s) => <option key={s} value={s}>{s}</option>)}
            </select>
          </Field>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "8px", marginTop: "10px" }}>
          <span style={{ fontSize: "13px", fontWeight: 700, color: "var(--primary)" }}>
            Kỳ: {rangeLabel}{compare ? ` • so với ${formatRangeLabel(prevRange).toLowerCase()}` : ""}
          </span>
          <label style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "13px", color: "var(--text)", cursor: "pointer" }}>
            <input type="checkbox" checked={compare} onChange={(e) => setCompare(e.target.checked)} style={{ accentColor: "var(--primary)" }} />
            So sánh kỳ trước
          </label>
        </div>
      </div>

      {/* Chọn báo cáo */}
      <div style={{ display: "flex", gap: "6px", overflowX: "auto", paddingBottom: "6px", marginBottom: "10px" }}>
        {REPORT_KINDS.map((k) => {
          const Icon = KIND_ICONS[k.kind];
          const on = k.kind === kind;
          return (
            <button
              key={k.kind}
              onClick={() => setKind(k.kind)}
              style={{
                display: "flex", alignItems: "center", gap: "6px", flexShrink: 0, padding: "7px 12px", borderRadius: "16px",
                border: `1px solid ${on ? "var(--primary)" : "var(--border)"}`, background: on ? "var(--primary)" : "var(--surface)",
                color: on ? "#fff" : "var(--text)", fontSize: "12px", fontWeight: on ? 700 : 500, cursor: "pointer", whiteSpace: "nowrap",
              }}
            >
              <Icon size={14} color={on ? "#fff" : "var(--primary)"} /> {k.title}
            </button>
          );
        })}
      </div>

      {/* Chỉ số tài chính cốt lõi */}
      <div style={card}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: "8px", flexWrap: "wrap", marginBottom: "10px" }}>
          <span style={{ fontSize: "12px", fontWeight: 800, color: "var(--subtext)", letterSpacing: "0.3px" }}>CHỈ SỐ TÀI CHÍNH CỐT LÕI</span>
          {compare && <span style={{ fontSize: "12px", fontWeight: 600, color: "#16A34A" }}>Đang so sánh kỳ trước</span>}
        </div>
        <div style={{ display: "flex", flexWrap: "wrap", gap: "8px" }}>
          <Kpi
            title="Doanh thu thuần" icon={Wallet} color="#7E2930"
            value={loading ? "…" : formatVND(overview.netRevenue)} sub={`Gộp ${formatVND(overview.grossRevenue)}`}
            delta={prevOverview ? percentChange(overview.netRevenue, prevOverview.netRevenue) : undefined}
          />
          <Kpi
            title="Lợi nhuận gộp" icon={TrendingUp} color="#166534"
            value={loading ? "…" : formatVND(overview.grossProfit)} sub={`Biên LN: ${overview.grossProfitMarginPercent}%`}
            delta={prevOverview ? percentChange(overview.grossProfit, prevOverview.grossProfit) : undefined}
          />
          <Kpi
            title="Số hóa đơn" icon={ReceiptText} color="#1E40AF"
            value={loading ? "…" : `${overview.paidBillsCount} đơn`} sub={`TB: ${formatVND(overview.avgRevenuePerPaidBill)}`}
            delta={prevOverview ? percentChange(overview.paidBillsCount, prevOverview.paidBillsCount) : undefined}
          />
          <Kpi
            title="Tổng giảm giá" icon={BadgePercent} color="#9A3412"
            value={loading ? "…" : formatVND(overview.totalDiscount)} sub={`VAT: ${formatVND(overview.vatTotal)}`}
            delta={prevOverview ? percentChange(overview.totalDiscount, prevOverview.totalDiscount) : undefined}
          />
        </div>
      </div>

      {/* Biểu đồ */}
      {CHART_KINDS.includes(kind) && (
        <div style={card}>
          <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "14px", fontWeight: 800, color: "var(--text)", marginBottom: "8px" }}>
            {kind === "paymentMethods" ? <ChartPie size={16} color="var(--primary)" /> : <ChartColumn size={16} color="var(--primary)" />}
            Biểu đồ {meta.title.toLowerCase()}
          </div>
          {chartData.length === 0 ? (
            <p style={{ fontSize: "13px", color: "var(--subtext)", textAlign: "center", padding: "32px 0", margin: 0 }}>Chưa có dữ liệu trong kỳ.</p>
          ) : (
            <ResponsiveContainer width="100%" height={260}>
              {kind === "paymentMethods" ? (
                <PieChart>
                  <Pie data={chartData} dataKey="value" nameKey="label" innerRadius={55} outerRadius={95} paddingAngle={2}>
                    {chartData.map((_, i) => <PieCell key={i} fill={PIE_COLORS[i % PIE_COLORS.length]} />)}
                  </Pie>
                  <Tooltip formatter={(v) => formatVND(Number(v))} />
                  <Legend />
                </PieChart>
              ) : (
                <BarChart data={chartData} margin={{ left: 8, right: 8 }}>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--border)" />
                  <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--subtext)" }} interval="preserveStartEnd" />
                  <YAxis tick={{ fontSize: 11, fill: "var(--subtext)" }} width={56} tickFormatter={(v) => (v >= 1_000_000 ? `${(v / 1_000_000).toFixed(1)}tr` : v >= 1000 ? `${Math.round(v / 1000)}k` : String(v))} />
                  <Tooltip formatter={(v) => [formatVND(Number(v)), "Doanh thu thuần"]} />
                  <Bar dataKey="value" fill="#7E2930" radius={[6, 6, 0, 0]} maxBarSize={44} />
                </BarChart>
              )}
            </ResponsiveContainer>
          )}
        </div>
      )}

      {/* Bảng báo cáo */}
      <div style={card}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "10px", marginBottom: "10px" }}>
          <div style={{ minWidth: 0 }}>
            <div style={{ display: "flex", alignItems: "center", gap: "6px", fontSize: "15px", fontWeight: 800, color: "var(--text)" }}>
              <BarChart3 size={16} color="var(--primary)" style={{ flexShrink: 0 }} /> {meta.title}
            </div>
            <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
              {meta.code} • {table.rows.length} dòng{filterNote ? ` • ${filterNote}` : ""}
            </div>
          </div>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            <button onClick={() => exportStandardReportExcel(exportOpts())} disabled={loading} style={btn("#107C41")}>
              <FileSpreadsheet size={15} /> Excel
            </button>
            <button onClick={() => printStandardReportPDF(exportOpts())} disabled={loading} style={btn("var(--primary)")}>
              <FileText size={15} /> PDF
            </button>
          </div>
        </div>

        {kind === "product" && (
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", marginBottom: "10px" }}>
            <Field label="Tìm món / mã / nhóm" grow={3}>
              <span style={{ display: "flex", alignItems: "center", gap: "6px" }}>
                <Search size={14} color="var(--subtext)" style={{ flexShrink: 0 }} />
                <input aria-label="Tìm món" placeholder="Nhập tên món, mã món…" value={productSearch} onChange={(e) => setProductSearch(e.target.value)} style={bare} />
              </span>
            </Field>
            <Field label="Sắp xếp">
              <select aria-label="Sắp xếp" value={productSort} onChange={(e) => setProductSort(e.target.value as ProductSort)} style={{ ...bare, cursor: "pointer" }}>
                <option value="REV_DESC">Doanh thu cao nhất</option>
                <option value="QTY_DESC">Bán chạy nhất</option>
                <option value="NAME_ASC">Tên A → Z</option>
              </select>
            </Field>
          </div>
        )}

        {hasStatusFilter && (
          <div style={{ display: "flex", gap: "6px", flexWrap: "wrap", marginBottom: "10px" }}>
            {([["ALL", "Tất cả"], ["PAID", "Hoàn thành"], ["CANCELLED", "Đã hủy"]] as [BillStatusFilter, string][]).map(([v, l]) => (
              <button
                key={v}
                onClick={() => setBillStatus(v)}
                style={{
                  padding: "5px 12px", borderRadius: "14px", fontSize: "12px", cursor: "pointer",
                  border: `1px solid ${billStatus === v ? "var(--primary)" : "var(--border)"}`,
                  background: billStatus === v ? "var(--primary-light)" : "var(--bg)", color: "var(--text)", fontWeight: billStatus === v ? 700 : 500,
                }}
              >
                {l}
              </button>
            ))}
          </div>
        )}

        <div style={{ overflow: "auto", maxHeight: "70vh", border: "1px solid var(--border)", borderRadius: "10px" }}>
          <table style={{ width: "100%", borderCollapse: "collapse" }}>
            <thead>
              <tr>
                {table.columns.map((c) => (
                  <th key={c.label} style={{ ...th, textAlign: c.type === "text" ? "left" : "right" }}>{c.label}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {shownRows.map((r, i) => (
                <tr key={i} style={{ background: i % 2 ? "var(--bg)" : undefined }}>
                  {r.map((v, j) => {
                    const type = table.columns[j]?.type ?? "text";
                    const isNum = typeof v === "number" || type !== "text";
                    return (
                      <td key={j} style={{ ...td, textAlign: isNum ? "right" : "left", whiteSpace: isNum ? "nowrap" : undefined, fontVariantNumeric: "tabular-nums" }}>
                        {fmtCell(v, type)}
                      </td>
                    );
                  })}
                </tr>
              ))}
              {!loading && table.rows.length === 0 && (
                <tr>
                  <td colSpan={table.columns.length} style={{ ...td, textAlign: "center", color: "var(--subtext)", padding: "28px" }}>
                    Không có dữ liệu trong {rangeLabel.toLowerCase()}.
                  </td>
                </tr>
              )}
              {loading && (
                <tr>
                  <td colSpan={table.columns.length} style={{ ...td, textAlign: "center", color: "var(--subtext)", padding: "28px" }}>Đang tải dữ liệu…</td>
                </tr>
              )}
            </tbody>
            {table.total && table.rows.length > 0 && (
              <tfoot>
                <tr>
                  {table.total.map((v, j) => {
                    const type = table.columns[j]?.type ?? "text";
                    return (
                      <td key={j} style={{ ...td, fontWeight: 800, background: "var(--primary-light)", position: "sticky", bottom: 0, textAlign: type === "text" ? "left" : "right", whiteSpace: "nowrap" }}>
                        {fmtCell(v, type)}
                      </td>
                    );
                  })}
                </tr>
              </tfoot>
            )}
          </table>
        </div>
        {table.rows.length > MAX_ROWS && (
          <p style={{ fontSize: "12px", color: "var(--subtext)", margin: "8px 0 0" }}>
            Đang hiện {MAX_ROWS} / {table.rows.length} dòng. Xuất Excel để xem đủ.
          </p>
        )}
      </div>

      <p style={{ fontSize: "12px", color: "var(--subtext)", textAlign: "center", margin: "0 0 24px" }}>
        Topping tách thành dòng riêng trong mọi báo cáo. Số liệu theo giờ bắt đầu ngày kinh doanh của cửa hàng.
      </p>
    </div>
  );
}
