# ĐẶC TẢ BÁO CÁO TÀI CHÍNH & VẬN HÀNH CHUẨN XÁC (REPORT SPEC)
## HỆ THỐNG POS TRẠM F&B (ENTERPRISE FINANCIAL & ANALYTICS SPECIFICATION)
**Mã tài liệu:** `DOCS-REPORT-SPEC-2026-01`  
**Phiên bản:** `2.0.0`  
**Áp dụng cho:** `app_flutter` (POS Cashier/Manager/Reports), `web` (Next.js Admin Dashboard), Engine xuất Excel/PDF.  
**Bộ dữ liệu đối soát chuẩn:** `docs/report_golden.json` (20 đơn mẫu đã xác minh 100%).  
**Trạng thái:** Dự thảo chuyển giao kỹ thuật (Chờ phê duyệt).

---

## 1. MỤC TIÊU & PHẠM VI ĐẶC TẢ

Hệ thống POS Trạm phục vụ quản lý chuỗi F&B với yêu cầu khắt khe về độ chính xác số liệu tài chính. Trước đây, giữa ứng dụng Flutter POS và Web Admin tồn tại sự lệch pha trong cách tính doanh thu (ví dụ: Web tự ước lượng ngược thuế $8\%$ qua công thức `Math.round(netRevenue * 0.08 / 1.08)` thay vì lấy giá trị chốt trên bill; Web tính doanh thu gộp lấy nhầm `finalAmount`; cách làm tròn thập phân chưa thống nhất).

Đặc tả này thiết lập:
1. **Chuẩn hóa công thức tài chính duy nhất**: Đảm bảo $100\%$ báo cáo trên Flutter App và Web Admin cho ra kết quả khớp nhau đến từng đơn vị đồng (VND).
2. **Quy chuẩn ranh giới thời gian**: Định nghĩa chính xác múi giờ UTC+7, ranh giới ngày và ranh giới ca xuyên đêm.
3. **Đặc tả chi tiết 12 mẫu báo cáo nghiệp vụ**: Đầy đủ bộ lọc, cột hiển thị, công thức, quy tắc làm tròn và chữ ký hàm thuần (Pure Functions) đồng nhất cho cả Dart và TypeScript.
4. **Tích hợp quản lý giá vốn (`costPrice`)**: Đưa trường giá vốn từ `ProductModel` vào tính toán chính xác Lợi nhuận gộp (Gross Profit) và Tỷ suất lợi nhuận (Margin).
5. **Bộ dữ liệu chuẩn hóa (`docs/report_golden.json`)**: Bộ 20 hóa đơn mẫu thực tế đi kèm kết quả mong đợi đã được tính toán đối soát tự động.

---

## 2. HỆ THỐNG ĐỊNH NGHĨA & CÔNG THỨC TÀI CHÍNH CỐT LÕI

### 2.1. Doanh thu gộp (Gross Revenue / Subtotal)
- **Định nghĩa:** Tổng giá trị của toàn bộ món ăn, đồ uống và dịch vụ theo đơn giá niêm yết (đã cộng phụ thu size và topping) trước khi áp dụng bất kỳ hình thức giảm giá hay thuế suất nào.
- **Công thức tính cho 1 dòng món (Line Item Gross):**
  $$\text{LineGrossAmount} = (\text{BasePrice} + \text{SizeExtraPrice} + \text{ToppingPrice}) \times \text{Quantity}$$
- **Công thức tính cho 1 hóa đơn:**
  $$\text{SubTotal} = \sum_{i=1}^{n} \text{LineGrossAmount}_i$$
- **Doanh thu gộp của kỳ báo cáo:**
  $$\text{GrossRevenue} = \sum_{b \in \text{PAID}} b.\text{subTotal}$$
  *(Lưu ý: Chỉ tính các hóa đơn có trạng thái `PAID`).*

### 2.2. Giảm giá & Chiết khấu (Discounts)
Hệ thống phân tách chiết khấu thành 4 tầng rõ rệt:
1. **Giảm giá theo món (Item Discount):** Giảm giá trực tiếp trên từng dòng món, áp dụng cho **số phần được chọn** trong dòng (VD: dòng 5 ly A, chỉ giảm 2 ly).
   - Mỗi dòng có `discountedQuantity` ($0 \le dq \le quantity$) và cấu hình giảm **mỗi phần**: `discountPercent` (% trên đơn giá đã gồm size + topping) **hoặc** `discountUnitAmount` (đ/phần).
   - Tổng giảm của dòng (lưu tường minh trên dòng ở cả `lineDiscountTotal` và `discountAmount`):
     $$\text{LineDiscount} = \min\Big(\text{unitPrice} \times \text{quantity},\ \begin{cases} \text{round}\big(\text{unitPrice} \times \text{percent} \times dq / 100\big) & \text{(PERCENT)} \\ \min(\text{discountUnitAmount}, \text{unitPrice}) \times dq & \text{(AMOUNT)} \end{cases}\Big)$$
   - Báo cáo **không tính lại** mà đọc giá trị đã lưu:
     $$\text{ItemDiscounts} = \sum_{i=1}^{n} \min\big(\text{item.lineDiscountTotal} \ ?? \ \text{item.discountAmount},\ \text{unitPrice} \times \text{quantity}\big)$$
   - **Dữ liệu cũ** (dòng không có `discountedQuantity`/`lineDiscountTotal`): `discountAmount` luôn là giảm giá **CẢ DÒNG** (app Flutter và web cũ đều tính tiền như vậy), **không nhân với quantity**; coi $dq = quantity$. Nhờ đó tổng tiền đã thu của hóa đơn cũ không thay đổi khi đọc lại.
   - Nếu hóa đơn có `itemDiscounts` ở cấp hóa đơn (web tạo), báo cáo tổng quan dùng giá trị đó.
2. **Giảm giá hóa đơn (Bill Discount / Promo Discount):** Áp dụng mã Voucher, Coupon hoặc chiến dịch giảm % theo tổng đơn (`b.discounts`).
   $$\text{BillDiscounts} = \sum_{d \in b.\text{discounts}} d.\text{amount}$$
3. **Giảm giá tích điểm (Points Discount):** Khách hàng thân thiết quy đổi điểm thưởng trừ tiền trực tiếp trên hóa đơn (`b.pointsDiscount`).
4. **Chiết khấu thủ công (Manual Discount):** Thu ngân/Quản lý bớt tiền hoặc chiết khấu đặc biệt theo quyền hạn (`OVERRIDE_MANUAL_DISCOUNT`).

- **Tổng giảm giá của 1 hóa đơn:**
  $$\text{TotalDiscount} = \min\Big(\text{SubTotal}, \text{ItemDiscounts} + \text{BillDiscounts} + \text{PointsDiscount} + \text{ManualDiscount}\Big)$$
  *(Quy tắc chặn: Tổng giảm giá không được vượt quá Doanh thu gộp của hóa đơn).*

### 2.3. Số tiền sau giảm giá (After Discount / Pre-VAT Amount)
- **Công thức:**
  $$\text{AfterDiscount} = \text{SubTotal} - \text{TotalDiscount}$$

### 2.4. Thuế Giá trị gia tăng (VAT)
- **Cấu hình:** Thuế suất VAT (`vatRate`) cấu hình linh hoạt theo cửa hàng tại `/stores/{storeCode}/storeInfo/defaultVatRate` (thường là $8.0\%$ hoặc $10.0\%$, một số đơn mang về hoặc ăn vặt là $0.0\%$).
- **Công thức tính tiền thuế VAT:** Thuế VAT được tính trên số tiền **sau khi đã trừ toàn bộ các khoản giảm giá**:
  $$\text{VatAmount} = \text{round}\left(\text{AfterDiscount} \times \frac{\text{vatRate}}{100}\right)$$
- **Quy tắc làm tròn:** Làm tròn số học chuẩn về số nguyên gần nhất (`round()`), vì đơn vị tiền tệ VND không có số thập phân.
- **NGUYÊN TẮC BÃI BỎ:** Tuyệt đối không tính toán ngược `Math.round(netRevenue * 0.08 / 1.08)` trên giao diện báo cáo. Báo cáo bắt buộc phải đọc trực tiếp trường `b.vatAmount` đã được chốt và lưu cố định tại thời điểm lập hóa đơn.

### 2.5. Doanh thu thuần (Net Revenue / Final Amount)
- **Doanh thu thuần của 1 hóa đơn:**
  $$\text{FinalAmount} = \text{AfterDiscount} + \text{VatAmount}$$
- **Doanh thu thuần tổng thể kỳ báo cáo:**
  $$\text{NetRevenue} = \sum_{b \in \text{PAID}} b.\text{finalAmount}$$
- **Doanh thu thuần sau điều chỉnh (Net Revenue with Adjustments):**
  $$\text{NetRevenueAdjusted} = \text{NetRevenue} + \text{OtherIncome} - \text{RefundAmount}$$
  *(Trong đó $\text{OtherIncome}$ là thu khác ngoài bill, $\text{RefundAmount}$ là tổng số tiền hoàn trả khách của các đơn `REFUNDED`).*

### 2.6. Giá vốn hàng bán (COGS) & Lợi nhuận gộp (Gross Profit)
- **Giá vốn của một đơn vị món:**
  $$\text{UnitCost} = \text{Product.costPrice} + \sum \text{Topping.costPrice}$$
  *(Trường `costPrice` được lấy từ `ProductModel` tại `lib/data/models/product_model.dart` hoặc từ `InventoryCatalogItem` tại `inventory_models.dart`).*
- **Tổng giá vốn của hóa đơn:**
  $$\text{BillCOGS} = \sum_{i=1}^{n} (\text{UnitCost}_i \times \text{item.quantity}_i)$$
- **Lợi nhuận gộp (Gross Profit):**
  $$\text{GrossProfit} = \text{AfterDiscount} - \text{BillCOGS}$$
  *(Lợi nhuận gộp được đo lường trước thuế VAT để phản ánh đúng hiệu quả kinh doanh cốt lõi).*
- **Tỷ suất lợi nhuận gộp (Gross Profit Margin):**
  $$\text{GrossProfitMargin (\%)} = \frac{\text{GrossProfit}}{\text{AfterDiscount}} \times 100\%$$

### 2.7. Xử lý các trạng thái đơn đặc biệt
1. **Đơn hủy (`status == 'CANCELLED'`):**
   - **Tuyệt đối KHÔNG cộng** vào Doanh thu gộp, Doanh thu thuần hay Tổng số lượng ly bán ra.
   - Được gom riêng vào **Báo cáo Hủy món & Hủy đơn hàng** để quản lý thất thoát và kiểm toán gian lận.
   - Giá trị thất thoát đơn hủy ghi nhận theo `b.subTotal`.
   - **Lịch sử hóa đơn / xuất Excel** vẫn liệt kê đơn hủy với cột *Trạng thái* (`PAID` → "Hoàn thành", `CANCELLED` → "Đã hủy") và bộ lọc trạng thái; mọi tổng tiền trên màn hình chỉ cộng đơn `PAID`.
   - **Giảm giá đơn** (cột "Giảm giá đơn" của Tổng hợp đơn hàng) $= \max(0, \text{totalDiscount} - \text{ItemDiscounts})$, trong đó $\text{ItemDiscounts}$ = `b.itemDiscounts` nếu có, ngược lại $\sum$ `lineDiscountTotal` của các dòng. Cột "Giảm giá món" của Chi tiết món = `lineDiscountTotal` của dòng.
2. **Đơn hoàn tiền (`status == 'REFUNDED'`):**
   - Tiền hoàn trả khách ghi nhận tại trường `b.refundAmount`.
   - Được thể hiện là một dòng giảm trừ doanh thu hoặc chi hoàn trả trong Báo cáo Thu chi và Báo cáo Cuối ngày.
3. **Đơn ghép bàn (`mergedTableNames != null`):**
   - Khi nhiều bàn ghép chung (ví dụ Bàn 01 ghép Bàn 02), chỉ phát sinh **01 hóa đơn chính duy nhất** được thanh toán. Doanh thu chỉ được ghi nhận một lần tại hóa đơn chính.
   - Các bàn phụ chuyển trạng thái trống hoặc trỏ `mergedIntoTable`.
4. **Đơn tách bàn / Tách đơn (`parentBillId != null`):**
   - Mỗi hóa đơn tách ra có một mã `id` độc lập và được tính doanh thu độc lập khi thanh toán thành công (`PAID`).

---

## 3. QUY CHUẨN THỜI GIAN & RANH GIỚI KẾ TOÁN

### 3.1. Múi giờ chuẩn hệ thống
- Múi giờ áp dụng duy nhất cho toàn hệ thống: **UTC+7 (Asia/Ho_Chi_Minh)**.
- Mọi timestamp lưu trữ trên Realtime Database là số nguyên mili-giây (Unix Epoch Milliseconds).
- Khi hiển thị hoặc nhóm theo ngày, tuần, tháng, hệ thống bắt buộc chuyển đổi về múi giờ UTC+7 trước khi trích xuất `year`, `month`, `day`, `hour`.

### 3.2. Ranh giới ngày (Calendar Day Boundary)
- Một ngày kinh doanh theo lịch bắt đầu chính xác từ `00:00:00.000` và kết thúc tại `23:59:59.999` (UTC+7).

### 3.3. Ranh giới ca làm việc (Shift Boundary)
- Quán F&B thường có các ca làm việc kéo dài xuyên đêm (ví dụ: Ca tối mở từ 18:00 ngày hôm trước đến 02:00 sáng hôm sau).
- Khi xem báo cáo theo ca két (`CashShiftModel`), **không được cắt đứt dữ liệu lúc 00:00**. Ranh giới tính toán của ca được neo cố định theo:
  $$\text{openedAt} \le b.\text{closedAt} \le \text{closedAt}$$
  hoặc neo theo trường `b.shiftId == shift.id`.

### 3.4. Quy tắc lựa chọn trường thời gian xếp ngày (Date Sorting Field Priority)
Khi lọc dữ liệu hóa đơn vào các khoảng ngày/kỳ báo cáo, thứ tự ưu tiên áp dụng bắt buộc:
1. **Ưu tiên 1 (Số 1): `closedAt`**  
   Áp dụng cho mọi hóa đơn đã thanh toán (`status == 'PAID'`) hoặc hoàn tiền (`status == 'REFUNDED'`). Doanh thu tài chính ghi nhận tại thời điểm giao dịch hoàn tất và thu tiền.
2. **Ưu tiên 2: `createdAt`**  
   Áp dụng cho các đơn đang mở / đang phục vụ (`status == 'OPEN'`) hoặc đơn hủy (`CANCELLED`) chưa kịp đóng.
3. **Ưu tiên 3: `timestamp`**  
   Chỉ dùng làm giá trị dự phòng (Fallback) khi dữ liệu lịch sử kế thừa cũ (`legacy`) không có trường `closedAt` hay `createdAt`.

---

## 4. ÁNH XẠ TRƯỜNG DỮ LIỆU & KHỬ TRÙNG LẶP ID (DATA PARITY)

### 4.1. Bảng ánh xạ trường giữa Flutter App và Web Admin

| Ý nghĩa nghiệp vụ | Flutter Model (`bill_model.dart`) | Web Interface (`HistoryOrder`) | Kiểu dữ liệu | Chuẩn hóa quy ước |
| :--- | :--- | :--- | :--- | :--- |
| Khóa chính hóa đơn | `id` | `id` | `string` | Bắt buộc duy nhất |
| Mã hóa đơn chính | `billCode` | `billCode` / `orderCode` | `string` | Format: `HD-yyMMdd-HHmmss` |
| Tên bàn | `tableName` | `tableName` | `string` | Ví dụ: "Bàn 01", "Mang về" |
| Khu vực | `zone` | `zone` | `string` | Ví dụ: "Tầng 1", "Tầng 2" |
| Thời điểm tạo | `createdAt` | `createdAt` / `timestamp` | `number` (ms) | Unix Timestamp UTC ms |
| Thời điểm đóng đơn | `closedAt` | `closedAt` | `number?` (ms) | Dùng làm mốc phân loại ngày |
| Trạng thái đơn | `status` | `status` | `string` | `PAID`, `CANCELLED`, `OPEN`, `REFUNDED` |
| Nhân viên thu ngân | `staffFullName` / `staffUsername` | `cashierName` / `staffFullName` | `string` | Người bấm thanh toán bill |
| Nhân viên nhận order | `orderStaffSummary` | `orderStaff` | `string` | Ghép từ các `orderedByName` của món |
| Danh sách món | `items: List<OrderItemModel>` | `items: OrderItem[]` | `array` | Danh sách chi tiết dòng món |
| Doanh thu gộp | `subTotal` | `subTotal` / `totalAmount` | `number` (int) | Tổng trước giảm giá & VAT |
| Tổng tiền giảm giá | `totalDiscount` | `discountAmount` | `number` (int) | Gồm giảm món + bill + điểm |
| Thuế suất VAT (%) | `vatRate` | `vatRate` | `number` (float) | Mặc định 8.0, 10.0 hoặc 0.0 |
| Tiền thuế VAT | `vatAmount` | `vatAmount` | `number` (int) | Tính trên số tiền sau giảm giá |
| Doanh thu thuần | `finalAmount` | `totalAmount` | `number` (int) | Số tiền thực tế khách trả |
| Hình thức thanh toán | `paymentMethod` | `paymentMethod` | `string` | `CASH`, `TRANSFER_QR`, `CARD` |
| Mã ca làm việc | `shiftId` | `shiftId` | `string?` | Khóa ngoại liên kết ca két |

### 4.2. Thuật toán khử trùng lặp ID (Deduplication Algorithm)
Do cơ chế đồng bộ kép (ghi song song cả `/stores/{storeCode}/bills` và `/history`), khi Web Admin hoặc Flutter đọc từ nhiều nguồn có thể nhận được các bản ghi trùng lặp ID.

#### Thuật toán khử trùng lặp chuẩn:
```typescript
// Web TypeScript Implementation
export function deduplicateBills(rawList: HistoryOrder[]): HistoryOrder[] {
  const map = new Map<string, HistoryOrder>();
  for (const bill of rawList) {
    if (!bill.id) continue;
    // Nếu chưa có, hoặc bản ghi mới hơn có trạng thái đóng đơn rõ ràng hơn thì ghi đè
    if (!map.has(bill.id)) {
      map.set(bill.id, bill);
    } else {
      const existing = map.get(bill.id)!;
      const existingTime = existing.closedAt || existing.createdAt || 0;
      const newTime = bill.closedAt || bill.createdAt || 0;
      if (newTime >= existingTime) {
        map.set(bill.id, bill);
      }
    }
  }
  return Array.from(map.values());
}
```

```dart
// Flutter Dart Implementation
List<BillModel> deduplicateBills(List<BillModel> rawList) {
  final Map<String, BillModel> map = {};
  for (final b in rawList) {
    if (b.id.isEmpty) continue;
    if (!map.containsKey(b.id)) {
      map[b.id] = b;
    } else {
      final existing = map[b.id]!;
      final exTime = existing.closedAt ?? existing.createdAt;
      final newTime = b.closedAt ?? b.createdAt;
      if (newTime >= exTime) {
        map[b.id] = b;
      }
    }
  }
  return map.values.toList();
}
```

---

## 5. CHI TIẾT 12 BÁO CÁO CHUẨN MỰC

Mỗi báo cáo dưới đây được đặc tả tường minh gồm: Mục đích, Bộ lọc, Cột hiển thị, Công thức tính toán và Chữ ký hàm thuần (Pure Contract Signature) cho cả Dart và TypeScript.

---

### BÁO CÁO 1: BÁO CÁO TỔNG QUAN QUẢN TRỊ (EXECUTIVE OVERVIEW)
- **Mục đích:** Cung cấp bức tranh toàn cảnh về doanh số, lượng khách, dòng tiền và lợi nhuận gộp của cửa hàng trong kỳ chọn.
- **Bộ lọc:** Cửa hàng (`storeCode`), Khoảng thời gian (`dateRange`: Hôm nay, Hôm qua, 7 ngày, Tháng này, Tùy chọn).
- **Các chỉ số chính hiển thị (KPI Cards):**
  1. *Doanh thu thuần*: $\text{NetRevenue} = \sum \text{finalAmount}$ (VND).
  2. *Doanh thu gộp*: $\text{GrossRevenue} = \sum \text{subTotal}$ (VND).
  3. *Tổng giảm giá*: $\text{TotalDiscount} = \sum \text{totalDiscount}$ (VND).
  4. *Tiền thuế VAT*: $\text{VatTotal} = \sum \text{vatAmount}$ (VND).
  5. *Giá vốn hàng bán (COGS)*: $\text{TotalCOGS} = \sum \text{cogs}$ (VND).
  6. *Lợi nhuận gộp*: $\text{GrossProfit} = \text{AfterDiscount} - \text{TotalCOGS}$ (VND).
  7. *Tỷ suất lợi nhuận*: $\text{Margin (\%)} = \frac{\text{GrossProfit}}{\text{AfterDiscount}} \times 100\%$.
  8. *Tổng số đơn hoàn tất*: Số đơn `PAID`.
  9. *Giá trị trung bình / đơn*: $\text{AvgPerBill} = \text{round}(\text{NetRevenue} / \text{PaidBillsCount})$.
  10. *Tổng lượt khách*: $\sum \text{guestCount}$.
  11. *Số đơn hủy & Thất thoát*: Số lượng đơn `CANCELLED` & Tổng tiền hủy.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `OverviewReportResult calculateOverviewReport(List<BillModel> bills, {int refundAmount = 0})`
  - **TypeScript:** `calculateOverviewReport(bills: HistoryOrder[], refundAmount?: number): OverviewReportResult`

---

### BÁO CÁO 2: BÁO CÁO DOANH THU THEO KỲ (REVENUE BY PERIOD)
- **Mục đích:** Phân tích xu hướng tăng trưởng doanh thu theo Ngày, Tuần, Tháng, Năm để hỗ trợ ra quyết định kinh doanh.
- **Bộ lọc:** Cửa hàng, Kỳ phân tích (`DAY`, `WEEK`, `MONTH`, `YEAR`).
- **Các cột hiển thị:**
  1. *Thời gian*: Ngày (dd/MM/yyyy) hoặc Tháng (MM/yyyy) hoặc Tuần.
  2. *Số lượng đơn*: Số đơn `PAID`.
  3. *Doanh thu gộp (VND)*: Căn phải, định dạng tiền tệ.
  4. *Giảm giá (VND)*: Căn phải.
  5. *Doanh thu thuần (VND)*: Căn phải, in đậm.
  6. *Tiền mặt (VND)*: Căn phải.
  7. *Chuyển khoản QR (VND)*: Căn phải.
  8. *Thẻ / Ví (VND)*: Căn phải.
  9. *Tỷ trọng đóng góp (%)*: Căn phải, 1 chữ số thập phân.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `List<PeriodRevenueItem> calculateRevenueByPeriod(List<BillModel> bills, PeriodType period)`
  - **TypeScript:** `calculateRevenueByPeriod(bills: HistoryOrder[], period: "DAY" | "WEEK" | "MONTH" | "YEAR"): PeriodRevenueItem[]`

---

### BÁO CÁO 3: BÁO CÁO THEO NHÓM HÀNG / DANH MỤC (CATEGORY SALES)
- **Mục đích:** Đánh giá danh mục nào đóng góp doanh thu lớn nhất (Trà trái cây, Cà phê, Sinh tố, Đồ ăn vặt...).
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Danh mục cụ thể (hoặc Tất cả).
- **Các cột hiển thị:**
  1. *STT*: Căn giữa.
  2. *Tên nhóm hàng*: Căn trái, in đậm.
  3. *Số lượng bán (Ly/Phần)*: Căn phải, định dạng số nguyên.
  4. *Doanh thu gộp (VND)*: Căn phải.
  5. *Giảm giá món (VND)*: Căn phải.
  6. *Doanh thu thực tế (VND)*: Căn phải, in đậm.
  7. *Giá vốn (COGS) (VND)*: Căn phải.
  8. *Lợi nhuận gộp (VND)*: Căn phải, màu xanh lá nếu dương.
  9. *Tỷ suất LN (%):* Căn phải, 2 chữ số thập phân.
  10. *Tỷ trọng doanh số (%)*: Căn phải.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `List<CategoryReportItem> calculateCategoryReport(List<BillModel> bills, Map<int, ProductModel> productsMap)`
  - **TypeScript:** `calculateCategoryReport(bills: HistoryOrder[], productsMap: Record<number, ProductItem>): CategoryReportItem[]`

---

### BÁO CÁO 4: BÁO CÁO MÓN ĂN / HÀNG HÓA (PRODUCT SALES PERFORMANCE)
- **Mục đích:** Xếp hạng các món bán chạy nhất (Best-sellers) và các món ế ẩm cần tinh chỉnh thực đơn.
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Nhóm hàng, Tìm kiếm theo tên món, Sắp xếp (`REV_DESC`, `QTY_DESC`, `NAME_ASC`).
- **Các cột hiển thị:**
  1. *Mã món*: Căn trái (SKU).
  2. *Tên món*: Căn trái, in đậm.
  3. *Nhóm hàng*: Căn trái.
  4. *Đơn vị tính*: Căn giữa (Ly, Đĩa, Gói).
  5. *Đơn giá niêm yết (VND)*: Căn phải.
  6. *Số lượng bán*: Căn phải, in đậm.
  7. *Doanh thu gộp (VND)*: Căn phải.
  8. *Giảm giá món (VND)*: Căn phải.
  9. *Doanh thu thực tế (VND)*: Căn phải, in đậm.
  10. *Giá vốn đơn vị (VND)*: Căn phải.
  11. *Lợi nhuận gộp (VND)*: Căn phải.
  12. *Tỷ suất LN (%)*: Căn phải.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `List<ProductReportItem> calculateProductReport(List<BillModel> bills, Map<int, ProductModel> productsMap)`
  - **TypeScript:** `calculateProductReport(bills: HistoryOrder[], productsMap: Record<number, ProductItem>): ProductReportItem[]`

---

### BÁO CÁO 5: BÁO CÁO THEO NHÂN VIÊN (STAFF SALES PERFORMANCE)
- **Mục đích:** Đo lường năng suất bán hàng của từng nhân viên theo 2 phân vai: Nhân viên Order (Phục vụ gọi món) và Nhân viên Thu ngân (Thu tiền chốt hóa đơn).
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Chế độ xem (`ORDER_STAFF` hoặc `CASHIER_STAFF`), Nhân viên cụ thể.
- **Các cột hiển thị:**
  - *Chế độ Order Staff (Nhân viên nhận order):*
    1. *Tên nhân viên*: Căn trái, in đậm.
    2. *Tên đăng nhập*: Căn trái (@username).
    3. *Tổng số món nhận order*: Căn phải, in đậm.
    4. *Tổng giá trị order (VND)*: Căn phải.
    5. *Doanh thu thực tế (VND)*: Căn phải, in đậm.
    6. *Năng suất trung bình / đơn*: Căn phải.
  - *Chế độ Cashier Staff (Thu ngân):*
    1. *Thu ngân*: Căn trái, in đậm.
    2. *Số hóa đơn đã thanh toán*: Căn phải.
    3. *Doanh thu tiền mặt thu được (VND)*: Căn phải.
    4. *Doanh thu chuyển khoản thu được (VND)*: Căn phải.
    5. *Tổng doanh thu thu ngân chốt (VND)*: Căn phải, in đậm.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `StaffPerformanceResult calculateStaffPerformance(List<BillModel> bills)`
  - **TypeScript:** `calculateStaffPerformance(bills: HistoryOrder[]): StaffPerformanceResult`

---

### BÁO CÁO 6: BÁO CÁO THEO KHUNG GIỜ (HOURLY HEATMAP)
- **Mục đích:** Nhận diện khung giờ cao điểm (Peak Hours) và giờ thấp điểm từ $00:00$ đến $23:00$ để bố trí ca nhân sự và chuẩn bị nguyên vật liệu.
- **Bộ lọc:** Cửa hàng, Khoảng ngày.
- **Các cột hiển thị (24 dòng tương ứng 24 giờ):**
  1. *Khung giờ*: Căn giữa (08:00 - 08:59, 09:00 - 09:59...).
  2. *Số lượng hóa đơn*: Căn phải.
  3. *Doanh thu gộp (VND)*: Căn phải.
  4. *Tổng giảm giá (VND)*: Căn phải.
  5. *Doanh thu thuần (VND)*: Căn phải, in đậm.
  6. *Tỷ lệ đóng góp ngày (%)*: Căn phải.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `List<HourlyReportItem> calculateHourlyReport(List<BillModel> bills)`
  - **TypeScript:** `calculateHourlyReport(bills: HistoryOrder[]): HourlyReportItem[]`

---

### BÁO CÁO 7: BÁO CÁO HÌNH THỨC THANH TOÁN (PAYMENT METHODS)
- **Mục đích:** Kiểm soát dòng tiền theo từng kênh thanh toán (Tiền mặt, Chuyển khoản VietQR, Quẹt thẻ POS) để đối soát với ngân hàng và sổ quỹ.
- **Bộ lọc:** Cửa hàng, Khoảng ngày.
- **Các dòng hiển thị:**
  1. *Tiền mặt (CASH)*.
  2. *Chuyển khoản VietQR (TRANSFER_QR)*.
  3. *Thẻ ngân hàng / Ví điện tử (CARD)*.
- **Các cột hiển thị:**
  1. *Hình thức thanh toán*: Căn trái, in đậm.
  2. *Số lượng giao dịch*: Căn phải.
  3. *Doanh thu gộp (VND)*: Căn phải.
  4. *Tổng giảm giá (VND)*: Căn phải.
  5. *Tiền thuế VAT (VND)*: Căn phải.
  6. *Số tiền thực thu (VND)*: Căn phải, in đậm.
  7. *Tỷ trọng (%)*: Căn phải.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `Map<String, PaymentMethodSummary> calculatePaymentMethodsReport(List<BillModel> bills)`
  - **TypeScript:** `calculatePaymentMethodsReport(bills: HistoryOrder[]): Record<string, PaymentMethodSummary>`

---

### BÁO CÁO 8: BÁO CÁO KHUYẾN MÃI & VOUCHER (PROMOTIONS & DISCOUNTS)
- **Mục đích:** Đánh giá hiệu quả của từng chiến dịch khuyến mãi, số lượng voucher đã phát hành và chi phí chiết khấu thực tế.
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Loại khuyến mãi (Voucher theo Bill, Giảm giá món, Tích điểm).
- **Các cột hiển thị:**
  1. *Mã chương trình / Voucher*: Căn trái (CHAOBAN20, TRIAN10K...).
  2. *Tên chương trình*: Căn trái, in đậm.
  3. *Loại hình*: Căn giữa (Voucher Bill, Chiết khấu món, Đổi điểm thưởng).
  4. *Số lượt áp dụng*: Căn phải.
  5. *Tổng doanh thu kích cầu (VND)*: Tổng subTotal của các đơn áp dụng.
  6. *Tổng chi phí giảm giá (VND)*: Căn phải, in đậm.
  7. *Tỷ lệ chiết khấu trung bình (%)*: Căn phải.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `PromotionsReportResult calculatePromotionsReport(List<BillModel> bills)`
  - **TypeScript:** `calculatePromotionsReport(bills: HistoryOrder[]): PromotionsReportResult`

---

### BÁO CÁO 8b: BÁO CÁO KHUYẾN MÃI THEO CHƯƠNG TRÌNH (CAMPAIGN REPORT)
- **Nguồn:** `b.discounts[]` của hóa đơn `PAID` (đơn hủy bỏ qua). Mỗi dòng: `campaignId, campaignName, programCode, campaignType, voucherCode, amount`; dữ liệu cũ chỉ có `promoId / promoCode / promoName / description`.
- **Khóa nhóm:** `campaignId` → `promoId` → mã (`programCode/promoCode`) → tên (`campaignName/promoName/name/description`).
- **Cột:** Tên, Mã, Loại (`BILL_DISCOUNT` Giảm giá đơn hàng, `ORDER_VALUE_ITEM_BENEFIT` Tặng/giảm món theo giá trị đơn, `BUY_X_GET_Y` Mua X tặng Y, `ITEM_PRICE_RULE` Đồng giá/đồng giảm), Số hóa đơn (không trùng), Tổng giảm $= \sum \text{amount}$, Doanh thu các HĐ $= \sum b.\text{finalAmount}$ (mỗi HĐ một lần), Lượt dùng voucher (số dòng có `voucherCode`).
- **Chi tiết (drill-down):** Mã HĐ, Thời gian, Bàn, Mã voucher, Giảm giá, Tổng tiền HĐ, Nhân viên.
- **TypeScript:** `calculateCampaignReport(bills)` — `web/lib/promotion-report.ts`.

---

### BÁO CÁO 9: BÁO CÁO HỦY MÓN & HỦY ĐƠN HÀNG (CANCELLATIONS & AUDIT)
- **Mục đích:** Chống gian lận và kiểm soát thất thoát nguyên vật liệu khi hủy món đã gửi bếp hoặc hủy đơn đã in bill.
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Nhân viên thực hiện, Lý do hủy.
- **Các cột hiển thị:**
  1. *Thời điểm hủy*: Căn giữa (HH:mm - dd/MM/yyyy).
  2. *Mã hóa đơn*: Căn trái (`billCode`).
  3. *Bàn / Khu vực*: Căn trái.
  4. *Chi tiết món hủy*: Căn trái (Tên món x Số lượng).
  5. *Giá trị thất thoát (VND)*: Căn phải, in đậm, màu đỏ.
  6. *Nhân viên thực hiện*: Căn trái (Họ tên + username).
  7. *Lý do hủy*: Căn trái (Khách đổi ý, Bếp làm sai, Đợi lâu...).
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `CancellationReportResult calculateCancellationReport(List<BillModel> bills)`
  - **TypeScript:** `calculateCancellationReport(bills: HistoryOrder[]): CancellationReportResult`

---

### BÁO CÁO 9b: BÁO CÁO XÓA MÓN (DELETED ITEMS)
- **Hợp đồng dữ liệu (chung Flutter/Web):** xóa dòng / giảm số lượng món của đơn đã lưu trên bàn **bắt buộc lý do**: `Khách đổi món`, `Khách hủy món`, `Nhập sai`, `Hết món/hết nguyên liệu`, `Khác` (+ nội dung bắt buộc, lưu dạng `Khác: …`). Món đã gửi bếp vẫn cần quyền `CANCEL_KITCHEN_ITEM` / PIN quản lý.
  - Bản ghi: `{name, productId, quantity, unitPrice (gồm size/topping), amount (sau phần giảm giá dòng), reason, staffUsername, staffFullName, timestamp, sentToKitchen}`.
  - Bàn: `deletedItemsJson` (chuỗi JSON mảng). Thanh toán & hủy đơn ghi lên bill + history: `deletedItems`, `deletedItemsCount` (tổng số phần), `deletedItemsAmount`; trả bàn xóa `deletedItemsJson`; chuyển bàn mang theo; gộp bàn nối thêm. Xóa hết món đã lưu của bàn ⇒ ghi hóa đơn `CANCELLED` với lý do `Xóa hết món — {reason}` (kèm `deletedItems`) và trả bàn.
  - Audit log mỗi lần xóa: `action = "DELETE_ITEM"`, `targetType = "ORDER_ITEM"`, `details = "Xóa {qty} x {name} ({amount}đ) bàn {table} — Lý do: {reason}"`, kèm `productName, quantity, amount, reason, tableName, orderCode`.
- **Tổng hợp:** danh sách + nhóm theo lý do (gộp `Khác: …` về `Khác`) và theo nhân viên: số lần, số phần, giá trị.
- **TypeScript:** `deletionReportFromBills(bills)` (PAID + CANCELLED), `deletionReportFromAuditLogs(logs)` — `web/lib/item-deletion.ts`.

---

### BÁO CÁO 10: BÁO CÁO BÀN GIAO CA & CHÊNH LỆCH KÉT (CASH SHIFT VARIANCE)
- **Mục đích:** Đối soát tiền mặt cuối ca, phát hiện thừa/thiếu tiền két giữa số sách lý thuyết và tiền đếm thực tế của thu ngân.
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Thu ngân phụ trách, Trạng thái ca (`OPEN`, `CLOSED`).
- **Các cột hiển thị:**
  1. *Mã phiên ca*: Căn trái (`shiftCode`).
  2. *Tên ca / Nhân viên*: Căn trái.
  3. *Thời gian mở / đóng*: Căn giữa.
  4. *Tiền đầu ca (VND)*: Căn phải.
  5. *Doanh số tiền mặt (VND)*: Căn phải.
  6. *Thu nộp thêm (VND)*: Căn phải.
  7. *Chi vặt trong ca (VND)*: Căn phải.
  8. *Hoàn tiền mặt (VND)*: Căn phải.
  9. *Tiền lý thuyết kỳ vọng (VND)*: Căn phải, in đậm.  
     $$\text{ExpectedCash} = \text{InitialCash} + \text{CashSales} - \text{RefundCash} + \text{CashIn} - \text{CashOut}$$
  10. *Tiền kiểm đếm thực tế (VND)*: Căn phải.
  11. *Chênh lệch két (VND)*: Căn phải, in đậm:
      - Bằng $0$: Màu xanh lá (Khớp két).
      - Dương ($>0$): Màu xanh dương (Thừa két $+X$ đ).
      - Âm ($<0$): Màu đỏ (Thiếu két $-X$ đ).
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `List<CashShiftAuditItem> calculateCashShiftReport(List<CashShiftModel> shifts, List<BillModel> bills)`
  - **TypeScript:** `calculateCashShiftReport(shifts: CashShiftItem[], bills: HistoryOrder[]): CashShiftAuditItem[]`

---

### BÁO CÁO 11: BÁO CÁO LỢI NHUẬN GỘP & GIÁ VỐN (GROSS PROFIT & COGS)
- **Mục đích:** Phân tích cấu trúc chi phí giá vốn (COGS) và biên lợi nhuận gộp từng mặt hàng để tối ưu hóa giá bán thực đơn.
- **Bộ lọc:** Cửa hàng, Khoảng ngày, Nhóm hàng.
- **Các cột hiển thị:**
  1. *Tên món*: Căn trái, in đậm.
  2. *Số lượng bán*: Căn phải.
  3. *Giá bán bình quân (VND)*: Căn phải.
  4. *Giá vốn bình quân (VND)*: Căn phải (`costPrice` + topping cost).
  5. *Doanh thu sau giảm giá (VND)*: Căn phải.
  6. *Tổng giá vốn hàng bán (VND)*: Căn phải.
  7. *Lợi nhuận gộp (VND)*: Căn phải, in đậm.
  8. *Tỷ suất LN gộp (%)*: Căn phải, định dạng `XX.XX%`.
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `GrossProfitReportResult calculateGrossProfitReport(List<BillModel> bills, Map<int, ProductModel> productsMap)`
  - **TypeScript:** `calculateGrossProfitReport(bills: HistoryOrder[], productsMap: Record<number, ProductItem>): GrossProfitReportResult`

---

### BÁO CÁO 12: BÁO CÁO CUỐI NGÀY (END-OF-DAY Z-REPORT)
- **Mục đích:** Báo cáo chốt sổ tổng hợp toàn diện cuối ngày gồm 4 phân hệ (Tổng hợp, Thu chi, Hàng hóa, Phòng bàn) để Chủ quán kiểm tra doanh số và in biên bản bàn giao.
- **Cấu trúc 4 Phân hệ (4 Tabs):**
  - **Tab 1 - Tổng hợp:**
    - Doanh thu gộp: $\sum \text{subTotal}$.
    - Giảm giá: Giảm giá món, Giảm giá bill/voucher, Tích điểm.
    - Doanh thu sau giảm giá: $\text{AfterDiscount}$.
    - Thuế GTGT VAT: $\sum \text{vatAmount}$.
    - Doanh thu thuần: $\sum \text{finalAmount}$.
    - Hoàn trả: $\sum \text{refundAmount}$.
    - Doanh thu thực thu cuối ngày: $\text{NetRevenue} - \text{RefundAmount}$.
    - Số hóa đơn hoàn tất, Số lượt khách, Giá trị TB/đơn.
    - Số hóa đơn đã hủy (`cancelledBillsCount`) và giá trị đơn hủy (`cancelledBillsAmount` $= \sum_{b \in \text{CANCELLED}} b.\text{subTotal}$) — hiển thị riêng, **không** cộng doanh thu.
    - **Số món xóa** (`deletedItemsCount`) $= \sum_{b \in \text{PAID} \cup \text{CANCELLED}} \sum_{d \in b.\text{deletedItems}} d.\text{quantity}$ (tổng số PHẦN).
    - **Tổng tiền xóa món** (`deletedItemsAmount`) $= \sum d.\text{amount}$ (giá trị sau phần giảm giá dòng tương ứng). Đọc từ mảng `deletedItems` của hóa đơn (không dùng `deletedItemsCount/Amount` lưu sẵn để tránh lệch dữ liệu cũ).
  - **Tab 2 - Thu chi:**
    - Doanh số Tiền mặt, Chuyển khoản QR, Thẻ POS.
    - Tổng tiền nộp thêm vào két trong ngày (`cashIn`).
    - Tổng chi tiền mặt phát sinh trong ngày (`cashOut`).
    - Tiền hoàn trả khách trong ngày (`refundTotal`).
  - **Tab 3 - Hàng hóa:**
    - Tổng số lượng sản phẩm bán ra trong ngày.
    - Bảng chi tiết từng món: Tên, Nhóm, Số lượng, Thành tiền.
  - **Tab 4 - Phòng bàn:**
    - Thống kê lượt phục vụ và doanh thu phân bổ theo từng Khu vực (Tầng 1, Tầng 2, Mang về).
- **Hợp đồng hàm thuần đề xuất:**
  - **Dart:** `EndOfDayReportData generateEndOfDayZReport(List<BillModel> bills, List<CashShiftModel> shifts, List<TableModel> tables, Map<int, ProductModel> productsMap)`
  - **TypeScript:** `generateEndOfDayZReport(bills: HistoryOrder[], shifts: CashShiftItem[], tables: TableItem[], productsMap: Record<number, ProductItem>): EndOfDayReportData`

---

## 6. ĐỐI SOÁT CHUẨN VỚI BỘ DỮ LIỆU `report_golden.json`

Bộ dữ liệu `docs/report_golden.json` bao gồm 20 hóa đơn thực tế trong ngày kinh doanh mẫu `2026-10-04` tại cửa hàng `TRAM01`.

### Bảng kết quả đối soát vàng (Golden Verification Parity Table):

| Chỉ số tài chính | Giá trị chuẩn xác mong đợi | Ghi chú đối soát |
| :--- | :---: | :--- |
| **Tổng số hóa đơn mẫu** | **20 đơn** | Gồm 17 PAID, 2 CANCELLED, 1 REFUNDED |
| **Số hóa đơn hoàn tất (PAID)** | **17 đơn** | Đơn được tính vào doanh thu |
| **Số hóa đơn bị hủy (CANCELLED)** | **2 đơn** | BILL_003 (50k) và BILL_015 (70k) |
| **Số hóa đơn hoàn tiền (REFUNDED)**| **1 đơn** | BILL_019 (Hoàn 47k tiền mặt do order nhầm) |
| **Tổng số lượt khách phục vụ** | **37 khách** | Tính trên 17 đơn hoàn tất |
| **Doanh thu gộp (Gross Revenue)** | **1.167.000 đ** | Tổng `subTotal` của 17 đơn PAID |
| **Giảm giá theo món (Item Discounts)**| **5.000 đ** | Đơn BILL_002 giảm 5k cho Trà đào |
| **Giảm giá hóa đơn (Bill Discounts)**| **30.000 đ** | BILL_005 giảm 20k, BILL_012 giảm 10k |
| **Giảm giá tích điểm (Points)** | **10.000 đ** | BILL_007 đổi 100 điểm giảm 10k |
| **Tổng tiền giảm giá (Total Discounts)**| **45.000 đ** | $5.000 + 30.000 + 10.000 = 45.000$ đ |
| **Doanh thu sau giảm giá (After Discount)**| **1.122.000 đ** | $1.167.000 - 45.000 = 1.122.000$ đ |
| **Tổng tiền thuế VAT (8%)** | **82.560 đ** | Tính trên AfterDiscount của từng đơn |
| **Doanh thu thuần (Net Revenue)** | **1.204.560 đ** | $1.122.000 + 82.560 = 1.204.560$ đ |
| **Tiền hoàn trả khách (Refund)** | **47.000 đ** | Đơn BILL_019 hoàn lại tiền mặt |
| **Doanh thu thuần sau hoàn trả** | **1.157.560 đ** | $1.204.560 - 47.000 = 1.157.560$ đ |
| **Giá trị trung bình / đơn** | **70.856 đ** | $\text{round}(1.204.560 / 17)$ |
| **Tổng giá vốn hàng bán (COGS)** | **426.000 đ** | Tính từ `costPrice` món + topping |
| **Lợi nhuận gộp (Gross Profit)** | **696.000 đ** | $1.122.000 - 426.000 = 696.000$ đ |
| **Tỷ suất lợi nhuận gộp (%)** | **62.03%** | $(696.000 / 1.122.000) \times 100\%$ |
| **Doanh thu Tiền mặt (CASH)** | **588.960 đ** | 8 hóa đơn |
| **Doanh thu Chuyển khoản (TRANSFER_QR)**| **464.400 đ** | 7 hóa đơn |
| **Doanh thu Thẻ POS (CARD)** | **151.200 đ** | 2 hóa đơn |
| **Ca sáng (SHIFT_01) - Két kỳ vọng** | **1.440.560 đ** | Đầu 1.000k + Bán mặt 340.560 + Nộp 200k - Chi 100k |
| **Ca sáng (SHIFT_01) - Thực đếm / Lệch**| **1.440.560 đ (Lệch: 0 đ)** | Khớp két $100\%$ |
| **Ca tối (SHIFT_02) - Két kỳ vọng** | **1.251.400 đ** | Đầu 1.100k + Bán mặt 248.400 - Hoàn 47k - Chi 50k |
| **Ca tối (SHIFT_02) - Thực đếm / Lệch**| **1.256.400 đ (Lệch: +5.000 đ)**| Thừa 5.000 đ do khách không lấy tiền lẻ |

---

## 7. QUY ĐỊNH XUẤT FILE & TIÊU ĐỀ EXCEL / PDF

### 7.1. Quy ước đặt tên file (Naming Convention)
Tên tệp tin xuất ra phải tuân theo cấu trúc chuẩn, viết hoa không dấu, phân tách bằng dấu gạch dưới:

$$\text{[MaLoaiBaoCao]}\_\text{[StoreCode]}\_\text{[TuNgay]}\_\text{[DenNgay]}\_\text{[Timestamp]}.\text{xlsx}$$

- **Định dạng ngày:** `yyyyMMdd`
- **Định dạng giờ:** `HHmmss`
- **Bảng mã loại báo cáo:**
  - `BC_TONGHOP`: Báo cáo Tổng quan Quản trị
  - `BC_DOANHTHU_KY`: Báo cáo Doanh thu theo kỳ
  - `BC_NHOMHANG`: Báo cáo Doanh thu theo Nhóm hàng
  - `BC_HANGHOA`: Báo cáo Hiệu suất Món ăn / Hàng hóa
  - `BC_NHANVIEN`: Báo cáo Năng suất Nhân viên
  - `BC_KHUNGGIO`: Báo cáo Phân bổ theo Khung giờ
  - `BC_PTTT`: Báo cáo Hình thức Thanh toán
  - `BC_KHUYENMAI`: Báo cáo Khuyến mãi & Voucher
  - `BC_HUYMON`: Báo cáo Hủy món & Hủy đơn hàng
  - `BC_CAKET`: Báo cáo Bàn giao Ca & Chênh lệch Két
  - `BC_LOINHUAN`: Báo cáo Lợi nhuận gộp & Giá vốn
  - `BC_CUOINGAY_Z`: Báo cáo Cuối ngày Z-Report

*Ví dụ:*  
`BC_CUOINGAY_Z_TRAM01_20261004_20261004_230500.xlsx`  
`BC_HANGHOA_TRAM01_20261001_20261031_083015.xlsx`

### 7.2. Cấu trúc trang bìa & Tiêu đề trong file Excel/PDF
Mỗi file xuất báo cáo phải tuân thủ chuẩn dàn trang chuyên nghiệp:
1. **Header cửa hàng (Góc trên bên trái):**
   - Dòng 1: **TÊN CỬA HÀNG / CHI NHÁNH** (In hoa, font Be Vietnam Pro, size 12, bold).
   - Dòng 2: Địa chỉ cửa hàng.
   - Dòng 3: Số điện thoại liên hệ.
2. **Tiêu đề báo cáo (Căn giữa trang):**
   - Tên báo cáo bằng tiếng Việt có dấu, in hoa (Size 16, Bold, Màu sắc nhận diện hệ thống: `#7E2930`).
   - Dòng phụ: *Kỳ báo cáo: Từ ngày dd/MM/yyyy đến ngày dd/MM/yyyy*.
   - Dòng phụ: *Ngày giờ xuất: dd/MM/yyyy HH:mm:ss (UTC+7)*.
3. **Phần bảng dữ liệu (Data Grid):**
   - Header bảng: Nền xám nhạt (`#F8F4EE`) hoặc đỏ thương hiệu Trạm (`#7E2930`), chữ trắng hoặc đậm, căn giữa.
   - Các cột số tiền: Căn phải, định dạng có dấu chấm phân cách hàng nghìn (ví dụ `1.204.560`).
   - Cột tỷ lệ: Căn phải, định dạng `0.00%`.
   - Dòng tổng cộng (Total Row): In đậm, nền viền đôi trên dưới.
4. **Chữ ký xác nhận (Cuối trang):**
   - Bên trái: *Người lập biểu (Ký, ghi rõ họ tên)*.
   - Ở giữa: *Thu ngân trưởng / Quản lý (Ký, ghi rõ họ tên)*.
   - Bên phải: *Chủ cửa hàng / Giám đốc (Ký, duyệt)*.

---

## 8. CẦN CHỦ DỰ ÁN XÁC NHẬN (SIGN-OFF CHECKLIST)

Trước khi chuyển giao hợp đồng cho đội ngũ lập trình hoàn thiện mã nguồn, các điểm sau cần được Chủ dự án xem xét và phê duyệt:

- [ ] **1. Thống nhất công thức tính VAT:** Xác nhận việc bỏ hoàn toàn công thức tính ngược `Math.round(netRevenue * 0.08 / 1.08)` trên Web và bắt buộc dùng trường `vatAmount` chốt trên đơn hàng.
- [ ] **2. Quy định tính Lợi nhuận gộp:** Phê duyệt việc đo lường Lợi nhuận gộp dựa trên Doanh thu sau giảm giá trước VAT trừ đi Giá vốn ($\text{AfterDiscount} - \text{COGS}$).
- [ ] **3. Phân định ranh giới ngày và ca:** Phê duyệt quy tắc lọc ngày ưu tiên trường `closedAt` và quy tắc giữ nguyên ca xuyên đêm theo `shiftId`.
- [ ] **4. Nghiệp vụ hoàn tiền (Refund):** Phê duyệt việc đơn hoàn tiền ghi nhận giảm trừ doanh thu và trừ tiền mặt trong két ca.
- [ ] **5. Bộ dữ liệu vàng kiểm thử:** Phê duyệt bộ số liệu chuẩn hóa trong `docs/report_golden.json` làm thước đo tự động cho toàn bộ unit test của dự án.

---
*Tài liệu được soạn thảo bởi Đội ngũ Phân tích Nghiệp vụ & Kế toán POS Trạm.*
