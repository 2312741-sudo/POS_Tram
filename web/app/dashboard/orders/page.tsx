"use client";
import { useState, useMemo } from "react";
import { format } from "date-fns";
import { vi } from "date-fns/locale";
import {
  Download,
  Search,
  ChevronLeft,
  ChevronRight,
  Calendar,
  Filter,
  Eye,
  FileText,
  User,
  CreditCard,
  Clock,
  History,
  X,
  CheckCircle,
  Printer,
  Utensils,
  Layers,
  ShoppingBag,
  MapPin,
  DollarSign,
  Banknote,
  Trash2,
  XCircle,
} from "lucide-react";
import { exportHistory, exportSingleBillExcel, exportCancellationReport } from "@/lib/export";
import { useDashboardData, HistoryOrder } from "@/lib/data-context";
import { calculateCancellationReport, formatVND } from "@/lib/reports";

const PAGE_SIZE = 20;

export default function OrdersPage() {
  const { historyData, historyLoaded, tables, stores, currentStoreCode, cancelOrder, deleteOrder } = useDashboardData();
  const loading = !historyLoaded && historyData.length === 0;
  const [search, setSearch] = useState("");
  const [datePreset, setDatePreset] = useState<"ALL" | "TODAY" | "YESTERDAY" | "7DAYS" | "THIS_MONTH" | "LAST_MONTH" | "CUSTOM">("ALL");
  const [filterDate, setFilterDate] = useState("");
  const [filterMethod, setFilterMethod] = useState("");
  const [filterStatus, setFilterStatus] = useState("");
  const [filterZone, setFilterZone] = useState("");
  const [filterTable, setFilterTable] = useState("");
  const [page, setPage] = useState(1);
  const [selectedOrder, setSelectedOrder] = useState<HistoryOrder | null>(null);

  const isTakeaway = (order: HistoryOrder) => {
    const t = (order.tableName || "").toLowerCase();
    const z = (order.zone || "").toLowerCase();
    const type = (order.orderType || "").toLowerCase();
    return t.includes("mang về") || t.includes("mang ve") || z.includes("mang về") || z.includes("mang ve") || type === "takeaway";
  };

  const availableZones = useMemo(() => {
    const set = new Set<string>();
    tables.forEach((t) => { if (t.zone) set.add(t.zone); });
    historyData.forEach((h) => { if (h.zone) set.add(h.zone); });
    const list = Array.from(set).filter((z) => !z.toLowerCase().includes("mang về") && !z.toLowerCase().includes("mang ve")).sort();
    return ["Mang về", ...list];
  }, [tables, historyData]);

  const availableTables = useMemo(() => {
    const set = new Set<string>();
    tables.forEach((t) => {
      if (!filterZone || t.zone === filterZone || (filterZone === "Mang về" && (t.zone.toLowerCase().includes("mang về") || t.name.toLowerCase().includes("mang về")))) {
        if (t.name) set.add(t.name);
      }
    });
    historyData.forEach((h) => {
      if (!filterZone || h.zone === filterZone || (filterZone === "Mang về" && isTakeaway(h))) {
        if (h.tableName) set.add(h.tableName);
      }
    });
    return Array.from(set).sort((a, b) => a.localeCompare(b, undefined, { numeric: true }));
  }, [tables, historyData, filterZone]);

  const filtered = useMemo(() => {
    const now = new Date();
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

    return historyData.filter((h) => {
      const matchSearch =
        !search ||
        (h.billCode || "").toLowerCase().includes(search.toLowerCase()) ||
        (h.orderCode || "").toLowerCase().includes(search.toLowerCase()) ||
        (h.tableName || "").toLowerCase().includes(search.toLowerCase()) ||
        (h.orderStaff || "").toLowerCase().includes(search.toLowerCase()) ||
        (h.cashierName || "").toLowerCase().includes(search.toLowerCase());

      const dt = new Date(typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime());
      let matchDate = true;
      if (datePreset === "TODAY") {
        matchDate = dt.getFullYear() === now.getFullYear() && dt.getMonth() === now.getMonth() && dt.getDate() === now.getDate();
      } else if (datePreset === "YESTERDAY") {
        const yest = new Date(today);
        yest.setDate(yest.getDate() - 1);
        matchDate = dt.getFullYear() === yest.getFullYear() && dt.getMonth() === yest.getMonth() && dt.getDate() === yest.getDate();
      } else if (datePreset === "7DAYS") {
        const d7 = new Date(today);
        d7.setDate(d7.getDate() - 7);
        matchDate = dt >= d7 && dt <= now;
      } else if (datePreset === "THIS_MONTH") {
        matchDate = dt.getFullYear() === now.getFullYear() && dt.getMonth() === now.getMonth();
      } else if (datePreset === "LAST_MONTH") {
        const lm = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        matchDate = dt.getFullYear() === lm.getFullYear() && dt.getMonth() === lm.getMonth();
      } else if (datePreset === "CUSTOM") {
        matchDate = !filterDate || format(dt, "yyyy-MM-dd") === filterDate;
      }

      const matchMethod =
        !filterMethod || (h.paymentMethod || "").toLowerCase().includes(filterMethod.toLowerCase());
      const matchZone =
        !filterZone ||
        (filterZone === "Mang về" ? isTakeaway(h) : (h.zone || "").toLowerCase() === filterZone.toLowerCase());
      const matchTable =
        !filterTable || (h.tableName || "").toLowerCase() === filterTable.toLowerCase();
      const matchStatus =
        !filterStatus || (h.status || "PAID") === filterStatus;

      return matchSearch && matchDate && matchMethod && matchZone && matchTable && matchStatus;
    });
  }, [historyData, search, datePreset, filterDate, filterMethod, filterStatus, filterZone, filterTable]);

  // Aggregate stats (Chỉ tính đơn hợp lệ, loại trừ đơn đã hủy)
  const totalAmount = useMemo(() => {
    return filtered
      .filter((h) => h.status !== "CANCELLED")
      .reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
  }, [filtered]);

  const takeawayOrders = useMemo(() => {
    return filtered.filter(isTakeaway);
  }, [filtered]);
  const takeawayCount = takeawayOrders.length;
  const takeawayRevenue = useMemo(() => {
    return takeawayOrders.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);
  }, [takeawayOrders]);

  const cashOrders = useMemo(() => {
    return filtered.filter(h => (h.paymentMethod || "").toLowerCase().includes("cash") || (h.paymentMethod || "").toLowerCase().includes("tiền mặt"));
  }, [filtered]);
  const cashAmount = cashOrders.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);

  const transferOrders = useMemo(() => {
    return filtered.filter(h => (h.paymentMethod || "").toLowerCase().includes("transfer") || (h.paymentMethod || "").toLowerCase().includes("chuyển"));
  }, [filtered]);
  const transferAmount = transferOrders.reduce((s, h) => s + (Number(h.totalAmount) || 0), 0);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const cancellationReport = useMemo(() => {
    return calculateCancellationReport(filtered);
  }, [filtered]);

  const targetStoreInfo = useMemo(() => {
    if (currentStoreCode === "ALL") return { storeName: "Tất cả chi nhánh", storeCode: "ALL" };
    return (
      stores.find((s) => s.storeCode === currentStoreCode) || {
        storeName: "POS Trạm",
        storeCode: currentStoreCode,
      }
    );
  }, [stores, currentStoreCode]);

  const handleExportCancellationExcel = () => {
    exportCancellationReport(cancellationReport, targetStoreInfo).toExcel();
  };

  const handleExportCancellationPDF = () => {
    exportCancellationReport(cancellationReport, targetStoreInfo).toPDF();
  };

  const handleExportAll = () => {
    exportHistory(filtered);
  };

  const handleExportSingle = (order: HistoryOrder) => {
    exportSingleBillExcel(order);
  };

  const handlePrint = (order: HistoryOrder) => {
    const printWindow = window.open("", "_blank");
    if (!printWindow) return;

    const ts = typeof order.timestamp === "number" ? order.timestamp : new Date(order.timestamp || 0).getTime();
    const timeStr = format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi });

    const itemsHtml = (order.items || []).map((it, idx) => `
      <tr>
        <td style="padding: 6px 4px; border-bottom: 1px dashed #ccc;">${idx + 1}. ${it.name} ${it.selectedSize ? `(Size ${it.selectedSize})` : ""}</td>
        <td style="padding: 6px 4px; text-align: center; border-bottom: 1px dashed #ccc;">${it.quantity || 1}</td>
        <td style="padding: 6px 4px; text-align: right; border-bottom: 1px dashed #ccc;">${formatVND(it.price)}</td>
        <td style="padding: 6px 4px; text-align: right; border-bottom: 1px dashed #ccc; font-weight: bold;">${formatVND((it.price || 0) * (it.quantity || 1))}</td>
      </tr>
      ${it.orderedByName ? `<tr><td colspan="4" style="font-size: 11px; color: #666; padding-left: 16px;">Phục vụ: ${it.orderedByName}</td></tr>` : ""}
    `).join("");

    printWindow.document.write(`
      <!DOCTYPE html>
      <html>
        <head>
          <title>Hóa đơn ${order.billCode || order.orderCode || order.id}</title>
          <style>
            body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; padding: 20px; max-width: 400px; margin: 0 auto; color: #333; }
            .header { text-align: center; border-bottom: 2px dashed #7E2930; padding-bottom: 12px; margin-bottom: 12px; }
            .title { font-size: 20px; font-weight: 800; color: #7E2930; margin: 0; }
            .meta { font-size: 12px; color: #666; margin: 4px 0; }
            table { width: 100%; border-collapse: collapse; margin: 14px 0; font-size: 13px; }
            .total-row { font-size: 15px; font-weight: bold; border-top: 2px solid #333; padding-top: 8px; }
            .footer { text-align: center; margin-top: 24px; font-size: 12px; color: #777; border-top: 1px dashed #ccc; padding-top: 10px; }
          </style>
        </head>
        <body>
          <div class="header">
            <h2 class="title">TRẠM F&B SYSTEM</h2>
            <div class="meta">HÓA ĐƠN THANH TOÁN</div>
            <div class="meta">Số HĐ: <strong>${order.billCode || order.orderCode || order.id?.slice(0, 8)}</strong>${order.orderCode && order.billCode && order.orderCode !== order.billCode ? ` | Mã đơn: <strong>${order.orderCode}</strong>` : ''} | Bàn: <strong>${order.tableName || "—"}</strong></div>
            <div class="meta">Giờ: ${timeStr}</div>
            <div class="meta">Người nhận order: <strong>${order.orderStaff || "—"}</strong></div>
            <div class="meta">Thu ngân: <strong>${order.cashierName || "—"}</strong></div>
          </div>
          <table>
            <thead>
              <tr style="border-bottom: 1px solid #333; font-weight: bold;">
                <th style="text-align: left; padding-bottom: 4px;">Món</th>
                <th style="text-align: center; padding-bottom: 4px;">SL</th>
                <th style="text-align: right; padding-bottom: 4px;">Đơn giá</th>
                <th style="text-align: right; padding-bottom: 4px;">T.Tiền</th>
              </tr>
            </thead>
            <tbody>
              ${itemsHtml}
            </tbody>
          </table>
          <div style="display: flex; justify-content: space-between; margin-top: 8px;" class="total-row">
            <span>TỔNG CỘNG:</span>
            <span style="color: #7E2930;">${formatVND(order.totalAmount || 0)}</span>
          </div>
          <div style="font-size: 12px; margin-top: 4px; text-align: right; color: #555;">
            Phương thức: ${order.paymentMethod || "Tiền mặt"}
          </div>
          <div class="footer">
            <p>Cảm ơn quý khách và hẹn gặp lại! ✨</p>
          </div>
          <script>
            window.onload = function() { window.print(); }
          </script>
        </body>
      </html>
    `);
    printWindow.document.close();
  };

  const getPaymentBadge = (method?: string) => {
    const m = (method || "").toLowerCase();
    if (m.includes("cash") || m.includes("tiền mặt")) {
      return <span className="badge badge-success">💵 Tiền mặt</span>;
    }
    if (m.includes("transfer") || m.includes("chuyển")) {
      return <span className="badge badge-info">🏦 Chuyển khoản</span>;
    }
    return <span className="badge badge-warning">💳 {method || "N/A"}</span>;
  };

  if (loading) {
    return (
      <div style={{ display: "flex", alignItems: "center", justifyContent: "center", height: "60vh" }}>
        <div className="spinner" />
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "24px" }}>
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "12px" }}>
        <div>
          <h1 className="section-title">Lịch sử Giao dịch & Hóa đơn 🧾</h1>
          <p className="section-subtitle">
            Quản lý {filtered.length} hóa đơn, chi tiết món theo người nhận order & lịch sử thao tác
          </p>
        </div>
        <div style={{ display: "flex", gap: "8px", flexWrap: "wrap", alignItems: "center" }}>
          {filterStatus === "CANCELLED" ? (
            <>
              <button
                className="btn-primary"
                style={{ background: "#107C41" }}
                onClick={handleExportCancellationExcel}
              >
                <Download size={16} /> Xuất Báo cáo Hủy món (Excel)
              </button>
              <button
                className="btn-primary"
                style={{ background: "#7E2930" }}
                onClick={handleExportCancellationPDF}
              >
                <Printer size={16} /> In / PDF Kiểm toán Thất thoát
              </button>
            </>
          ) : (
            <button className="btn-primary" onClick={handleExportAll}>
              <Download size={16} />
              Xuất Toàn bộ Excel (3 Sheets)
            </button>
          )}
        </div>
      </div>

      {/* Cancellation Loss Audit Banner */}
      {filterStatus === "CANCELLED" && (
        <div
          style={{
            padding: "16px 20px",
            background: "#FFF1F2",
            border: "1px solid #FECDD3",
            borderRadius: "12px",
            display: "flex",
            alignItems: "center",
            gap: "12px",
          }}
        >
          <XCircle size={22} color="#DC2626" />
          <div>
            <div style={{ fontWeight: "700", color: "#991B1B", fontSize: "14px" }}>
              Báo cáo Kiểm toán Thất thoát: {cancellationReport.cancelledBillsCount} hóa đơn bị hủy
            </div>
            <div style={{ fontSize: "12px", color: "#B91C1C", marginTop: "2px" }}>
              Tổng giá trị thất thoát tài chính ghi nhận: <strong>{formatVND(cancellationReport.totalLossValue)}</strong>
            </div>
          </div>
        </div>
      )}

      {/* Summary KPI Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(220px, 1fr))", gap: "16px" }}>
        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#7E293018", display: "flex", alignItems: "center", justifyContent: "center", color: "#7E2930", flexShrink: 0 }}>
              <DollarSign size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(totalAmount)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Tổng doanh thu lọc</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{filtered.length} hóa đơn</div>
            </div>
          </div>
        </div>

        <div
          className="stat-card"
          onClick={() => { setFilterZone(prev => prev === "Mang về" ? "" : "Mang về"); setFilterTable(""); setPage(1); }}
          style={{ cursor: "pointer", border: filterZone === "Mang về" ? "2px solid #8B5CF6" : undefined, background: filterZone === "Mang về" ? "#F5F3FF" : undefined }}
          title="Bấm để lọc nhanh đơn mang về"
        >
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#8B5CF618", display: "flex", alignItems: "center", justifyContent: "center", color: "#8B5CF6", flexShrink: 0 }}>
              <ShoppingBag size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(takeawayRevenue)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>
                🥡 Mang về {filterZone === "Mang về" ? "(Đang lọc)" : ""}
              </div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{takeawayCount} hóa đơn mang về</div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#146A6518", display: "flex", alignItems: "center", justifyContent: "center", color: "#146A65", flexShrink: 0 }}>
              <Banknote size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(cashAmount)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Tiền mặt</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{cashOrders.length} hóa đơn</div>
            </div>
          </div>
        </div>

        <div className="stat-card">
          <div style={{ display: "flex", gap: "12px", alignItems: "center" }}>
            <div style={{ width: "42px", height: "42px", borderRadius: "10px", background: "#1C4E6B18", display: "flex", alignItems: "center", justifyContent: "center", color: "#1C4E6B", flexShrink: 0 }}>
              <CreditCard size={20} />
            </div>
            <div>
              <div style={{ fontSize: "17px", fontWeight: "800", color: "#1C1A2D" }}>{formatVND(transferAmount)}</div>
              <div style={{ fontSize: "12px", fontWeight: "600", color: "#5D5B63" }}>Chuyển khoản (QR)</div>
              <div style={{ fontSize: "11px", color: "#8B8FA8" }}>{transferOrders.length} hóa đơn</div>
            </div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", gap: "12px", flexWrap: "wrap", alignItems: "center" }}>
          <div style={{ position: "relative", flex: "1", minWidth: "220px" }}>
            <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "#8B8FA8" }} />
            <input
              className="input-field"
              placeholder="Tìm mã đơn, tên bàn, người order, thu ngân..."
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              style={{ paddingLeft: "38px" }}
            />
          </div>
          <select
            className="input-field"
            value={datePreset}
            onChange={(e) => { setDatePreset(e.target.value as typeof datePreset); setPage(1); }}
            style={{ width: "auto", minWidth: "160px" }}
          >
            <option value="ALL">📅 Tất cả thời gian</option>
            <option value="TODAY">Hôm nay</option>
            <option value="YESTERDAY">Hôm qua</option>
            <option value="7DAYS">7 ngày qua</option>
            <option value="THIS_MONTH">Tháng này</option>
            <option value="LAST_MONTH">Tháng trước</option>
            <option value="CUSTOM">Tùy chọn ngày...</option>
          </select>

          {datePreset === "CUSTOM" && (
            <input
              type="date"
              className="input-field"
              value={filterDate}
              onChange={(e) => { setFilterDate(e.target.value); setPage(1); }}
              style={{ width: "160px", colorScheme: "dark" }}
            />
          )}

          <select
            className="input-field"
            value={filterZone}
            onChange={(e) => { setFilterZone(e.target.value); setFilterTable(""); setPage(1); }}
            style={{ width: "auto", minWidth: "185px" }}
          >
            <option value="">📍 Tất cả phòng / khu vực</option>
            {availableZones.map((z) => (
              <option key={z} value={z}>{z === "Mang về" ? "🥡 Mang về" : `📍 ${z}`}</option>
            ))}
          </select>

          <select
            className="input-field"
            value={filterTable}
            onChange={(e) => { setFilterTable(e.target.value); setPage(1); }}
            style={{ width: "auto", minWidth: "140px" }}
          >
            <option value="">🍽️ Tất cả bàn</option>
            {availableTables.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>

          <select
            className="input-field"
            value={filterMethod}
            onChange={(e) => { setFilterMethod(e.target.value); setPage(1); }}
            style={{ width: "auto", minWidth: "175px" }}
          >
            <option value="">💳 Tất cả phương thức</option>
            <option value="cash">💵 Tiền mặt</option>
            <option value="transfer">📱 Chuyển khoản</option>
          </select>

          <select
            className="input-field"
            value={filterStatus}
            onChange={(e) => { setFilterStatus(e.target.value); setPage(1); }}
            style={{ width: "auto", minWidth: "165px" }}
          >
            <option value="">🏷️ Tất cả trạng thái</option>
            <option value="PAID">✅ Đã thanh toán</option>
            <option value="CANCELLED">❌ Đã hủy</option>
          </select>
          {(search || filterDate || filterMethod || filterStatus || filterZone || filterTable) && (
            <button className="btn-secondary" onClick={() => { setSearch(""); setFilterDate(""); setFilterMethod(""); setFilterStatus(""); setFilterZone(""); setFilterTable(""); setPage(1); }}>
              Xóa lọc
            </button>
          )}
        </div>
      </div>

      {/* Orders Table */}
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th>#</th>
              <th>Mã đơn</th>
              <th>Bàn</th>
              <th>Tổng tiền</th>
              <th>Thanh toán</th>
              <th>Người nhận order</th>
              <th>Người thanh toán</th>
              <th>Trạng thái</th>
              <th>Thời gian</th>
              <th style={{ textAlign: "center" }}>Thao tác</th>
            </tr>
          </thead>
          <tbody>
            {paginated.length === 0 ? (
              <tr>
                <td colSpan={10} style={{ textAlign: "center", padding: "48px", color: "#8B8FA8" }}>
                  Không tìm thấy hóa đơn nào
                </td>
              </tr>
            ) : (
              paginated.map((h, i) => {
                const ts = typeof h.timestamp === "number" ? h.timestamp : new Date(h.timestamp || 0).getTime();
                const itemCount = Array.isArray(h.items) ? h.items.reduce((s, it) => s + (it.quantity || 1), 0) : 0;
                return (
                  <tr key={h.id + '-' + i} style={{ cursor: "pointer" }} onClick={() => setSelectedOrder(h)}>
                    <td style={{ color: "#8B8FA8" }}>{(page - 1) * PAGE_SIZE + i + 1}</td>
                    <td>
                      <span style={{ fontFamily: "monospace", fontWeight: "700", color: "#7E2930", fontSize: "13px" }}>
                        {h.billCode || h.orderCode || h.id?.slice(0, 8) || "N/A"}
                      </span>
                      {h.orderCode && h.billCode && h.orderCode !== h.billCode && (
                        <div style={{ fontSize: "11px", color: "#8B8FA8", fontFamily: "monospace" }}>
                          Đơn: {h.orderCode}
                        </div>
                      )}
                    </td>
                    <td style={{ fontWeight: "700", color: "#1C1A2D" }}>
                      {h.tableName || "—"}
                      {h.zone ? <span style={{ fontSize: "11px", color: "#8B8FA8", marginLeft: "4px" }}>({h.zone})</span> : null}
                    </td>
                    <td style={{ fontWeight: "800", color: "#146A65" }}>
                      {formatVND(Number(h.totalAmount) || 0)}
                      {itemCount > 0 && (
                        <div style={{ fontSize: "11px", color: "#8B8FA8", fontWeight: "normal" }}>
                          {itemCount} món
                        </div>
                      )}
                    </td>
                    <td>{getPaymentBadge(h.paymentMethod)}</td>
                    <td>
                      <span
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "4px",
                          background: "#F8F4EE",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          fontSize: "12px",
                          fontWeight: "600",
                          color: "#7E2930",
                          border: "1px solid #E6DEC8"
                        }}
                      >
                        <User size={12} />
                        {h.orderStaff || "—"}
                      </span>
                    </td>
                    <td>
                      <span
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "4px",
                          background: "#E6F4F2",
                          padding: "3px 8px",
                          borderRadius: "6px",
                          fontSize: "12px",
                          fontWeight: "600",
                          color: "#146A65",
                          border: "1px solid #B8E2DC"
                        }}
                      >
                        <CreditCard size={12} />
                        {h.cashierName || "Thu ngân"}
                      </span>
                    </td>
                    <td>
                      <span className={`badge ${h.status === "CANCELLED" ? "badge-danger" : h.status === "PAID" || h.status === "paid" || h.status === "Đã thanh toán" ? "badge-success" : "badge-warning"}`}>
                        {h.status === "CANCELLED" ? "Đã hủy" : (h.status || "Đã thanh toán")}
                      </span>
                    </td>
                    <td style={{ color: "#8B8FA8", fontSize: "13px" }}>
                      {h.timestamp ? format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi }) : "—"}
                    </td>
                    <td style={{ textAlign: "center" }} onClick={(e) => e.stopPropagation()}>
                      <div style={{ display: "flex", gap: "6px", justifyContent: "center" }}>
                        <button
                          className="btn-secondary"
                          style={{ padding: "6px 10px", fontSize: "12px" }}
                          title="Xem chi tiết đơn"
                          onClick={() => setSelectedOrder(h)}
                        >
                          <Eye size={14} />
                          Chi tiết
                        </button>
                        <button
                          className="btn-secondary"
                          style={{ padding: "6px 10px", fontSize: "12px" }}
                          title="Xuất Excel đơn này"
                          onClick={() => handleExportSingle(h)}
                        >
                          <Download size={14} />
                        </button>
                        <button
                          className="btn-secondary"
                          style={{ padding: "6px 10px", fontSize: "12px" }}
                          title="In hóa đơn"
                          onClick={() => handlePrint(h)}
                        >
                          <Printer size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div style={{ display: "flex", alignItems: "center", justifyContent: "center", gap: "8px" }}>
          <button className="btn-secondary" onClick={() => setPage(p => Math.max(1, p - 1))} disabled={page === 1} style={{ padding: "6px 10px" }}>
            <ChevronLeft size={16} />
          </button>
          {Array.from({ length: Math.min(7, totalPages) }, (_, i) => {
            const p = i + 1;
            return (
              <button
                key={p}
                onClick={() => setPage(p)}
                style={{
                  width: "36px",
                  height: "36px",
                  borderRadius: "8px",
                  border: "1px solid",
                  borderColor: page === p ? "#7E2930" : "#E6DEC8",
                  background: page === p ? "#FBECEE" : "transparent",
                  color: page === p ? "#7E2930" : "#5D5B63",
                  cursor: "pointer",
                  fontWeight: "600",
                  fontSize: "14px",
                  transition: "all 0.2s",
                }}
              >
                {p}
              </button>
            );
          })}
          <button className="btn-secondary" onClick={() => setPage(p => Math.min(totalPages, p + 1))} disabled={page === totalPages} style={{ padding: "6px 10px" }}>
            <ChevronRight size={16} />
          </button>
        </div>
      )}

      {/* Order Detail Modal */}
      {selectedOrder && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            background: "rgba(0, 0, 0, 0.6)",
            zIndex: 1000,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: "20px",
            backdropFilter: "blur(4px)",
          }}
          onClick={() => setSelectedOrder(null)}
        >
          <div
            className="card"
            style={{
              width: "100%",
              maxWidth: "850px",
              maxHeight: "90vh",
              overflowY: "auto",
              padding: "28px",
              position: "relative",
              boxShadow: "0 20px 40px rgba(0, 0, 0, 0.2)",
              display: "flex",
              flexDirection: "column",
              gap: "20px",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", borderBottom: "1px solid #ECE5D8", paddingBottom: "16px" }}>
              <div>
                <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                  <h2 style={{ fontSize: "20px", fontWeight: "800", color: "#1C1A2D", margin: 0 }}>
                    Chi tiết Hóa đơn #{selectedOrder.billCode || selectedOrder.orderCode || selectedOrder.id?.slice(0, 8)}
                  </h2>
                  <span className={`badge ${selectedOrder.status === "CANCELLED" ? "badge-danger" : "badge-success"}`}>
                    {selectedOrder.status === "CANCELLED" ? "Đã hủy" : (selectedOrder.status || "Đã thanh toán")}
                  </span>
                </div>
                <p style={{ fontSize: "13px", color: "#5D5B63", marginTop: "4px" }}>
                  Bàn: <strong style={{ color: "#7E2930" }}>{selectedOrder.tableName || "—"}</strong>
                  {selectedOrder.zone ? ` (${selectedOrder.zone})` : ""}
                  {selectedOrder.orderCode && selectedOrder.billCode && selectedOrder.orderCode !== selectedOrder.billCode && (
                    <span> • Mã đặt món: <strong style={{ fontFamily: "monospace", color: "#146A65" }}>{selectedOrder.orderCode}</strong></span>
                  )} •
                  Thời gian: {selectedOrder.timestamp ? format(new Date(typeof selectedOrder.timestamp === "number" ? selectedOrder.timestamp : new Date(selectedOrder.timestamp || 0).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "—"}
                </p>
              </div>
              <button
                onClick={() => setSelectedOrder(null)}
                style={{
                  border: "none",
                  background: "#FAF7F2",
                  cursor: "pointer",
                  borderRadius: "8px",
                  padding: "8px",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: "#5D5B63"
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Top Info Cards */}
            <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))", gap: "12px" }}>
              <div style={{ background: "#F8F4EE", padding: "14px", borderRadius: "10px", border: "1px solid #E6DEC8" }}>
                <div style={{ fontSize: "11px", color: "#7E2930", fontWeight: "700", textTransform: "uppercase", marginBottom: "4px", display: "flex", alignItems: "center", gap: "4px" }}>
                  <User size={13} /> Người nhận order
                </div>
                <div style={{ fontSize: "15px", fontWeight: "800", color: "#1C1A2D" }}>
                  {selectedOrder.orderStaff || "—"}
                </div>
                <div style={{ fontSize: "11px", color: "#5D5B63", marginTop: "2px" }}>
                  Nhân viên nhận đơn
                </div>
              </div>

              <div style={{ background: "#E6F4F2", padding: "14px", borderRadius: "10px", border: "1px solid #B8E2DC" }}>
                <div style={{ fontSize: "11px", color: "#146A65", fontWeight: "700", textTransform: "uppercase", marginBottom: "4px", display: "flex", alignItems: "center", gap: "4px" }}>
                  <CreditCard size={13} /> Người thanh toán
                </div>
                <div style={{ fontSize: "15px", fontWeight: "800", color: "#1C1A2D" }}>
                  {selectedOrder.cashierName || "Thu ngân"}
                </div>
                <div style={{ fontSize: "11px", color: "#5D5B63", marginTop: "2px" }}>
                  {selectedOrder.paymentMethod || "Tiền mặt"}
                </div>
              </div>

              <div style={{ background: "#FFF0F2", padding: "14px", borderRadius: "10px", border: "1px solid #F3C9CE" }}>
                <div style={{ fontSize: "11px", color: "#7E2930", fontWeight: "700", textTransform: "uppercase", marginBottom: "4px", display: "flex", alignItems: "center", gap: "4px" }}>
                  <CheckCircle size={13} /> Tổng tiền hóa đơn
                </div>
                <div style={{ fontSize: "18px", fontWeight: "800", color: "#7E2930" }}>
                  {formatVND(Number(selectedOrder.totalAmount) || 0)}
                </div>
                {selectedOrder.discountAmount ? (
                  <div style={{ fontSize: "11px", color: "#146A65", marginTop: "2px" }}>
                    Đã giảm: {formatVND(selectedOrder.discountAmount)}
                  </div>
                ) : (
                  <div style={{ fontSize: "11px", color: "#5D5B63", marginTop: "2px" }}>
                    Giá gốc: {formatVND(selectedOrder.subTotal || selectedOrder.totalAmount || 0)}
                  </div>
                )}
              </div>
            </div>

            {/* Section 1: Item Breakdown */}
            <div>
              <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "12px" }}>
                <Utensils size={18} style={{ color: "#7E2930" }} />
                <h3 style={{ fontSize: "15px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                  Chi tiết Món trong Đơn ({selectedOrder.items?.length || 0} món)
                </h3>
              </div>
              <div style={{ overflowX: "auto", border: "1px solid #ECE5D8", borderRadius: "10px" }}>
                <table style={{ margin: 0 }}>
                  <thead>
                    <tr style={{ background: "#FAF7F2" }}>
                      <th>#</th>
                      <th>Tên món</th>
                      <th>Tùy chọn & Ghi chú</th>
                      <th style={{ textAlign: "center" }}>SL</th>
                      <th style={{ textAlign: "right" }}>Đơn giá</th>
                      <th style={{ textAlign: "right" }}>Thành tiền</th>
                      <th>Người nhận món</th>
                    </tr>
                  </thead>
                  <tbody>
                    {!selectedOrder.items || selectedOrder.items.length === 0 ? (
                      <tr>
                        <td colSpan={7} style={{ textAlign: "center", padding: "20px", color: "#8B8FA8" }}>
                          Không có thông tin chi tiết món
                        </td>
                      </tr>
                    ) : (
                      selectedOrder.items.map((it, idx) => {
                        const unitPrice = Number(it.price) || 0;
                        const qty = Number(it.quantity) || 1;
                        const lineTotal = unitPrice * qty;
                        return (
                          <tr key={idx}>
                            <td style={{ color: "#8B8FA8" }}>{idx + 1}</td>
                            <td style={{ fontWeight: "700", color: "#1C1A2D" }}>{it.name}</td>
                            <td>
                              {it.optionsSummary ? (
                                <span style={{ fontSize: "12px", color: "#5D5B63" }}>{it.optionsSummary}</span>
                              ) : it.selectedSize ? (
                                <span style={{ fontSize: "12px", color: "#5D5B63" }}>Size {it.selectedSize}</span>
                              ) : (
                                <span style={{ fontSize: "12px", color: "#8B8FA8" }}>Chuẩn</span>
                              )}
                              {it.note ? (
                                <div style={{ fontSize: "11px", color: "#D97706", fontStyle: "italic", marginTop: "2px" }}>
                                  Ghi chú: {it.note}
                                </div>
                              ) : null}
                            </td>
                            <td style={{ textAlign: "center", fontWeight: "700" }}>{qty}</td>
                            <td style={{ textAlign: "right", color: "#5D5B63" }}>{formatVND(unitPrice)}</td>
                            <td style={{ textAlign: "right", fontWeight: "700", color: "#146A65" }}>
                              {formatVND(lineTotal)}
                            </td>
                            <td>
                              <span
                                style={{
                                  display: "inline-flex",
                                  alignItems: "center",
                                  gap: "4px",
                                  background: "#F8F4EE",
                                  padding: "2px 6px",
                                  borderRadius: "4px",
                                  fontSize: "11px",
                                  fontWeight: "600",
                                  color: "#7E2930",
                                  border: "1px solid #E6DEC8"
                                }}
                              >
                                <User size={10} />
                                {it.orderedByName || selectedOrder.orderStaff || "—"}
                              </span>
                              {it.orderedAt ? (
                                <div style={{ fontSize: "10px", color: "#8B8FA8", marginTop: "2px" }}>
                                  {format(new Date(typeof it.orderedAt === "number" ? it.orderedAt : new Date(it.orderedAt).getTime()), "HH:mm dd/MM")}
                                </div>
                              ) : null}
                            </td>
                          </tr>
                        );
                      })
                    )}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Section 2: Order Action Timeline */}
            <div>
              <div style={{ display: "flex", alignItems: "center", gap: "8px", marginBottom: "12px" }}>
                <History size={18} style={{ color: "#7E2930" }} />
                <h3 style={{ fontSize: "15px", fontWeight: "700", color: "#1C1A2D", margin: 0 }}>
                  Lịch sử Thao tác Đơn Hàng (Action Audit Trail)
                </h3>
              </div>
              <div
                style={{
                  background: "#FAF7F2",
                  border: "1px solid #ECE5D8",
                  borderRadius: "10px",
                  padding: "16px 20px",
                  display: "flex",
                  flexDirection: "column",
                  gap: "12px",
                }}
              >
                {!selectedOrder.actionLogs || selectedOrder.actionLogs.length === 0 ? (
                  <div style={{ color: "#8B8FA8", fontSize: "13px", textAlign: "center", padding: "12px" }}>
                    Chưa có nhật ký thao tác
                  </div>
                ) : (
                  selectedOrder.actionLogs.map((log, idx) => {
                    const logTs = typeof log.timestamp === "number" ? log.timestamp : new Date(log.timestamp || 0).getTime();
                    const isPay = log.action === "PAY_BILL";
                    const isSendKitchen = log.action === "SEND_KITCHEN";

                    return (
                      <div
                        key={idx}
                        style={{
                          display: "flex",
                          alignItems: "flex-start",
                          gap: "12px",
                          position: "relative",
                        }}
                      >
                        {/* Timeline dot */}
                        <div
                          style={{
                            width: "28px",
                            height: "28px",
                            borderRadius: "50%",
                            background: isPay ? "#146A65" : isSendKitchen ? "#D97706" : "#7E2930",
                            color: "white",
                            display: "flex",
                            alignItems: "center",
                            justifyContent: "center",
                            fontSize: "12px",
                            flexShrink: 0,
                            marginTop: "2px",
                          }}
                        >
                          {isPay ? "✓" : isSendKitchen ? "🍽️" : "📝"}
                        </div>

                        {/* Content */}
                        <div style={{ flex: 1 }}>
                          <div style={{ display: "flex", alignItems: "center", gap: "8px", flexWrap: "wrap" }}>
                            <span style={{ fontWeight: "700", fontSize: "13px", color: "#1C1A2D" }}>
                              {log.staffFullName || log.staffUsername || "Nhân viên"}
                            </span>
                            <span
                              style={{
                                fontSize: "10px",
                                fontWeight: "700",
                                padding: "1px 6px",
                                borderRadius: "4px",
                                background: isPay ? "#E6F4F2" : isSendKitchen ? "#FBEFD4" : "#FBECEE",
                                color: isPay ? "#146A65" : isSendKitchen ? "#D97706" : "#7E2930",
                              }}
                            >
                              {log.action}
                            </span>
                            <span style={{ fontSize: "12px", color: "#8B8FA8", marginLeft: "auto" }}>
                              {log.timestamp ? format(new Date(logTs), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "—"}
                            </span>
                          </div>
                          <div style={{ fontSize: "13px", color: "#5D5B63", marginTop: "2px" }}>
                            {log.details}
                          </div>
                        </div>
                      </div>
                    );
                  })
                )}
              </div>
            </div>

            {/* Modal Footer Actions */}
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                alignItems: "center",
                gap: "12px",
                borderTop: "1px solid #ECE5D8",
                paddingTop: "16px",
                flexWrap: "wrap",
              }}
            >
              {selectedOrder.status !== "CANCELLED" && (
                <button
                  className="btn-secondary"
                  onClick={async () => {
                    const reason = window.prompt("Nhập lý do hủy hóa đơn này:", "Khách đổi ý hủy đơn");
                    if (!reason) return;
                    const res = await cancelOrder(selectedOrder.id, reason);
                    if (res.success) {
                      alert("Đã hủy hóa đơn thành công!");
                      setSelectedOrder(null);
                    } else {
                      alert(res.error || "Lỗi khi hủy hóa đơn");
                    }
                  }}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "6px",
                    color: "#D9383A",
                    borderColor: "rgba(217, 56, 58, 0.4)",
                    background: "#FFF0F2"
                  }}
                >
                  <XCircle size={16} />
                  Hủy Hóa Đơn
                </button>
              )}
              <button
                className="btn-secondary"
                onClick={async () => {
                  const ok = window.confirm(`Bạn có chắc chắn muốn XÓA VĨNH VIỄN hóa đơn #${selectedOrder.billCode || selectedOrder.orderCode || selectedOrder.id?.slice(0, 8)} khỏi hệ thống không?\nHành động này không thể hoàn tác!`);
                  if (!ok) return;
                  const res = await deleteOrder(selectedOrder.id);
                  if (res.success) {
                    alert("Đã xóa vĩnh viễn hóa đơn khỏi hệ thống!");
                    setSelectedOrder(null);
                  } else {
                    alert(res.error || "Lỗi khi xóa hóa đơn");
                  }
                }}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "6px",
                  color: "#B22222",
                  borderColor: "rgba(178, 34, 34, 0.3)",
                }}
              >
                <Trash2 size={16} />
                Xóa Vĩnh Viễn
              </button>
              <button
                className="btn-secondary"
                onClick={() => handlePrint(selectedOrder)}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
              >
                <Printer size={16} />
                In Hóa Đơn
              </button>
              <button
                className="btn-secondary"
                onClick={() => handleExportSingle(selectedOrder)}
                style={{ display: "flex", alignItems: "center", gap: "6px" }}
              >
                <Download size={16} />
                Xuất Excel Đơn Này
              </button>
              <button
                className="btn-primary"
                onClick={() => setSelectedOrder(null)}
              >
                Đóng
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
