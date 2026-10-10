"use client";
import { useState, useMemo } from "react";
import { format, formatDistanceToNow } from "date-fns";
import { vi } from "date-fns/locale";
import {
  Download,
  Search,
  AlertTriangle,
  Eye,
  PlusCircle,
  ChefHat,
  CreditCard,
  GitMerge,
  ArrowRightLeft,
  Scissors,
  XCircle,
  Wallet,
  LogIn,
  LogOut,
  Utensils,
  Info,
  X,
  CheckCircle2,
  Copy,
  Check,
  Printer,
  Trash2,
  type LucideIcon,
} from "lucide-react";
import { exportAuditLogs, exportCancellationReport, exportDeletionReport } from "@/lib/export";
import { deletionReportFromAuditLogs } from "@/lib/item-deletion";
import { useDashboardData, AuditLogItem } from "@/lib/data-context";
import { calculateCancellationReport, formatVND } from "@/lib/reports";

// Cấu hình định danh các hành động
interface ActionConfig {
  label: string;
  shortLabel: string;
  icon: LucideIcon;
  color: string;
  bg: string;
  border: string;
  category: "ALL" | "ORDER" | "PAYMENT" | "TABLE_MGMT" | "CANCEL" | "DELETE_ITEM" | "SHIFT" | "AUTH" | "SUSPICIOUS";
}

const ACTION_CONFIGS: Record<string, ActionConfig> = {
  ADD_ITEMS: {
    label: "Thêm món vào bàn",
    shortLabel: "+ Nhập món",
    icon: PlusCircle,
    color: "#146A65",
    bg: "#E6F4F2",
    border: "#A3D9D2",
    category: "ORDER",
  },
  SEND_KITCHEN: {
    label: "Gửi báo bếp",
    shortLabel: "🍳 Gửi bếp",
    icon: ChefHat,
    color: "#0D9488",
    bg: "#CCFBF1",
    border: "#5EEAD4",
    category: "ORDER",
  },
  PAY_BILL: {
    label: "Thanh toán hóa đơn",
    shortLabel: "💳 Thanh toán",
    icon: CreditCard,
    color: "#7E2930",
    bg: "#FBECEE",
    border: "#E8A2A8",
    category: "PAYMENT",
  },
  PAYMENT: {
    label: "Thanh toán hóa đơn",
    shortLabel: "💳 Thanh toán",
    icon: CreditCard,
    color: "#7E2930",
    bg: "#FBECEE",
    border: "#E8A2A8",
    category: "PAYMENT",
  },
  MERGE_TABLE: {
    label: "Ghép bàn",
    shortLabel: "🔀 Gộp bàn",
    icon: GitMerge,
    color: "#D97706",
    bg: "#FEF3C7",
    border: "#FDE68A",
    category: "TABLE_MGMT",
  },
  TRANSFER_TABLE: {
    label: "Chuyển bàn",
    shortLabel: "🔄 Chuyển bàn",
    icon: ArrowRightLeft,
    color: "#0284C7",
    bg: "#E0F2FE",
    border: "#BAE6FD",
    category: "TABLE_MGMT",
  },
  SPLIT_BILL: {
    label: "Tách hóa đơn",
    shortLabel: "✂️ Tách đơn",
    icon: Scissors,
    color: "#4F46E5",
    bg: "#EEF2FF",
    border: "#C7D2FE",
    category: "TABLE_MGMT",
  },
  CANCEL_ITEM: {
    label: "Hủy / Bỏ bớt món",
    shortLabel: "❌ Bỏ món",
    icon: XCircle,
    color: "#E11D48",
    bg: "#FFE4E6",
    border: "#FECDD3",
    category: "CANCEL",
  },
  DELETE_ITEM: {
    label: "Xóa món khỏi đơn",
    shortLabel: "🗑️ Xóa món",
    icon: Trash2,
    color: "#BE123C",
    bg: "#FFE4E6",
    border: "#FDA4AF",
    category: "DELETE_ITEM",
  },
  CANCEL_KITCHEN_ITEM: {
    label: "Hủy món đã gửi bếp",
    shortLabel: "⚠️ Hủy món bếp",
    icon: AlertTriangle,
    color: "#DC2626",
    bg: "#FEE2E2",
    border: "#FCA5A5",
    category: "CANCEL",
  },
  CANCEL_ORDER: {
    label: "Hủy cả đơn hàng",
    shortLabel: "🚫 Hủy đơn",
    icon: AlertTriangle,
    color: "#DC2626",
    bg: "#FEE2E2",
    border: "#FCA5A5",
    category: "CANCEL",
  },
  OPEN_SHIFT: {
    label: "Mở ca làm việc",
    shortLabel: "💰 Mở ca két",
    icon: Wallet,
    color: "#059669",
    bg: "#D1FAE5",
    border: "#6EE7B7",
    category: "SHIFT",
  },
  CLOSE_SHIFT: {
    label: "Chốt két / Đóng ca",
    shortLabel: "🔒 Chốt két ca",
    icon: Wallet,
    color: "#059669",
    bg: "#D1FAE5",
    border: "#6EE7B7",
    category: "SHIFT",
  },
  LOGIN: {
    label: "Đăng nhập POS",
    shortLabel: "🔑 Đăng nhập",
    icon: LogIn,
    color: "#475569",
    bg: "#F1F5F9",
    border: "#CBD5E1",
    category: "AUTH",
  },
  LOGOUT: {
    label: "Đăng xuất POS",
    shortLabel: "🚪 Đăng xuất",
    icon: LogOut,
    color: "#64748B",
    bg: "#F8FAFC",
    border: "#E2E8F0",
    category: "AUTH",
  },
};

const SUSPICIOUS_ACTIONS = ["CANCEL_KITCHEN_ITEM", "CANCEL_ORDER", "DELETE_HISTORY", "DELETE_USER", "FORCE_LOGOUT"];

function getActionMeta(action: string): ActionConfig {
  if (ACTION_CONFIGS[action]) return ACTION_CONFIGS[action];

  const isSuspicious = SUSPICIOUS_ACTIONS.includes(action) || action.startsWith("DELETE") || action.startsWith("CANCEL");
  return {
    label: action,
    shortLabel: action,
    icon: isSuspicious ? AlertTriangle : Info,
    color: isSuspicious ? "#DC2626" : "#475569",
    bg: isSuspicious ? "#FEE2E2" : "#F1F5F9",
    border: isSuspicious ? "#FCA5A5" : "#CBD5E1",
    category: isSuspicious ? "SUSPICIOUS" : "ALL",
  };
}

// Trích xuất Bàn hoặc Đối tượng từ targetId hoặc details nếu chưa có
function extractTarget(log: AuditLogItem): { label: string; isTable: boolean } {
  if (log.action === "DELETE_ITEM" && typeof log.tableName === "string" && log.tableName) {
    return { label: log.tableName, isTable: true };
  }
  if (log.targetId && log.targetId.trim().length > 0) {
    const isTable = log.targetType === "TABLE" || log.targetId.toLowerCase().includes("bàn") || /^[A-Z0-9_\-\s]+$/.test(log.targetId);
    return { label: log.targetId, isTable };
  }
  // Thử trích xuất từ details (ví dụ: "Gửi bếp bàn A2, 1 món" -> "Bàn A2")
  if (log.details) {
    const match = log.details.match(/(?:bàn|bàn\s+)([A-Za-z0-9_\-]+(?:\s*->\s*[A-Za-z0-9_\-]+)?)/i);
    if (match && match[1]) {
      return { label: `Bàn ${match[1].toUpperCase()}`, isTable: true };
    }
  }
  return { label: log.targetType || "Hệ thống", isTable: false };
}

function getRoleName(role?: string): string {
  if (!role) return "Nhân viên";
  const r = role.toUpperCase();
  if (r.includes("MANAGER") || r.includes("OWNER") || r.includes("ADMIN")) return "👑 Quản lý";
  if (r.includes("KITCHEN") || r.includes("BẾP")) return "🍳 Bếp";
  if (r.includes("CASHIER") || r.includes("THU NGÂN")) return "💳 Thu ngân";
  return "👤 Nhân viên";
}

const PAGE_SIZE = 25;

export default function AuditPage() {
  const { auditLogs: logs, historyData, stores, currentStoreCode, loading: ctxLoading } = useDashboardData();
  const loading = ctxLoading && logs.length === 0;

  const [search, setSearch] = useState("");
  const [categoryFilter, setCategoryFilter] = useState<string>("ALL");
  const [filterAction, setFilterAction] = useState("");
  const [filterUser, setFilterUser] = useState("");
  const [page, setPage] = useState(1);
  const [selectedLog, setSelectedLog] = useState<AuditLogItem | null>(null);
  const [copied, setCopied] = useState(false);
  // "Báo cáo xóa món": tổng hợp theo lý do / nhân viên từ audit log DELETE_ITEM
  const [showDeletionReport, setShowDeletionReport] = useState(false);

  const cancellationReport = useMemo(() => {
    return calculateCancellationReport(historyData);
  }, [historyData]);

  const targetStoreInfo = useMemo(() => {
    if (currentStoreCode === "ALL") return { storeName: "Tất cả chi nhánh", storeCode: "ALL" };
    return (
      stores.find((s) => s.storeCode === currentStoreCode) || {
        storeName: "POS Trạm",
        storeCode: currentStoreCode,
      }
    );
  }, [stores, currentStoreCode]);

  // Danh sách các hành động và người dùng duy nhất
  const uniqueActions = useMemo(() => {
    return [...new Set(logs.map((l) => l.action).filter(Boolean))].sort();
  }, [logs]);

  const uniqueUsers = useMemo(() => {
    return [...new Set(logs.map((l) => l.userFullName || l.username).filter(Boolean))].sort();
  }, [logs]);

  // Bộ lọc nâng cao
  const filtered = useMemo(() => {
    return logs.filter((l) => {
      const meta = getActionMeta(l.action);
      const target = extractTarget(l);

      // Lọc theo Category Tab
      if (categoryFilter !== "ALL") {
        if (categoryFilter === "SUSPICIOUS") {
          const isSuspicious = l.isSuspicious || SUSPICIOUS_ACTIONS.includes(l.action);
          if (!isSuspicious) return false;
        } else if (meta.category !== categoryFilter) {
          return false;
        }
      }

      // Lọc theo Action cụ thể
      if (filterAction && l.action !== filterAction) return false;

      // Lọc theo User
      if (filterUser) {
        const u = l.userFullName || l.username || "";
        if (u !== filterUser) return false;
      }

      // Tìm kiếm tự do
      if (search.trim()) {
        const q = search.toLowerCase();
        const inAction = (l.action || "").toLowerCase().includes(q);
        const inDetails = (l.details || "").toLowerCase().includes(q);
        const inUser = (l.username || "").toLowerCase().includes(q) || (l.userFullName || "").toLowerCase().includes(q);
        const inTarget = target.label.toLowerCase().includes(q);
        if (!inAction && !inDetails && !inUser && !inTarget) return false;
      }

      return true;
    });
  }, [logs, categoryFilter, filterAction, filterUser, search]);

  // Thống kê nhanh
  const stats = useMemo(() => {
    let orderCount = 0;
    let paymentCount = 0;
    let tableMgmtCount = 0;
    let cancelCount = 0;
    let deleteItemCount = 0;
    let shiftCount = 0;
    let suspiciousCount = 0;

    logs.forEach((l) => {
      const meta = getActionMeta(l.action);
      if (meta.category === "ORDER") orderCount++;
      if (meta.category === "PAYMENT") paymentCount++;
      if (meta.category === "TABLE_MGMT") tableMgmtCount++;
      if (meta.category === "CANCEL") cancelCount++;
      if (meta.category === "DELETE_ITEM") deleteItemCount++;
      if (meta.category === "SHIFT") shiftCount++;
      if (l.isSuspicious || SUSPICIOUS_ACTIONS.includes(l.action)) suspiciousCount++;
    });

    return { orderCount, paymentCount, tableMgmtCount, cancelCount, deleteItemCount, shiftCount, suspiciousCount };
  }, [logs]);

  // Báo cáo xóa món theo bộ lọc hiện tại (nhân viên / tìm kiếm)
  const deletionReport = useMemo(() => deletionReportFromAuditLogs(filtered), [filtered]);

  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const paginated = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const handleExport = () => {
    const exportData = filtered.map((l) => {
      const meta = getActionMeta(l.action);
      const target = extractTarget(l);
      return {
        ...l,
        actionDisplay: meta.label,
        targetId: target.label,
      };
    });
    exportAuditLogs(exportData);
  };

  const handleExportCancellationExcel = () => {
    exportCancellationReport(cancellationReport, targetStoreInfo).toExcel();
  };

  const handleExportCancellationPDF = () => {
    exportCancellationReport(cancellationReport, targetStoreInfo).toPDF();
  };

  const handleCopyDetails = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
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
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", flexWrap: "wrap", gap: "16px" }}>
        <div>
          <h1 className="section-title" style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            Kiểm soát Hệ thống & Nhật ký Thao tác 🔍
          </h1>
          <p className="section-subtitle">
            Theo dõi chi tiết từng thao tác: nhập món, gửi bếp, thanh toán, ghép bàn, tách hóa đơn, hủy món theo thời gian thực.
          </p>
        </div>
        <div style={{ display: "flex", gap: "10px", alignItems: "center", flexWrap: "wrap" }}>
          {categoryFilter === "DELETE_ITEM" ? (
            <>
              <button
                className="btn-secondary"
                onClick={() => setShowDeletionReport((v) => !v)}
                aria-pressed={showDeletionReport}
              >
                <Trash2 size={16} /> {showDeletionReport ? "Xem nhật ký" : "Báo cáo xóa món"}
              </button>
              <button
                className="btn-primary"
                style={{ background: "#107C41" }}
                onClick={() => exportDeletionReport(deletionReport, targetStoreInfo).toExcel()}
              >
                <Download size={16} /> Xuất Báo cáo Xóa món (Excel)
              </button>
            </>
          ) : categoryFilter === "CANCEL" ? (
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
                style={{ background: "var(--primary)" }}
                onClick={handleExportCancellationPDF}
              >
                <Printer size={16} /> In / PDF Kiểm toán Thất thoát
              </button>
            </>
          ) : (
            <button className="btn-primary" onClick={handleExport}>
              <Download size={16} />
              Xuất Excel ({filtered.length} bản ghi)
            </button>
          )}
        </div>
      </div>

      {/* Quick Category Summary Cards */}
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(160px, 100%), 1fr))", gap: "12px" }}>
        <div
          onClick={() => { setCategoryFilter("ALL"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "ALL" ? "2px solid var(--primary)" : "1px solid var(--border)",
            background: categoryFilter === "ALL" ? "var(--primary-light)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: "600" }}>Tất cả thao tác</div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--primary)", marginTop: "4px" }}>{logs.length}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("ORDER"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "ORDER" ? "2px solid var(--success)" : "1px solid var(--border)",
            background: categoryFilter === "ORDER" ? "var(--success-bg)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "var(--success)", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <PlusCircle size={14} /> Nhập món & Bếp
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--success)", marginTop: "4px" }}>{stats.orderCount}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("PAYMENT"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "PAYMENT" ? "2px solid var(--primary)" : "1px solid var(--border)",
            background: categoryFilter === "PAYMENT" ? "var(--primary-light)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "var(--primary)", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <CreditCard size={14} /> Thanh toán bàn
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--primary)", marginTop: "4px" }}>{stats.paymentCount}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("TABLE_MGMT"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "TABLE_MGMT" ? "2px solid var(--warning)" : "1px solid var(--border)",
            background: categoryFilter === "TABLE_MGMT" ? "var(--warning-bg)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "var(--warning)", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <GitMerge size={14} /> Ghép / Chuyển / Tách
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--warning)", marginTop: "4px" }}>{stats.tableMgmtCount}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("CANCEL"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "CANCEL" ? "2px solid #E11D48" : "1px solid var(--border)",
            background: categoryFilter === "CANCEL" ? "#FFE4E6" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "#E11D48", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <XCircle size={14} /> Hủy / Bớt món
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "#E11D48", marginTop: "4px" }}>{stats.cancelCount}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("DELETE_ITEM"); setPage(1); }}
          className="card"
          role="button"
          aria-pressed={categoryFilter === "DELETE_ITEM"}
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "DELETE_ITEM" ? "2px solid #BE123C" : "1px solid var(--border)",
            background: categoryFilter === "DELETE_ITEM" ? "#FFE4E6" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "#BE123C", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <Trash2 size={14} /> Xóa món
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "#BE123C", marginTop: "4px" }}>{stats.deleteItemCount}</div>
        </div>

        <div
          onClick={() => { setCategoryFilter("SUSPICIOUS"); setPage(1); }}
          className="card"
          style={{
            padding: "14px 16px",
            cursor: "pointer",
            border: categoryFilter === "SUSPICIOUS" ? "2px solid var(--danger)" : "1px solid var(--border)",
            background: categoryFilter === "SUSPICIOUS" ? "var(--danger-bg)" : "var(--surface)",
          }}
        >
          <div style={{ fontSize: "12px", color: "var(--danger)", fontWeight: "600", display: "flex", alignItems: "center", gap: "4px" }}>
            <AlertTriangle size={14} /> Cảnh báo đáng ngờ
          </div>
          <div style={{ fontSize: "20px", fontWeight: "800", color: "var(--danger)", marginTop: "4px" }}>{stats.suspiciousCount}</div>
        </div>
      </div>

      {/* Cancellation Loss Audit Banner */}
      {categoryFilter === "CANCEL" && (
        <div
          style={{
            padding: "16px 20px",
            background: "var(--danger-bg)",
            border: "1px solid #FECDD3",
            borderRadius: "12px",
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            flexWrap: "wrap",
            gap: "12px",
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
            <AlertTriangle size={20} color="#DC2626" />
            <div>
              <div style={{ fontWeight: "700", color: "#991B1B", fontSize: "14px" }}>
                Kiểm toán Thất thoát: {cancellationReport.cancelledBillsCount} hóa đơn bị hủy
              </div>
              <div style={{ fontSize: "12px", color: "var(--danger)" }}>
                Tổng giá trị thất thoát tài chính từ các đơn hủy: <strong>{formatVND(cancellationReport.totalLossValue)}</strong>
              </div>
            </div>
          </div>
        </div>
      )}

      {categoryFilter === "DELETE_ITEM" && (
        <div className="card" style={{ padding: "16px 20px", display: "flex", gap: "24px", flexWrap: "wrap", alignItems: "center" }}>
          <div>
            <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 600 }}>Số lần xóa</div>
            <div style={{ fontSize: "18px", fontWeight: 800, color: "var(--text)" }}>{deletionReport.entries}</div>
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 600 }}>Số món xóa</div>
            <div style={{ fontSize: "18px", fontWeight: 800, color: "var(--text)" }}>{deletionReport.quantity}</div>
          </div>
          <div>
            <div style={{ fontSize: "12px", color: "var(--subtext)", fontWeight: 600 }}>Tổng tiền xóa món</div>
            <div style={{ fontSize: "18px", fontWeight: 800, color: "var(--danger)" }}>{formatVND(deletionReport.amount)}</div>
          </div>
        </div>
      )}

      {categoryFilter === "DELETE_ITEM" && showDeletionReport && (
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(min(360px, 100%), 1fr))", gap: "16px" }}>
          {([
            { title: "Theo lý do", groups: deletionReport.byReason, head: "Lý do" },
            { title: "Theo nhân viên", groups: deletionReport.byStaff, head: "Nhân viên" },
          ] as const).map((sec) => (
            <div key={sec.title} className="card" style={{ padding: "16px 20px" }}>
              <h3 style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)", margin: "0 0 10px" }}>Báo cáo xóa món — {sec.title}</h3>
              <div className="table-wrapper">
                <table>
                  <thead>
                    <tr>
                      <th>{sec.head}</th>
                      <th style={{ textAlign: "right" }}>Số lần</th>
                      <th style={{ textAlign: "right" }}>Số món</th>
                      <th style={{ textAlign: "right" }}>Giá trị</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sec.groups.length === 0 ? (
                      <tr><td colSpan={4} style={{ textAlign: "center", color: "var(--muted)", padding: "20px" }}>Chưa có dữ liệu xóa món</td></tr>
                    ) : (
                      sec.groups.map((g) => (
                        <tr key={g.key}>
                          <td style={{ fontWeight: 600 }}>{g.label}</td>
                          <td style={{ textAlign: "right" }}>{g.count}</td>
                          <td style={{ textAlign: "right" }}>{g.quantity}</td>
                          <td style={{ textAlign: "right", fontWeight: 700, color: "var(--danger)" }}>{formatVND(g.amount)}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          ))}
          <div className="card" style={{ padding: "16px 20px", gridColumn: "1 / -1" }}>
            <h3 style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)", margin: "0 0 10px" }}>Danh sách món đã xóa</h3>
            <div className="table-wrapper">
              <table>
                <thead>
                  <tr>
                    <th>Thời gian</th>
                    <th>Bàn</th>
                    <th>Món</th>
                    <th style={{ textAlign: "right" }}>SL</th>
                    <th style={{ textAlign: "right" }}>Giá trị</th>
                    <th>Lý do</th>
                    <th>Nhân viên</th>
                  </tr>
                </thead>
                <tbody>
                  {deletionReport.rows.length === 0 ? (
                    <tr><td colSpan={7} style={{ textAlign: "center", color: "var(--muted)", padding: "20px" }}>Chưa có dữ liệu xóa món</td></tr>
                  ) : (
                    deletionReport.rows.map((r, i) => (
                      <tr key={`${r.timestamp}-${i}`}>
                        <td style={{ fontSize: "12px" }}>{r.timestamp ? format(new Date(r.timestamp), "HH:mm dd/MM/yyyy", { locale: vi }) : "—"}</td>
                        <td style={{ fontWeight: 600 }}>{r.tableName || "—"}</td>
                        <td>
                          {r.name}
                          {r.sentToKitchen ? <div style={{ fontSize: "11px", color: "var(--warning)" }}>Đã gửi bếp</div> : null}
                        </td>
                        <td style={{ textAlign: "right" }}>{r.quantity}</td>
                        <td style={{ textAlign: "right", fontWeight: 700, color: "var(--danger)" }}>{formatVND(r.amount)}</td>
                        <td style={{ fontSize: "12px" }}>{r.reason || "—"}</td>
                        <td style={{ fontSize: "12px" }}>{r.staffFullName || r.staffUsername || "—"}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {/* Filters Toolbar */}
      <div className="card" style={{ padding: "16px 20px" }}>
        <div style={{ display: "flex", gap: "12px", flexWrap: "wrap", alignItems: "center" }}>
          {/* Search bar */}
          <div style={{ position: "relative", flex: "1", minWidth: "240px" }}>
            <Search size={16} style={{ position: "absolute", left: "12px", top: "50%", transform: "translateY(-50%)", color: "var(--muted)" }} />
            <input
              className="input-field"
              placeholder="Tìm theo món, tên bàn, nhân viên, mã đơn..."
              value={search}
              onChange={(e) => { setSearch(e.target.value); setPage(1); }}
              style={{ paddingLeft: "38px", width: "100%" }}
            />
          </div>

          {/* Action select */}
          <select
            className="input-field"
            value={filterAction}
            onChange={(e) => { setFilterAction(e.target.value); setPage(1); }}
            style={{ width: "auto", minWidth: "200px" }}
          >
            <option value="">⚙️ Tất cả loại hành động</option>
            {uniqueActions.map((a) => {
              const meta = getActionMeta(a);
              return (
                <option key={a} value={a}>
                  {meta.label} ({a})
                </option>
              );
            })}
          </select>

          {/* User select */}
          <select
            className="input-field"
            value={filterUser}
            onChange={(e) => { setFilterUser(e.target.value); setPage(1); }}
            style={{ width: "auto", minWidth: "180px" }}
          >
            <option value="">👤 Tất cả nhân viên</option>
            {uniqueUsers.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>

          {(search || filterAction || filterUser || categoryFilter !== "ALL") && (
            <button
              className="btn-secondary"
              onClick={() => {
                setSearch("");
                setFilterAction("");
                setFilterUser("");
                setCategoryFilter("ALL");
                setPage(1);
              }}
              style={{ padding: "8px 14px", fontSize: "13px" }}
            >
              Đặt lại lọc
            </button>
          )}
        </div>
      </div>

      {/* Main Table */}
      {!(categoryFilter === "DELETE_ITEM" && showDeletionReport) && (
      <div className="table-wrapper">
        <table>
          <thead>
            <tr>
              <th style={{ width: "45px" }}>#</th>
              <th style={{ width: "180px" }}>HÀNH ĐỘNG</th>
              <th style={{ width: "160px" }}>BÀN / ĐỐI TƯỢNG</th>
              <th style={{ width: "170px" }}>NGƯỜI THỰC HIỆN</th>
              <th style={{ width: "150px" }}>THỜI GIAN</th>
              <th>CHI TIẾT THAO TÁC</th>
              <th style={{ width: "80px", textAlign: "center" }}>CHI TIẾT</th>
            </tr>
          </thead>
          <tbody>
            {paginated.length === 0 ? (
              <tr>
                <td colSpan={7} style={{ textAlign: "center", padding: "64px", color: "var(--muted)" }}>
                  <div style={{ fontSize: "16px", fontWeight: "600", marginBottom: "6px" }}>Không tìm thấy nhật ký phù hợp</div>
                  <div style={{ fontSize: "13px" }}>Thử điều chỉnh lại từ khóa tìm kiếm hoặc bỏ bớt các bộ lọc</div>
                </td>
              </tr>
            ) : (
              paginated.map((log, i) => {
                const ts = log.timestamp ? (typeof log.timestamp === "number" ? log.timestamp : new Date(log.timestamp).getTime()) : null;
                const meta = getActionMeta(log.action);
                const target = extractTarget(log);
                const IconComponent = meta.icon;
                const isSuspicious = log.isSuspicious || SUSPICIOUS_ACTIONS.includes(log.action);

                return (
                  <tr
                    key={log.id}
                    onClick={() => setSelectedLog(log)}
                    style={{
                      cursor: "pointer",
                      background: isSuspicious ? "rgba(220, 38, 38, 0.04)" : undefined,
                      borderLeft: isSuspicious ? "4px solid var(--danger)" : undefined,
                    }}
                  >
                    {/* Index */}
                    <td style={{ color: "var(--muted)", fontSize: "12px", fontWeight: "500" }}>
                      {(page - 1) * PAGE_SIZE + i + 1}
                    </td>

                    {/* Action Badge */}
                    <td>
                      <div
                        style={{
                          display: "inline-flex",
                          alignItems: "center",
                          gap: "6px",
                          padding: "4px 10px",
                          borderRadius: "20px",
                          fontSize: "12px",
                          fontWeight: "700",
                          color: meta.color,
                          backgroundColor: meta.bg,
                          border: `1px solid ${meta.border}`,
                          whiteSpace: "nowrap",
                        }}
                      >
                        <IconComponent size={14} />
                        <span>{meta.shortLabel}</span>
                      </div>
                    </td>

                    {/* Table / Target */}
                    <td>
                      <div style={{ display: "inline-flex", alignItems: "center", gap: "6px" }}>
                        {target.isTable ? (
                          <span
                            style={{
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "4px",
                              background: "var(--warning-bg)",
                              color: "#B45309",
                              border: "1px solid #FDE68A",
                              padding: "3px 8px",
                              borderRadius: "6px",
                              fontWeight: "700",
                              fontSize: "13px",
                            }}
                          >
                            <Utensils size={12} />
                            {target.label}
                          </span>
                        ) : (
                          <span
                            style={{
                              display: "inline-flex",
                              alignItems: "center",
                              gap: "4px",
                              background: "var(--surface-muted)",
                              color: "var(--subtext)",
                              padding: "3px 8px",
                              borderRadius: "6px",
                              fontSize: "12px",
                              fontWeight: "600",
                            }}
                          >
                            {target.label}
                          </span>
                        )}
                      </div>
                    </td>

                    {/* User / Role */}
                    <td>
                      <div>
                        <div style={{ fontWeight: "700", fontSize: "13px", color: "var(--text)" }}>
                          {log.userFullName || log.username || "—"}
                        </div>
                        <div style={{ fontSize: "11px", color: "var(--subtext)", marginTop: "2px" }}>
                          {log.username && log.userFullName && (
                            <span style={{ fontFamily: "monospace", color: "var(--muted)" }}>@{log.username} • </span>
                          )}
                          <span>{getRoleName(log.userRole)}</span>
                        </div>
                      </div>
                    </td>

                    {/* Timestamp */}
                    <td>
                      <div style={{ fontSize: "12px", fontWeight: "600", color: "var(--text)" }}>
                        {ts ? format(new Date(ts), "HH:mm:ss", { locale: vi }) : "—"}
                      </div>
                      <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
                        {ts ? format(new Date(ts), "dd/MM/yyyy", { locale: vi }) : "—"}
                      </div>
                    </td>

                    {/* Details Content */}
                    <td>
                      <div
                        style={{
                          fontSize: "13px",
                          lineHeight: "1.45",
                          color: isSuspicious ? "var(--danger)" : "#2E2C34",
                          fontWeight: isSuspicious ? "600" : "400",
                          wordBreak: "break-word",
                        }}
                      >
                        {log.details || "—"}
                      </div>
                    </td>

                    {/* View Details Eye */}
                    <td style={{ textAlign: "center" }}>
                      <button
                        className="btn-secondary"
                        style={{
                          padding: "6px 8px",
                          borderRadius: "8px",
                          color: "var(--primary)",
                          borderColor: "var(--border)",
                        }}
                        onClick={(e) => {
                          e.stopPropagation();
                          setSelectedLog(log);
                        }}
                        title="Xem chi tiết bản ghi"
                      >
                        <Eye size={15} />
                      </button>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      )}

      {/* Pagination */}
      {totalPages > 1 && !(categoryFilter === "DELETE_ITEM" && showDeletionReport) && (
        <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "center", justifyContent: "space-between", marginTop: "8px" }}>
          <div style={{ fontSize: "13px", color: "var(--subtext)" }}>
            Hiển thị <strong>{paginated.length}</strong> / <strong>{filtered.length}</strong> bản ghi
          </div>
          <div style={{ display: "flex", alignItems: "center", gap: "8px" }}>
            <button
              className="btn-secondary"
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              style={{ padding: "6px 14px", fontSize: "13px" }}
            >
              ‹ Trang trước
            </button>
            <span style={{ fontSize: "13px", fontWeight: "600", color: "var(--text)" }}>
              Trang {page} / {totalPages}
            </span>
            <button
              className="btn-secondary"
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              style={{ padding: "6px 14px", fontSize: "13px" }}
            >
              Trang sau ›
            </button>
          </div>
        </div>
      )}

      {/* ==================== AUDIT LOG DETAIL MODAL ==================== */}
      {selectedLog && (
        <div
          style={{
            position: "fixed",
            inset: 0,
            backgroundColor: "rgba(0, 0, 0, 0.5)",
            backdropFilter: "blur(4px)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            zIndex: 9999,
            padding: "20px",
          }}
          onClick={() => setSelectedLog(null)}
        >
          <div
            className="card"
            style={{
              width: "100%",
              maxWidth: "600px",
              maxHeight: "90vh",
              overflowY: "auto",
              backgroundColor: "var(--surface)",
              borderRadius: "16px",
              boxShadow: "0 20px 40px rgba(0, 0, 0, 0.2)",
              padding: "24px",
            }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "flex-start", justifyContent: "space-between", marginBottom: "20px" }}>
              <div style={{ display: "flex", alignItems: "center", gap: "10px" }}>
                {(() => {
                  const meta = getActionMeta(selectedLog.action);
                  const Icon = meta.icon;
                  return (
                    <div
                      style={{
                        width: "42px",
                        height: "42px",
                        borderRadius: "12px",
                        backgroundColor: meta.bg,
                        border: `1px solid ${meta.border}`,
                        display: "flex",
                        alignItems: "center",
                        justifyContent: "center",
                        color: meta.color,
                      }}
                    >
                      <Icon size={22} />
                    </div>
                  );
                })()}
                <div>
                  <h3 style={{ fontSize: "18px", fontWeight: "700", color: "var(--text)", margin: 0 }}>
                    {getActionMeta(selectedLog.action).label}
                  </h3>
                  <div style={{ fontSize: "12px", color: "var(--subtext)", marginTop: "2px" }}>
                    Mã hành động: <code style={{ backgroundColor: "var(--surface-muted)", padding: "2px 6px", borderRadius: "4px" }}>{selectedLog.action}</code>
                  </div>
                </div>
              </div>

              <button
                onClick={() => setSelectedLog(null)}
                style={{
                  background: "transparent",
                  border: "none",
                  cursor: "pointer",
                  color: "var(--muted)",
                  padding: "4px",
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Grid properties */}
            <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "14px", marginBottom: "20px" }}>
              {/* Bàn / Đối tượng */}
              <div style={{ background: "var(--bg)", padding: "12px 14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--subtext)", textTransform: "uppercase" }}>
                  Bàn / Đối tượng
                </div>
                <div style={{ fontSize: "15px", fontWeight: "700", color: "var(--primary)", marginTop: "4px" }}>
                  {extractTarget(selectedLog).label}
                </div>
                {selectedLog.targetType && (
                  <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
                    Loại: {selectedLog.targetType}
                  </div>
                )}
              </div>

              {/* Thời gian */}
              <div style={{ background: "var(--bg)", padding: "12px 14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--subtext)", textTransform: "uppercase" }}>
                  Thời gian ghi nhận
                </div>
                <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginTop: "4px" }}>
                  {selectedLog.timestamp
                    ? format(new Date(typeof selectedLog.timestamp === "number" ? selectedLog.timestamp : new Date(selectedLog.timestamp).getTime()), "HH:mm:ss dd/MM/yyyy", { locale: vi })
                    : "—"}
                </div>
                {selectedLog.timestamp && (
                  <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
                    {formatDistanceToNow(new Date(typeof selectedLog.timestamp === "number" ? selectedLog.timestamp : new Date(selectedLog.timestamp).getTime()), { addSuffix: true, locale: vi })}
                  </div>
                )}
              </div>

              {/* Người thực hiện */}
              <div style={{ background: "var(--bg)", padding: "12px 14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--subtext)", textTransform: "uppercase" }}>
                  Người thực hiện
                </div>
                <div style={{ fontSize: "14px", fontWeight: "700", color: "var(--text)", marginTop: "4px" }}>
                  {selectedLog.userFullName || selectedLog.username || "—"}
                </div>
                <div style={{ fontSize: "11px", color: "var(--subtext)", marginTop: "2px" }}>
                  {selectedLog.username && <span>@{selectedLog.username} • </span>}
                  {getRoleName(selectedLog.userRole)}
                </div>
              </div>

              {/* Mức độ bảo mật */}
              <div style={{ background: "var(--bg)", padding: "12px 14px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                <div style={{ fontSize: "11px", fontWeight: "600", color: "var(--subtext)", textTransform: "uppercase" }}>
                  Mức độ giám sát
                </div>
                <div style={{ marginTop: "4px" }}>
                  {selectedLog.isSuspicious || SUSPICIOUS_ACTIONS.includes(selectedLog.action) ? (
                    <span style={{ color: "var(--danger)", fontWeight: "700", fontSize: "13px", display: "flex", alignItems: "center", gap: "4px" }}>
                      <AlertTriangle size={14} /> Cảnh báo đáng ngờ
                    </span>
                  ) : (
                    <span style={{ color: "var(--success)", fontWeight: "600", fontSize: "13px", display: "flex", alignItems: "center", gap: "4px" }}>
                      <CheckCircle2 size={14} /> Thao tác hợp lệ
                    </span>
                  )}
                </div>
                <div style={{ fontSize: "11px", color: "var(--muted)", marginTop: "2px" }}>
                  Log ID: {selectedLog.id}
                </div>
              </div>
            </div>

            {selectedLog.action === "DELETE_ITEM" && (
              <div className="grid-stack-sm" style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "10px", marginBottom: "20px" }}>
                {[
                  ["Món", String(selectedLog.productName ?? "—")],
                  ["Số lượng", String(selectedLog.quantity ?? "—")],
                  ["Giá trị xóa", formatVND(Number(selectedLog.amount) || 0)],
                  ["Lý do", String(selectedLog.reason ?? "—")],
                  ["Bàn", String(selectedLog.tableName ?? "—")],
                  ["Mã đơn", String(selectedLog.orderCode || "—")],
                ].map(([k, v]) => (
                  <div key={k} style={{ background: "var(--bg)", padding: "10px 12px", borderRadius: "10px", border: "1px solid var(--border)" }}>
                    <div style={{ fontSize: "11px", fontWeight: 600, color: "var(--subtext)", textTransform: "uppercase" }}>{k}</div>
                    <div style={{ fontSize: "14px", fontWeight: 700, color: "var(--text)", marginTop: "2px", wordBreak: "break-word" }}>{v}</div>
                  </div>
                ))}
              </div>
            )}

            {/* Chi tiết đầy đủ */}
            <div style={{ marginBottom: "20px" }}>
              <div style={{ display: "flex", flexWrap: "wrap", rowGap: "8px", alignItems: "center", justifyContent: "space-between", marginBottom: "8px" }}>
                <div style={{ fontSize: "13px", fontWeight: "700", color: "var(--text)" }}>
                  Nội dung chi tiết thao tác:
                </div>
                <button
                  onClick={() => handleCopyDetails(selectedLog.details || "")}
                  style={{
                    background: "none",
                    border: "none",
                    cursor: "pointer",
                    fontSize: "12px",
                    color: copied ? "var(--success)" : "var(--primary)",
                    display: "flex",
                    alignItems: "center",
                    gap: "4px",
                    fontWeight: "600",
                  }}
                >
                  {copied ? <Check size={14} /> : <Copy size={14} />}
                  {copied ? "Đã sao chép" : "Sao chép"}
                </button>
              </div>

              <div
                style={{
                  background: "var(--surface-muted)",
                  border: "1px solid var(--border)",
                  borderRadius: "12px",
                  padding: "16px",
                  fontSize: "14px",
                  lineHeight: "1.6",
                  color: "var(--text)",
                  whiteSpace: "pre-wrap",
                  wordBreak: "break-word",
                }}
              >
                {selectedLog.details || "Không có chi tiết bổ sung."}
              </div>
            </div>

            {/* Modal Actions */}
            <div style={{ display: "flex", justifyContent: "flex-end", gap: "10px" }}>
              <button
                className="btn-secondary"
                onClick={() => setSelectedLog(null)}
                style={{ padding: "8px 18px", fontSize: "13px" }}
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
