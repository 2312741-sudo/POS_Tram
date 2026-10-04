# PROMPT TRIỂN KHAI KHUYẾN MÃI VÀ KHO HÀNG — POS TRẠM F&B

Ngày khảo sát: 01/10/2026. Ngôn ngữ sản phẩm: tiếng Việt. Múi giờ mặc định đề xuất: Asia/Ho_Chi_Minh.

Đây là prompt giao việc cho đội kỹ thuật hoặc coding agent. Đọc toàn bộ trước khi triển khai. Các yêu cầu thiết kế dưới đây là thiết kế đề xuất cho POS Trạm; không phải mô tả kiến trúc nội bộ của KiotViet. Việc có tài liệu này không tự cấp quyền sửa production, chuyển dữ liệu, phát hành hóa đơn, kết nối tài khoản hay triển khai ứng dụng.

## 1. Vai trò / Role

Bạn là Principal Engineer kiêm Business Analyst chuyên POS F&B, khuyến mãi, quản lý tồn kho nhiều chi nhánh và tính nhất quán giao dịch. Chịu trách nhiệm biến yêu cầu thành hệ thống hoạt động xuyên suốt Web Admin, Flutter POS và backend, có kiểm chứng bằng tình huống nghiệp vụ thực tế.

Bạn phải phân biệt sự kiện đã xác minh, quyết định thiết kế và điều chưa biết. Không tự nhận đã sao chép đầy đủ một sản phẩm khi chưa có bằng chứng. Không tạo màn hình có nút hoạt động giả, dữ liệu mẫu thay cho dữ liệu thật, hoặc thông báo thành công khi giao dịch chưa được backend chấp nhận.

## 2. Bối cảnh / Context

### 2.1. Nhu cầu và phạm vi

Chủ hệ thống đang xây dựng một hệ sinh thái POS tương tự KiotViet, cần hai phân hệ **Khuyến mãi** và **Kho hàng** đủ chiều sâu nghiệp vụ để vận hành nhà hàng/quán. Tham chiếu chính là phiên bản KiotViet F&B trên Safari của người dùng, ảnh danh sách khuyến mãi và hướng dẫn chính thức F&B. Không mặc định yêu cầu parity với bản bán lẻ, nhà thuốc, khách sạn hay mọi gói dịch vụ của KiotViet.

“Đầy đủ” nghĩa là tất cả năng lực trong bản đồ bên dưới có chức năng, dữ liệu, luồng trạng thái, phân quyền, lỗi và tiêu chí nghiệm thu. Chức năng không hiện trong tài khoản vẫn phải được ghi nhận theo tài liệu, cùng điều kiện bật tính năng và mức kiểm chứng. Không được bỏ kho chỉ vì đã có danh sách món; không được gọi giảm % đơn hàng đơn giản là toàn bộ hệ khuyến mãi.

### 2.2. Mã nguồn hiện có đã đọc

| Đầu vào | Sự kiện xác minh trên working tree ngày khảo sát | Hệ quả khi triển khai |
|---|---|---|
| README.md; web/package.json | Web Next.js 16.2.9, React 19.2.4, TypeScript; Firebase SDK; Flutter POS | Tích hợp vào dự án hiện tại; không dựng một app rời để giả hoàn thành |
| web/app; web/lib; web/components | Cấu trúc không dùng web/src | Đặt route/module phù hợp cấu trúc thật |
| docs/database_schema.md; web/lib/data-context.tsx | Có /stores/{storeCode}; tồn tại dữ liệu và fallback legacy ở root | Phải lập bản đồ dữ liệu và migration; không xóa hoặc dual-write tùy tiện |
| app_flutter/lib/data/models/app_models.dart, PromotionModel | Các loại PERCENT_BILL, FIXED_BILL, PERCENT_ITEM, FIXED_ITEM, VOUCHER; quy tắc còn đơn giản | Dùng adapter sang schema mới, không ép bốn hình thức mới vào trường type cũ |
| PromotionModel.calculateDiscount | VOUCHER đi cùng nhánh tính %; targetCategory chưa tham gia vòng tính giảm món; nhánh giảm món dùng price; giảm cố định món chưa chặn theo giá dòng | Kiểm tra dữ liệu legacy để xác định ý nghĩa rồi sửa có test; không chuyển voucher sang tiền cố định bằng suy đoán |
| firebase_service.dart, incrementPromotionUsage | Đọc usageCount rồi ghi count+1; lỗi bị bỏ qua | Có thể mất lượt khi đồng thời; thay bằng luồng authoritative có quota và idempotency |
| firebase_service.dart, closeAndPayBill | Trạng thái bill, history, bàn và lượt khuyến mãi được ghi ở nhiều bước; một số tác vụ không await | Phải thiết kế commit/recovery trước khi gắn khuyến mãi và kho vào thanh toán |
| web/lib/data-context.tsx, checkoutAndFreeTable | Web tự tính tổng và nhận discountAmount rồi thực hiện các ghi dữ liệu | Web và Flutter phải gọi cùng nghiệp vụ có kiểm tra phía server |
| OrderItemModel và end_of_day_report_screen.dart | itemTotal trừ discountAmount ở mức dòng; báo cáo có chỗ nhân discountAmount với quantity | Chuẩn hóa ý nghĩa giảm theo đơn vị hay theo dòng và chuyển đổi rõ ràng |
| promotions_screen.dart | Có nhánh đưa khuyến mãi mẫu khi danh sách rỗng | Phân biệt EMPTY, LOADING, ERROR; dữ liệu demo chỉ ở môi trường demo được đánh dấu |
| web/lib/auth.tsx; Flutter auth_service.dart | Có xác thực/fallback phía client và vai trò lưu local | Không coi localStorage/SharedPreferences hoặc role do client gửi là quyền server; xác minh cơ chế Firebase Auth thật |
| app_flutter/pubspec.yaml | Có firebase_auth, firebase_database, cloud_firestore, go_router, Riverpod | Có dependency không có nghĩa dự án đã dùng đúng cho các luồng hiện tại; không đổi sang Firestore chỉ vì thấy package |
| web/AGENTS.md | Có yêu cầu đọc tài liệu Next.js cục bộ trước khi sửa code | Đọc node_modules/next/dist/docs liên quan trước khi triển khai Web |

Các kết luận trên là kiểm tra tĩnh, chưa phải kết quả chạy ứng dụng hay kiểm thử bảo mật. Không tìm thấy rules qua tìm kiếm tên file cục bộ không chứng minh production thiếu rules. Working tree đã có nhiều sửa đổi của người dùng: giữ nguyên, ghi nhận baseline, chỉ sửa phần thuộc nhiệm vụ sau khi được giao triển khai.

### 2.3. Bằng chứng UI trực tiếp

| Mã | Đã xem, chỉ đọc hoặc mở biểu mẫu chưa lưu | Giới hạn kiểm chứng |
|---|---|---|
| UI-P1 | Danh sách chương trình, tìm mã/tên, bộ lọc chi nhánh, hình thức, có mã, hiệu lực, kích hoạt; cột ngân sách | Chưa thực thi áp dụng vào đơn thật |
| UI-P2 | Biểu mẫu bốn hình thức: giảm đơn; giảm/tặng món theo giá trị đơn; mua món giảm/tặng món; đồng giá/đồng giảm giá | Không bấm Lưu |
| UI-P3 | Cấu hình thời gian, lịch, sinh nhật, loại trừ ngày, khách hàng, món, ngân sách, số lượt/khách, tự áp dụng khi biểu mẫu có trường | Chưa kiểm chứng mọi biên lịch, ưu tiên và cộng dồn bằng thanh toán |
| UI-P4 | Tab phát hành mã; nhập tay/import/tạo ngẫu nhiên; tab mã và lịch sử trên chi tiết chương trình | Chưa phát hành, hủy hoặc sử dụng mã thật |
| UI-K1 | Menu Kho hàng tài khoản hiện tại: Danh sách hàng hóa, Kiểm kho, Nhập hàng, Trả hàng nhập, Nhà cung cấp | Không thấy chuyển hàng/sản xuất/xuất hủy/nội bộ trong menu này; chưa xác định do gói hay thiết lập/quyền |
| UI-K2 | Danh mục; thêm nguyên vật liệu/công cụ dụng cụ/món/topping; nhóm quản lý, loại, thương hiệu, tồn, thuộc tính, vị trí, trạng thái | Danh mục không thể hiện mọi nghiệp vụ kho |
| UI-K3 | Biểu mẫu nguyên liệu: mã tự động, tên, nhóm, thương hiệu, ảnh, giá vốn, quản lý tồn, tồn đầu, min/max, đơn vị/thuộc tính, mô tả, chi nhánh sử dụng, vị trí/khối lượng | Không lưu hàng mới hoặc thay số tồn |
| UI-K4 | Chi tiết hàng: Thông tin, Thẻ kho, Tồn kho, Mô tả; thẻ kho theo đơn vị cơ bản; tồn theo chi nhánh có cột Khách đặt | Chưa xác minh cơ chế giữ tồn phía backend KiotViet |
| UI-K5 | Kiểm kho: trạng thái Phiếu tạm/Đã cân bằng/Đã hủy; form tìm hàng, Excel, Tất cả/Khớp/Lệch/Chưa kiểm, thực tế, giá trị lệch, ghi chú, Lưu tạm/Hoàn thành | Form trống; không cân bằng kho thật |
| UI-K6 | Nhập hàng: bộ lọc, phiếu đã nhập, chi tiết, trả hàng/in/export/in mã vạch; form tìm hàng, nhập Excel, nhà cung cấp, số-ngày hóa đơn, mã, ghi chú, Lưu tạm/Hoàn thành, thiết lập VAT | Một số cột tiền không hiện trong trạng thái tài khoản khảo sát; không suy ra tính giá không tồn tại |
| UI-K7 | Nhà cung cấp: tìm mã/tên/điện thoại, nhóm, tổng mua, khoảng thời gian, nợ hiện tại, trạng thái; form tên/mã/phone/email, CCCD, địa chỉ hành chính, nhóm/ghi chú, MST/công ty | Tên/phone/email có placeholder “Bắt buộc”; chưa bấm Lưu để kiểm validation thực tế; không nhập CCCD thật |
| UI-K8 | Trả hàng nhập: tìm mã, thời gian, Phiếu tạm/Đã trả hàng/Đã hủy; form tìm/quét hàng, Excel, NCC, mã tự động, ghi chú, Lưu tạm/Hoàn thành | Form trả nhanh trống; chưa commit hoặc kiểm hoàn tiền/công nợ thật |

Không chép dữ liệu kinh doanh, mã voucher đang dùng, tên khách, nhà cung cấp hay thông tin đăng nhập của tài khoản khảo sát vào fixtures. Các ví dụ phía dưới là dữ liệu giả.

### 2.4. Nguồn chính thức và các quy tắc quan trọng

Các đoạn này là bản ghi đối chiếu ngắn; xem nguồn khi cần chi tiết. Tài liệu một số nghiệp vụ đang mô tả UI 2025 trong khi gian hàng hiển thị UI 2026. Chọn UI 2026 cho bố cục, đối chiếu nghiệp vụ và ghi xung đột vào decision log.

- **S1 — [Khuyến mãi F&B](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-khuyen-mai/khuyen-mai/):** chương trình đã có giao dịch, kể cả hủy, không được xóa; điều kiện bị khóa, chỉnh sửa không đổi đơn đang áp dụng trước đó. Ngày loại trừ được ưu tiên. Nguồn nêu giới hạn 100 nhóm/200 đối tượng riêng lẻ; xác minh phạm vi trước khi hard-code. Quy tắc lựa chọn và trả hàng được ghi tại P-09/X-05.
- **S2 — [Phát hành mã khuyến mãi](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-voucher/voucher/):** mã gắn với giảm đơn hàng; chế độ có mã không đổi sau lưu. Mã gồm A–Z, 0–9, dài 5–15, không khoảng trắng/ký tự đặc biệt; không trùng trong gian hàng kể cả mã đã xóa/hết hạn. Import tối đa 5.000 mã/lần và không nhập một phần khi có lỗi; phần ngẫu nhiên ít nhất 5 ký tự. Chỉ mã đã phát hành được sử dụng. Không suy ra quy tắc khôi phục mã sau hủy từ nguồn này.
- **S3 — [Hàng hóa trong Kho hàng](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-hang-hoa/quan-ly-hang-hoa-trong-kho-hang/):** tách kho với thực đơn trong UI mới; quản lý nguyên vật liệu, công cụ dụng cụ và hàng bán có tồn. Có đơn vị quy đổi, thuộc tính, nhập dữ liệu. Đối chiếu mẫu Excel của phiên bản hiện tại thay vì dùng mẫu cũ cho mọi loại.
- **S4 — [Nhập hàng](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-kho-hang/nhap-hang/):** có lượng, giá, giảm giá, thanh toán/công nợ; một hàng có thể có nhiều mức nhập, tối đa ba theo hướng dẫn. Lưu tạm chưa tăng tồn; hoàn thành tăng tồn; hủy điều chỉnh kho và công nợ. Phiếu hoàn thành giới hạn chỉnh sửa.
- **S5 — [Nhà cung cấp](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-kho-hang/quan-ly-nha-cung-cap/):** quản lý thông tin, tìm kiếm/import/export, lịch sử mua/trả, công nợ và thanh toán. Kiểm chứng lại quy tắc bắt buộc, trùng số điện thoại và phạm vi công nợ trên UI trước khi sao chép validation.
- **S6 — [Kiểm kho](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-hang-hoa/kiem-kho/):** chọn/tìm/quét/import hàng, đối chiếu thực tế, lưu tạm hoặc cân bằng; có khả năng gộp phiếu tạm. Các biến thể app/thiết bị không mặc định có giao diện giống Web.
- **S7 — [Chuyển hàng](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-hang-hoa/chuyen-hang/):** nguồn gửi và đích nhận tách bước; có phiếu tạm, đang chuyển, đã nhận, hủy. Hướng dẫn nhận thiếu đưa phần chênh về tồn nguồn. Chưa xác minh nhận từng phần nhiều lần trong tài khoản này.
- **S8 — [Xuất hủy](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-kho-hang/xuat-huy/):** phiếu tạm không trừ tồn; hoàn thành trừ tồn; giá trị dựa trên giá vốn. Phiếu hoàn thành giới hạn sửa; hủy hoàn trả tồn. Có tìm/lọc, sao chép, in và export.
- **S9 — [Xuất dùng nội bộ](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-hang-hoa/xuat-dung-noi-bo/):** ghi nhận dùng hàng trong vận hành, tách mục đích sử dụng và tác động kho khỏi bán hàng.
- **S10 — [Hàng sản xuất](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-hang-hoa/hang-san-xuat/):** sản xuất theo lô trừ nguyên liệu và tăng thành phẩm; khác hàng chế biến trừ nguyên liệu khi bán. Thành phẩm có thể làm nguyên liệu món khác. Có phiếu tạm/hoàn thành, hủy, chỉnh thời gian/ghi chú, bảng kê nguyên liệu tổng hợp/chi tiết. UI 2026 chuyển các nghiệp vụ này về Kho hàng.
- **S11 — [Trả hàng nhập](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-giao-dich/tra-hang-nhap/):** tạo nhanh hoặc theo phiếu nhập; giảm tồn và điều chỉnh công nợ/tiền hoàn. Phải giữ liên kết chứng từ để hủy và đối soát.
- **S12 — [Hóa đơn đầu vào](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-giao-dich/hoa-don-dau-vao/):** có kết nối ngoài, đồng bộ, ghép nhà cung cấp/hàng hóa và liên kết phiếu nhập/chi phí; nguồn nêu khoảng đồng bộ tối đa 90 ngày mỗi yêu cầu. Không đồng nhất hóa đơn đầu vào với phiếu nhập đã tăng tồn.
- **S13 — [Báo cáo F&B](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/fnb-bao-cao/bao-cao/):** báo cáo hàng hóa có bán hàng, lợi nhuận, xuất nhập tồn, chi tiết và xuất hủy; có nhà cung cấp, kênh bán và khuyến mãi trong báo cáo liên quan. Dùng sổ giao dịch để định nghĩa chỉ tiêu cho POS Trạm.
- **S14 — [Thiết lập F&B](https://www.kiotviet.vn/huong-dan-su-dung-kiotviet/huong-dan-bar-cafe-nha-hang/thong-tin-cua-hang-web-fnb/):** tài liệu mô tả tùy chọn giá vốn trung bình và giá vốn cố định. Kiểm chứng cấu hình được dùng thực tế; không đổi chế độ trên dữ liệu thật trong khảo sát.
- **T1 — [RTDB đọc/ghi](https://firebase.google.com/docs/database/web/read-and-write), [RTDB Security Rules](https://firebase.google.com/docs/database/security):** transaction có thể chạy lại và phải xử lý dữ liệu null; multipath update hỗ trợ ghi nguyên tử nhưng bản thân không kiểm tra quota nghiệp vụ. Atomic increment giải quyết cộng số, chưa đủ ngăn dùng trùng hoặc vượt hạn mức. Cache Web không bảo đảm lưu offline xuyên phiên. Áp dụng tài liệu SDK đúng phiên bản lúc triển khai.

### 2.5. Giả định, giới hạn và đầu vào còn thiếu

- Giả định F&B Việt Nam, VND, nhiều chi nhánh cùng một chủ hệ thống; POS có size/topping. Có thể sửa giả định khi chủ dự án cung cấp thông tin khác.
- Chưa xác định storeCode là chi nhánh của một tổ chức hay tenant độc lập. Không cho phép chia sẻ voucher, công nợ hoặc hàng giữa hai tenant chỉ vì cùng dùng database.
- Chưa đo tải, số SKU, số chi nhánh, số máy POS, độ dài offline, cấu hình giá vốn thật, thuế/phụ thu, nhà cung cấp hóa đơn ngoài và backend được triển khai.
- Chưa có bằng chứng trực tiếp các biên cộng dồn, thời điểm trừ kho món chế biến, hồi mã khi hủy, nhận thiếu, đơn mở trước khi đổi chương trình.
- Lô/hạn dùng, serial, FEFO/FIFO, đặt hàng nhập, nhiều kho con, nhận chuyển nhiều lần, coupon riêng, thẻ quà tặng trả trước là khả năng mở rộng; không được tự gắn nhãn đã thấy trên KiotViet F&B của tài khoản này.
- Chỉ hỏi quyết định ảnh hưởng kết quả; vẫn làm phần độc lập. Tính năng có phụ thuộc chưa sẵn sàng phải có trạng thái BLOCKED/DEFERRED rõ ràng, không giả thành công.

## 3. Mục tiêu / Objective

Thiết kế và triển khai hai phân hệ có thể nghiệm thu xuyên suốt: cấu hình khuyến mãi → định giá đơn → giữ hạn mức/mã → thanh toán → ghi nhận sử dụng/báo cáo; danh mục → nhập → tồn và giá vốn → kiểm/chuyển/sản xuất/xuất → tác động từ bán/tặng/hủy → đối soát.

Kết quả cần đạt: mọi máy dùng cùng quy tắc tiền, cùng tồn kho và lịch sử; không trừ kho/cộng lượt hai lần; không vượt quota khi hai thu ngân thao tác đồng thời; hóa đơn cũ không đổi vì sửa tên, công thức hay chương trình; mọi điều chỉnh có chứng từ và người chịu trách nhiệm.

### 3.1. Bản đồ năng lực và thứ tự phụ thuộc

| Module | Năng lực bắt buộc | Phụ thuộc | ID yêu cầu |
|---|---|---|---|
| Foundation | danh tính tin cậy, tenant/chi nhánh, quyền, tiền/đơn vị, thời gian, audit, idempotency | hiện trạng app | F-01…F-08 |
| Catalog | hàng kho, món, biến thể, đơn vị, nhóm, trạng thái, công thức version | Foundation | K-01…K-03 |
| Inventory Core | balances, reservation, ledger, giá vốn, reversal, đối soát | Catalog | K-04…K-05 |
| Purchasing | NCC, nhập, trả nhập, thanh toán/công nợ, hóa đơn đầu vào | Inventory Core | K-06…K-09 |
| Stock Operations | kiểm, chuyển, xuất hủy, nội bộ, sản xuất | Inventory Core | K-10…K-14 |
| Promotion Config | bốn hình thức, lịch/khách/món, version, voucher | Foundation + Catalog | P-01…P-08 |
| Pricing Engine | lựa chọn, cộng dồn, phân bổ, giải thích, quote/reserve | Promotion Config | P-09 |
| Commerce Integration | giỏ hàng, bếp, tặng, thanh toán, đổi bàn/tách gộp/hủy, rollback | Pricing + Inventory | X-01…X-05 |
| Reporting & Operations | báo cáo, import/export/in, offline, monitoring, migration | các module trên | R-01…R-04 |

## 4. Yêu cầu & Ràng buộc / Requirements & Constraints

### 4.1. Nguyên tắc kiến trúc chung

**F-01 — Phạm vi dữ liệu và danh tính.** Xác định organization/tenant/branch bằng session đã xác minh phía server. Client chọn chi nhánh là yêu cầu lựa chọn, không phải bằng chứng quyền. ALL chỉ là chế độ xem báo cáo; cấm ghi giao dịch vào ALL. SKU và customerId không được vô tình trùng giữa tổ chức. Voucher uniqueness và ngân sách toàn chuỗi nằm ở tổ chức; tồn vật lý nằm ở chi nhánh/kho. Lập bảng mapping storeCode → organizationId, branchId và kiểm thử cách ly.

**F-02 — Backend là nơi chốt nghiệp vụ.** Tách domain pure functions khỏi React/Flutter. Web/Flutter được preview, server quyết định giá, quyền, tồn, mã và hạn mức. Dùng endpoint/service đã xác thực; không chỉ ẩn nút. Xác minh Firebase Auth thực tế và migration tài khoản legacy trước khi dùng ID token. Không dùng tài khoản demo/fallback client làm quyền ghi ledger, voucher, ngân sách hoặc công nợ. Không đưa mật khẩu, service account vào source/client/log.

**F-03 — Chuẩn số học.** Tiền lưu số nguyên VND; phần trăm lưu basis points 0…10000; số lượng dùng số nguyên theo quantityScale từng đơn vị cơ bản hoặc decimal library được kiểm chứng. Conversion là rational numerator/denominator >0, không double tích lũy. Chặn NaN, Infinity, số âm không hợp lệ, vượt safe integer và precision ngoài cấu hình. Màn hình hiểu nhập dấu thập phân tiếng Việt nhưng không suy đoán nhầm 1.000 thành 1 kg. Quy tắc làm tròn phải duy nhất trên server, Web, Flutter, in và export.

**F-04 — Version và snapshot.** Tạo schemaVersion, entityVersion, expectedVersion cho cập nhật. Chứng từ giữ snapshot tên/SKU/đơn vị/quy đổi/giá vốn/công thức/quy tắc khuyến mãi và người thao tác. Version mới không sửa chứng từ đã commit. Lưu eventOccurredAt, committedAt bằng UTC epoch milliseconds; lịch chương trình dùng IANA timezone. Tên có thể đổi, identity không đổi.

**F-05 — Idempotency và commit.** Mọi command tác động tiền/tồn/quota có idempotencyKey, actor, scope, payloadHash, trạng thái, kết quả. Cùng key/cùng payload trả kết quả cũ; cùng key/khác payload bị từ chối. Transaction retry không gọi API ngoài, gửi email hoặc in. Chọn một chiến lược atomicity thực thi được với RTDB; nếu giao dịch ở nhiều aggregate thì có reservation, journal, recovery và compensation. Không gọi nhiều set riêng rồi coi là nguyên tử. Không transaction toàn root chứa lịch sử lớn. Khi atomic boundary chưa bảo đảm, không báo PAID/COMPLETED cuối cùng.

**F-06 — Sổ bất biến.** Ledger append-only cho nghiệp vụ đã commit; balance là projection có thể tái tạo. Reversal là event liên kết originalEventId, không xóa dòng cũ. Không sửa tay số tồn/giá trị/counter để che lệch. Stock initialization và import tồn cũng phải có opening/adjustment document. Audit bao gồm actor thật, quyền sử dụng, trước/sau, lý do, timestamp, sourceDevice và correlationId; log không chứa token/mật khẩu/mã voucher đầy đủ không cần thiết.

**F-07 — Phân quyền.** Permission độc lập theo action và chi nhánh; mặc định từ chối. Hỗ trợ view/create/edit/activate/archive promotion; generate/import/release/cancel/export code; override manual discount; view cost; catalog edit; supplier view/edit/payment; receipt draft/complete/cancel; return; count draft/approve; transfer send/receive/cancel; waste/internal/production complete/cancel; report/export/audit. Quyền xem giá vốn độc lập xem số lượng. Nhân viên bếp không được thấy voucher/NCC/công nợ chỉ vì xem đơn. Kiểm quyền lại khi commit và khi quyền bị thu hồi.

**F-08 — UI thực dụng.** Tiếng Việt nhất quán, tiền/số lượng phân biệt, ngày giờ rõ múi giờ; màn hình desktop quản trị và Flutter tablet/mobile phù hợp thao tác quét. Có loading/empty/error/retry, validation theo field, xác nhận bỏ draft có thay đổi, nút vô hiệu trong khi gửi, kết quả thành công sau server. Search phân trang có debounce; filter giữ lại khi quay chi tiết. Cột tiền chỉ xuất khi đủ quyền cả UI lẫn API/export. Hoạt động được bằng bàn phím và có nhãn hỗ trợ tiếp cận; không tái sử dụng logo/asset độc quyền.

### 4.2. Khuyến mãi: cấu hình và quản lý

Các trường mô tả ở P-01…P-07 dựa trên UI-P1…P4 khi được đánh dấu [UI]; các quyết định xử lý bên dưới là yêu cầu thiết kế POS Trạm [TK]. Chỉ các quy tắc đối chiếu ở §2.4 được coi là khẳng định từ tài liệu.

**P-01 — Danh sách và vòng đời.** [UI] Mã chương trình, tên, phát hành mã có/không, từ/đến, hình thức, ngân sách đã dùng, hiệu lực và trạng thái kích hoạt. Search mã/tên; filter chi nhánh, bốn hình thức, có mã, upcoming/ongoing/ended, active/inactive/all; chọn cột, sort, pagination. Tạo, xem, sao chép, sửa, bật/tắt, xóa theo điều kiện. Chi tiết có thông tin/mã/lịch sử giao dịch. [TK] Hiệu lực được tính từ lịch; activation là cờ riêng. Không ghi ended chỉ vì tắt. Sao chép tạo id/code mới, reset ngân sách/lượt/history, không sao chép voucher cũ.

**P-02 — Trường chung.** [UI] Tên bắt buộc; mã tự động hoặc nhập; ghi chú; chọn chi nhánh; kích hoạt; điều kiện thời gian, khách hàng và món; ngân sách tiền giảm tổng, tùy chọn ẩn khi đạt; giới hạn số lượt/khách; cảnh báo từ lần thứ hai; tự áp dụng khi hình thức có trường này. [TK] Có form validation cho tên/code uniqueness, start≤end, amount≥0, %≤100, cap≥0, giới hạn integer hợp lệ. Không dùng 0 đồng thời cho “không giới hạn” và “cấm dùng”: schema dùng null cho unlimited. Cờ warnRepeatedCustomer chỉ cảnh báo, maxUsesPerCustomer là hard limit; không trộn.

**P-03 — Thời gian và đối tượng.** [UI] Khoảng ngày giờ, sinh nhật theo ngày/tuần/tháng; lịch Theo thứ/Theo ngày trong tháng/Theo thứ trong tuần/Tùy chỉnh; thứ trong tuần, khung giờ, ngày loại trừ. Khách hàng bao gồm/loại trừ; món bắt buộc hoặc món loại trừ khỏi phần giảm. [TK] Tách điều kiện đủ điều kiện với selection nhận lợi ích. Match theo id/groupId, không theo text tên. Quy tắc group membership là snapshot hay động phải ghi version; đề xuất dynamic khi tạo quote, snapshot khi reserve. Điều kiện món bắt buộc không có nghĩa món đó tự được giảm. Anonymous customer không được mượn quota của khách khác; khuyến mãi sinh nhật/giới hạn cá nhân cần customerId đã liên kết hợp lệ. Thiếu guestCount thì không đoán =1 cho chương trình theo số khách.

Thiết kế time predicate theo thứ tự: active → branch → absolute range → excluded local date → birthday → recurring schedule → time window. Mọi phép so ngày dùng timezone chương trình. Với qua nửa đêm phải ghi anchor day của khung; test 23:00–02:00 và ngày loại trừ. Quy tắc “tuần sinh nhật”, ngày 29/2, ngày 31 ở tháng thiếu, inclusive endAt, order đang mở qua hết hạn là quyết định D-01/D-02, chưa được chứng minh qua UI. Không bật các lịch chưa có semantics và test rõ.

**P-04 — Giảm giá đơn hàng / BILL_DISCOUNT.** [UI] Cơ sở điều kiện là tổng tiền hàng hoặc số khách; nhiều dòng ngưỡng; giảm VND/%; giảm % có trần tiền; chọn bao gồm/loại trừ món, khách; mã chỉ xuất hiện ở hình thức này. [TK] Schema mỗi tier gồm conditionBasis, threshold, benefitMode, value, maxDiscountMoney. Define subtotalEligible riêng totalMerchandiseBeforePromotion; phụ thu/thuế/phí không tự thuộc cơ sở giảm. Chọn tier theo chính sách có version, không giảm mọi tier vì chỉ “>=” tất cả. VND tối đa bằng số tiền còn có thể giảm. Phân bổ giảm đơn xuống dòng bằng quy tắc làm tròn ở P-09.

**P-05 — Giảm/tặng món theo giá trị đơn / ORDER_VALUE_ITEM_BENEFIT.** [UI] Ngưỡng giá trị đơn, chọn món nhận, VND/% và số món tối đa, nhiều điều kiện, món bắt buộc; tặng biểu diễn bằng lợi ích phù hợp trên form. [TK] Tách qualifying subtotal khỏi eligible reward pool. Benefit 100% tạo món tặng giá thuần 0, vẫn giữ giá gốc, sourcePromotionId và chi phí kho. Nếu có nhiều món/size khác giá, phải chọn quantity nào theo benefitSelectionPolicy; mặc định đề xuất CHEAPEST_ELIGIBLE, hiển thị preview. Không mặc định thêm món vào giỏ khi khách chưa chọn; POS gợi ý chọn và kiểm tồn. Không lấy món tặng để tự đạt lại ngưỡng cùng chương trình.

**P-06 — Mua món được giảm/tặng món / BUY_X_GET_Y.** [UI] Số lượng mua và danh sách X; số lượng Y tối đa và món Y; giá trị giảm VND/%; nhiều điều kiện; checkbox “Số lượng món giảm nhân theo số lượng mua” mặc định bật trong form khảo sát. [TK] Buy selection và reward selection là hai tập khác nhau, có thể giao nhau nhưng cùng unit không được vừa là điều kiện vừa là phần thưởng trong cùng bundle. Với multiplier bật, bundleCount=floor(eligibleBuyQty/requiredBuyQty), rewardCap=bundleCount×rewardQty; tắt thì một rewardCap cho đơn. Trường hợp X=Y cần matching cụ thể, không dùng công thức đó trực tiếp mà không loại reward units. Gói chưa đủ không nhận một phần. Topping không tăng số lượng món mua. Giữ usedUnitIds/matchedBundles để giải thích và tránh lặp.

**P-07 — Đồng giá hoặc đồng giảm giá / ITEM_PRICE_RULE.** [UI] Chọn món, số lượng mua tối thiểu, dropdown Đồng giá/Giảm giá, số tiền, thêm mức giá/điều kiện. Form khảo sát không thấy checkbox tự áp dụng ở hình thức này; không ép field giống các loại khác. [TK] FIXED_PRICE thiết lập giá sau giảm cho phần đủ điều kiện; FIXED_DISCOUNT giảm số tiền/đơn vị. Fixed price không được tăng giá món vốn rẻ hơn: effectiveUnitPrice=min(currentEligibleUnitPrice,fixedPrice). Nếu muốn khác phải là thay đổi chính sách được chủ quán duyệt. Topping/size base phụ thuộc D-03. Rule không âm và tổng lợi ích không vượt tổng dòng.

**P-08 — Mã/voucher và hạn mức.** [UI] Tab bật chế độ mã, nhập từng mã/import/tạo tự động; số lượng, prefix, random length, suffix, phát hành ngay. Danh sách mã search, trạng thái tất cả/chưa phát hành/đã phát hành/đã dùng/đã hủy, thời điểm phát hành/dùng, bill; export. [TK] Voucher là phương thức truy cập một chương trình, không là công thức % thứ năm. State nội bộ DRAFT → RELEASED → RESERVED → REDEEMED; DRAFT/RELEASED có thể CANCELLED theo quyền, reserve có TTL, hết hạn giữ chỗ trở về RELEASED nếu còn hiệu lực. UI có thể gộp trạng thái nội bộ nhưng không mất trace.

Normalize uppercase trước validation; đảm bảo index code normalized ở organization, giữ tombstone không tái dùng code. Sinh mã bằng random an toàn, thử lại khi collision, chặn yêu cầu quá lớn, kiểm prefix+random+suffix. Import preview và báo row lỗi/trùng trong file/trùng hệ thống; validate toàn bộ trước commit và dùng batch protocol bảo đảm không hiển thị file nhập thành công một phần. Mốc 5.000 ở S2 là giới hạn tham chiếu; server phải chặn và UI chia file có chỉ dẫn. Không cho export mã đầy đủ nếu thiếu quyền; log che mã. Thao tác phát hành/hủy hàng loạt có preview số lượng và audit.

BudgetSpent là tiền giảm thực tế đã commit, không doanh thu; budgetReserved tách biệt. CustomerUseCount tính một lần/program/bill nếu có benefit>0, không một lần/dòng. Voucher một lần chỉ redeem một bill; idempotency cho retry. Global maxUses nếu cần bảo tồn legacy là trường riêng khỏi ngân sách tiền. Hold khóa chương trình, quota khách, code và billVersion; không chỉ increment usageCount. Cancellation/restore policy phải chốt D-04; không tự tái phát hành mã redeemed.

**P-09 — Pricing Engine duy nhất.** Đầu vào tối thiểu: organizationId, branchId, orderId, orderVersion, lineIds, product/variant ids, quantity, base/topping/size prices từ dữ liệu tin cậy, customerId, guestCount, saleChannel nếu có policy, manualDiscounts, enteredCode, serverNow, pricingPolicyVersion. Không nhận finalTotal của client làm căn cứ.

Trả về PriceQuote có expiresAt, inputHash, catalog/promo versions, grossMoney, eligibleBase, lineBenefits, billBenefits, allocatedDiscounts, totalDiscountMoney, netMoney, appliedCampaignIds, selectedTierIds, rewardChoices, quotaPreview, stockWarnings và reasons cho chương trình không áp dụng. Lý do tiếng Việt phục vụ thu ngân; mã lỗi ổn định phục vụ code. Preview không chiếm quota. Reserve chỉ nhận quote còn hợp lệ và orderVersion chưa đổi; sửa giỏ làm quote cũ hết giá trị.

Pipeline thiết kế đề xuất, phải chốt D-03/D-05: tải giá gốc → định giá món/đồng giá → item/bundle benefits → bill benefits → manual discount được cấp quyền → thuế/phụ thu theo policy hiện có. Không mặc định thứ tự này là hành vi KiotViet. Mỗi bước nhận remainingEligibleMoney và remainingUnitCapacity; không giảm âm, không hưởng hai lần trên cùng phần cấm cộng dồn. Cộng dồn có mode DISABLED/ENABLED và conflict groups rõ ràng, sorting stable theo priority rồi createdAt/id. Điều kiện tier xét trên base được đóng băng, không recalculation tạo vòng lặp.

Ở DISABLED, nếu chọn parity S1 thì chọn BILL_DISCOUNT có lợi ích tiền thực tính lớn nhất; tie-break deterministic. “Chương trình đầu tiên” ở trường hợp không có giảm bill chưa có bằng chứng thứ tự: chốt D-05 trước acceptance parity. Không âm thầm đổi thành “tối ưu mọi tổ hợp” vì đó là chính sách khác. Ở ENABLED, có chiến lược ALL_QUALIFIED_TIERS hay BEST_TIER và guard chống trùng; form phải ghi rõ để chủ quán hiểu.

Phân bổ giảm bill: dùng remaining eligible line money làm trọng số; lấy floor phần chia, phân bổ đồng còn dư theo largest remainder, tie-break lineId. Tổng phân bổ đúng số giảm, từng dòng không âm. Không nhân totalLineDiscount lần nữa với quantity. Ví dụ 3 dòng cùng trọng số, giảm 10đ → 4/3/3 theo tie-break; báo cáo/in/hoàn tiền sử dụng snapshot đó. Không dùng giá trị floating rải đều rồi làm tròn độc lập.

### 4.3. Kho hàng: danh mục và lõi tồn kho

**K-01 — Danh mục hàng và liên kết thực đơn.** [UI-K2/K3] Có nguyên liệu, công cụ dụng cụ, hàng bán, topping; code, tên, nhóm, brand, ảnh, vị trí, khối lượng, mô tả, chi nhánh dùng, trackStock, tồn đầu, min/max, active. [TK] Loại nghiệp vụ riêng: RAW_MATERIAL, TOOL, DIRECT_SALE, MADE_TO_ORDER, MANUFACTURED, TOPPING, SERVICE. managementGroup khác productType. Món không quản lý tồn không tự tạo balance. Service không trừ kho. Made-to-order trừ thành phần, không đồng thời trừ tồn món giả. Manufactured bán thì trừ thành phẩm, không trừ lại nguyên liệu đã tiêu hao lúc sản xuất.

Một identity vật lý dùng chung tham chiếu danh mục kho và menu; nếu menu hiện có productId integer, giữ alias mapping sang id mới. Không tạo hai SKU tồn độc lập cho cùng chai nước chỉ vì ở hai menu. Giá bán khác giá vốn. Soft-discontinue ngăn dùng mới, giữ chứng từ; xóa chỉ hàng chưa được tham chiếu và qua kiểm server. Tạo nhóm/brand/location qua hộp thoại có quyền, không hard-code theo tên UI tham chiếu. Min≥0, max≥min; ngưỡng theo đơn vị cơ bản; tồn âm theo policy riêng, không chặn bằng min.

**K-02 — Đơn vị, biến thể và import.** Base unit một loại đo lường; bán/nhập theo đơn vị chuyển đổi có quy tắc. Ví dụ 1kg=1.000g; carton=24chai là quy đổi riêng SKU. Không chuyển kg↔lít không có hệ số được khai báo cho hàng đó. Size là variant ảnh hưởng công thức/giá; attribute combinatorial tạo SKU riêng nếu quản lý riêng. Topping là modifier hoặc SKU có tiêu hao, giữ identity rõ. Barcode unique theo scope; scan quy đổi về đúng variant/unit. Không đổi base unit/conversion retroactively khi đã giao dịch; version và migration có kiểm soát.

Excel: cung cấp template đúng loại hàng/version; preview create/update, line number, missing/duplicate IDs, units, price, trackStock, openingStock, min/max. Import sửa tồn tạo adjustment event, không set balance. File lỗi không biến thành thành công rỗng; template ghi rõ blank=không đổi hay null, không ghi 0 ngầm. Xử lý sheet/type mismatch, CSV formula injection khi export, file quá lớn, encoding tiếng Việt, lỗi đọc và permission. Image upload nếu bổ sung dùng storage phù hợp, không làm phình root RTDB bằng nhiều base64 lớn.

**K-03 — Công thức/định mức.** Mỗi recipeVersion có output variant, outputQuantity/baseUnit, ingredient item/variant/unit/quantity, wasteRate nếu đã chốt, effectiveFrom, branch override nếu cần. Đổi size/topping chọn recipe đúng; không cộng cả công thức tổng và công thức từng thành phần hai lần. Chặn cycle A→B→A, tự tham chiếu, ingredient discontinued hoặc conversion thiếu; đặt giới hạn chiều sâu. Thành phẩm tồn kho là leaf khi bán, công thức thành phẩm chỉ dùng ở production command. Cho preview nguyên liệu và chi phí; lưu recipe snapshot vào consumption event. Phân biệt nguyên liệu thiếu với không có công thức.

**K-04 — Balances, reservation, ledger.** Balance theo branch/warehouse + itemVariant gồm onHandBaseQty, reservedBaseQty, availableBaseQty=onHand-reserved, inventoryValueMoney, averageCostScaled, version, lastEventSeq. In-transit là vị trí riêng hoặc ledger state riêng không bán được. Khách đặt trong UI-K4 là cột tham chiếu; cơ chế reservation dưới đây là thiết kế POS Trạm. Cấm reserved<0, reserve vượt available khi không cho âm; riêng policy cho âm phải yêu cầu quyền/lý do và cảnh báo.

StockEvent gồm eventId, commandId, documentId/type/lineId, organizationId, branchId, warehouseId, itemVariantId, qtyDeltaBase, valueDeltaMoney, unitCostSnapshot, conversionSnapshot, occurredAt, committedAt, actorId, correlationId, reversalOf, sequence. Có event điều chỉnh giá vốn với qtyDelta=0 khi nghiệp vụ được hỗ trợ; không giấu trong thay giá catalog. Mỗi event unique theo document-line-effect. Số dư thẻ kho phải liên tục, có openingBalance và filters; không tính running balance từ chỉ các dòng đang hiện của trang hiện tại.

**K-05 — Giá vốn và đối soát.** Đề xuất moving weighted average cho nguyên liệu/hàng thường; có mode FIXED nếu chốt. Lưu cả quantity và inventoryValue để không cộng sai tiền vì làm tròn unit cost. Receipt tăng giá trị theo giá nhập ròng + chi phí phân bổ được chốt; VAT có vào giá vốn không tùy policy, không suy đoán pháp lý. Sale/waste/internal dùng cost snapshot tại thời điểm commit. Returns giữ original cost/link nếu theo phiếu nhập; trường hợp trả nhanh có cost policy riêng. Khi quantity=0, value còn lẻ cần adjustment rõ ràng.

Ví dụ giả: 10kg giá vốn 100.000đ/kg, nhập 10kg giá 120.000đ/kg, không phụ phí → qty20kg, value2.200.000đ, average110.000đ/kg. Xuất2kg → qty18kg, value1.980.000đ, event value−220.000đ. Reverse event phải trả đúng snapshot value đã xuất, không lấy giá vốn mới. Negative stock/backdated receipt/cancel receipt sau khi đã xuất phải có policy D-06; chưa chốt thì chặn nghiệp vụ nguy hiểm có giải thích. Đối soát quantity/value theo ledger, báo chênh lệch, chạy repair projection có audit trên môi trường được phép.

### 4.4. Mua hàng và nhà cung cấp

Các biểu mẫu chi tiết sau là yêu cầu thiết kế, đối chiếu S4/S5/S11/S12 và UI đã xem; không khẳng định mọi field đã hiện trên gian hàng khảo sát.

**K-06 — Nhà cung cấp và công nợ.** List/search/filter trạng thái; code/name, phone/email, taxId/address/contact, group/tags, note, enabledBranches, active. Có filter nhóm, tổng mua, khoảng thời gian và nợ hiện tại theo UI-K7. Địa chỉ tách các cấp hành chính khi phù hợp dữ liệu hiện tại; không hard-code danh sách địa giới từ ảnh. Validate tên bắt buộc; quy tắc bắt buộc phone/email cần xác minh; taxId/phone trùng báo rõ thay vì tự gộp. UI có CCCD: chỉ đưa vào phạm vi khi có nhu cầu, quyền và chính sách lưu phù hợp; không bắt người dùng nhập tùy tiện. Tạo/sửa/ngừng dùng, import/export; lịch sử mua/trả, ledger công nợ, payment detail. Scope NCC master toàn tổ chức, debt theo branch hoặc toàn chuỗi phải chốt D-07. Ledger định nghĩa debt>0 là quán còn phải trả; openingDebt là chứng từ đầu kỳ. Payment nhiều phương thức có allocation vào receipt, không chỉ trừ một field debt; credit/prepayment là số riêng có liên kết.

**K-07 — Nhập hàng.** Form mã tự động, branch/warehouse, supplier, người tạo/người nhập, occurredAt, số/ngày hóa đơn đầu vào, note; search/scan/select group/import lines. Dòng gồm itemVariant, purchaseUnit, conversion, qty>0, unitPrice≥0, lineDiscount VND/%, tax theo cấu hình, lineNet và cost allocation. Cho nhiều dòng cùng SKU nếu khác mức giá; UI không gộp mất hàng tặng nhập 0đ. Chọn chính sách giới hạn mức giá tương thích S4. Global discount không giảm âm; tổng supplierPayable và inventoryReceiptValue tách biệt nếu thuế/phụ phí khác nhau.

State DRAFT → COMPLETED hoặc CANCELLED. Lưu draft không tăng tồn/debt/payment. Complete khóa version, tính ròng, tạo stock+supplier ledger+payment nếu có, không báo xong khi một phần thất bại. Thanh toán 0/một phần/toàn bộ, overpay cần policy prepayment. Completed không sửa qty/cost trong place; cập nhật metadata trong allowlist và audit. Cancel tạo reversal, xử lý các receipt return/stock consumption/payment dependencies, preview tác động và chặn theo D-06. Có print/export/duplicate, danh sách filtered, chi tiết, từ receipt mở tạo return và in barcode. Copy reset trạng thái/tiền thanh toán/liên kết ngoại, không cộng tồn.

**K-08 — Trả hàng nhập.** Tạo từ receipt hoặc trả nhanh; supplier/branch phải đúng nguồn. Reference return kiểm qty remainingReturnable=received−priorCompletedReturns; giữ original line cost, conversion và discounts allocated. Qty>0 và không vượt returnable; còn đủ hàng vật lý nếu policy cấm âm. Chọn credit against debt hoặc supplier cash refund; tránh vừa giảm nợ vừa ghi tiền thu hai lần. Draft không tác động. Complete giảm stock/value, giảm debt hoặc tăng supplier credit, ghi payment/refund allocation. Cancel reverse liên kết và kiểm tiền đã đối trừ tiếp. History không xóa khi hủy. Returned items bị hỏng nhưng đã xuất hủy không thể trả lại lần nữa không có điều chỉnh vật lý phù hợp.

**K-09 — Hóa đơn đầu vào.** List/search/date/supplier/source/status; raw invoice immutable, matching supplier by trusted identifiers, line mappings quantity/unit/tax, linked receipt/expense, unmatched/conflict/error states. Idempotency dựa externalProvider+externalInvoiceId+version; sync retry không tạo hai receipt. Nhận invoice không tự tăng kho: tạo draft rồi user hoàn thành. Import/link thủ công nếu chưa có connector. Hợp đồng adapter hỗ trợ fetchPage/syncCursor/normalize; credentials server-only, không yêu cầu paste mật khẩu thuế vào client. Real integration cần tên provider, API/schema, môi trường sandbox và quyền do chủ dự án cung cấp; báo BLOCKED phần kết nối nếu thiếu, triển khai phần nội bộ có thật. Không gắn nhãn live sync đã nghiệm thu bằng mock.

### 4.5. Kiểm kho, chuyển hàng, xuất và sản xuất

**K-10 — Kiểm kho.** List search mã/note/items, filter branch/time/status; form scan/search/group/import; tabs all/match/different/notCounted; columns bookQty snapshot, actualQty nullable, deltaQty, unitCost snapshot, deltaValue. Null actual khác 0. Không ép hàng chưa kiểm =0. Có count session snapshot time/sequence; nhân viên nhập thực tế, supervisor complete nếu có quyền. Draft lưu được/reopen/gộp draft cùng scope, duplicate item conflict phải chọn nguồn hoặc cộng theo quy tắc minh thị; không cân bằng hai lần.

Concurrent policy bắt buộc: nếu đếm book10, actual8 ở seq100, sau đó bán2 trước finalize, apply adjustment−2 lên current8 →6; không overwrite current8 thành actual8. Nếu thực tế được đếm sau giao dịch bán thì cập nhật count cut-off theo hàng hoặc bắt đếm lại. UI giải thích giao dịch phát sinh trong lúc kiểm. Complete tạo count adjustment events, state BALANCED; cancel reverse đúng delta, không đặt lại stock cũ. Món chế biến có công thức không tự count nguyên liệu bằng số lượng món; chọn SKU vật lý. Với xuất hủy phát sinh khi kiểm, tạo draft waste liên kết rồi hoàn thành riêng, tránh trừ cả count delta và waste lần hai.

**K-11 — Chuyển hàng.** Một document có source/destination branch+warehouse khác nhau, sender/receiver, lines/base qty/cost snapshot, note, thời điểm gửi/nhận. State DRAFT → IN_TRANSIT → RECEIVED; DRAFT cancel không ảnh hưởng, IN_TRANSIT cancel hoàn nguồn theo event, RECEIVED reverse phải kiểm đích và quyền. Send trừ onHand source và đưa qty/value vào inTransit; receive giảm inTransit, tăng target. Không tăng target ngay khi tạo draft, không coi source giảm là mất mát. Cross-tenant chuyển bị chặn.

Receive form actualQty, varianceReason, receiver; ≤sent theo baseline. Policy parity tham chiếu S7 đưa thiếu về nguồn bằng reversal riêng; phải chốt D-08 vì thực tế thiếu hàng có thể là mất trong vận chuyển. Không silently hồi kho nguồn khi không có xác nhận. Đề xuất alternative TRANSIT_VARIANCE ghi loss/damage sau xác nhận là mở rộng được ghi rõ. Nhận từng phần nhiều lần chỉ triển khai nếu được chọn; có remainingQty, unique receiveId và trạng thái PARTIALLY_RECEIVED, không giả đây là chức năng đã thấy. Preserve transferValue toàn hệ thống; average cost đích tính đúng khi nhập vào tồn sẵn.

**K-12 — Xuất hủy.** Form branch/warehouse, mã/time/actor, reason (hư/hết hạn/vỡ/sai pha chế/khác), lines qty, cost snapshot, note/attachment optional. Draft không trừ; completed trừ qty/value và ghi expense classification; copy/in/export/search/filter. Cancel đảo đúng event, chặn trùng; completed chỉ sửa metadata allowlist. Không dùng phiếu hủy để che sai count hay sửa bill; cần liên kết nguồn và lý do. Lô/hạn dùng chưa xác minh nên reason hết hạn không đồng nghĩa hệ thống FEFO đã có.

**K-13 — Xuất dùng nội bộ.** Tách document khỏi waste/sale/gift; purpose (nhân viên, vệ sinh, thử món, sử dụng dụng cụ…), department/actor, lines, amount theo cost, note. Draft/complete/cancel dùng ledger chuẩn. Dụng cụ dùng nhiều lần không tự chuyển thành tài sản/khấu hao kế toán: nghiệp vụ asset lifecycle là phần riêng chưa nằm scope. Quà khuyến mãi xuất qua sale-linked event, không bắt user tạo thêm internal document gây trừ đôi.

**K-14 — Sản xuất và chế biến.** Form chọn thành phẩm có recipe, planned/outputQty, recipeVersion, preview required ingredients/available, actual ingredient quantities nếu được chọn, actor/time/note. Draft không ảnh hưởng; complete trừ từng nguyên liệu và tăng output thành phẩm trong cùng nghiệp vụ có recovery. Cost output=totalIngredientCost+approvedAdditionalProductionCost; yield/waste không chia 0; nếu thêm công lao động/overhead phải chốt policy riêng, không bịa từ KiotViet. Thiếu nguyên liệu chặn theo negative-stock policy; màu cảnh báo không thay server validation.

Cancel production phải xử lý finished goods đã bán/chuyển/tiêu hao, không cộng trả nguyên liệu trong khi finished goods chưa thu hồi. Completed không sửa recipe/qty in place; sửa time/note theo quyền, dữ liệu sổ vẫn lưu committedAt. Bảng kê nguyên liệu tổng hợp và chi tiết theo nhiều phiếu; chi tiết dẫn tới stock events. Recipe DAG và manufactured-as-ingredient phải chạy đúng không tiêu hao nguyên liệu cấp trước lần nữa khi bán món sau.

### 4.6. Tích hợp POS, bếp và vòng đời hóa đơn

**X-01 — Giỏ hàng và áp dụng.** POS hiển thị chương trình đủ điều kiện, auto apply khi policy cho phép, mã nhập tay, lý do không hợp lệ, preview tiền giảm, gift selection và warning lặp khách. Thay qty/size/topping/khách/guest/chi nhánh/kênh làm quote cũ invalid. Ô manualDiscount không thay thế selection program; có quyền/giới hạn/lý do riêng. Gift lines có sourcePromotionId và parentBundleId, không cho xóa điều kiện mua mà giữ quà. Giá 0 vẫn có stock/cost và history. Không giảm topping nếu policy chỉ giảm món gốc.

**X-02 — Thời điểm tiêu hao.** Quyết định D-09: direct-sale có thể reserve khi xác nhận, consume khi pay; made-to-order nên consume khi bếp xác nhận chế biến nếu quán cần phản ánh thực tế, hoặc ở pay theo policy được chọn. Đây là thiết kế chưa xác minh timing KiotViet. Mỗi line có consumptionState và consumedEventIds; pay không consume lại phần bếp đã trừ. Hủy trước chế biến release reservation; hủy sau chế biến không tự hoàn nguyên liệu, chuyển cost sang waste hoặc cancellation loss có chứng từ. Món không chế biến đã trả lại vật lý có flag restock và supervisor approval. Đổi recipe giữa mở đơn và gửi bếp giữ snapshot đúng thời điểm đã chốt.

**X-03 — Thanh toán đồng thời.** Luồng yêu cầu: validate session/branch/orderVersion → quote server → reserve voucher/budget/customer quota/stock → payment attempt theo phương thức → commit bill + promo redemption + stock events + supplier-independent financial event + outbox → trả receipt → projection history/report/table và in theo kết quả. Thiết kế crash recovery cho từng bước. Không giữ transaction DB khi gọi payment provider. CASH không có gateway nhưng vẫn cần commit. TRANSFER không suy ra nhận tiền chỉ vì hiện QR; giữ workflow hiện tại có xác nhận được cấp quyền hoặc callback tin cậy nếu có tích hợp.

Hai thiết bị cùng pay một bill: một kết quả commit, thiết bị kia nhận ALREADY_COMMITTED với receipt gốc; không tạo billId ngẫu nhiên mới mỗi retry. Budget/coupon race: chỉ số giao dịch trong giới hạn được chấp nhận; phần còn lại được quote lại với lời giải thích. Tác vụ in lỗi không rollback khoản thanh toán đã commit; reprint audit và giữ receipt number. Projection history lỗi hiển thị “đã thanh toán, đang đồng bộ” và worker retry; không trả success giả trước authoritative commit.

**X-04 — Đổi bàn, tách/gộp và chỉnh hóa đơn.** Identity order/line không bị mất khi chuyển bàn. Tách/gộp trước commit phải re-evaluate conditions, release/rebind holds, phân bổ line quantities và consumption events; cấm copy gift/voucher sang hai bill. Không tăng usage do chuyển bàn. Đơn đã paid chỉnh metadata theo quyền; thay tiền/tồn bằng adjustment document có trace. Không xóa history để “hủy đơn”. Existing report/export/receipt printer dùng normalized discount snapshots; tránh discount theo dòng bị nhân qty lần hai.

**X-05 — Hủy, trả và khôi phục quota.** Phân biệt cancel open order, void paid bill, sales return, remove line, supplier return. Baseline parity S1 chặn sales return đối với hóa đơn có promotion; thông báo rõ, không chặn mọi hủy mở đơn. Nếu chủ quán muốn hỗ trợ hoàn một phần thì coi là extension D-10 và thiết kế reverse allocated discount/gift eligibility/quota/payment/restock, kiểm thử riêng trước bật. Restore spent budget/usage/code khi void là D-04, không tự suy ra. Mọi reversal idempotent, link original receipt; báo cáo có gross issuance, committed spend và reversal tách biệt.

### 4.7. Hợp đồng dữ liệu đề xuất

Đây là logical schema, không là đường dẫn sẵn có trong app. Sau khi kiểm tenant mapping và atomic boundary mới quyết định layout RTDB vật lý. Không copy cây dưới đây rồi bỏ qua indexes/rules/lifecycle.

| Entity | Trường tối thiểu ngoài id/schemaVersion/orgId/version | Invariant |
|---|---|---|
| BranchMembership | userId, branchIds, permissions, active, updatedAt | server xác minh; client không tự cấp |
| CatalogItem/Variant | legacyAliases, sku, name, kind, managementGroup, groupIds, brandId, attributes, baseUnitId, quantityScale, trackStock, enabledBranches, min/max, status | không đổi identity/conversion chứng từ cũ |
| UnitConversion | itemVariantId, unitId, numerator, denominator, version, active | >0; đo lường tương thích |
| RecipeVersion | outputVariantId, outputQty, ingredients[], branchScope, effectiveFrom, status | acyclic; quantity>0 |
| CampaignVersion | programCode, name, type, schedule, scope, customerPredicate, itemPredicate, tiers[], stackingPolicy, autoApplyPolicy, budgetMoney, perCustomerLimit, hasCodes, active | released version bất biến khi referenced |
| CampaignCounters | spentMoney, reservedMoney, committedUseCount, reservedUseCount, version | spent+reserved≤budget nếu hard limit |
| CustomerCampaignCounter | customerId, campaignId, usedCount, heldCount | used+held≤limit; anonymous policy |
| Voucher | normalizedCode/indexKey, campaignId, state, releaseAt, holdId, redeemedBillId, tombstone | chỉ một redeem; uniqueness không mất khi archive |
| PriceQuote/Hold | orderId/version, inputHash, expiresAt, policyVersion, benefits, allocations, snapshots, state | quote không trừ quota; hold có release/commit |
| StockBalance | branchId, warehouseId, variantId, onHand, reserved, value, costScale, lastSeq | ledger tái tạo được; availability đúng |
| StockEvent | các trường K-04, reason, snapshotRefs | unique effect; reversal liên kết |
| Supplier | supplierCode, contact fields, status, branchScope | referenced không hard-delete |
| SupplierLedger/Payment | supplierId, branchId, type, amount, referenceDocument, allocations, reversedBy | cộng sổ đúng debt/credit/payment |
| InventoryDocument | docType, status, scope, code, occurredAt, actor, lines[], totals, sourceRefs, committedEventIds | draft không ảnh hưởng; completed không sửa tiền/lượng |
| InputInvoice | providerId, externalId, rawVersion, lineMappings, supplierMapping, linkedDocs, syncState | unique source; link không auto complete |
| BillSnapshot | order identity, lineSnapshots, promo allocations, codeRefsMasked, consumptionRefs, totals, pricingVersion, paymentState | đủ tái in/tái báo cáo dù catalog đổi |
| CommandJournal/Outbox | idempotencyKey, payloadHash, actor, state, aggregateRefs, retries, lastError, result | retry không trùng effect |
| AuditEvent | actorId, action, entity, reason, before/after summaries, correlationId, serverTime | append-only, scope protected |

Bảo toàn /stores/{storeCode} trong migration. Có thể thêm /organizations/{orgId} cho master/index toàn chuỗi sau khi chứng minh mapping. Read models theo branch, /byStatus, /byDate, /bySupplier, /byCampaign cần thiết kế và .indexOn theo query thực tế. Không subscribe onValue toàn /stores hoặc /organizations rồi tải mọi history để filter client. Lịch sử append-only phải có cursor/time range, giới hạn page, tổng hợp nền và version. Money/quota/ledger paths deny direct client writes; read rules theo membership thật. Data validation server đầy đủ, rules không thay domain validation.

RTDB không có transaction tùy ý trải mọi path rời rạc. Chọn common ancestor nhỏ chứa state cần chốt hoặc command orchestration với holds/compensation và durable journal; đo contention. Multipath update dùng để commit writes đã được bảo vệ, không thay bước compare-and-check version/quota. Nếu dùng saga: COMMITTING chưa phải PAID; recovery phải có chủ sở hữu lease và fencing token để worker cũ không tiếp tục commit. Batch nhiều dòng kho bị fail giữa chừng không được bỏ qua; inventory doc có planned/applied/reversed effects và tái lập được.

### 4.8. Hợp đồng API/domain commands

REST path là đề xuất; giữ framework hiện có. Mọi mutation có authorization, scope, expectedVersion, idempotencyKey khi có effect; response chứa authoritativeVersion, correlationId và result. Không dùng GET gây mutation.

| Command/query | Nội dung và kết quả phải có |
|---|---|
| list/get/create/update/copy/activate/archiveCampaign | filters/cursor; immutable referenced conditions; version conflict |
| validateCampaign + simulateCampaign | lỗi từng field; fake scenario rõ nhãn, không tạo usage |
| import/generate/release/cancel/exportCodes | jobId, preview counts, row errors, permission, immutable uniqueness |
| quoteOrder | giá server, reasons, allocations, stock/quota preview, expiry |
| reserveQuote / releaseHold | atomically validate/recheck; bound bill+version; release idempotent |
| commitCheckout / getCommandResult | payment state/receipt, stock+promo effect refs; retry result gốc |
| voidBill / returnBill nếu bật | preview dependencies; policy/rule violations; original refs |
| list/get/upsertItem / recipe/version / importCatalog | validation units/recipe cycles; no direct balance writes |
| list/getStock / listStockLedger | opening/running/closing, cursor, asOf, cost permission |
| create/updateDraft/complete/cancelInventoryDocument | type-specific validation, effects, dependency blockers |
| sendTransfer / receiveTransfer | scope rights source/target; actual/variance preview; no overreceive |
| supplier statement / recordPayment / reversePayment | debt/credit/allocation và expectedVersion |
| sync/list/match/linkInputInvoice | pagination/cursor, duplicate-safe, unmatched errors, connector availability |
| reports/exportJobs/printSnapshot | filters, asOf, schemaVersion, permissions, immutable totals |

Error enums tối thiểu: UNAUTHENTICATED, FORBIDDEN, TENANT_MISMATCH, BRANCH_NOT_ALLOWED, VALIDATION_ERROR, VERSION_CONFLICT, QUOTE_EXPIRED, PRICE_CHANGED, NOT_ELIGIBLE, PROMOTION_INACTIVE, OUTSIDE_SCHEDULE, CUSTOMER_REQUIRED, GUEST_COUNT_REQUIRED, BUDGET_EXCEEDED, CUSTOMER_LIMIT_REACHED, CODE_INVALID, CODE_NOT_RELEASED, CODE_RESERVED, CODE_REDEEMED, CODE_CANCELLED, INSUFFICIENT_STOCK, UNIT_CONVERSION_MISSING, RECIPE_CYCLE, DOCUMENT_STATE_INVALID, DEPENDENCY_EXISTS, RETURN_NOT_SUPPORTED_WITH_PROMOTION, RETURN_QTY_EXCEEDED, ALREADY_COMMITTED, IDEMPOTENCY_CONFLICT, SYNC_PENDING, CONNECTOR_UNAVAILABLE. Không trả stacktrace/secrets; frontend hiển thị giải pháp phù hợp, giữ draft khi lỗi.

### 4.9. Báo cáo, vận hành, offline và migration

**R-01 — Báo cáo nhất quán.** Promotion report theo program/code/branch/customer/time: bill count, actual benefit, budget spent/reserved/remaining, redeemed/cancelled/unused codes, gross vs net revenue, reversals. Inventory: tồn theo branch/SKU/unit, available/reserved/inTransit, low/high stock, inventoryValue, stockcard, tổng/chi tiết nhập-xuất-tồn, waste/internal, production yields/cost, transfer variance. Supplier: mua/trả, phải trả/credit/prepayment, thanh toán phân bổ và overdue nếu có dueDate. Mỗi số có định nghĩa, timezone, asOf, source event; drilldown tới chứng từ, không lấy “discountAmount * quantity” chưa rõ nghĩa làm chuẩn.

**R-02 — Import, export, in.** Export theo đúng filters và quyền, không chỉ trang hiện tại; file có đơn vị, time range, branch và totals, masked code nếu không có quyền. Print nhận document/bill snapshot, template tiếng Việt có trạng thái draft/cancel rõ; K80/A4 tùy capability máy in, không claim phần cứng đã kiểm chứng khi chưa có thiết bị. Reprint không tăng usage/tồn. Import job có preview/validate/commit/errors/retry; không bật import overwrite root.

**R-03 — Offline và quan sát.** Khi offline cho xem cache và chỉnh draft nếu hệ hiện tại hỗ trợ, đánh dấu stale/lastSyncAt. Không tự redeem voucher một lần, quota toàn chuỗi hay complete kho khi không có server. Offline checkout chỉ được bật với cơ chế allowance/escrow và sync conflict policy được duyệt; nếu chưa có thì pending payment và giải thích, không PAID giả. Queue có idempotency persist phù hợp platform; restart không tạo key mới. Theo dõi failed commands, pending ages, projection lag, quota contention, reservation leaks, stock/value drift, denied permission và connector failures. Không log mã đầy đủ hay nội dung bí mật. Runbook chỉ rõ retry/reconcile/repair có quyền, không thao tác DB thủ công tùy ý.

**R-04 — Migration và rollout.** Đọc code hiện tại lại trước sửa vì baseline có thay đổi người dùng. Lập mapping old promotion→new campaign theo từng type/value/code/cap/time/category/product; ambiguity VOUCHER phải báo dữ liệu cần phân loại. Backfill billed discounts/stock opening không bịa lịch sử; thiếu thì opening document có nhãn migration. Dry-run counts/sums/ids; backup/recovery do người có quyền; không xuất credentials. Migrate schema additive, adapters đọc cả phiên bản nhưng writer authoritative một nguồn. Feature flags riêng promoEngineV2/inventoryV1, staging shadow quote không tạo effects, pilot branch, so totals and stock, rollback UI mà giữ committed ledger. Không rollback bằng xóa ledger/mã redeemed.

### 4.10. Các quyết định cần chốt trước nghiệm thu chức năng liên quan

| ID | Câu hỏi quyết định | Mặc định đề xuất / giới hạn | Phần bị ảnh hưởng |
|---|---|---|---|
| D-01 | Lịch tuần/tháng sinh nhật, 29/2, ngày 31, overnight tính ngày nào? | Không bịa parity; chỉ bật lịch có semantics đã duyệt | P-03 |
| D-02 | Đơn mở trước sửa/tắt/hết hạn được giữ benefit đến lúc nào? | Snapshot version; server hold có TTL, grandfather phải là policy minh thị | P-03/P-09/X-03 |
| D-03 | Giá size/topping, ngưỡng tổng, manual discount, thuế/phụ thu tính trước/sau thế nào? | Base món và additions tách, không auto giảm additions; chốt price waterfall | P-04…P-09 |
| D-04 | Hủy paid bill có hoàn budget/lượt và tái dùng voucher không? | Chưa tự hồi redeemed code; reserve hết hạn được release | P-08/X-05 |
| D-05 | Cộng dồn các tier, chọn Y và thứ tự “đầu tiên” khi không có bill discount? | BEST_TIER, CHEAPEST_ELIGIBLE và stable priority là đề xuất, không parity đã chứng minh | P-05/P-06/P-09 |
| D-06 | Cho âm tồn, backdate, giá vốn trung bình/cố định và hủy nhập đã dùng thế nào? | Chặn âm/backdate tác động kỳ đã khóa; average minh họa cần duyệt | K-05/K-07/K-14 |
| D-07 | Tổ chức/chi nhánh, công nợ/khách/SKU/voucher chia sẻ scope nào? | Isolate tenant, xác minh mapping trước dữ liệu crossbranch | Foundation/K-06 |
| D-08 | Nhận thiếu là trả nguồn hay hao hụt vận chuyển? Có nhận nhiều lần? | Chọn policy có UI xác nhận, không tự hồi vật lý | K-11 |
| D-09 | Món chế biến trừ nguyên liệu lúc gửi bếp, xác nhận làm hay pay? | Consume một lần tại sự kiện được policy chọn; hủy cooked cần waste | X-02 |
| D-10 | Có cần trả một phần hóa đơn promotion vượt parity tham chiếu? | Baseline chặn sales return có promotion, extension cần spec riêng | X-05 |
| D-11 | Backend deployment/auth và nhà cung cấp invoice/gateway thực tế là gì? | Xác minh, không dùng demo auth cho tài chính/kho; connector missing báo blocked | F-02/K-09/X-03 |
| D-12 | Tải mục tiêu, offline duration, roles, print hardware và subwarehouse? | Thu số liệu; đề xuất benchmark staging có nhãn, không bịa SLA đã được yêu cầu | R-02/R-03 |

Không dùng bảng này để bỏ qua toàn bộ công việc. Hoàn thành module độc lập, ghi decisions vào ADR; chỉ chặn phần có kết quả phụ thuộc quyết định chưa có. Không tuyên bố parity 100% khi D-01…D-12 chưa chốt.

### 4.11. Ma trận nghiệm thu bắt buộc

Mỗi test có fixture giả, setup, command/UI steps, expected money/qty/state, expected ledger/audit và kiểm Web/Flutter nếu có. Các kết quả cụ thể dưới đây áp dụng policy đã ghi trong test; không dùng để tự quyết D-03/D-05. Kiểm concurrency bằng backend/emulator integration, không chỉ unit mock.

| Test | Kịch bản và kỳ vọng | Yêu cầu |
|---|---|---|
| A-01 | User chi nhánh A đọc/ghi/export chi nhánh B không có quyền; sửa scope trong request vẫn bị chặn | F-01/F-02/F-07 |
| A-02 | Client role local bị đổi; endpoint vẫn từ chối; thu hồi quyền trong lúc form mở bị kiểm lại ở commit | F-02/F-07 |
| A-03 | Input NaN/âm/overprecision/%>100/conversion0 hoặc date range sai bị field errors; không tạo effects | F-03/F-08 |
| A-04 | Đồng thời edit cùng version: một commit, một VERSION_CONFLICT, không mất thay đổi | F-04 |
| A-05 | Cùng key gọi 20 lần và sau restart: một effect; cùng key khác payload IDEMPOTENCY_CONFLICT | F-05/F-06 |
| A-06 | Tạo/sửa/copy chương trình, lọc upcoming/ended và inactive độc lập; copy reset counters/codes | P-01/P-02 |
| A-07 | Sai branch/customer/guest/lịch và ngày loại trừ trả đúng reason; biên timezone/overnight theo D-01 | P-03 |
| A-08 | Bill 100.000, giảm 30%, cap 20.000 →20.000, net80.000; fixed 200.000 →100.000 nếu đủ điều kiện | P-04/P-09 |
| A-09 | Bill theo guestCount thiếu dữ liệu →GUEST_COUNT_REQUIRED; tăng guests đúng ngưỡng mở benefit | P-04 |
| A-10 | Đơn chưa đạt ngưỡng không có quà; đạt 200.000 được tặng 1 Y, Y ghi giá gốc/net 0 và consume/cost 1 Y | P-05/X-01 |
| A-11 | Buy2 X get1 Y, buy5 X, multiplier on →cap2 Y; off→cap1 Y; không đủ X không thưởng | P-06 |
| A-12 | X=Y, buy 2 get 1 với tổng3 unit →1reward, không phải cùng unit vừa buy vừa reward; tổng2 unit chưa đủ bundle | P-06 |
| A-13 | Giá gốc30.000, fixedprice20.000 →giảm 10.000/unit; món15.000 không bị nâng lên20.000 | P-07 |
| A-14 | Mã lower-case normalize; invalid length/space, duplicate deleted code, unreleased/cancelled code bị chặn | P-08 |
| A-15 | Import file có một dòng lỗi không phát hành/import thành công phần còn lại; báo row cụ thể; >limit bị chặn | P-08 |
| A-16 | Hai thu ngân redeem cùng one-use code đồng thời →một receipt có lợi ích; bên kia nhận conflict/requote | P-08/X-03 |
| A-17 | Budget 10.000 còn lại, hai bill mỗi lợi ích 10.000 đồng thời →một được dùng; per-customer limit 1 cũng tương tự | P-08 |
| A-18 | Hold hết TTL/cancel release quota/stock một lần; commit retry không cộng lại; redeemed restoration theo D-04 | P-08/X-05 |
| A-19 | Hai bill discount giảm 10.000 và 15.000, no-stack parity →15.000; tie & non-bill chọn theo D-05 | P-09 |
| A-20 | Stack/tier theo policy, không giảm âm/áp dụng hai lần cùng unit; Web/Flutter/server same fixtures | P-09 |
| A-21 | Bill discount 10đ trên3 dòng equal →4/3/3; total allocated 10; quantity 3 không nhân lineDiscount lần nữa | F-03/P-09/R-01 |
| A-22 | Đổi giỏ sau quote →quote invalid; campaign edited không sửa paid receipt; đơn đang mở theo D-02 | F-04/P-09/X-01 |
| A-23 | SKU cùng identity hiển thị menu/kho; recipe cycle bị chặn; discontinued không vào đơn mới nhưng history còn | K-01/K-03 |
| A-24 | Nhập 1,5kg →1.500g; xuất 200g →1.300g; bán 1 carton 24 chai →24 base units | K-02/F-03 |
| A-25 | Opening/import stock tạo document+ledger; file blank không reset quantity thành0; export protected costs | K-02/F-07/R-02 |
| A-26 | Receipt draft qty 10 không đổi stock/debt; complete tăng10 đúng một lần và cost/debt/payment cân | K-04/K-06/K-07 |
| A-27 | Cost fixture §K-05: value2.200.000, average110.000/kg, xuất2kg value1.980.000; reversal original snapshot | K-05 |
| A-28 | Nhập 10 đã return 3, return 8 bị chặn; return 2 đúng stock/debt/refund; cancel không double refund | K-08 |
| A-29 | Cùng external invoice sync 2 lần tạo một record; link draft chưa tăng tồn; unmatched báo lỗi | K-09 |
| A-30 | Count actual null không zero; book 10, actual 8 rồi sale 2, finalize →current 6 theo snapshotdelta | K-10 |
| A-31 | Complete count retry và cancel đều một lần; gộp draft duplicate conflict hiển thị rõ | K-10 |
| A-32 | Transfer send 10 →source −10, transit +10, target 0; receive 10 →transit 0, target +10; cost bảo toàn | K-11 |
| A-33 | Receive 8 of 10 xử lý 2 theo D-08; reject overreceive; receive đồng thời không vượt sent; cross-tenant fail | K-11/F-01 |
| A-34 | Waste/internal draft không stock; complete−3; cancel+3 snapshotcost; report classification khác sale | K-12/K-13 |
| A-35 | Produce 5kg từ ingredient 3kg+2kg → input −3/−2, output +5; sell output không trừ lại ingredients | K-14/K-03 |
| A-36 | Production thiếu nguyên liệu/cycle bị chặn; cancel output đã dùng có dependency block | K-14 |
| A-37 | Made-to-order/topping/size/gift đúng recipe; consume ở bếp rồi thanh toán không tiêu hao lần hai | X-01/X-02 |
| A-38 | Cancel cooked không tăng nguyên liệu tự động; cancel chưa làm release stock, events phân biệt | X-02/X-05 |
| A-39 | Hai thiết bị pay cùng bill →một receipt; crash sau mỗi bước hồi phục không mất/nhân tiền,tồn,quota | X-03/F-05 |
| A-40 | Chuyển/tách/gộp bàn giữ consumption refs; voucher không copy vào hai bill; quote điều kiện lại | X-04 |
| A-41 | Return bill có promotion baseline bị chặn; void/cancel theo policy có linked reversal, history giữ lại | X-05 |
| A-42 | Mất mạng/restart hiện stale/pending, không redeemed/PAID giả; reconnect queue cùng key | R-03 |
| A-43 | Stockcard opening+deltas=closing; filtered export tổng bằng report; budget report lấy actual discount | R-01/R-02 |
| A-44 | Lỗi máy in sau thanh toán: tiền/tồn/quota vẫn committed, reprint cùng snapshot, không tạo bill mới | R-02/X-03 |
| A-45 | Projection worker fail/retry, worker thu hồi hold hết hạn tranh chấp với commit, đối soát ledger và recovery có audit | R-03/F-05 |
| A-46 | Migration legacy types/code/discount nghĩa đúng; unresolved VOUCHER bị báo, không đoán; old bills tái in | R-04/F-04 |
| A-47 | UI keyboard/search/pagination/forms errors/empty states; Web desktop và Flutter tablet các luồng chính | F-08/R-02 |
| A-48 | Supplier statement opening+purchases−returns−payments đúng convention, credit/prepayment không double count | K-06/K-08 |

Bổ sung test tập trung theo D-01…D-12 sau chốt, đặc biệt tax/topping/rounding, negative stock, original cost return và cancellation. Không viết test chỉ lặp lại implementation; oracle tính tay các fixture và ledger invariants.

### 4.12. Trình tự triển khai có thể kiểm chứng

1. **Khảo sát lại và chốt nền:** đọc instructions/code hiện tại, ghi baseline thay đổi sẵn có, xác minh auth/tenant/backend/rules, lập decision log, acceptance inventory. Chưa can thiệp production.
2. **Domain contracts:** schema/version/unit/money/pricing fixture, permission contracts, commands/idempotency, strategy commit/recovery; có test invariants và emulator evidence trước UI nhiều màn hình.
3. **Thin slice kho:** catalog1SKU → receipt draft/complete → ledger/balance/cost → sale1SKU → report. Nghiệm thu auth, retry và đồng thời. Sau đó mở units/variants/recipes.
4. **Thin slice khuyến mãi:** bill discount không mã → quote/reserve/pay → usage/budget/receipt → cancel policy. Sau đó voucher single-use concurrency.
5. **Mở đầy đủ chức năng:** ba hình thức promotion còn lại, lịch/customer/tier/stack; supplier/payment/return; count/transfer/waste/internal/production; tests theo ma trận, không giảm scope âm thầm.
6. **Tích hợp Web/Flutter/bếp:** shared fixtures, size/topping/free items, table lifecycle, receipt/export/report, offline states, recovery worker.
7. **Invoice và khả năng có điều kiện:** triển khai internal invoice mapping và adapter; live connector chỉ khi đầu vào thật sẵn sàng; extensions lô/FEFO/partialtransfer tách milestone nếu được yêu cầu.
8. **Migration/rollout:** staging, dry-run, pilot, shadow comparison, monitoring và rollback được duyệt theo quyền hệ thống; báo nghiệm thu từng module và giới hạn còn lại.

Trước mỗi phase nêu đầu vào, phạm vi file, lệnh/check cần chạy và tiêu chí ra. Sau phase báo verified/failed/blocked, không coi placeholder là done. Dùng Next.js local docs và Firebase official docs cho API đang dùng; Flutter analyzer/tests đúng project. Chạy Web lint/build và các test cần bổ sung cho logic nghiệp vụ; Flutter analyze/test và integration phù hợp thiết bị. Không bịa lệnh test đã tồn tại: web/package.json hiện không có test script, phải chọn/set up runner phù hợp nếu triển khai.

### 4.13. Màn hình và ranh giới trạng thái

Các route dưới đây là đề xuất cho Web Trạm, không phải URL backend KiotViet. Kiểm route hiện có và quyền trước khi tạo. Trên Flutter đưa vào Manager Hub/thu ngân theo vai trò; không nhất thiết sao chép cây route Web.

| Màn hình đề xuất | Nội dung chính | Liên kết hành động |
|---|---|---|
| /dashboard/promotions | danh sách, filters P-01, tạo bốn hình thức | detail, copy, edit, activate |
| /dashboard/promotions/{id} | thông tin, mã, lịch sử, usage/budget và version | edit cho phép; simulate; export |
| /dashboard/inventory/items | danh mục kho, nhóm, units/variants, tồn min/max | detail, import, công thức |
| /dashboard/inventory/items/{id} | thông tin, thẻ kho, tồn chi nhánh, mô tả | drilldown chứng từ; edit có quyền |
| /dashboard/inventory/receipts | phiếu nhập và form draft | supplier, invoice, return, payment, print |
| /dashboard/inventory/purchase-returns | trả nhanh/theo phiếu, states | original receipt, refund, reversal |
| /dashboard/inventory/stocktakes | sessions đếm/cân bằng, tabs, merge | snapshot, adjustments, export |
| /dashboard/inventory/transfers | gửi/nhận, transit, discrepancy | source/destination events |
| /dashboard/inventory/waste; /internal-use | phiếu theo lý do/mục đích | complete/cancel, ledger/report |
| /dashboard/inventory/production | recipe/output/ingredients, availability | complete/cancel, bảng kê |
| /dashboard/suppliers | directory/statement/payments | receipts/returns/debt drilldown |
| /dashboard/input-invoices | synced/manual invoices, matching/link | draft receipt/expense, error/retry |
| /dashboard/reports/promotion; /inventory | các chỉ tiêu R-01 | filtered export, source document |

| Đối tượng | Trạng thái nghiệp vụ | Effect và giới hạn |
|---|---|---|
| Campaign | activation active/inactive; hiệu lực tính riêng; version referenced | sửa theo allowlist S1; không xóa reference/history |
| Voucher | DRAFT/RELEASED/RESERVED/REDEEMED/CANCELLED | redeem từ hold hợp lệ; hồi mã theo D-04 |
| Quote/Hold | quote valid/expired; hold ACTIVE/COMMITTED/RELEASED/EXPIRED | quote chỉ preview; hold giữ quota, không tăng spent |
| Receipt/return/waste/internal/production | DRAFT/COMMITTING/COMPLETED/CANCELLED | COMMITTING là trạng thái kỹ thuật chưa kết thúc; COMPLETED bất biến tiền/lượng |
| Stocktake | DRAFT/COMMITTING/BALANCED/CANCELLED | delta snapshot; uncounted=null |
| Transfer | DRAFT/IN_TRANSIT/RECEIVED/CANCELLED | PARTIALLY_RECEIVED chỉ nếu extension được chọn |
| Checkout | OPEN/HELD/PAYMENT_PENDING/COMMITTING/PAID/VOIDED | failed payment có attempt state riêng; PAID chỉ authoritative commit |
| Input invoice | FETCHED/UNMATCHED/MATCHED/LINKED/ERROR | invoice state không thay receipt stock state |

### 4.14. Truy vết nguồn và từ vựng

| Yêu cầu | Bằng chứng tham chiếu | Thiết kế bổ sung của POS Trạm |
|---|---|---|
| F-01…F-08 | code hiện tại §2.2, T1 | scope/auth, atomicity, numeric rules, audit, quyền server |
| P-01…P-03 | UI-P1/UI-P2/UI-P3, S1 | predicate/version/state, lịch biên chưa xác minh |
| P-04…P-07 | UI-P2/UI-P3 | enums/domain types, quantity matching, topping/price policy |
| P-08 | UI-P4, S2, counter code hiện tại | hold/TTL/budget/quota/idempotency/uniqueness index |
| P-09 | UI-P3, S1 | quote contract, deterministic matching, allocation engine |
| K-01…K-03 | UI-K2/UI-K3, S3/S10 | identity, recipe versions, precision và DAG |
| K-04…K-05 | UI-K4, S14 | immutable ledger, reservations, reconcile và cost contracts |
| K-06…K-09 | UI-K6/UI-K7/UI-K8, S4/S5/S11/S12 | payment ledger, matching adapter, commit/reversal |
| K-10 | UI-K5, S6 | concurrent snapshot-delta policy và approval |
| K-11…K-14 | S7/S8/S9/S10; chưa mở trực tiếp trên tài khoản | transit/variance/production recovery, extension gating |
| X-01…X-05 | models/checkout hiện tại, UI-P2…P4; S1 cho giới hạn return | orchestration bếp/pay, partial effects, cancel/recovery |
| R-01…R-04 | S13, code reports/export, T1 | event-derived totals, offline policy, migration và rollout |

Thuật ngữ: **snapshot** là bản chụp dữ liệu dùng tại giao dịch; **ledger** là sổ các biến động; **projection** là số tổng hợp dựng từ sổ; **reservation/hold** là giữ tạm, chưa chốt; **commit** là ghi nhận giao dịch có hiệu lực; **reversal** là biến động đảo có liên kết bản gốc; **idempotency** là gửi lại cùng yêu cầu vẫn chỉ có một tác động; **parity** là khớp hành vi tham chiếu đã kiểm chứng; **fixture** là dữ liệu thử nghiệm giả với kết quả biết trước.

## 5. Đầu ra mong muốn / Expected Output

Khi được giao **triển khai** prompt này, bàn giao bằng tiếng Việt, code phù hợp repo hiện có, bao gồm:

1. Capability map/spec hoàn chỉnh với từng ID F/P/K/X/R, đường dẫn màn hình, fields, validation, quyền, trạng thái, side effects và acceptance IDs. Không chỉ làm mockup danh sách.
2. ADRs cho D-01…D-12 và architecture commit/auth/tenant/cost/discount semantics. Phân loại VERIFIED_UI, VERIFIED_DOC, PROPOSED, UNRESOLVED, EXTENSION cho các khác biệt.
3. Schema/API contracts, rules/indexes, migration adapters/dry-run, domain engine, command handlers/recovery, Web Admin và Flutter POS tích hợp thật cho scope đã chốt.
4. Fixture giả và báo cáo unit/integration/concurrency/UI tests, nêu môi trường và lệnh thực chạy, kết quả/thất bại. Các trường hợp tiền, tồn, voucher và retry phải có chứng cứ; screenshot không thay kiểm sổ.
5. Hướng dẫn vận hành: tạo khuyến mãi, phát hành mã, áp dụng/quà, nhập/trả/kiểm/chuyển/xuất/sản xuất, công nợ, lỗi mạng, reprint, đối soát và recovery. Có quickstart ngắn cho chủ quán và thu ngân.
6. Bảng coverage cuối: requirement ID → UI/API/domain/data → test IDs → trạng thái; thông báo rõ connector/hardware/policy nào chưa nghiệm thu. Không nói “đầy đủ 100%” khi còn placeholder hoặc blocking decision.

**Điều kiện hoàn thành:** các năng lực bắt buộc trong scope đã chốt chạy xuyên suốt, ma trận tests cần thiết đạt, sổ tiền/tồn/quota cân và dữ liệu cũ đọc đúng; mọi phần bị chặn có đầu vào thiếu và owner rõ. Giao file/PR/review theo yêu cầu chủ dự án, giữ nguyên thay đổi sẵn có không thuộc nhiệm vụ. Tài liệu này là đầu vào triển khai, chưa phải bằng chứng ứng dụng hiện tại đã có những chức năng mô tả.
