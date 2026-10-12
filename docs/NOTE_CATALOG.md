# Danh mục note & topping (gắn theo nhóm món / món)

## Vì sao
Trước đây màn chỉnh món luôn hiện bộ topping đồ uống (Thạch chanh, Trân châu...) và ghi chú nhanh "Ít đá / Nhiều đá" cho MỌI món,
kể cả bánh. Giờ chủ quán tự tạo danh mục và gắn vào nhóm món hoặc từng món; không gắn thì chỉ còn ô ghi chú tự do.

## Dữ liệu (mỗi chi nhánh)
| Đường dẫn | Trường |
|---|---|
| `stores/{s}/note_groups/{id}` | `name`, `sortOrder`, `active`, `items: [{id, text}]` |
| `stores/{s}/topping_groups/{id}` | `name`, `sortOrder`, `active`, `multi` (mặc định true), `max` (0 = không giới hạn), `items: [{id, name, price}]` |
| `stores/{s}/categories/{nhóm}` | thêm `noteGroupIds[]`, `toppingGroupIds[]` |
| `stores/{s}/products/{món}` | thêm `noteGroupIds[]`, `toppingGroupIds[]` |

Rules: đọc — mọi thành viên đang hoạt động của quán; ghi — chỉ Chủ / Quản lý (cùng biểu thức với `product_notes`).
Quyền giao diện: `MANAGE_NOTE_CATALOG` (hàm một chỗ: `canManageNoteCatalog` — Dart `features/menu_management/note_catalog_access.dart`, web `lib/note-catalog-access.ts`).

## Quy tắc áp dụng (`resolveItemOptions` — Dart `core/domain/item_options.dart`, TS `web/lib/item-options.ts`, cùng ngữ nghĩa)
1. Món CÓ trường (kể cả "không có") → dùng của món (ghi đè). Món KHÔNG có trường → kế thừa nhóm món. Nhóm món cũng không có → KHÔNG có gì.
2. RTDB không lưu mảng rỗng, nên "ghi đè = không có" được lưu `["__none__"]` (`NO_GROUPS`). Xóa trường = quay về kế thừa.
3. Nhóm đã tắt (`active=false`), không tồn tại, hoặc không có mục nào → bỏ. Giữ thứ tự gắn, bỏ trùng; câu note và topping trùng tên chỉ hiện một lần.
4. Topping: `multi=false` → chọn một trong nhóm; `max>0` → tối đa N trong nhóm (`toggleTopping`).
5. **Legacy**: chi nhánh chưa có `note_groups` lẫn `topping_groups` (kể cả nhóm đã tắt) → giữ cách hiển thị cũ, không vỡ gì. Màn quản lý thực đơn (app + web) hiện banner "Chưa cấu hình danh mục note/topping — bấm để thiết lập".
   Ngay khi có nhóm đầu tiên, MỌI món chuyển sang chế độ mới (chỉ hiện nhóm đã gắn) → nên chạy "Nhập từ cấu hình cũ" để gắn sẵn cho đồ uống.
6. Size / đường / đá KHÔNG đổi: vẫn là trường của món (`sizes`, `hasIceSugarOptions`) kèm suy đoán theo tên nhóm (trà, cà phê, sữa...). Bánh/đồ ăn không có.
   Muốn món đồ uống không hỏi size/đường/đá thì sửa các trường đó của món (chưa có kế thừa riêng cho các mục này).

Dữ liệu dòng món KHÔNG đổi (`selectedToppings`, `toppingPrice`, `note`...): giá topping vẫn cộng vào đơn giá, gộp dòng / bếp / in như cũ.

## Giao diện
- Web: `/dashboard/note-catalog` (Sidebar "Danh mục note & topping", cần MANAGE_NOTE_CATALOG): CRUD nhóm note (câu note), nhóm topping (tên + giá, chọn nhiều/một, tối đa), sắp xếp, nút "Nhập từ cấu hình cũ".
  Gắn: trang Thực đơn → sửa nhóm món, sửa món ("Kế thừa từ nhóm món" / "Tùy chỉnh cho món này").
- App: Quản lý thực đơn → biểu tượng ghi chú (màn `NoteCatalogScreen`); gắn cho nhóm món ở Quản lý danh mục (chạm vào nhóm), cho món ở hộp thoại sửa món.
- Gọi món: bảng chỉnh món của app (`order_cart_screen`, `order_list_screen`) và hộp thoại gọi món web chỉ hiện nhóm đã gắn; câu note nhanh = các nhóm note đã gắn.

## Sao chép thực đơn
`copyCatalog` (mặc định bật): sao chép `note_groups` / `topping_groups` sang chi nhánh đích — nhóm trùng TÊN (bỏ dấu) dùng lại, không ghi đè;
id nhóm nguồn giữ nếu còn trống (không thì `id_2`...); `noteGroupIds`/`toppingGroupIds` của món và nhóm món được đổi sang id đích.
Id không còn ở nguồn → `["__none__"]`. Nhóm món có sẵn ở đích chỉ được bổ sung phần gắn nếu đích chưa có.

## Nhập từ cấu hình cũ
Nút trong app/web và script `scripts/migrate_note_catalog/` (mặc định DRY-RUN, xem README). Quy tắc (idempotent, chỉ thêm):
- `legacy_toppings`: mọi món Topping (hoặc bộ chuẩn nếu chưa có); gắn vào nhóm món là đồ uống chưa có `allowedToppingIds`.
- nhóm có `allowedToppingIds` → `legacy_cat_<nhóm>`; món có `allowedToppings` riêng → `legacy_set_<hash>`.
- `legacy_notes` từ `product_notes`, gắn vào nhóm món là đồ uống. Bánh/đồ ăn không gắn gì.
Bản thuần: Dart `core/domain/note_catalog_migration.dart`, TS `web/lib/note-catalog-migrate.ts`, JS `scripts/migrate_note_catalog/plan.js` (hash djb2 giống nhau).
