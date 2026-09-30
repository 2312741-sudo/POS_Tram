import * as XLSX from "xlsx";
import { format } from "date-fns";
import { vi } from "date-fns/locale";

function downloadWorkbook(wb: XLSX.WorkBook, filename: string) {
  XLSX.writeFile(wb, filename);
}

export function exportRevenue(data: any[], title = "Doanh thu") {
  const rows = data.map((item) => ({
    "Ngày": item.date || "",
    "Số hóa đơn": item.totalOrders || 0,
    "Doanh thu (VNĐ)": item.totalRevenue || 0,
    "Tiền mặt (VNĐ)": item.cashRevenue || 0,
    "Chuyển khoản (VNĐ)": item.transferRevenue || 0,
    "TB/Đơn (VNĐ)": item.avgPerOrder || 0,
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [{ wch: 16 }, { wch: 14 }, { wch: 18 }, { wch: 18 }, { wch: 20 }, { wch: 16 }];
  XLSX.utils.book_append_sheet(wb, ws, title);
  downloadWorkbook(wb, `${title}_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportHistory(data: any[]) {
  const wb = XLSX.utils.book_new();

  // 1. Sheet Tổng hợp Hóa đơn
  const summaryRows = data.map((item) => {
    const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
    const createdTs = typeof item.createdAt === "number" ? item.createdAt : new Date(item.createdAt || ts).getTime();
    const closedTs = typeof item.closedAt === "number" ? item.closedAt : new Date(item.closedAt || ts).getTime();
    const itemCount = Array.isArray(item.items) ? item.items.reduce((s: number, i: any) => s + (i.quantity || 1), 0) : 0;

    return {
      "Mã đơn": item.orderCode || item.id?.slice(0, 8) || "",
      "Bàn": item.tableName || "",
      "Khu vực": item.zone || "",
      "Tổng tiền (VNĐ)": Number(item.totalAmount) || 0,
      "Phương thức TT": item.paymentMethod || "",
      "Trạng thái": item.status || "PAID",
      "Người nhận order": item.orderStaff || item.staffFullName || "—",
      "Người thanh toán": item.cashierName || item.staffFullName || "—",
      "Thời gian tạo": item.createdAt ? format(new Date(createdTs), "dd/MM/yyyy HH:mm", { locale: vi }) : "—",
      "Thời gian thanh toán": item.timestamp ? format(new Date(closedTs), "dd/MM/yyyy HH:mm", { locale: vi }) : "—",
      "Số lượng món": itemCount,
    };
  });
  const wsSummary = XLSX.utils.json_to_sheet(summaryRows);
  wsSummary["!cols"] = [
    { wch: 18 }, { wch: 12 }, { wch: 14 }, { wch: 18 }, { wch: 16 },
    { wch: 16 }, { wch: 22 }, { wch: 20 }, { wch: 20 }, { wch: 20 }, { wch: 14 }
  ];
  XLSX.utils.book_append_sheet(wb, wsSummary, "Tổng hợp Hóa đơn");

  // 2. Sheet Chi tiết Món trong Đơn (Item Breakdown)
  const itemRows: any[] = [];
  data.forEach((item) => {
    const billCode = item.orderCode || item.id?.slice(0, 8) || "";
    const tableName = item.tableName || "";
    const cashier = item.cashierName || item.staffFullName || "—";
    const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
    const billClosedTime = item.timestamp ? format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi }) : "—";

    if (Array.isArray(item.items) && item.items.length > 0) {
      item.items.forEach((it: any) => {
        const orderTime = it.orderedAt
          ? format(new Date(typeof it.orderedAt === "number" ? it.orderedAt : new Date(it.orderedAt).getTime()), "dd/MM/yyyy HH:mm", { locale: vi })
          : billClosedTime;
        const unitPrice = Number(it.price) || 0;
        const qty = Number(it.quantity) || 1;
        const total = unitPrice * qty;

        itemRows.push({
          "Mã đơn": billCode,
          "Bàn": tableName,
          "Tên món": it.name || "",
          "Tùy chọn (Size/Đường/Đá)": it.optionsSummary || it.selectedSize ? `Size ${it.selectedSize || ""}` : "Chuẩn",
          "Ghi chú": it.note || "",
          "Số lượng": qty,
          "Đơn giá (VNĐ)": unitPrice,
          "Thành tiền (VNĐ)": total,
          "Người nhận order món": it.orderedByName || item.orderStaff || "—",
          "Thời gian gọi món": orderTime,
          "Người thanh toán HĐ": cashier,
          "Thời gian thanh toán": billClosedTime,
        });
      });
    }
  });
  if (itemRows.length > 0) {
    const wsItems = XLSX.utils.json_to_sheet(itemRows);
    wsItems["!cols"] = [
      { wch: 18 }, { wch: 12 }, { wch: 26 }, { wch: 25 }, { wch: 20 },
      { wch: 10 }, { wch: 16 }, { wch: 16 }, { wch: 22 }, { wch: 20 }, { wch: 20 }, { wch: 20 }
    ];
    XLSX.utils.book_append_sheet(wb, wsItems, "Chi tiết Món & Người nhận");
  }

  // 3. Sheet Lịch sử Thao tác (Action Logs / Timeline)
  const logRows: any[] = [];
  data.forEach((item) => {
    const billCode = item.orderCode || item.id?.slice(0, 8) || "";
    const tableName = item.tableName || "";

    if (Array.isArray(item.actionLogs) && item.actionLogs.length > 0) {
      item.actionLogs.forEach((log: any) => {
        const logTime = log.timestamp
          ? format(new Date(typeof log.timestamp === "number" ? log.timestamp : new Date(log.timestamp).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi })
          : "—";
        logRows.push({
          "Mã đơn": billCode,
          "Bàn": tableName,
          "Thời gian": logTime,
          "Nhân viên thực hiện": log.staffFullName || log.staffUsername || "—",
          "Hành động": log.action || "",
          "Chi tiết thao tác": log.details || "",
        });
      });
    }
  });
  if (logRows.length > 0) {
    const wsLogs = XLSX.utils.json_to_sheet(logRows);
    wsLogs["!cols"] = [
      { wch: 18 }, { wch: 12 }, { wch: 22 }, { wch: 22 }, { wch: 18 }, { wch: 45 }
    ];
    XLSX.utils.book_append_sheet(wb, wsLogs, "Lịch sử Thao tác");
  }

  downloadWorkbook(wb, `LichSu_HoaDon_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportSingleBillExcel(order: any) {
  const wb = XLSX.utils.book_new();
  const billCode = order.orderCode || order.id?.slice(0, 8) || "HD";
  const ts = typeof order.timestamp === "number" ? order.timestamp : new Date(order.timestamp || 0).getTime();
  const billTime = order.timestamp ? format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi }) : "—";

  // 1. Info Sheet
  const infoRows = [
    { "Thuộc tính": "Mã hóa đơn", "Giá trị": billCode },
    { "Thuộc tính": "Tên bàn", "Giá trị": order.tableName || "—" },
    { "Thuộc tính": "Khu vực", "Giá trị": order.zone || "—" },
    { "Thuộc tính": "Tổng thanh toán", "Giá trị": `${new Intl.NumberFormat("vi-VN", { style: "currency", currency: "VND" }).format(order.totalAmount || 0)}` },
    { "Thuộc tính": "Phương thức thanh toán", "Giá trị": order.paymentMethod || "Tiền mặt" },
    { "Thuộc tính": "Trạng thái", "Giá trị": order.status || "Đã thanh toán" },
    { "Thuộc tính": "Người nhận order", "Giá trị": order.orderStaff || "—" },
    { "Thuộc tính": "Người thanh toán (Thu ngân)", "Giá trị": order.cashierName || "—" },
    { "Thuộc tính": "Thời gian thanh toán", "Giá trị": billTime },
  ];
  const wsInfo = XLSX.utils.json_to_sheet(infoRows);
  wsInfo["!cols"] = [{ wch: 25 }, { wch: 35 }];
  XLSX.utils.book_append_sheet(wb, wsInfo, "Thông tin HĐ");

  // 2. Items Sheet
  if (Array.isArray(order.items) && order.items.length > 0) {
    const itemRows = order.items.map((it: any, idx: number) => {
      const unitPrice = Number(it.price) || 0;
      const qty = Number(it.quantity) || 1;
      return {
        "STT": idx + 1,
        "Tên món": it.name || "",
        "Tùy chọn": it.optionsSummary || (it.selectedSize ? `Size ${it.selectedSize}` : "Chuẩn"),
        "Ghi chú": it.note || "",
        "Số lượng": qty,
        "Đơn giá (VNĐ)": unitPrice,
        "Thành tiền (VNĐ)": unitPrice * qty,
        "Người nhận order món": it.orderedByName || order.orderStaff || "—",
      };
    });
    const wsItems = XLSX.utils.json_to_sheet(itemRows);
    wsItems["!cols"] = [{ wch: 6 }, { wch: 28 }, { wch: 22 }, { wch: 18 }, { wch: 10 }, { wch: 16 }, { wch: 18 }, { wch: 22 }];
    XLSX.utils.book_append_sheet(wb, wsItems, "Chi tiết Món");
  }

  // 3. Action Logs Sheet
  if (Array.isArray(order.actionLogs) && order.actionLogs.length > 0) {
    const logRows = order.actionLogs.map((l: any) => ({
      "Thời gian": l.timestamp ? format(new Date(typeof l.timestamp === "number" ? l.timestamp : new Date(l.timestamp).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "—",
      "Nhân viên": l.staffFullName || l.staffUsername || "—",
      "Hành động": l.action || "",
      "Chi tiết": l.details || "",
    }));
    const wsLogs = XLSX.utils.json_to_sheet(logRows);
    wsLogs["!cols"] = [{ wch: 22 }, { wch: 22 }, { wch: 18 }, { wch: 45 }];
    XLSX.utils.book_append_sheet(wb, wsLogs, "Lịch sử Thao tác");
  }

  downloadWorkbook(wb, `HoaDon_${billCode}_${format(new Date(), "yyyyMMdd_HHmm")}.xlsx`);
}

export function exportUsers(data: any[]) {
  const rows = data.map((item) => ({
    "Họ tên": item.fullName || "",
    "Tài khoản": item.username || "",
    "Vai trò": item.role || "",
    "Doanh số (VNĐ)": item.totalSales || 0,
    "Số đơn": item.totalOrders || 0,
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [{ wch: 24 }, { wch: 16 }, { wch: 12 }, { wch: 18 }, { wch: 12 }];
  XLSX.utils.book_append_sheet(wb, ws, "Nhân viên");
  downloadWorkbook(wb, `NhanVien_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportProducts(data: any[]) {
  const rows = data.map((item) => ({
    "Tên sản phẩm": item.name || "",
    "Danh mục": item.category || "",
    "Giá (VNĐ)": item.price || 0,
    "Đơn vị": item.unit || "",
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [{ wch: 28 }, { wch: 16 }, { wch: 14 }, { wch: 12 }];
  XLSX.utils.book_append_sheet(wb, ws, "Sản phẩm");
  downloadWorkbook(wb, `SanPham_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportAuditLogs(data: any[]) {
  const rows = data.map((item) => ({
    "Hành động": item.actionDisplay || item.action || "",
    "Mã hành động": item.action || "",
    "Bàn / Đối tượng": item.targetId || item.target || "—",
    "Loại đối tượng": item.targetType || "—",
    "Người thực hiện": item.userFullName ? `${item.userFullName} (${item.username})` : (item.username || "—"),
    "Vai trò": item.userRole || "",
    "Thời gian": item.timestamp ? format(new Date(typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "",
    "Chi tiết thao tác": item.details || "",
    "Cảnh báo": item.isSuspicious ? "Đáng ngờ" : "Bình thường",
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [
    { wch: 22 },
    { wch: 18 },
    { wch: 24 },
    { wch: 16 },
    { wch: 24 },
    { wch: 14 },
    { wch: 22 },
    { wch: 55 },
    { wch: 14 },
  ];
  XLSX.utils.book_append_sheet(wb, ws, "Nhật ký Hệ thống");
  downloadWorkbook(wb, `NhatKyHeThong_${format(new Date(), "yyyy-MM-dd_HHmm")}.xlsx`);
}
