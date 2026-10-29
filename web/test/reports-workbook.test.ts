import { describe, it, expect } from "vitest";
import fs from "fs";
import path from "path";
import * as XLSX from "xlsx";
import { buildReportsWorkbook } from "../lib/export";

const g = JSON.parse(fs.readFileSync(path.resolve(__dirname, "../../docs/report_golden.json"), "utf-8"));

describe("Excel tổng hợp của Trung tâm báo cáo", () => {
  const wb = buildReportsWorkbook({ bills: g.bills, rangeLabel: "Ngày 04/10/2026", range: { from: "2026-10-04", to: "2026-10-04" }, storeInfo: { storeCode: "TRAM01", storeName: "Trạm" } });
  const rows = (name: string) => XLSX.utils.sheet_to_json<unknown[]>(wb.Sheets[name], { header: 1 });

  it("đủ 12 sheet tài chính & vận hành", () => {
    expect(wb.SheetNames).toEqual(["Tổng quan", "Doanh thu theo ngày", "Thanh toán", "Hàng hóa", "Nhóm hàng", "Nhân viên", "NV x Món", "Chi tiết món đã bán", "Hóa đơn", "Khung giờ", "Hủy đơn", "Lợi nhuận gộp"]);
  });
  it("chi tiết món có người order món và người thu tiền; topping là dòng riêng", () => {
    const r = rows("Chi tiết món đã bán");
    const header = r[3] as string[];
    expect(header).toContain("Người order món");
    expect(header).toContain("Người thu tiền");
    const body = r.slice(4) as unknown[][];
    const staffCol = header.indexOf("Người order món");
    expect(body.every((x) => String(x[staffCol] || "").length > 0)).toBe(true);
    const nameCol = header.indexOf("Tên món");
    expect(body.some((x) => x[nameCol] === "Trân châu trắng")).toBe(true);
  });
  it("NV × Món tổng số lượng khớp số món đã bán", () => {
    const sold = (rows("Chi tiết món đã bán").slice(4) as unknown[][]).reduce((s, x) => s + Number(x[7] || 0), 0);
    const byStaff = (rows("NV x Món").slice(4) as unknown[][]).reduce((s, x) => s + Number(x[4] || 0), 0);
    expect(byStaff).toBe(sold);
    expect(sold).toBe(47);
  });
});
