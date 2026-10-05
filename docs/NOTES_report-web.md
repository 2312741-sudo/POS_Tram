# Báo Cáo Phân Hệ Báo Cáo Quản Trị Web (Agent 4: report-web)

## 1. Danh sách file đã sửa và tạo mới
- `web/lib/reports.ts`: Động cơ tính toán báo cáo tài chính & chỉ số quản trị bằng TypeScript thuần (100% pure functions, không phụ thuộc React hay Next.js).
- `web/lib/export.ts`: Tiện ích xuất Excel đa định dạng theo chuẩn mã file `[MaLoaiBaoCao]_[StoreCode]_[TuNgay]_[DenNgay]_[Timestamp].xlsx`, hỗ trợ in trình duyệt và styling UTF-8 tiếng Việt.
- `web/lib/data-context.tsx`: Tích hợp trường `costPrice` cho sản phẩm, bổ sung hàm khử trùng lặp đơn hàng `deduplicateBills`.
- `web/app/dashboard/analytics/page.tsx`: Màn hình Tổng quan phân tích (Executive Overview) với bộ lọc thời gian UTC+7, heatmap 24 giờ, năng suất nhân viên, top sản phẩm.
- `web/app/dashboard/revenue/page.tsx`: Màn hình Doanh thu theo ngày/tuần/tháng/năm kèm so sánh kỳ trước và hình thức thanh toán.
- `web/app/dashboard/product-sales/page.tsx`: Màn hình Hiệu suất món ăn, doanh số theo nhóm hàng, phân tích lợi nhuận gộp & tỷ suất lãi gộp (COGS).
- `web/app/dashboard/end-of-day/page.tsx`: Màn hình Báo cáo cuối ngày (Z-Report) 4 Tab đầy đủ (Tổng hợp, Thanh toán & Ca két, Bán hàng theo món, Kiểm toán hủy & giảm giá).
- `web/app/dashboard/shifts/page.tsx`: Màn hình Quản lý ca làm việc và đối soát chênh lệch két tiền mặt.
- `web/app/dashboard/orders/page.tsx`: Danh sách đơn hàng đối soát kèm bộ lọc cửa hàng và trạng thái.
- `web/app/dashboard/audit/page.tsx`: Nhật ký kiểm toán đơn hủy, món hủy, giảm giá voucher & điểm tích lũy.
- `web/app/dashboard/products/page.tsx`: Ô nhập `costPrice` (giá vốn) cho từng sản phẩm và biến thể, đọc mượt mà dữ liệu cũ thiếu trường này.
- `web/test/reports.test.ts`: Bộ kiểm thử tự động 13 ca đối soát 100% với `docs/report_golden.json`.

## 2. Kết quả kiểm thử
- `npx vitest run test/reports.test.ts`: **13/13 test PASS** (khớp từng con số với `docs/report_golden.json` và bản Flutter).
- `npm run build`: **PASS 100%**, tạo thành công 20/20 static pages mà không có bất kỳ lỗi TypeScript hay linting nào.

## 3. Khả năng tương thích
- Khử trùng lặp đơn hàng theo `id` và ưu tiên bản ghi có timestamp / status mới nhất.
- Hỗ trợ xem đa cửa hàng (ALL stores hoặc chọn riêng từng chi nhánh `TRAM01`, `TRAM02`).
- Trường `costPrice` là tùy chọn; nếu chưa có giá vốn hệ thống sẽ hiển thị "Chưa nhập giá vốn" và không tự tiện tính là 0 để tránh méo mó tỷ suất lợi nhuận.
