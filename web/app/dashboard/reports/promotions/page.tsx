"use client";
import { Fragment, useMemo, useState } from "react";
import { format } from "date-fns";
import { BadgePercent, Calendar, ChevronDown, ChevronRight, Download, Receipt, Store, Ticket, TrendingUp } from "lucide-react";
import { useDashboardData } from "@/lib/data-context";
import { formatVND, getBillTimestamp, getUTC7Date } from "@/lib/reports";
import { calculateCampaignReport } from "@/lib/promotion-report";
import { exportCampaignReportExcel, type ReportStoreInfo } from "@/lib/export";

type RangeKey = "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM";

const selectBox = {
  display: "flex",
  alignItems: "center",
  gap: "8px",
  background: "var(--bg)",
  border: "1px solid var(--border)",
  borderRadius: "10px",
  padding: "6px 12px",
} as const;

const selectStyle = {
  background: "transparent",
  border: "none",
  outline: "none",
  fontSize: "13px",
  fontWeight: 600,
  color: "var(--text)",
  cursor: "pointer",
} as const;

export default function PromotionReportPage() {
  const { stores, currentStoreCode, setCurrentStoreCode, historyData, historyLoaded } = useDashboardData();
  const [dateRange, setDateRange] = useState<RangeKey>("TODAY");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [expanded, setExpanded] = useState<string | null>(null);

  const currentStore = useMemo(() => {
    if (currentStoreCode === "ALL") return undefined;
    return stores.find((s) => s.storeCode === currentStoreCode);
  }, [stores, currentStoreCode]);

  // Khoảng thời gian (UTC+7) — giống các báo cáo khác
  const range = useMemo(() => {
    const now = new Date().getTime();
    const n = getUTC7Date(now);
    const y = n.getUTCFullYear();
    const m = n.getUTCMonth();
    const d = n.getUTCDate();
    const OFF = 7 * 3600 * 1000;
    const dayStart = (yy: number, mm: number, dd: number) => Date.UTC(yy, mm, dd) - OFF;
    switch (dateRange) {
      case "TODAY":
        return { start: dayStart(y, m, d), end: dayStart(y, m, d + 1) - 1 };
      case "YESTERDAY":
        return { start: dayStart(y, m, d - 1), end: dayStart(y, m, d) - 1 };
      case "7DAYS":
        return { start: dayStart(y, m, d - 7), end: now };
      case "THIS_MONTH":
        return { start: dayStart(y, m, 1), end: dayStart(y, m + 1, 1) - 1 };
      case "LAST_MONTH":
        return { start: dayStart(y, m - 1, 1), end: dayStart(y, m, 1) - 1 };
      case "CUSTOM": {
        if (!customStart) return { start: 0, end: Number.MAX_SAFE_INTEGER };
        const s = new Date(customStart + "T00:00:00").getTime();
        const e = new Date((customEnd || customStart) + "T23:59:59").getTime();
        return { start: s, end: e };
      }
    }
  }, [dateRange, customStart, customEnd]);

  const rangeLabel = useMemo(() => {
    if (dateRange === "CUSTOM" && !customStart) return "Tất cả thời gian";
    const f = (t: number) => format(new Date(t), "dd/MM/yyyy");
    return `Từ ${f(range.start)} đến ${f(Math.min(range.end, new Date().getTime()))}`;
  }, [dateRange, customStart, range]);

  const bills = useMemo(
    () =>
      historyData.filter((b) => {
        if (currentStoreCode !== "ALL" && b.storeCode && b.storeCode !== currentStoreCode) return false;
        const ts = getBillTimestamp(b);
        return ts >= range.start && ts <= range.end;
      }),
    [historyData, currentStoreCode, range]
  );

  const report = useMemo(() => calculateCampaignReport(bills), [bills]);

  const handleExport = () => {
    const info: ReportStoreInfo = {
      storeName: currentStore?.storeName || (currentStoreCode === "ALL" ? "Tất cả chi nhánh" : "POS Trạm"),
      address: currentStore?.address,
      phone: currentStore?.phone,
      storeCode: currentStoreCode,
    };
    exportCampaignReportExcel(report, info, `Kỳ báo cáo: ${rangeLabel}`, { start: range.start ? new Date(range.start) : null, end: new Date(Math.min(range.end, 8.64e15)) });
  };

  const kpis = [
    { label: "Tổng giảm giá khuyến mãi", value: formatVND(report.totalDiscount), icon: BadgePercent, color: "var(--danger)" },
    { label: "Hóa đơn có khuyến mãi", value: `${report.billCount} đơn`, icon: Receipt, color: "var(--primary)" },
    { label: "Doanh thu các hóa đơn này", value: formatVND(report.revenue), icon: TrendingUp, color: "var(--success)" },
    { label: "Lượt dùng voucher", value: `${report.vouchersUsed} lượt`, icon: Ticket, color: "var(--warning)" },
  ];

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", flexWrap: "wrap", gap: "12px" }}>
        <div>
          <h1 className="section-title">Báo cáo khuyến mãi</h1>
          <p className="section-subtitle">Hiệu quả từng chương trình khuyến mãi / voucher trên hóa đơn đã thanh toán — {rangeLabel}</p>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" }}>
          <div style={selectBox}>
            <Calendar size={16} color="var(--primary)" />
            <select aria-label="Khoảng thời gian" value={dateRange} onChange={(e) => setDateRange(e.target.value as RangeKey)} style={selectStyle}>
              <option value="TODAY">Hôm nay</option>
              <option value="YESTERDAY">Hôm qua</option>
              <option value="7DAYS">7 ngày qua</option>
              <option value="THIS_MONTH">Tháng này</option>
              <option value="LAST_MONTH">Tháng trước</option>
              <option value="CUSTOM">Tùy chọn ngày</option>
            </select>
          </div>
          {dateRange === "CUSTOM" && (
            <div style={{ display: "flex", alignItems: "center", gap: "6px" }}>
              <input type="date" aria-label="Từ ngày" className="input-field" value={customStart} onChange={(e) => setCustomStart(e.target.value)} style={{ width: "auto" }} />
              <span style={{ fontSize: "12px", color: "var(--subtext)" }}>đến</span>
              <input type="date" aria-label="Đến ngày" className="input-field" value={customEnd} onChange={(e) => setCustomEnd(e.target.value)} style={{ width: "auto" }} />
            </div>
          )}
          <div style={selectBox}>
            <Store size={16} color="var(--primary)" />
            <select aria-label="Chi nhánh" value={currentStoreCode} onChange={(e) => setCurrentStoreCode(e.target.value)} style={selectStyle}>
              <option value="ALL">Tất cả chi nhánh</option>
              {stores.map((s) => (
                <option key={s.storeCode} value={s.storeCode}>
                  {s.storeName}
                </option>
              ))}
            </select>
          </div>
          <button className="btn-primary" style={{ background: "var(--success)" }} onClick={handleExport} disabled={report.campaigns.length === 0}>
            <Download size={16} /> Xuất Excel
          </button>
        </div>
      </div>

      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(220px, 100%), 1fr))", gap: "14px" }}>
        {kpis.map((k) => (
          <div key={k.label} className="stat-card">
            <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
              <k.icon size={22} color={k.color} aria-hidden />
              <div>
                <div style={{ fontSize: "17px", fontWeight: 800, color: "var(--text)" }}>{k.value}</div>
                <div style={{ fontSize: "12px", fontWeight: 600, color: "var(--subtext)" }}>{k.label}</div>
              </div>
            </div>
          </div>
        ))}
      </div>

      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th style={{ width: "36px" }} />
              <th>Chương trình</th>
              <th>Mã</th>
              <th>Loại</th>
              <th style={{ textAlign: "right" }}>Số HĐ</th>
              <th style={{ textAlign: "right" }}>Tổng giảm</th>
              <th style={{ textAlign: "right" }}>Doanh thu HĐ</th>
              <th style={{ textAlign: "right" }}>Voucher đã dùng</th>
            </tr>
          </thead>
          <tbody>
            {!historyLoaded && historyData.length === 0 ? (
              <tr>
                <td colSpan={8} style={{ textAlign: "center", padding: "40px" }}>
                  <div className="spinner" style={{ margin: "0 auto" }} />
                </td>
              </tr>
            ) : report.campaigns.length === 0 ? (
              <tr>
                <td colSpan={8} style={{ textAlign: "center", padding: "40px", color: "var(--muted)" }}>
                  Không có hóa đơn nào áp dụng khuyến mãi trong khoảng thời gian này
                </td>
              </tr>
            ) : (
              report.campaigns.map((c) => {
                const open = expanded === c.key;
                return (
                  <Fragment key={c.key}>
                    <tr style={{ cursor: "pointer" }} onClick={() => setExpanded(open ? null : c.key)}>
                      <td>
                        <button
                          type="button"
                          aria-expanded={open}
                          aria-label={open ? `Thu gọn ${c.name}` : `Xem hóa đơn của ${c.name}`}
                          onClick={(e) => {
                            e.stopPropagation();
                            setExpanded(open ? null : c.key);
                          }}
                          style={{ background: "none", border: "none", color: "var(--subtext)", cursor: "pointer", display: "flex" }}
                        >
                          {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
                        </button>
                      </td>
                      <td style={{ fontWeight: 700, color: "var(--text)" }}>{c.name}</td>
                      <td style={{ fontFamily: "monospace", fontSize: "12px" }}>{c.code || "—"}</td>
                      <td style={{ fontSize: "12px", color: "var(--subtext)" }}>{c.typeLabel}</td>
                      <td style={{ textAlign: "right" }}>{c.billCount}</td>
                      <td style={{ textAlign: "right", fontWeight: 700, color: "var(--danger)" }}>{formatVND(c.totalDiscount)}</td>
                      <td style={{ textAlign: "right", fontWeight: 700, color: "var(--success)" }}>{formatVND(c.revenue)}</td>
                      <td style={{ textAlign: "right" }}>{c.vouchersUsed}</td>
                    </tr>
                    {open && (
                      <tr>
                        <td colSpan={8} style={{ background: "var(--surface-muted)", padding: "12px 16px" }}>
                          <table style={{ margin: 0 }}>
                            <thead>
                              <tr>
                                <th>Mã hóa đơn</th>
                                <th>Thời gian</th>
                                <th>Bàn</th>
                                <th>Mã voucher</th>
                                <th style={{ textAlign: "right" }}>Giảm giá</th>
                                <th style={{ textAlign: "right" }}>Tổng tiền HĐ</th>
                                <th>Nhân viên</th>
                              </tr>
                            </thead>
                            <tbody>
                              {c.bills.map((b) => (
                                <tr key={b.billId}>
                                  <td style={{ fontFamily: "monospace", fontWeight: 700, color: "var(--primary)", fontSize: "12px" }}>{b.billCode}</td>
                                  <td style={{ fontSize: "12px" }}>{b.timestamp ? format(new Date(b.timestamp), "dd/MM/yyyy HH:mm") : "—"}</td>
                                  <td>{b.tableName || "—"}</td>
                                  <td style={{ fontFamily: "monospace", fontSize: "12px" }}>{b.voucherCode || "—"}</td>
                                  <td style={{ textAlign: "right", color: "var(--danger)", fontWeight: 700 }}>{formatVND(b.discount)}</td>
                                  <td style={{ textAlign: "right" }}>{formatVND(b.finalAmount)}</td>
                                  <td style={{ fontSize: "12px" }}>{b.staff || "—"}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </td>
                      </tr>
                    )}
                  </Fragment>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
