"use client";
import React, { useEffect, useMemo, useState } from "react";
import { onValue, ref, update } from "firebase/database";
import { db } from "@/lib/firebase";
import { useAuth, canAccessRoute } from "@/lib/auth";
import { useDashboardData } from "@/lib/data-context";
import {
  computeKitchenSla,
  formatDurationMs,
  kitchenGroupLabel,
  KITCHEN_GROUP_DRINK,
  KITCHEN_GROUP_FOOD,
  KitchenSlaSummary,
} from "@/lib/kitchen-sla";
import {
  Clock,
  Timer,
  AlertTriangle,
  Coffee,
  CheckCircle2,
  FileSpreadsheet,
  RefreshCw,
  Search,
  Filter,
  Flame,
  Trash2,
} from "lucide-react";
import * as XLSX from "xlsx";

type DateFilterType = "today" | "yesterday" | "last7Days" | "thisMonth" | "custom";

export default function KitchenSlaPage() {
  const { user } = useAuth();
  const { stores, currentStoreCode } = useDashboardData();

  const storeCode =
    currentStoreCode !== "ALL" && currentStoreCode
      ? currentStoreCode
      : user?.storeCode || stores[0]?.storeCode || "";

  const [dateFilter, setDateFilter] = useState<DateFilterType>("today");
  const [customStart, setCustomStart] = useState("");
  const [customEnd, setCustomEnd] = useState("");
  const [thresholdMinutes, setThresholdMinutes] = useState(15);
  const [activeTab, setActiveTab] = useState<"orders" | "items">("orders");
  const [groupFilter, setGroupFilter] = useState<"ALL" | "drink" | "food">("ALL");
  const [search, setSearch] = useState("");

  const [rawTickets, setRawTickets] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Lắng nghe dữ liệu kitchen_orders
  useEffect(() => {
    if (!storeCode) return;
    setLoading(true);
    return onValue(
      ref(db, `stores/${storeCode}/kitchen_orders`),
      (snap) => {
        setRawTickets(snap.val() || {});
        setLoading(false);
        setError("");
      },
      (e) => {
        setError(e.message || "Không thể tải dữ liệu bếp");
        setLoading(false);
      }
    );
  }, [storeCode]);

  // Tính khoảng thời gian từ dateFilter
  const { fromMs, toMs } = useMemo(() => {
    const now = new Date();
    if (dateFilter === "today") {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0);
      const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
      return { fromMs: start.getTime(), toMs: end.getTime() };
    }
    if (dateFilter === "yesterday") {
      const y = new Date(now);
      y.setDate(y.getDate() - 1);
      const start = new Date(y.getFullYear(), y.getMonth(), y.getDate(), 0, 0, 0, 0);
      const end = new Date(y.getFullYear(), y.getMonth(), y.getDate(), 23, 59, 59, 999);
      return { fromMs: start.getTime(), toMs: end.getTime() };
    }
    if (dateFilter === "last7Days") {
      const s = new Date(now);
      s.setDate(s.getDate() - 6);
      const start = new Date(s.getFullYear(), s.getMonth(), s.getDate(), 0, 0, 0, 0);
      const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
      return { fromMs: start.getTime(), toMs: end.getTime() };
    }
    if (dateFilter === "thisMonth") {
      const start = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0);
      const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
      return { fromMs: start.getTime(), toMs: end.getTime() };
    }
    // Custom
    const start = customStart ? new Date(`${customStart}T00:00:00`).getTime() : 0;
    const end = customEnd ? new Date(`${customEnd}T23:59:59.999`).getTime() : Date.now();
    return { fromMs: start, toMs: end };
  }, [dateFilter, customStart, customEnd]);

  // Tính toán SLA
  const summary: KitchenSlaSummary = useMemo(() => {
    return computeKitchenSla(rawTickets, fromMs, toMs, thresholdMinutes);
  }, [rawTickets, fromMs, toMs, thresholdMinutes]);

  // Bộ lọc tìm kiếm và nhóm món
  const filteredOrders = useMemo(() => {
    const q = search.trim().toLowerCase();
    return summary.orders.filter((o) => {
      if (!q) return true;
      return (
        o.tableName.toLowerCase().includes(q) ||
        o.orderCode.toLowerCase().includes(q)
      );
    });
  }, [summary.orders, search]);

  const filteredItems = useMemo(() => {
    const q = search.trim().toLowerCase();
    return summary.items.filter((it) => {
      if (groupFilter !== "ALL" && it.group !== groupFilter) return false;
      if (!q) return true;
      return (
        it.itemName.toLowerCase().includes(q) ||
        it.tableName.toLowerCase().includes(q)
      );
    });
  }, [summary.items, groupFilter, search]);

  const formatTime = (ms: number) => {
    if (!ms) return "--:--";
    const d = new Date(ms);
    return `${d.getHours().toString().padStart(2, "0")}:${d
      .getMinutes()
      .toString()
      .padStart(2, "0")}:${d.getSeconds().toString().padStart(2, "0")}`;
  };

  const formatDate = (ms: number) => {
    if (!ms) return "";
    const d = new Date(ms);
    return `${d.getDate().toString().padStart(2, "0")}/${(d.getMonth() + 1)
      .toString()
      .padStart(2, "0")}/${d.getFullYear()}`;
  };

  // Xuất file Excel
  const handleExportExcel = () => {
    if (summary.orders.length === 0) {
      alert("Không có dữ liệu đơn bếp để xuất file!");
      return;
    }

    const orderRows = summary.orders.map((o) => [
      o.orderCode,
      o.tableName,
      o.itemCount,
      `${formatDate(o.sentAt)} ${formatTime(o.sentAt)}`,
      `${formatDate(o.doneAt)} ${formatTime(o.doneAt)}`,
      (o.durationMs / 60000).toFixed(1),
      o.isLate ? `TRỄ (>${summary.thresholdMinutes}p)` : "ĐẠT",
      o.isPartialSplit ? "Có tách xong từng phần" : "",
    ]);

    const itemRows = summary.items.map((it) => [
      it.orderKey,
      it.tableName,
      it.itemName,
      kitchenGroupLabel(it.group),
      it.quantity,
      `${formatDate(it.sentAt)} ${formatTime(it.sentAt)}`,
      `${formatDate(it.doneAt)} ${formatTime(it.doneAt)}`,
      (it.durationMs / 60000).toFixed(1),
      it.durationMs > summary.thresholdMinutes * 60000 ? "Trễ" : "Đạt",
    ]);

    const wsOrders = XLSX.utils.aoa_to_sheet([
      [
        "Mã đơn",
        "Tên bàn",
        "Số lượng món",
        "Gửi bếp lúc",
        "Hoàn thành lúc",
        "Thời gian làm (phút)",
        "Trạng thái SLA",
        "Ghi chú",
      ],
      ...orderRows,
    ]);

    const wsItems = XLSX.utils.aoa_to_sheet([
      [
        "Mã đơn",
        "Tên bàn",
        "Tên món",
        "Phân loại",
        "Số lượng",
        "Gửi bếp lúc",
        "Hoàn thành lúc",
        "Thời gian làm (phút)",
        "Trạng thái SLA",
      ],
      ...itemRows,
    ]);

    const wb = XLSX.utils.book_new();
    XLSX.utils.book_append_sheet(wb, wsOrders, "BaoCao_DonBep");
    XLSX.utils.book_append_sheet(wb, wsItems, "ChiTiet_Mon");
    XLSX.writeFile(
      wb,
      `BaoCao_SOS_Bep_${storeCode}_${new Date().toISOString().slice(0, 10)}.xlsx`
    );
  };

  const handleClearSlaData = async (mode: "range" | "all") => {
    if (!storeCode || !rawTickets) return;
    const entries = Object.entries(rawTickets);
    const updates: Record<string, null> = {};
    for (const [key, val] of entries) {
      if (!val || typeof val !== "object") continue;
      const ticket = val as Record<string, unknown>;
      if (ticket.isDone !== true) continue;
      const ts = Number(ticket.timestamp || 0);
      if (mode === "range" && (ts < fromMs || ts > toMs)) continue;
      updates[key] = null;
    }
    const count = Object.keys(updates).length;
    if (count === 0) {
      alert("Không có dữ liệu SOS nào để xoá!");
      return;
    }
    const confirmMsg =
      mode === "range"
        ? `Bạn có chắc muốn xoá ${count} bản ghi SOS trong khoảng thời gian đang lọc của chi nhánh ${storeCode}?`
        : `Bạn có chắc muốn xoá TOÀN BỘ (${count} bản ghi) dữ liệu SOS đã hoàn thành của chi nhánh ${storeCode}?`;
    if (!window.confirm(confirmMsg)) return;

    try {
      await update(ref(db, `stores/${storeCode}/kitchen_orders`), updates);
      alert(`Đã xoá ${count} bản ghi dữ liệu SOS thành công!`);
    } catch (e: unknown) {
      alert(`Lỗi khi xoá dữ liệu SOS: ${e instanceof Error ? e.message : String(e)}`);
    }
  };

  return (
    <div className="container" style={{ paddingBottom: "60px" }}>
      {/* Header */}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          alignItems: "flex-start",
          flexWrap: "wrap",
          gap: "16px",
          marginBottom: "20px",
        }}
      >
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <div
              style={{
                width: "40px",
                height: "40px",
                borderRadius: "10px",
                background: "linear-gradient(135deg, #E65100, #C2410C)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                color: "white",
              }}
            >
              <Flame size={24} />
            </div>
            <div>
              <h1 style={{ fontSize: "22px", fontWeight: "bold", margin: 0 }}>
                Đo Tốc Độ Phục Vụ Bếp (SOS / SLA)
              </h1>
              <p style={{ margin: "2px 0 0", fontSize: "13px", color: "var(--text-secondary)" }}>
                Từ lúc lobby gửi bếp đến khi bếp bấm xong • Chi nhánh: <strong>{storeCode}</strong>
              </p>
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: "10px", alignItems: "center", flexWrap: "wrap" }}>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={handleExportExcel}
            style={{ display: "flex", alignItems: "center", gap: "6px" }}
          >
            <FileSpreadsheet size={16} color="var(--success)" />
            Xuất Excel (.xlsx)
          </button>
          <button
            type="button"
            className="btn btn-secondary"
            onClick={() => handleClearSlaData("range")}
            style={{ display: "flex", alignItems: "center", gap: "6px", color: "var(--danger)", borderColor: "var(--danger)" }}
          >
            <Trash2 size={16} />
            Xoá dữ liệu lọc
          </button>
          <button
            type="button"
            className="btn btn-danger"
            onClick={() => handleClearSlaData("all")}
            style={{ display: "flex", alignItems: "center", gap: "6px" }}
          >
            <Trash2 size={16} />
            Xoá tất cả SOS
          </button>
        </div>
      </div>

      {/* Filter Bar */}
      <div
        className="card"
        style={{
          padding: "14px 18px",
          marginBottom: "20px",
          display: "flex",
          flexWrap: "wrap",
          alignItems: "center",
          justifyContent: "space-between",
          gap: "12px",
        }}
      >
        <div style={{ display: "flex", flexWrap: "wrap", alignItems: "center", gap: "8px" }}>
          <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--text-secondary)" }}>
            Thời gian:
          </span>
          {(
            [
              { key: "today", label: "Hôm nay" },
              { key: "yesterday", label: "Hôm qua" },
              { key: "last7Days", label: "7 ngày qua" },
              { key: "thisMonth", label: "Tháng này" },
              { key: "custom", label: "Tùy chọn" },
            ] as const
          ).map((t) => (
            <button
              key={t.key}
              type="button"
              className={`btn btn-sm ${dateFilter === t.key ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setDateFilter(t.key)}
            >
              {t.label}
            </button>
          ))}

          {dateFilter === "custom" && (
            <div style={{ display: "flex", alignItems: "center", gap: "6px", marginLeft: "6px" }}>
              <input
                type="date"
                className="input input-sm"
                value={customStart}
                onChange={(e) => setCustomStart(e.target.value)}
              />
              <span>-</span>
              <input
                type="date"
                className="input input-sm"
                value={customEnd}
                onChange={(e) => setCustomEnd(e.target.value)}
              />
            </div>
          )}
        </div>

        <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
          <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--text-secondary)" }}>
            Ngưỡng trễ SLA:
          </span>
          <select
            className="input input-sm"
            style={{ width: "110px" }}
            value={thresholdMinutes}
            onChange={(e) => setThresholdMinutes(Number(e.target.value) || 15)}
          >
            <option value={5}>5 phút</option>
            <option value={10}>10 phút</option>
            <option value={15}>15 phút</option>
            <option value={20}>20 phút</option>
            <option value={30}>30 phút</option>
          </select>
        </div>
      </div>

      {/* KPI Cards */}
      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))",
          gap: "14px",
          marginBottom: "24px",
        }}
      >
        <div
          className="card"
          style={{
            padding: "16px",
            borderLeft: "4px solid #0284C7",
            display: "flex",
            alignItems: "center",
            gap: "14px",
          }}
        >
          <div
            style={{
              width: "44px",
              height: "44px",
              borderRadius: "10px",
              background: "rgba(2, 132, 199, 0.12)",
              color: "#0284C7",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Timer size={22} />
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--text-secondary)", fontWeight: "500" }}>
              TB / Đơn
            </div>
            <div style={{ fontSize: "20px", fontWeight: "bold", color: "var(--text-primary)" }}>
              {formatDurationMs(summary.averageOrderMs)}
            </div>
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: "16px",
            borderLeft: "4px solid #EA580C",
            display: "flex",
            alignItems: "center",
            gap: "14px",
          }}
        >
          <div
            style={{
              width: "44px",
              height: "44px",
              borderRadius: "10px",
              background: "rgba(234, 88, 12, 0.12)",
              color: "#EA580C",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <AlertTriangle size={22} />
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--text-secondary)", fontWeight: "500" }}>
              Đơn chậm nhất
            </div>
            <div style={{ fontSize: "20px", fontWeight: "bold", color: "var(--text-primary)" }}>
              {formatDurationMs(summary.maxOrderMs)}
            </div>
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: "16px",
            borderLeft: "4px solid #0D9488",
            display: "flex",
            alignItems: "center",
            gap: "14px",
          }}
        >
          <div
            style={{
              width: "44px",
              height: "44px",
              borderRadius: "10px",
              background: "rgba(13, 148, 136, 0.12)",
              color: "#0D9488",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            <Coffee size={22} />
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--text-secondary)", fontWeight: "500" }}>
              TB / Món
            </div>
            <div style={{ fontSize: "20px", fontWeight: "bold", color: "var(--text-primary)" }}>
              {formatDurationMs(summary.averageItemMs)}
            </div>
          </div>
        </div>

        <div
          className="card"
          style={{
            padding: "16px",
            borderLeft: `4px solid ${
              summary.lateOrderCount > 0 ? "var(--danger)" : "var(--success)"
            }`,
            display: "flex",
            alignItems: "center",
            gap: "14px",
          }}
        >
          <div
            style={{
              width: "44px",
              height: "44px",
              borderRadius: "10px",
              background:
                summary.lateOrderCount > 0
                  ? "rgba(220, 38, 38, 0.12)"
                  : "rgba(22, 163, 74, 0.12)",
              color: summary.lateOrderCount > 0 ? "var(--danger)" : "var(--success)",
              display: "flex",
              alignItems: "center",
              justifyContent: "center",
            }}
          >
            {summary.lateOrderCount > 0 ? <AlertTriangle size={22} /> : <CheckCircle2 size={22} />}
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--text-secondary)", fontWeight: "500" }}>
              Tỉ lệ trễ SLA (&gt;{thresholdMinutes}p)
            </div>
            <div
              style={{
                fontSize: "20px",
                fontWeight: "bold",
                color: summary.lateOrderCount > 0 ? "var(--danger)" : "var(--success)",
              }}
            >
              {summary.lateOrderCount}/{summary.orders.length}{" "}
              {summary.orders.length > 0 &&
                `(${((summary.lateOrderCount * 100) / summary.orders.length).toFixed(0)}%)`}
            </div>
          </div>
        </div>
      </div>

      {/* Main Table Tabs */}
      <div className="card" style={{ padding: "0", overflow: "hidden" }}>
        {/* Tab Headers and Filter */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            flexWrap: "wrap",
            padding: "12px 18px",
            borderBottom: "1px solid var(--border)",
            background: "var(--surface-elevated)",
            gap: "12px",
          }}
        >
          <div style={{ display: "flex", gap: "8px" }}>
            <button
              type="button"
              className={`btn ${activeTab === "orders" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setActiveTab("orders")}
            >
              📋 Theo Đơn Hàng ({summary.orders.length})
            </button>
            <button
              type="button"
              className={`btn ${activeTab === "items" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setActiveTab("items")}
            >
              🍲 Chi Tiết Từng Món ({summary.items.length})
            </button>
          </div>

          <div style={{ display: "flex", gap: "10px", alignItems: "center" }}>
            {activeTab === "items" && (
              <div style={{ display: "flex", gap: "4px" }}>
                <button
                  type="button"
                  className={`btn btn-sm ${groupFilter === "ALL" ? "btn-primary" : "btn-secondary"}`}
                  onClick={() => setGroupFilter("ALL")}
                >
                  Tất cả
                </button>
                <button
                  type="button"
                  className={`btn btn-sm ${groupFilter === "drink" ? "btn-primary" : "btn-secondary"}`}
                  onClick={() => setGroupFilter("drink")}
                >
                  Nước uống
                </button>
                <button
                  type="button"
                  className={`btn btn-sm ${groupFilter === "food" ? "btn-primary" : "btn-secondary"}`}
                  onClick={() => setGroupFilter("food")}
                >
                  Bánh & Đồ ăn
                </button>
              </div>
            )}

            <div style={{ position: "relative" }}>
              <input
                type="text"
                className="input input-sm"
                placeholder="Tìm bàn, món, mã đơn..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                style={{ paddingLeft: "30px", width: "190px" }}
              />
              <Search
                size={14}
                style={{
                  position: "absolute",
                  left: "9px",
                  top: "50%",
                  transform: "translateY(-50%)",
                  color: "var(--text-hint)",
                }}
              />
            </div>
          </div>
        </div>

        {/* Tab 1: Orders Table */}
        {activeTab === "orders" && (
          <div className="table-responsive">
            <table className="table" style={{ width: "100%", margin: 0 }}>
              <thead>
                <tr>
                  <th style={{ width: "16%" }}>Bàn / Không gian</th>
                  <th style={{ width: "14%" }}>Mã đơn</th>
                  <th style={{ width: "10%", textAlign: "center" }}>Số món</th>
                  <th style={{ width: "15%" }}>Gửi bếp</th>
                  <th style={{ width: "15%" }}>Hoàn thành</th>
                  <th style={{ width: "15%" }}>Thời gian làm</th>
                  <th style={{ width: "15%", textAlign: "center" }}>Trạng thái SLA</th>
                </tr>
              </thead>
              <tbody>
                {filteredOrders.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center", padding: "36px", color: "var(--text-secondary)" }}>
                      {loading ? "Đang tải dữ liệu..." : "Không có đơn bếp nào phù hợp với bộ lọc."}
                    </td>
                  </tr>
                ) : (
                  filteredOrders.map((o) => (
                    <tr key={o.orderKey}>
                      <td>
                        <strong>{o.tableName}</strong>
                        {o.isPartialSplit && (
                          <span
                            className="badge badge-warning"
                            style={{ marginLeft: "6px", fontSize: "10px" }}
                          >
                            Tách phần
                          </span>
                        )}
                      </td>
                      <td style={{ fontFamily: "monospace", fontSize: "12px", color: "var(--text-secondary)" }}>
                        {o.orderCode}
                      </td>
                      <td style={{ textAlign: "center" }}>
                        <span className="badge badge-neutral">{o.itemCount} món</span>
                      </td>
                      <td>
                        {formatTime(o.sentAt)} <small style={{ color: "var(--text-hint)" }}>{formatDate(o.sentAt)}</small>
                      </td>
                      <td>
                        {formatTime(o.doneAt)} <small style={{ color: "var(--text-hint)" }}>{formatDate(o.doneAt)}</small>
                      </td>
                      <td>
                        <strong
                          style={{
                            color: o.isLate ? "var(--danger)" : "var(--success)",
                          }}
                        >
                          {formatDurationMs(o.durationMs)}
                        </strong>
                      </td>
                      <td style={{ textAlign: "center" }}>
                        {o.isLate ? (
                          <span className="badge badge-danger">
                            Trễ (&gt;{thresholdMinutes}p)
                          </span>
                        ) : (
                          <span className="badge badge-success">Đạt chuẩn</span>
                        )}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}

        {/* Tab 2: Items Table */}
        {activeTab === "items" && (
          <div className="table-responsive">
            <table className="table" style={{ width: "100%", margin: 0 }}>
              <thead>
                <tr>
                  <th style={{ width: "24%" }}>Tên món</th>
                  <th style={{ width: "12%" }}>Phân loại</th>
                  <th style={{ width: "10%", textAlign: "center" }}>Số lượng</th>
                  <th style={{ width: "16%" }}>Bàn phục vụ</th>
                  <th style={{ width: "14%" }}>Gửi bếp</th>
                  <th style={{ width: "14%" }}>Hoàn tất</th>
                  <th style={{ width: "10%" }}>Thời gian</th>
                </tr>
              </thead>
              <tbody>
                {filteredItems.length === 0 ? (
                  <tr>
                    <td colSpan={7} style={{ textAlign: "center", padding: "36px", color: "var(--text-secondary)" }}>
                      {loading ? "Đang tải dữ liệu..." : "Không có món nào phù hợp với bộ lọc."}
                    </td>
                  </tr>
                ) : (
                  filteredItems.map((it, idx) => (
                    <tr key={`${it.orderKey}_${it.itemName}_${idx}`}>
                      <td>
                        <strong>{it.itemName}</strong>
                      </td>
                      <td>
                        <span
                          className={`badge ${
                            it.group === KITCHEN_GROUP_FOOD ? "badge-warning" : "badge-info"
                          }`}
                        >
                          {kitchenGroupLabel(it.group)}
                        </span>
                      </td>
                      <td style={{ textAlign: "center" }}>
                        <strong>x{it.quantity}</strong>
                      </td>
                      <td>{it.tableName}</td>
                      <td>{formatTime(it.sentAt)}</td>
                      <td>{formatTime(it.doneAt)}</td>
                      <td>
                        <strong
                          style={{
                            color:
                              it.durationMs > thresholdMinutes * 60000
                                ? "var(--danger)"
                                : "var(--success)",
                          }}
                        >
                          {formatDurationMs(it.durationMs)}
                        </strong>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
