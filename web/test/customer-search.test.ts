import { describe, it, expect } from "vitest";
import { searchCustomers, maskPhone, foldVi } from "../lib/customer-search";

const a = { id: "a", name: "Nguyễn Văn A", phone: "0901234567", points: 50, lastVisitAt: 100 };
const b = { id: "b", name: "Trần Thị Bình", phone: "0912 345 678", points: 300, lastVisitAt: 500 };
const c = { id: "c", name: "Lê Đức Anh", phone: "0987654321", points: 900 };
const all = [a, b, c];
const ids = (q: string) => searchCustomers(all, q).map((m) => m.customer.id);

describe("customer-search (khớp bản Dart)", () => {
  it("rỗng: gần đây trước rồi nhiều điểm", () => {
    expect(ids("")).toEqual(["b", "a", "c"]);
    expect(searchCustomers(all, "", 2)).toHaveLength(2);
  });
  it("SĐT: đủ số, 4 số cuối, một phần; dưới 3 số không khớp", () => {
    expect(ids("0901234567")[0]).toBe("a");
    expect(ids("4321")).toEqual(["c"]);
    expect(ids("345")).toContain("b");
    expect(ids("09")).toEqual([]);
    expect(ids("567")[0]).toBe("a");
  });
  it("tên không dấu, thứ tự từ bất kỳ", () => {
    expect(ids("nguyen van a")).toEqual(["a"]);
    expect(ids("binh tran")).toEqual(["b"]);
    expect(ids("duc")).toEqual(["c"]);
    expect(ids("zzz")).toEqual([]);
  });
  it("tô sáng và che SĐT", () => {
    expect(searchCustomers(all, "van")[0].nameRanges).toEqual([{ start: 7, end: 10 }]);
    expect(searchCustomers(all, "5678")[0].phoneRange).toEqual({ start: 7, end: 12 });
    expect(maskPhone("0901234567")).toBe("090****567");
    expect(foldVi("Đức")).toBe("duc");
  });
});
