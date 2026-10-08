import * as XLSX from "xlsx";
import { format } from "date-fns";
import { vi } from "date-fns/locale";
import {
  OverviewReportResult,
  PeriodRevenueItem,
  CategoryReportItem,
  ProductReportItem,
  StaffPerformanceResult,
  HourlyReportItem,
  PaymentMethodSummary,
  PromotionsReportResult,
  CancellationReportResult,
  CashShiftAuditItem,
  GrossProfitReportResult,
  EndOfDayReportData,
  HistoryOrder,
  OrderItem,
  extractBillItems,
  formatVND,
  formatNumber,
} from "./reports";

export interface ReportStoreInfo {
  storeName?: string;
  address?: string;
  phone?: string;
  storeCode?: string;
  [key: string]: unknown;
}

function downloadWorkbook(wb: XLSX.WorkBook, filename: string) {
  XLSX.writeFile(wb, filename);
}

/**
 * Định dạng tên file theo chuẩn DOCS-REPORT-SPEC-2026-01:
 * [MaLoaiBaoCao]_[StoreCode]_[TuNgay]_[DenNgay]_[Timestamp].xlsx
 */
export function formatReportFileName(
  reportCode: string,
  storeCode = "TRAM01",
  startDate?: Date | string | null,
  endDate?: Date | string | null,
  ext: "xlsx" | "pdf" = "xlsx"
): string {
  const now = new Date();
  const timeStr = format(now, "HHmmss");
  const sStr = startDate ? format(new Date(startDate), "yyyyMMdd") : format(now, "yyyyMMdd");
  const eStr = endDate ? format(new Date(endDate), "yyyyMMdd") : sStr;
  const cleanStore = (storeCode || "TRAM01").toUpperCase().replace(/[^A-Z0-9]/g, "");

  return `${reportCode}_${cleanStore}_${sStr}_${eStr}_${timeStr}.${ext}`;
}

export interface ExportReportOptions {
  reportCode: string;
  reportTitle: string;
  storeName?: string;
  storeAddress?: string;
  storePhone?: string;
  storeCode?: string;
  dateRangeText?: string;
  startDate?: Date | string | null;
  endDate?: Date | string | null;
  headers: string[];
  rows: (string | number)[][];
  totalRow?: (string | number)[];
  notes?: string;
}

/**
 * Xuất dữ liệu báo cáo dạng Excel chuyên nghiệp chuẩn dàn trang (Mục 7.2)
 */
export function exportStandardReportExcel(opts: ExportReportOptions) {
  const wb = XLSX.utils.book_new();

  const storeTitle = (opts.storeName || "POS TRẠM").toUpperCase();
  const address = opts.storeAddress || "Đà Lạt, Lâm Đồng";
  const phone = opts.storePhone || "0987.654.321";
  const rangeText = opts.dateRangeText || `Kỳ báo cáo: ${format(new Date(), "dd/MM/yyyy")}`;
  const exportTimeText = `Ngày giờ xuất: ${format(new Date(), "dd/MM/yyyy HH:mm:ss", { locale: vi })} (UTC+7)`;

  // Xây dựng ma trận dòng:
  // Dòng 1-3: Header cửa hàng
  // Dòng 4: trống
  // Dòng 5-7: Tiêu đề báo cáo
  // Dòng 8: trống
  // Dòng 9: Header cột
  // Dòng 10+: Dữ liệu
  // Dòng cuối: Tổng cộng
  // Cách 2 dòng: Chữ ký xác nhận
  const sheetAoa: (string | number)[][] = [
    [storeTitle],
    [`Địa chỉ: ${address}`],
    [`Điện thoại: ${phone}`],
    [],
    [opts.reportTitle.toUpperCase()],
    [rangeText],
    [exportTimeText],
    [],
    opts.headers,
    ...opts.rows,
  ];

  if (opts.totalRow) {
    sheetAoa.push(opts.totalRow);
  }

  // Chữ ký xác nhận
  sheetAoa.push([]);
  sheetAoa.push([]);
  const sigRow1: string[] = ["Người lập biểu", "", "Thu ngân trưởng / Quản lý", "", "Chủ cửa hàng / Giám đốc"];
  const sigRow2: string[] = ["(Ký, ghi rõ họ tên)", "", "(Ký, ghi rõ họ tên)", "", "(Ký, duyệt)"];
  sheetAoa.push(sigRow1);
  sheetAoa.push(sigRow2);

  const ws = XLSX.utils.aoa_to_sheet(sheetAoa);

  // Set độ rộng cột tự động
  const colWidths = opts.headers.map((h, i) => {
    let maxLen = h.length;
    opts.rows.forEach((r) => {
      const valStr = String(r[i] ?? "");
      if (valStr.length > maxLen) maxLen = valStr.length;
    });
    return { wch: Math.max(maxLen + 4, 14) };
  });
  ws["!cols"] = colWidths;

  const fileName = formatReportFileName(opts.reportCode, opts.storeCode, opts.startDate, opts.endDate, "xlsx");
  XLSX.utils.book_append_sheet(wb, ws, "Báo cáo");
  downloadWorkbook(wb, fileName);
}

/**
 * In / Xuất PDF từ trình duyệt với bố cục chuẩn, font Be Vietnam Pro, màu Trạm #7E2930
 */
export function printStandardReportPDF(opts: ExportReportOptions) {
  if (typeof window === "undefined") return;

  const storeTitle = (opts.storeName || "POS TRẠM").toUpperCase();
  const address = opts.storeAddress || "Đà Lạt, Lâm Đồng";
  const phone = opts.storePhone || "0987.654.321";
  const rangeText = opts.dateRangeText || `Kỳ báo cáo: ${format(new Date(), "dd/MM/yyyy")}`;
  const exportTimeText = `Ngày giờ xuất: ${format(new Date(), "dd/MM/yyyy HH:mm:ss", { locale: vi })} (UTC+7)`;

  const tableHeaderHtml = opts.headers
    .map((h) => `<th style="padding: 10px 12px; border: 1px solid #D8CFBD; background: #FAF7F2; color: #1C1A2D; font-weight: 700; text-align: center; font-size: 13px;">${h}</th>`)
    .join("");

  const tableRowsHtml = opts.rows
    .map((row, idx) => {
      const bg = idx % 2 === 0 ? "#FFFFFF" : "#FDFBF7";
      const cells = row
        .map((cell, cIdx) => {
          const isNum = typeof cell === "number" || (!isNaN(Number(cell)) && String(cell).trim() !== "" && cIdx > 1);
          const align = cIdx === 0 ? "center" : (isNum ? "right" : "left");
          const valDisplay = typeof cell === "number" ? formatNumber(cell) : String(cell);
          return `<td style="padding: 8px 12px; border: 1px solid #E6DEC8; text-align: ${align}; font-size: 13px; color: #1C1A2D;">${valDisplay}</td>`;
        })
        .join("");
      return `<tr style="background: ${bg};">${cells}</tr>`;
    })
    .join("");

  const totalRowHtml = opts.totalRow
    ? `<tr style="background: #F8F4EE; font-weight: 800; border-top: 2px solid #7E2930; border-bottom: 2px solid #7E2930;">
        ${opts.totalRow
          .map((cell, cIdx) => {
            const align = cIdx === 0 ? "center" : (typeof cell === "number" ? "right" : "left");
            const valDisplay = typeof cell === "number" ? formatNumber(cell) : String(cell);
            return `<td style="padding: 10px 12px; border: 1px solid #D8CFBD; text-align: ${align}; font-size: 13px; color: #7E2930;">${valDisplay}</td>`;
          })
          .join("")}
      </tr>`
    : "";

  const printWindow = window.open("", "_blank");
  if (!printWindow) {
    alert("Vui lòng cho phép mở popup để in / xuất PDF!");
    return;
  }

  const html = `
<!DOCTYPE html>
<html lang="vi">
<head>
  <meta charset="UTF-8">
  <title>${opts.reportTitle}</title>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Be+Vietnam+Pro:wght@400;500;600;700;800&display=swap');
    @page { size: A4 portrait; margin: 12mm; }
    body {
      font-family: 'Be Vietnam Pro', -apple-system, BlinkMacSystemFont, sans-serif;
      margin: 0;
      padding: 16px;
      color: #1C1A2D;
      background: #FFFFFF;
      -webkit-print-color-adjust: exact;
      print-color-adjust: exact;
    }
    .header-table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
    .store-name { font-size: 15px; font-weight: 800; color: #1C1A2D; letter-spacing: 0.02em; }
    .store-sub { font-size: 12px; color: #5D5B63; margin-top: 2px; }
    .report-title {
      text-align: center;
      font-size: 20px;
      font-weight: 800;
      color: #7E2930;
      text-transform: uppercase;
      margin: 12px 0 4px;
      letter-spacing: 0.04em;
    }
    .report-meta {
      text-align: center;
      font-size: 12px;
      color: #5D5B63;
      margin-bottom: 18px;
    }
    .data-table {
      width: 100%;
      border-collapse: collapse;
      margin-bottom: 30px;
    }
    .sig-table {
      width: 100%;
      border-collapse: collapse;
      margin-top: 24px;
      page-break-inside: avoid;
    }
    .sig-title { font-size: 13px; font-weight: 700; color: #1C1A2D; text-align: center; }
    .sig-sub { font-size: 11px; font-style: italic; color: #8B8FA8; text-align: center; margin-top: 4px; }
    .sig-space { height: 70px; }
    @media print {
      body { padding: 0; }
      .no-print { display: none !important; }
    }
  </style>
</head>
<body>
  <table class="header-table">
    <tr>
      <td style="vertical-align: top;">
        <div class="store-name">${storeTitle}</div>
        <div class="store-sub">Địa chỉ: ${address}</div>
        <div class="store-sub">Hotline: ${phone}</div>
      </td>
      <td style="text-align: right; vertical-align: top;">
        <div style="font-size: 11px; color: #8B8FA8; font-weight: 600;">HỆ THỐNG POS TRẠM F&B</div>
        <div style="font-size: 11px; color: #8B8FA8;">Mã BC: <strong>${opts.reportCode}</strong></div>
      </td>
    </tr>
  </table>

  <div class="report-title">${opts.reportTitle}</div>
  <div class="report-meta">
    <div>${rangeText}</div>
    <div style="margin-top: 2px;">${exportTimeText}</div>
  </div>

  <table class="data-table">
    <thead>
      <tr>${tableHeaderHtml}</tr>
    </thead>
    <tbody>
      ${tableRowsHtml}
      ${totalRowHtml}
    </tbody>
  </table>

  <table class="sig-table">
    <tr>
      <td style="width: 33%;">
        <div class="sig-title">Người lập biểu</div>
        <div class="sig-sub">(Ký, ghi rõ họ tên)</div>
        <div class="sig-space"></div>
      </td>
      <td style="width: 33%;">
        <div class="sig-title">Thu ngân trưởng / Quản lý</div>
        <div class="sig-sub">(Ký, ghi rõ họ tên)</div>
        <div class="sig-space"></div>
      </td>
      <td style="width: 34%;">
        <div class="sig-title">Chủ cửa hàng / Giám đốc</div>
        <div class="sig-sub">(Ký, duyệt)</div>
        <div class="sig-space"></div>
      </td>
    </tr>
  </table>

  <div class="no-print" style="text-align: center; margin-top: 30px;">
    <button onclick="window.print()" style="padding: 10px 24px; font-size: 14px; font-weight: 700; background: #7E2930; color: white; border: none; border-radius: 8px; cursor: pointer;">
      🖨️ In / Lưu PDF ngay
    </button>
  </div>

  <script>
    window.onload = function() {
      setTimeout(function() {
        window.print();
      }, 400);
    };
  </script>
</body>
</html>
  `;

  printWindow.document.open();
  printWindow.document.write(html);
  printWindow.document.close();
}

// ==================== CÁC HÀM XUẤT 12 BÁO CÁO ====================

// 1. BÁO CÁO TỔNG QUAN QUẢN TRỊ
export function exportOverviewReport(data: OverviewReportResult, storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = ["Chỉ số tài chính / Vận hành", "Giá trị ghi nhận (VNĐ / Số lượng)"];
  const rows: (string | number)[][] = [
    ["Tổng số hóa đơn phát sinh trong kỳ", data.totalBillsCount],
    ["Số hóa đơn hoàn tất thanh toán (PAID)", data.paidBillsCount],
    ["Số hóa đơn bị hủy (CANCELLED)", data.cancelledBillsCount],
    ["Số hóa đơn hoàn tiền (REFUNDED)", data.refundedBillsCount],
    ["Tổng số lượt khách phục vụ", data.totalGuests],
    ["Doanh thu gộp (Gross Revenue)", data.grossRevenue],
    ["Giảm giá theo món (Item Discount)", data.itemDiscounts],
    ["Giảm giá hóa đơn (Bill Discount / Voucher)", data.billDiscounts],
    ["Giảm giá đổi điểm (Points Discount)", data.pointsDiscounts],
    ["Tổng giá trị giảm giá (Total Discount)", data.totalDiscount],
    ["Doanh thu sau giảm giá (After Discount)", data.afterDiscount],
    ["Tổng tiền thuế GTGT (VAT)", data.vatTotal],
    ["Doanh thu thuần (Net Revenue)", data.netRevenue],
    ["Tiền hoàn trả khách (Refund)", data.refundAmount],
    ["Doanh thu thuần sau hoàn trả", data.netRevenueWithoutRefund],
    ["Giá trị trung bình / đơn hoàn tất", data.avgRevenuePerPaidBill],
    ["Tổng giá trị thất thoát đơn hủy", data.cancelledTotalValue],
    ["Tổng giá vốn hàng bán (COGS)", data.totalCostPrice],
    ["Lợi nhuận gộp (Gross Profit)", data.grossProfit],
    ["Tỷ suất lợi nhuận gộp (%)", `${data.grossProfitMarginPercent}%`],
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_TONGHOP",
    reportTitle: "Báo cáo Tổng quan Quản trị",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 2. BÁO CÁO DOANH THU THEO KỲ
export function exportRevenueByPeriodReport(items: PeriodRevenueItem[], storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Thời gian",
    "Số đơn",
    "Doanh thu gộp",
    "Tổng giảm giá",
    "Tiền thuế VAT",
    "Doanh thu thuần",
    "Tiền mặt",
    "Chuyển khoản QR",
    "Thẻ / Ví",
    "Tỷ trọng (%)",
  ];

  const rows = items.map((it) => [
    it.periodLabel,
    it.billCount,
    it.grossRevenue,
    it.discountAmount,
    it.vatAmount,
    it.netRevenue,
    it.cashRevenue,
    it.qrRevenue,
    it.cardRevenue,
    `${it.proportion}%`,
  ]);

  const totalBills = items.reduce((s, i) => s + i.billCount, 0);
  const totalGross = items.reduce((s, i) => s + i.grossRevenue, 0);
  const totalDisc = items.reduce((s, i) => s + i.discountAmount, 0);
  const totalVat = items.reduce((s, i) => s + i.vatAmount, 0);
  const totalNet = items.reduce((s, i) => s + i.netRevenue, 0);
  const totalCash = items.reduce((s, i) => s + i.cashRevenue, 0);
  const totalQr = items.reduce((s, i) => s + i.qrRevenue, 0);
  const totalCard = items.reduce((s, i) => s + i.cardRevenue, 0);

  const totalRow = [
    "TỔNG CỘNG",
    totalBills,
    totalGross,
    totalDisc,
    totalVat,
    totalNet,
    totalCash,
    totalQr,
    totalCard,
    "100%",
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_DOANHTHU_KY",
    reportTitle: "Báo cáo Doanh thu theo Kỳ",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 3. BÁO CÁO THEO NHÓM HÀNG / DANH MỤC
export function exportCategorySalesReport(items: CategoryReportItem[], storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "STT",
    "Nhóm hàng / Danh mục",
    "Số lượng bán",
    "Doanh thu gộp",
    "Giảm giá món",
    "Doanh thu thực tế",
    "Giá vốn (COGS)",
    "Lợi nhuận gộp",
    "Tỷ suất LN (%)",
    "Tỷ trọng (%)",
  ];

  const rows = items.map((it, idx) => [
    idx + 1,
    it.category,
    it.quantity,
    it.grossRevenue,
    it.itemDiscount,
    it.netRevenue,
    it.costPrice,
    it.grossProfit,
    `${it.grossProfitMarginPercent}%`,
    `${it.proportion || 0}%`,
  ]);

  const totalQty = items.reduce((s, i) => s + i.quantity, 0);
  const totalGross = items.reduce((s, i) => s + i.grossRevenue, 0);
  const totalDisc = items.reduce((s, i) => s + i.itemDiscount, 0);
  const totalNet = items.reduce((s, i) => s + i.netRevenue, 0);
  const totalCogs = items.reduce((s, i) => s + i.costPrice, 0);
  const totalProfit = items.reduce((s, i) => s + i.grossProfit, 0);
  const avgMargin = totalNet > 0 ? Number(((totalProfit / totalNet) * 100).toFixed(2)) : 0;

  const totalRow = [
    "TỔNG CỘNG",
    "—",
    totalQty,
    totalGross,
    totalDisc,
    totalNet,
    totalCogs,
    totalProfit,
    `${avgMargin}%`,
    "100%",
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_NHOMHANG",
    reportTitle: "Báo cáo Doanh thu theo Nhóm hàng",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 4. BÁO CÁO HIỆU SUẤT MÓN ĂN / HÀNG HÓA
export function exportProductSalesReport(items: ProductReportItem[], storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Mã món",
    "Tên món ăn / Đồ uống",
    "Nhóm hàng",
    "ĐVT",
    "Đơn giá niêm yết",
    "Số lượng bán",
    "Doanh thu gộp",
    "Giảm giá món",
    "Doanh thu thực tế",
    "Giá vốn đơn vị",
    "Lợi nhuận gộp",
    "Tỷ suất LN (%)",
  ];

  const rows = items.map((it) => [
    it.productCode || String(it.productId),
    it.productName,
    it.category,
    it.unit,
    it.basePrice,
    it.quantity,
    it.grossRevenue,
    it.itemDiscount,
    it.netRevenue,
    it.quantity > 0 ? Math.round(it.costPrice / it.quantity) : 0,
    it.grossProfit,
    `${it.grossProfitMarginPercent}%`,
  ]);

  const totalQty = items.reduce((s, i) => s + i.quantity, 0);
  const totalGross = items.reduce((s, i) => s + i.grossRevenue, 0);
  const totalDisc = items.reduce((s, i) => s + i.itemDiscount, 0);
  const totalNet = items.reduce((s, i) => s + i.netRevenue, 0);
  const totalProfit = items.reduce((s, i) => s + i.grossProfit, 0);
  const avgMargin = totalNet > 0 ? Number(((totalProfit / totalNet) * 100).toFixed(2)) : 0;

  const totalRow = [
    "TỔNG CỘNG",
    "—",
    "—",
    "—",
    "—",
    totalQty,
    totalGross,
    totalDisc,
    totalNet,
    "—",
    totalProfit,
    `${avgMargin}%`,
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_HANGHOA",
    reportTitle: "Báo cáo Hiệu suất Món ăn / Hàng hóa",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 5. BÁO CÁO NĂNG SUẤT NHÂN VIÊN
export function exportStaffPerformanceReport(data: StaffPerformanceResult, storeInfo?: ReportStoreInfo, dateText?: string) {
  // Order staff rows
  const orderRows = data.orderStaff.map((it) => [
    it.staffFullName,
    `@${it.staffUsername}`,
    it.itemsCount,
    it.grossRevenue,
    it.netRevenue,
  ]);

  const cashierRows = data.cashierStaff.map((it) => [
    it.staffFullName,
    `@${it.staffUsername}`,
    it.billCount,
    it.netRevenue,
  ]);

  // Combined matrix
  const combinedHeaders = [
    "Phân vai",
    "Nhân viên",
    "Tài khoản",
    "Số đơn / Số món",
    "Doanh số ghi nhận (VNĐ)",
  ];
  const combinedRows: (string | number)[][] = [
    ...orderRows.map((r) => ["Nhân viên Order", r[0], r[1], r[2], r[4]]),
    ...cashierRows.map((r) => ["Thu ngân chốt bill", r[0], r[1], r[2], r[3]]),
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_NHANVIEN",
    reportTitle: "Báo cáo Năng suất Bán hàng Nhân viên",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers: combinedHeaders,
    rows: combinedRows,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 6. BÁO CÁO THEO KHUNG GIỜ
export function exportHourlyReport(items: HourlyReportItem[], storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Khung giờ",
    "Số lượng hóa đơn",
    "Doanh thu gộp",
    "Tổng giảm giá",
    "Tiền thuế VAT",
    "Doanh thu thuần",
    "Tỷ lệ đóng góp ngày (%)",
  ];

  const rows = items.map((it) => [
    it.hourLabel,
    it.billCount,
    it.grossRevenue,
    it.totalDiscount,
    it.vatAmount,
    it.netRevenue,
    `${it.proportion || 0}%`,
  ]);

  const totalBills = items.reduce((s, i) => s + i.billCount, 0);
  const totalGross = items.reduce((s, i) => s + i.grossRevenue, 0);
  const totalDisc = items.reduce((s, i) => s + i.totalDiscount, 0);
  const totalVat = items.reduce((s, i) => s + i.vatAmount, 0);
  const totalNet = items.reduce((s, i) => s + i.netRevenue, 0);

  const totalRow = ["TỔNG CỘNG", totalBills, totalGross, totalDisc, totalVat, totalNet, "100%"];

  const opts: ExportReportOptions = {
    reportCode: "BC_KHUNGGIO",
    reportTitle: "Báo cáo Phân bổ theo Khung giờ",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 7. BÁO CÁO HÌNH THỨC THANH TOÁN
export function exportPaymentMethodsReport(data: Record<string, PaymentMethodSummary>, storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Hình thức thanh toán",
    "Số lượng giao dịch",
    "Doanh thu gộp",
    "Tổng giảm giá",
    "Tiền thuế VAT",
    "Số tiền thực thu",
    "Tỷ trọng (%)",
  ];

  const labelMap: Record<string, string> = {
    CASH: "Tiền mặt (CASH)",
    TRANSFER_QR: "Chuyển khoản VietQR (TRANSFER_QR)",
    CARD: "Thẻ ngân hàng / Ví điện tử (CARD)",
  };

  const rows = Object.entries(data).map(([k, it]) => [
    labelMap[k] || k,
    it.billCount,
    it.grossRevenue,
    it.totalDiscount,
    it.vatAmount,
    it.finalAmount,
    `${it.proportion || 0}%`,
  ]);

  const totalBills = Object.values(data).reduce((s, i) => s + i.billCount, 0);
  const totalGross = Object.values(data).reduce((s, i) => s + i.grossRevenue, 0);
  const totalDisc = Object.values(data).reduce((s, i) => s + i.totalDiscount, 0);
  const totalVat = Object.values(data).reduce((s, i) => s + i.vatAmount, 0);
  const totalNet = Object.values(data).reduce((s, i) => s + i.finalAmount, 0);

  const totalRow = ["TỔNG CỘNG", totalBills, totalGross, totalDisc, totalVat, totalNet, "100%"];

  const opts: ExportReportOptions = {
    reportCode: "BC_PTTT",
    reportTitle: "Báo cáo Hình thức Thanh toán",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 8. BÁO CÁO KHUYẾN MÃI & VOUCHER
export function exportPromotionsReport(data: PromotionsReportResult, storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Mã chương trình / Voucher",
    "Tên chương trình",
    "Loại hình áp dụng",
    "Số lượt áp dụng",
    "Tổng chi phí giảm giá (VNĐ)",
  ];

  const rows: (string | number)[][] = [];

  data.campaigns.forEach((c) => {
    rows.push([c.promoCode, c.name, "Voucher / Giảm giá đơn", c.usedCount, c.discountAmount]);
  });

  if (data.pointsRedemption.usedCount > 0) {
    rows.push([
      "DIEM_THUONG",
      `Đổi ${data.pointsRedemption.totalPointsUsed} điểm thưởng`,
      "Tích điểm thành viên",
      data.pointsRedemption.usedCount,
      data.pointsRedemption.discountAmount,
    ]);
  }

  data.itemDiscounts.details.forEach((d) => {
    rows.push([
      `MON_${d.productId || ""}`,
      `Giảm giá: ${d.productName}`,
      "Chiết khấu món",
      d.quantity,
      d.discountAmount,
    ]);
  });

  const totalRow = [
    "TỔNG CỘNG",
    "—",
    "—",
    data.campaigns.reduce((s, c) => s + c.usedCount, 0) + data.pointsRedemption.usedCount + data.itemDiscounts.appliedCount,
    data.totalDiscountAmount,
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_KHUYENMAI",
    reportTitle: "Báo cáo Khuyến mãi & Voucher",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 9. BÁO CÁO HỦY MÓN & HỦY ĐƠN HÀNG
export function exportCancellationReport(data: CancellationReportResult, storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Thời điểm hủy",
    "Mã hóa đơn",
    "Bàn / Khu vực",
    "Chi tiết món hủy",
    "Giá trị thất thoát (VNĐ)",
    "Nhân viên thực hiện",
    "Lý do hủy đơn",
  ];

  const rows = data.bills.map((b) => [
    format(new Date(b.cancelledAt), "dd/MM/yyyy HH:mm"),
    b.billCode,
    b.tableName,
    b.items.join(", "),
    b.subTotal,
    b.staffFullName,
    b.reason,
  ]);

  const totalRow = ["TỔNG THẤT THOÁT", "—", "—", `${data.cancelledBillsCount} đơn hủy`, data.totalLossValue, "—", "—"];

  const opts: ExportReportOptions = {
    reportCode: "BC_HUYMON",
    reportTitle: "Báo cáo Hủy món & Hủy đơn hàng (Kiểm toán Thất thoát)",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 10. BÁO CÁO BÀN GIAO CA & CHÊNH LỆCH KÉT
export function exportCashShiftReport(items: CashShiftAuditItem[], storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Mã ca",
    "Nhân viên",
    "Thời gian mở/đóng",
    "Tiền đầu ca",
    "Doanh số tiền mặt",
    "Thu nộp thêm",
    "Chi vặt",
    "Hoàn tiền mặt",
    "Tiền lý thuyết kỳ vọng",
    "Tiền thực đếm",
    "Chênh lệch két",
  ];

  const rows = items.map((s) => {
    const openTime = format(new Date(s.openedAt), "dd/MM HH:mm");
    const closeTime = s.closedAt ? format(new Date(s.closedAt), "dd/MM HH:mm") : "Chưa đóng";
    return [
      s.shiftCode,
      s.staffFullName,
      `${openTime} - ${closeTime}`,
      s.initialCash,
      s.cashSales,
      s.cashIn,
      s.cashOut,
      s.refundCash,
      s.expectedCash,
      s.actualCash != null ? s.actualCash : s.expectedCash,
      s.difference,
    ];
  });

  const opts: ExportReportOptions = {
    reportCode: "BC_CAKET",
    reportTitle: "Báo cáo Bàn giao Ca & Chênh lệch Két",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// BÁO CÁO KHUYẾN MÃI & GIẢM GIÁ TRONG CA (MODULE 4)
export function exportShiftPromotionsExcel(
  shift: CashShiftAuditItem,
  shiftBills: HistoryOrder[],
  storeInfo?: ReportStoreInfo
) {
  const headers = [
    "STT",
    "Mã hóa đơn",
    "Bàn / Phòng",
    "Thời gian",
    "Thu ngân",
    "Tiền hàng (gộp)",
    "Giảm giá món",
    "Voucher / KM",
    "Điểm dùng",
    "Giảm giá điểm",
    "Tổng giảm giá",
    "Thanh toán",
    "Phương thức",
  ];

  const paidBills = shiftBills.filter((b) => (b.status || "PAID").toUpperCase() === "PAID");

  let totalGross = 0;
  let totalItemDisc = 0;
  let totalVoucher = 0;
  let totalPointsUsed = 0;
  let totalPointsDisc = 0;
  let totalDisc = 0;
  let totalFinal = 0;

  const rows = paidBills.map((b, idx) => {
    const items = extractBillItems(b);
    const itemDisc = items.reduce((s, it) => s + (Number(it.discountAmount || 0) * Number(it.quantity || 1)), 0);
    const voucherDisc = Array.isArray(b.discounts)
      ? b.discounts.reduce((s, d) => s + Number(d.amount || 0), 0)
      : Number(b.billDiscounts || 0);
    const pUsed = Number(b.pointsUsed || 0);
    const pDisc = Number(b.pointsDiscount || 0);
    const gross = Number(b.subTotal != null ? b.subTotal : (b.totalAmount || 0));
    const billTotDisc = Number(b.totalDiscount != null ? b.totalDiscount : (itemDisc + voucherDisc + pDisc));
    const finalA = Number(b.finalAmount != null ? b.finalAmount : (b.totalAmount || 0));

    totalGross += gross;
    totalItemDisc += itemDisc;
    totalVoucher += voucherDisc;
    totalPointsUsed += pUsed;
    totalPointsDisc += pDisc;
    totalDisc += billTotDisc;
    totalFinal += finalA;

    const bTime = Number(b.closedAt || b.createdAt || b.timestamp || Date.now());
    const timeStr = format(new Date(bTime), "dd/MM/yyyy HH:mm");

    return [
      idx + 1,
      b.billCode || b.orderCode || b.id,
      b.tableName || "Mang về",
      timeStr,
      b.staffFullName || shift.staffFullName || "Thu ngân",
      gross,
      itemDisc,
      voucherDisc,
      pUsed,
      pDisc,
      billTotDisc,
      finalA,
      b.paymentMethod || "CASH",
    ];
  });

  const totalRow = [
    "TỔNG CỘNG",
    "—",
    "—",
    "—",
    "—",
    totalGross,
    totalItemDisc,
    totalVoucher,
    totalPointsUsed,
    totalPointsDisc,
    totalDisc,
    totalFinal,
    "—",
  ];

  const opts: ExportReportOptions = {
    reportCode: `KM_CA_${shift.shiftCode}`,
    reportTitle: `Báo cáo Khuyến Mãi & Giảm Giá Ca ${shift.shiftCode}`,
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode || shift.storeCode,
    dateRangeText: `Mã ca: ${shift.shiftCode} - Thu ngân: ${shift.staffFullName}`,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 11. BÁO CÁO LỢI NHUẬN GỘP & GIÁ VỐN
export function exportGrossProfitReport(data: GrossProfitReportResult, storeInfo?: ReportStoreInfo, dateText?: string) {
  const headers = [
    "Tên món ăn / Đồ uống",
    "Nhóm hàng",
    "Số lượng bán",
    "Giá bán bình quân",
    "Giá vốn bình quân",
    "Doanh thu sau giảm giá",
    "Tổng giá vốn (COGS)",
    "Lợi nhuận gộp",
    "Tỷ suất LN gộp (%)",
  ];

  const rows = data.items.map((it) => [
    it.productName,
    it.category || "—",
    it.quantity,
    it.avgSellingPrice,
    it.avgCostPrice,
    it.netRevenue,
    it.cogs,
    it.grossProfit,
    `${it.grossProfitMarginPercent}%`,
  ]);

  const totalRow = [
    "TỔNG CỘNG",
    "—",
    data.summary.totalQuantity,
    "—",
    "—",
    data.summary.netRevenue,
    data.summary.totalCOGS,
    data.summary.grossProfit,
    `${data.summary.grossProfitMarginPercent}%`,
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_LOINHUAN",
    reportTitle: "Báo cáo Lợi nhuận gộp & Giá vốn (Gross Profit & COGS)",
    storeName: storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: storeInfo?.storeCode,
    dateRangeText: dateText,
    headers,
    rows,
    totalRow,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// 12. BÁO CÁO CUỐI NGÀY Z-REPORT
export function exportEndOfDayZReport(data: EndOfDayReportData, storeInfo?: ReportStoreInfo) {
  const headers = ["Chỉ số", "Phân hệ / Diễn giải", "Giá trị ghi nhận (VNĐ / Đơn vị)"];
  const rows: (string | number)[][] = [
    ["1. TỔNG HỢP", "Doanh thu gộp", data.tab1_tongHop.grossRevenue],
    ["1. TỔNG HỢP", "Giảm giá món", data.tab1_tongHop.itemDiscounts],
    ["1. TỔNG HỢP", "Giảm giá đơn / Voucher", data.tab1_tongHop.billDiscounts],
    ["1. TỔNG HỢP", "Tổng giá trị giảm giá", data.tab1_tongHop.totalDiscount],
    ["1. TỔNG HỢP", "Doanh thu sau giảm giá", data.tab1_tongHop.afterDiscount],
    ["1. TỔNG HỢP", "Tiền thuế GTGT (VAT)", data.tab1_tongHop.vatTotal],
    ["1. TỔNG HỢP", "Doanh thu thuần", data.tab1_tongHop.netRevenue],
    ["1. TỔNG HỢP", "Tiền hoàn trả khách", data.tab1_tongHop.refundAmount],
    ["1. TỔNG HỢP", "Doanh thu thực thu sau hoàn", data.tab1_tongHop.netRevenueWithoutRefund],
    ["1. TỔNG HỢP", "Số hóa đơn hoàn tất", data.tab1_tongHop.paidBillsCount],
    ["1. TỔNG HỢP", "Tổng số lượt khách", data.tab1_tongHop.totalGuests],
    ["1. TỔNG HỢP", "Giá trị trung bình / đơn", data.tab1_tongHop.avgRevenuePerBill],

    ["2. THU CHI", "Doanh số Tiền mặt", data.tab2_thuChi.cashSales],
    ["2. THU CHI", "Doanh số Chuyển khoản QR", data.tab2_thuChi.transferSales],
    ["2. THU CHI", "Doanh số Thẻ POS", data.tab2_thuChi.cardSales],
    ["2. THU CHI", "Tổng doanh số bán lẻ", data.tab2_thuChi.totalRevenue],
    ["2. THU CHI", "Tổng tiền nộp thêm vào két (Cash In)", data.tab2_thuChi.cashInTotal],
    ["2. THU CHI", "Tổng chi tiền mặt trong ngày (Cash Out)", data.tab2_thuChi.cashOutTotal],
    ["2. THU CHI", "Tổng hoàn tiền khách (Refund)", data.tab2_thuChi.refundTotal],

    ["3. HÀNG HÓA", "Tổng số sản phẩm bán ra", `${data.tab3_hangHoa.totalItemsSold} ly/món`],
    ...data.tab3_hangHoa.products.map((p) => [
      "3. HÀNG HÓA",
      `${p.productName} (${p.category})`,
      `${p.quantity} ${p.unit} - ${formatVND(p.netRevenue)}`,
    ]),

    ...data.tab4_phongBan.zones.map((z) => [
      "4. PHÒNG BÀN",
      `Khu vực: ${z.zone}`,
      `${z.billCount} hóa đơn - ${formatVND(z.netRevenue)}`,
    ]),
  ];

  const opts: ExportReportOptions = {
    reportCode: "BC_CUOINGAY_Z",
    reportTitle: "Báo cáo Cuối ngày (End-of-Day Z-Report)",
    storeName: data.storeName || storeInfo?.storeName,
    storeAddress: storeInfo?.address,
    storePhone: storeInfo?.phone,
    storeCode: data.storeCode || storeInfo?.storeCode,
    dateRangeText: `Ngày kinh doanh: ${data.date}`,
    headers,
    rows,
  };

  return {
    toExcel: () => exportStandardReportExcel(opts),
    toPDF: () => printStandardReportPDF(opts),
  };
}

// ==================== LEGACY EXPORT FUNCTIONS (BẢO TOÀN TƯƠNG THÍCH) ====================

export function exportRevenue(
  data: Array<{
    date?: string;
    totalOrders?: number;
    totalRevenue?: number;
    cashRevenue?: number;
    transferRevenue?: number;
    avgPerOrder?: number;
    [key: string]: unknown;
  }>,
  title = "Doanh thu"
) {
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

export function exportHistory(data: HistoryOrder[]) {
  const wb = XLSX.utils.book_new();

  // 1. Sheet Tổng hợp Hóa đơn
  const summaryRows = data.map((item) => {
    const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
    const createdTs = typeof item.createdAt === "number" ? item.createdAt : new Date(item.createdAt || ts).getTime();
    const closedTs = typeof item.closedAt === "number" ? item.closedAt : new Date(item.closedAt || ts).getTime();
    const itemCount = Array.isArray(item.items) ? item.items.reduce((s: number, i: OrderItem) => s + (i.quantity || 1), 0) : 0;

    return {
      "Mã HĐ": item.billCode || item.orderCode || item.id?.slice(0, 8) || "",
      "Mã đặt món": item.orderCode || item.billCode || "",
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
  const itemRows: Array<Record<string, unknown>> = [];
  data.forEach((item) => {
    const billCode = item.billCode || item.orderCode || item.id?.slice(0, 8) || "";
    const orderCode = item.orderCode || billCode;
    const tableName = item.tableName || "";
    const cashier = item.cashierName || item.staffFullName || "—";
    const ts = typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp || 0).getTime();
    const billClosedTime = item.timestamp ? format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi }) : "—";

    if (Array.isArray(item.items) && item.items.length > 0) {
      item.items.forEach((it: OrderItem) => {
        const orderTime = it.orderedAt
          ? format(new Date(typeof it.orderedAt === "number" ? it.orderedAt : new Date(it.orderedAt).getTime()), "dd/MM/yyyy HH:mm", { locale: vi })
          : billClosedTime;
        const unitPrice = Number(it.price) || 0;
        const qty = Number(it.quantity) || 1;
        const total = unitPrice * qty;

        itemRows.push({
          "Mã HĐ": billCode,
          "Mã đặt món": orderCode,
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
      { wch: 18 }, { wch: 18 }, { wch: 12 }, { wch: 26 }, { wch: 25 }, { wch: 20 },
      { wch: 10 }, { wch: 16 }, { wch: 16 }, { wch: 22 }, { wch: 20 }, { wch: 20 }, { wch: 20 }
    ];
    XLSX.utils.book_append_sheet(wb, wsItems, "Chi tiết Món & Người nhận");
  }

  // 3. Sheet Lịch sử Thao tác (Action Logs / Timeline)
  const logRows: Array<Record<string, unknown>> = [];
  data.forEach((item) => {
    const billCode = item.billCode || item.orderCode || item.id?.slice(0, 8) || "";
    const orderCode = item.orderCode || billCode;
    const tableName = item.tableName || "";

    if (Array.isArray(item.actionLogs) && item.actionLogs.length > 0) {
      item.actionLogs.forEach((log: Record<string, unknown>) => {
        const logTime = log.timestamp
          ? format(new Date(typeof log.timestamp === "number" ? log.timestamp : new Date(log.timestamp as string).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi })
          : "—";
        logRows.push({
          "Mã HĐ": billCode,
          "Mã đặt món": orderCode,
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
      { wch: 18 }, { wch: 18 }, { wch: 12 }, { wch: 22 }, { wch: 22 }, { wch: 18 }, { wch: 45 }
    ];
    XLSX.utils.book_append_sheet(wb, wsLogs, "Lịch sử Thao tác");
  }

  downloadWorkbook(wb, `LichSu_HoaDon_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportSingleBillExcel(order: HistoryOrder) {
  const wb = XLSX.utils.book_new();
  const billCode = order.billCode || order.orderCode || order.id?.slice(0, 8) || "HD";
  const orderCode = order.orderCode || billCode;
  const ts = typeof order.timestamp === "number" ? order.timestamp : new Date(order.timestamp || 0).getTime();
  const billTime = order.timestamp ? format(new Date(ts), "dd/MM/yyyy HH:mm", { locale: vi }) : "—";

  // 1. Info Sheet
  const infoRows = [
    { "Thuộc tính": "Mã hóa đơn", "Giá trị": billCode },
    { "Thuộc tính": "Mã đặt món", "Giá trị": orderCode },
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
    const itemRows = order.items.map((it: OrderItem, idx: number) => {
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
    const logRows = order.actionLogs.map((l: Record<string, unknown>) => ({
      "Thời gian": l.timestamp ? format(new Date(typeof l.timestamp === "number" ? l.timestamp : new Date(l.timestamp as string).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "—",
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

export function exportUsers(data: Array<Record<string, unknown>>) {
  const rows = data.map((item) => ({
    "Họ tên": item.fullName || "",
    "Tài khoản": item.username || "",
    "Số điện thoại": item.phone || "",
    "Chi nhánh": item.storeName || item.storeCode || "Tất cả",
    "Vai trò": item.role || item.roleId || "",
    "Trạng thái": item.isActive !== false ? "Đang hoạt động" : "Đã khóa",
    "Doanh số (VNĐ)": item.totalSales || 0,
    "Số đơn": item.totalOrders || 0,
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [{ wch: 24 }, { wch: 16 }, { wch: 16 }, { wch: 20 }, { wch: 16 }, { wch: 16 }, { wch: 18 }, { wch: 12 }];
  XLSX.utils.book_append_sheet(wb, ws, "Nhân viên");
  downloadWorkbook(wb, `NhanVien_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportProducts(data: Array<any>) {
  const rows = data.map((item) => ({
    "Tên sản phẩm": item.name || "",
    "Danh mục": item.category || "",
    "Giá bán (VNĐ)": item.price || 0,
    "Giá vốn (VNĐ)": item.costPrice || 0,
    "Đơn vị": item.unit || "",
  }));
  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [{ wch: 28 }, { wch: 16 }, { wch: 14 }, { wch: 14 }, { wch: 12 }];
  XLSX.utils.book_append_sheet(wb, ws, "Sản phẩm");
  downloadWorkbook(wb, `SanPham_${format(new Date(), "yyyy-MM-dd")}.xlsx`);
}

export function exportAuditLogs(data: Array<Record<string, unknown>>) {
  const rows = data.map((item) => ({
    "Hành động": item.actionDisplay || item.action || "",
    "Mã hành động": item.action || "",
    "Bàn / Đối tượng": item.targetId || item.target || "—",
    "Loại đối tượng": item.targetType || "—",
    "Người thực hiện": item.userFullName ? `${item.userFullName} (${item.username})` : (item.username || "—"),
    "Vai trò": item.userRole || "",
    "Thời gian": item.timestamp ? format(new Date(typeof item.timestamp === "number" ? item.timestamp : new Date(item.timestamp as string).getTime()), "dd/MM/yyyy HH:mm:ss", { locale: vi }) : "",
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

export interface CustomerExportItem {
  maKhachHang: string;
  hoTen: string;
  soDienThoai: string;
  diemHienTai: number;
  giaTriQuyDoi: number;
  hangThanhVien: string;
  ngayTao?: string;
  tongChiTieu?: number;
  soDonDaMua?: number;
}

export function exportCustomersList(data: CustomerExportItem[], storeInfo?: ReportStoreInfo) {
  const rows = data.map((item, idx) => ({
    "STT": idx + 1,
    "Mã khách hàng": item.maKhachHang || "",
    "Họ và tên": item.hoTen || "Khách lẻ",
    "Số điện thoại": item.soDienThoai || "",
    "Điểm tích lũy (KMT)": item.diemHienTai || 0,
    "Giá trị quy đổi (VNĐ)": item.giaTriQuyDoi || 0,
    "Hạng thành viên": item.hangThanhVien || "Thành viên",
    "Ngày tham gia": item.ngayTao || "—",
    "Tổng chi tiêu (VNĐ)": item.tongChiTieu || 0,
    "Số lượt mua": item.soDonDaMua || 0,
  }));

  const wb = XLSX.utils.book_new();
  const ws = XLSX.utils.json_to_sheet(rows);
  ws["!cols"] = [
    { wch: 6 },
    { wch: 18 },
    { wch: 25 },
    { wch: 16 },
    { wch: 18 },
    { wch: 20 },
    { wch: 18 },
    { wch: 18 },
    { wch: 20 },
    { wch: 14 },
  ];
  XLSX.utils.book_append_sheet(wb, ws, "Khách hàng CRM");
  downloadWorkbook(wb, `DS_KhachHang_CRM_${format(new Date(), "yyyyMMdd_HHmm")}.xlsx`);
}
