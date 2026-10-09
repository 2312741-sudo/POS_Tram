import { escapeHtml } from "./html";
import { lineDiscountLabel, lineDiscountTotal, lineGross, lineUnitPrice, toppingLabel, type RawOrderLine } from "./order-math";
import { formatVND } from "./reports";

/** Pure HTML builders for browser print windows. Every interpolated value is escaped. */

export interface TableBillItem {
  sizeExtraPrice?: number;
  toppingPrice?: number;
  discountAmount?: number;
  lineDiscountTotal?: number;
  discountedQuantity?: number;
  discountPercent?: number;
  discountUnitAmount?: number;

  name: string;
  price: number;
  quantity?: number;
  count?: number;
  selectedSize?: string;
  selectedToppings?: unknown[];
}

export interface TableBillInput {
  tableName: string;
  zone: string;
  items: TableBillItem[];
  total: number;
  printedAt: string;
}

const formatPlainVND = (amount: number) => new Intl.NumberFormat("vi-VN").format(amount);

/** Thành tiền dòng sau giảm giá món (đơn giá gồm size + topping) */
const lineNet = (it: RawOrderLine) => lineGross(it) - lineDiscountTotal(it);
/** Chuyển dòng in sang RawOrderLine cho các hàm tính tiền dùng chung */
const asLine = (it: TableBillItem | ReceiptItem): RawOrderLine => ({ ...it });

/** Phiếu tạm tính bàn (Sơ đồ bàn). */
export function buildTableBillHtml({ tableName, zone, items, total, printedAt }: TableBillInput): string {
  const e = escapeHtml;
  const itemsHtml = items
    .map(
      (it) => `
      <tr>
        <td style="padding: 4px 0; text-align: left;">
          <strong>${e(it.name)}</strong>
          ${it.selectedSize ? `<br/><small>Size: ${e(it.selectedSize)}</small>` : ""}
          ${
            it.selectedToppings && it.selectedToppings.length > 0
              ? `<br/><small>+ ${e(it.selectedToppings.map(toppingLabel).filter(Boolean).join(", "))}</small>`
              : ""
          }
          ${lineDiscountTotal(asLine(it)) > 0 ? `<br/><small>${e(lineDiscountLabel(asLine(it), formatPlainVND))} (-${e(formatPlainVND(lineDiscountTotal(asLine(it))))}đ)</small>` : ""}
        </td>
        <td style="padding: 4px 0; text-align: center;">${e(it.quantity || it.count || 1)}</td>
        <td style="padding: 4px 0; text-align: right;">${e(formatPlainVND(lineUnitPrice(asLine(it))))}đ</td>
        <td style="padding: 4px 0; text-align: right; font-weight: bold;">
          ${e(formatPlainVND(lineNet(asLine(it))))}đ
        </td>
      </tr>
    `
    )
    .join("");

  return `
      <!DOCTYPE html>
      <html>
      <head>
        <title>Hóa đơn tạm tính - ${e(tableName)}</title>
        <style>
          body { font-family: monospace, sans-serif; width: 300px; margin: 0 auto; padding: 10px; color: #000; }
          .header { text-align: center; border-bottom: 1px dashed #000; padding-bottom: 8px; margin-bottom: 8px; }
          .title { font-size: 18px; font-weight: bold; }
          table { width: 100%; border-collapse: collapse; font-size: 13px; }
          th { border-bottom: 1px solid #000; padding: 4px 0; }
          .total { border-top: 1px dashed #000; margin-top: 10px; padding-top: 8px; }
          .total-row { display: flex; justify-content: space-between; font-size: 15px; font-weight: bold; }
          .footer { text-align: center; margin-top: 15px; font-size: 12px; border-top: 1px dashed #000; padding-top: 8px; }
        </style>
      </head>
      <body>
        <div class="header">
          <div class="title">TRẠM FnB SYSTEM</div>
          <div>PHIẾU TẠM TÍNH BÀN</div>
          <div style="margin-top: 4px;"><strong>${e(zone)} - ${e(tableName)}</strong></div>
          <div style="font-size: 11px;">Thời gian: ${e(printedAt)}</div>
        </div>
        <table>
          <thead>
            <tr>
              <th style="text-align: left;">Món</th>
              <th style="text-align: center;">SL</th>
              <th style="text-align: right;">Đơn giá</th>
              <th style="text-align: right;">T.Tiền</th>
            </tr>
          </thead>
          <tbody>
            ${itemsHtml}
          </tbody>
        </table>
        <div class="total">
          <div class="total-row">
            <span>TỔNG CỘNG:</span>
            <span>${e(formatPlainVND(total))} VNĐ</span>
          </div>
        </div>
        <div class="footer">
          <div>Cảm ơn Quý khách! Hẹn gặp lại.</div>
          <div style="font-size: 10px; margin-top: 4px;">Hệ thống Quản lý Vận hành POS Trạm</div>
        </div>
        <script>
          window.onload = function() { window.print(); }
        </script>
      </body>
      </html>
    `;
}

export interface ReceiptItem {
  sizeExtraPrice?: number;
  toppingPrice?: number;
  discountAmount?: number;
  lineDiscountTotal?: number;
  discountedQuantity?: number;
  discountPercent?: number;
  discountUnitAmount?: number;

  name: string;
  price: number;
  quantity?: number;
  selectedSize?: string;
  orderedByName?: string;
}

export interface ReceiptOrder {
  id: string;
  billCode?: string;
  orderCode?: string;
  tableName?: string;
  orderStaff?: string;
  cashierName?: string;
  paymentMethod?: string;
  totalAmount?: number;
  items?: ReceiptItem[];
}

/** Hóa đơn thanh toán (Lịch sử giao dịch). `timeStr` is the pre-formatted bill time. */
export function buildOrderReceiptHtml(order: ReceiptOrder, timeStr: string): string {
  const e = escapeHtml;
  const itemsHtml = (order.items || []).map((it, idx) => `
      <tr>
        <td style="padding: 6px 4px; border-bottom: 1px dashed #ccc;">${idx + 1}. ${e(it.name)} ${it.selectedSize ? `(Size ${e(it.selectedSize)})` : ""}</td>
        <td style="padding: 6px 4px; text-align: center; border-bottom: 1px dashed #ccc;">${e(it.quantity || 1)}</td>
        <td style="padding: 6px 4px; text-align: right; border-bottom: 1px dashed #ccc;">${e(formatVND(lineUnitPrice(asLine(it))))}</td>
        <td style="padding: 6px 4px; text-align: right; border-bottom: 1px dashed #ccc; font-weight: bold;">${e(formatVND(lineNet(asLine(it))))}</td>
      </tr>
      ${lineDiscountTotal(asLine(it)) > 0 ? `<tr><td colspan="4" style="font-size: 11px; color: #666; padding-left: 16px;">${e(lineDiscountLabel(asLine(it), formatVND))} (-${e(formatVND(lineDiscountTotal(asLine(it))))})</td></tr>` : ""}
      ${it.orderedByName ? `<tr><td colspan="4" style="font-size: 11px; color: #666; padding-left: 16px;">Phục vụ: ${e(it.orderedByName)}</td></tr>` : ""}
    `).join("");

  return `
      <!DOCTYPE html>
      <html>
        <head>
          <title>Hóa đơn ${e(order.billCode || order.orderCode || order.id)}</title>
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
            <div class="meta">Số HĐ: <strong>${e(order.billCode || order.orderCode || order.id?.slice(0, 8))}</strong>${order.orderCode && order.billCode && order.orderCode !== order.billCode ? ` | Mã đơn: <strong>${e(order.orderCode)}</strong>` : ''} | Bàn: <strong>${e(order.tableName || "—")}</strong></div>
            <div class="meta">Giờ: ${e(timeStr)}</div>
            <div class="meta">Người nhận order: <strong>${e(order.orderStaff || "—")}</strong></div>
            <div class="meta">Thu ngân: <strong>${e(order.cashierName || "—")}</strong></div>
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
            <span style="color: #7E2930;">${e(formatVND(order.totalAmount || 0))}</span>
          </div>
          <div style="font-size: 12px; margin-top: 4px; text-align: right; color: #555;">
            Phương thức: ${e(order.paymentMethod || "Tiền mặt")}
          </div>
          <div class="footer">
            <p>Cảm ơn quý khách và hẹn gặp lại! ✨</p>
          </div>
          <script>
            window.onload = function() { window.print(); }
          </script>
        </body>
      </html>
    `;
}
