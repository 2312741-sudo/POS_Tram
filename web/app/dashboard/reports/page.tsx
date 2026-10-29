"use client";
import React, { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  BarChart3,
  BadgePercent,
  CalendarRange,
  ClipboardCheck,
  Clock,
  FileSpreadsheet,
  History,
  Receipt,
  Search,
  ShieldAlert,
  ShoppingBag,
  ShoppingCart,
  Store,
  TrendingUp,
  Users,
  Wallet,
  Warehouse,
  type LucideIcon,
} from "lucide-react";
import { useDashboardData } from "@/lib/data-context";
import { useAuth, canAccessRoute } from "@/lib/auth";
import { businessDayStartFor } from "@/lib/business-day";
import { buildProductCodeMap } from "@/lib/product-code";
import { buildToppingLookup } from "@/lib/topping-split";
import { calculateOverviewReport, formatVND, type ProductLookup } from "@/lib/reports";
import {
  formatRangeLabel,
  inReportRange,
  resolveReportRange,
  soldItemRows,
  staffItemSummary,
  type ReportRangePreset,
} from "@/lib/staff-sales-report";
import { exportReportsWorkbook } from "@/lib/export";

const PRESETS: { key: ReportRangePreset; label: string }[] = [
  { key: "TODAY", label: "Hôm nay" },
  { key: "YESTERDAY", label: "Hôm qua" },
  { key: "7DAYS", label: "7 ngày qua" },
  { key: "THIS_MONTH", label: "Tháng này" },
  { key: "LAST_MONTH", label: "Tháng trước" },
  { key: "CUSTOM", label: "Tùy chọn" },
];

interface ReportLink {
  href: string;
  title: string;
  desc: string;
  icon: LucideIcon;
}

const GROUPS: { title: string; items: ReportLink[] }[] = [
  {
    title: "Tài chính",
    items: [
      { href: "/dashboard/end-of-day", title: "Cuối ngày (Z-Report)", desc: "Tổng hợp, thu chi, hàng hóa, phòng bàn", icon: ClipboardCheck },
      { href: "/dashboard/revenue", title: "Doanh thu theo kỳ", desc: "Ngày / tuần / tháng / năm, hình thức thanh toán", icon: TrendingUp },
      { href: "/dashboard/analytics", title: "Phân tích kinh doanh", desc: "20 chỉ số, khung giờ, năng suất nhân viên", icon: BarChart3 },
      { href: "/dashboard/shifts", title: "Ca két & chênh lệch", desc: "Phiếu bàn giao ca, tiền mặt thực tế", icon: Wallet },
      { href: "/dashboard/reports/promotions", title: "Khuyến mãi & voucher", desc: "Theo chương trình, đổi điểm, giảm theo món", icon: BadgePercent },
    ],
  },
  {
    title: "Vận hành",
    items: [
      { href: "/dashboard/product-sales", title: "Hàng hóa bán ra", desc: "Món, nhóm hàng, lợi nhuận gộp (topping tách riêng)", icon: ShoppingCart },
      { href: "/dashboard/orders", title: "Hóa đơn & chi tiết món", desc: "Từng hóa đơn, người order, người thu tiền", icon: ShoppingBag },
      { href: "/dashboard/kitchen-sla", title: "Tốc độ bếp", desc: "Thời gian ra món, món trễ", icon: Clock },
      { href: "/dashboard/reports/inventory", title: "Kho hàng", desc: "Tồn kho, nhập xuất, kiểm kho", icon: Warehouse },
    ],
  },
  {
    title: "Kiểm soát & khách hàng",
    items: [
      { href: "/dashboard/audit", title: "Nhật ký kiểm soát", desc: "Xóa món, hủy đơn, sửa giá", icon: ShieldAlert },
      { href: "/dashboard/reports/loyalty", title: "Lịch sử điểm khách", desc: "Tích / đổi điểm thành viên", icon: History },
      { href: "/dashboard/customers", title: "Khách hàng (CRM)", desc: "Khách quen, chi tiêu, sinh nhật", icon: Users },
    ],
  },
];

const card: React.CSSProperties = {
  background: "var(--surface)",
  borderRadius: "16px",
  border: "1px solid var(--border)",
  padding: "20px 24px",
  marginBottom: "20px",
  boxShadow: "0 2px 10px rgba(0,0,0,0.03)",
};
const control: React.CSSProperties = {
  display: "flex",
  alignItems: "center",
  gap: "8px",
  background: "var(--bg)",
  border: "1px solid var(--border)",
  borderRadius: "10px",
  padding: "6px 12px",
};
const bare: React.CSSProperties = { background: "transparent", border: "none", outline: "none", fontSize: "13px", fontWeight: 600, color: "var(--text)" };
const th: React.CSSProperties = { textAlign: "left", padding: "8px 10px", fontSize: "12px", color: "var(--subtext)", fontWeight: 700, borderBottom: "1px solid var(--border)", whiteSpace: "nowrap" };
const td: React.CSSProperties = { padding: "8px 10px", fontSize: "13px", borderBottom: "1px solid var(--border)", color: "var(--text)" };
const num: React.CSSProperties = { ...td, textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" };

export default function ReportsHubPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, historyLoaded, products } = useDashboardData();
  const [preset, setPreset] = useState<ReportRangePreset>("TODAY");
  const [customFrom, setCustomFrom] = useState("");
  const [customTo, setCustomTo] = useState("");
  const [staffFilter, setStaffFilter] = useState("ALL");
  const [search, setSearch] = useState("");

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

  const bills = useMemo(
    () => historyData.filter((b) => (currentStoreCode === "ALL" || !b.storeCode || b.storeCode === currentStoreCode) && inReportRange(b, range)),
    [historyData, currentStoreCode, range]
  );

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

  const overview = useMemo(() => calculateOverviewReport(bills), [bills]);
  const sold = useMemo(() => soldItemRows(bills, codeMap, undefined, toppingLookup), [bills, codeMap, toppingLookup]);
  const { items: staffItems, staff } = useMemo(() => staffItemSummary(sold), [sold]);

  const shownItems = useMemo(() => {
    const q = search.trim().toLowerCase();
    return staffItems.filter(
      (r) =>
        (staffFilter === "ALL" || r.orderStaffName === staffFilter) &&
        (!q || r.productName.toLowerCase().includes(q) || r.productCode.toLowerCase().includes(q))
    );
  }, [staffItems, staffFilter, search]);

  const storeInfo = useMemo(() => {
    const s = stores.find((x) => x.storeCode === currentStoreCode);
    return { storeCode: currentStoreCode === "ALL" ? "ALL" : currentStoreCode, storeName: s?.storeName || (currentStoreCode === "ALL" ? "Tất cả chi nhánh" : currentStoreCode) };
  }, [stores, currentStoreCode]);

  const exportAll = () =>
    exportReportsWorkbook({ bills, productsMap, codeMap, lookupTopping: toppingLookup, storeInfo, rangeLabel, range });

  const kpis: { label: string; value: string; sub?: string }[] = [
    { label: "Doanh thu thuần", value: formatVND(overview.netRevenue), sub: `Gộp ${formatVND(overview.grossRevenue)}` },
    { label: "Hóa đơn hoàn thành", value: String(overview.paidBillsCount), sub: `TB ${formatVND(overview.avgRevenuePerPaidBill)} / HĐ` },
    { label: "Tổng giảm giá", value: formatVND(overview.totalDiscount), sub: `Món ${formatVND(overview.itemDiscounts)} • Đơn ${formatVND(overview.billDiscounts)}` },
    { label: "Lợi nhuận gộp", value: formatVND(overview.grossProfit), sub: `${overview.grossProfitMarginPercent}% doanh thu` },
    { label: "Đơn hủy", value: String(overview.cancelledBillsCount), sub: formatVND(overview.cancelledTotalValue) },
  ];

  const loading = !historyLoaded && historyData.length === 0;

  return (
    <div style={{ maxWidth: "1280px", margin: "0 auto" }}>
      {/* Tiêu đề + bộ lọc */}
      <div style={card}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", flexWrap: "wrap", gap: "16px" }}>
          <div style={{ minWidth: 0 }}>
            <h1 style={{ fontSize: "22px", fontWeight: 800, color: "var(--text)", margin: 0 }}>Trung tâm báo cáo</h1>
            <p style={{ fontSize: "13px", color: "var(--subtext)", margin: "4px 0 0" }}>
              Tài chính & vận hành theo ngày kinh doanh • {rangeLabel}
            </p>
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
            <div style={control}>
              <Store size={16} color="var(--primary)" />
              <select aria-label="Chi nhánh" value={currentStoreCode} onChange={(e) => setCurrentStoreCode(e.target.value)} style={{ ...bare, cursor: "pointer" }}>
                <option value="ALL">Tất cả chi nhánh</option>
                {stores.map((s) => (
                  <option key={s.storeCode} value={s.storeCode}>
                    {s.storeCode} - {s.storeName}
                  </option>
                ))}
              </select>
            </div>
            <div style={control}>
              <CalendarRange size={16} color="var(--primary)" />
              <select aria-label="Khoảng ngày" value={preset} onChange={(e) => setPreset(e.target.value as ReportRangePreset)} style={{ ...bare, cursor: "pointer" }}>
                {PRESETS.map((p) => (
                  <option key={p.key} value={p.key}>
                    {p.label}
                  </option>
                ))}
              </select>
            </div>
            {preset === "CUSTOM" && (
              <div style={{ ...control, gap: "6px" }}>
                <input aria-label="Từ ngày" type="date" value={customFrom} onChange={(e) => setCustomFrom(e.target.value)} style={bare} />
                <span style={{ color: "var(--subtext)" }}>→</span>
                <input aria-label="Đến ngày" type="date" value={customTo} min={customFrom || undefined} onChange={(e) => setCustomTo(e.target.value)} style={bare} />
              </div>
            )}
            <button
              onClick={exportAll}
              disabled={loading}
              title="Một file gồm 12 sheet: tổng quan, doanh thu, thanh toán, hàng hóa, nhóm hàng, nhân viên, NV × món, chi tiết món, hóa đơn, khung giờ, hủy đơn, lợi nhuận"
              style={{ display: "flex", alignItems: "center", gap: "6px", padding: "8px 14px", background: "#107C41", color: "#fff", border: "none", borderRadius: "8px", fontSize: "13px", fontWeight: 700, cursor: loading ? "wait" : "pointer" }}
            >
              <FileSpreadsheet size={16} /> Xuất Excel tổng hợp
            </button>
          </div>
        </div>
      </div>

      {/* Chỉ số chính */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "12px", marginBottom: "20px" }}>
        {kpis.map((k) => (
          <div key={k.label} style={{ ...card, marginBottom: 0, padding: "14px 16px" }}>
            <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 600 }}>{k.label}</div>
            <div style={{ fontSize: "20px", fontWeight: 800, color: "var(--text)", marginTop: "4px", fontVariantNumeric: "tabular-nums" }}>{loading ? "…" : k.value}</div>
            {k.sub && <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>{loading ? "" : k.sub}</div>}
          </div>
        ))}
      </div>

      {/* Ai bán món gì */}
      <div style={card}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px", marginBottom: "12px" }}>
          <div>
            <h2 style={{ fontSize: "16px", fontWeight: 800, margin: 0, color: "var(--text)" }}>Nhân viên bán món nào</h2>
            <p style={{ fontSize: "12px", color: "var(--subtext)", margin: "2px 0 0" }}>Theo người order món; topping là dòng riêng. File Excel có thêm chi tiết từng món kèm người thu tiền.</p>
          </div>
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap" }}>
            <div style={control}>
              <Users size={15} color="var(--subtext)" />
              <select aria-label="Nhân viên" value={staffFilter} onChange={(e) => setStaffFilter(e.target.value)} style={{ ...bare, cursor: "pointer" }}>
                <option value="ALL">Tất cả nhân viên</option>
                {staff.map((s) => (
                  <option key={s.orderStaffName} value={s.orderStaffName}>
                    {s.orderStaffName}
                  </option>
                ))}
              </select>
            </div>
            <div style={control}>
              <Search size={15} color="var(--subtext)" />
              <input aria-label="Tìm món" placeholder="Tìm món / mã món" value={search} onChange={(e) => setSearch(e.target.value)} style={{ ...bare, width: "160px" }} />
            </div>
          </div>
        </div>

        {staff.length > 0 && (
          <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", marginBottom: "12px" }}>
            {staff.map((s) => (
              <button
                key={s.orderStaffName}
                onClick={() => setStaffFilter(staffFilter === s.orderStaffName ? "ALL" : s.orderStaffName)}
                style={{
                  padding: "6px 10px",
                  borderRadius: "10px",
                  border: `1px solid ${staffFilter === s.orderStaffName ? "var(--primary)" : "var(--border)"}`,
                  background: staffFilter === s.orderStaffName ? "var(--primary-light)" : "var(--bg)",
                  color: "var(--text)",
                  fontSize: "12px",
                  cursor: "pointer",
                  textAlign: "left",
                }}
              >
                <b>{s.orderStaffName}</b> • {s.itemCount} món • {s.billCount} HĐ • {formatVND(s.netAmount)}
              </button>
            ))}
          </div>
        )}

        <div style={{ overflowX: "auto" }}>
          <table style={{ width: "100%", borderCollapse: "collapse", minWidth: "640px" }}>
            <thead>
              <tr>
                <th style={th}>Nhân viên order</th>
                <th style={th}>Mã món</th>
                <th style={th}>Tên món</th>
                <th style={th}>Nhóm</th>
                <th style={{ ...th, textAlign: "right" }}>Số lượng</th>
                <th style={{ ...th, textAlign: "right" }}>Giảm giá</th>
                <th style={{ ...th, textAlign: "right" }}>Doanh thu thuần</th>
                <th style={{ ...th, textAlign: "right" }}>Số HĐ</th>
              </tr>
            </thead>
            <tbody>
              {shownItems.slice(0, 300).map((r) => (
                <tr key={`${r.orderStaffName}|${r.productCode}|${r.productName}`}>
                  <td style={td}>{r.orderStaffName}</td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{r.productCode}</td>
                  <td style={td}>{r.productName}</td>
                  <td style={{ ...td, color: "var(--subtext)" }}>{r.category}</td>
                  <td style={num}>{r.quantity}</td>
                  <td style={num}>{r.discountAmount ? formatVND(r.discountAmount) : "—"}</td>
                  <td style={{ ...num, fontWeight: 700 }}>{formatVND(r.netAmount)}</td>
                  <td style={num}>{r.billCount}</td>
                </tr>
              ))}
              {!loading && shownItems.length === 0 && (
                <tr>
                  <td style={{ ...td, textAlign: "center", color: "var(--subtext)", padding: "24px" }} colSpan={8}>
                    Không có món bán ra trong {rangeLabel.toLowerCase()}.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
          {shownItems.length > 300 && (
            <p style={{ fontSize: "12px", color: "var(--subtext)", margin: "8px 0 0" }}>
              Đang hiện 300 / {shownItems.length} dòng. Xuất Excel để xem đủ.
            </p>
          )}
        </div>
      </div>

      {/* Danh mục báo cáo chi tiết */}
      {GROUPS.map((g) => {
        const items = g.items.filter((i) => canAccessRoute(user, i.href));
        if (items.length === 0) return null;
        return (
          <div key={g.title} style={card}>
            <h2 style={{ fontSize: "16px", fontWeight: 800, margin: "0 0 12px", color: "var(--text)" }}>{g.title}</h2>
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))", gap: "10px" }}>
              {items.map((i) => (
                <Link
                  key={i.href}
                  href={i.href}
                  style={{ display: "flex", gap: "10px", alignItems: "flex-start", padding: "12px", border: "1px solid var(--border)", borderRadius: "12px", textDecoration: "none", background: "var(--bg)" }}
                >
                  <i.icon size={20} color="var(--primary)" style={{ flexShrink: 0, marginTop: "2px" }} />
                  <span style={{ minWidth: 0 }}>
                    <span style={{ display: "block", fontSize: "14px", fontWeight: 700, color: "var(--text)" }}>{i.title}</span>
                    <span style={{ display: "block", fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>{i.desc}</span>
                  </span>
                </Link>
              ))}
            </div>
          </div>
        );
      })}
      <p style={{ fontSize: "12px", color: "var(--subtext)", textAlign: "center", margin: "0 0 24px" }}>
        <Receipt size={12} style={{ verticalAlign: "-2px" }} /> Số liệu theo ngày kinh doanh của cửa hàng (Cài đặt cửa hàng → giờ bắt đầu ngày).
      </p>
    </div>
  );
}
