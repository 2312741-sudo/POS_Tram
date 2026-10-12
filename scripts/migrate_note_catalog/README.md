# migrate_note_catalog

Nhập cấu hình cũ (ghi chú mẫu `product_notes`, topping trong thực đơn / `allowedToppingIds` / `allowedToppings`) vào
danh mục note & topping mới (`note_groups`, `topping_groups`) và gắn vào nhóm món / món. Chi tiết: `docs/NOTE_CATALOG.md`.

```bash
cd scripts/migrate_note_catalog && npm install
npm test                                   # kiểm tra bộ lập kế hoạch
node migrate.js --service-account=KEY.json              # DRY-RUN: chỉ in kế hoạch
node migrate.js --service-account=KEY.json --stores=TRAM01 --apply   # ghi thật (có sao lưu migration_output/)
```

- Mặc định KHÔNG ghi. Chạy lại an toàn (không ghi đè nhóm/gắn kết đã có).
- Cùng quy tắc với nút "Nhập từ cấu hình cũ" trong app/web. `plan.js` được sinh từ `web/lib/note-catalog-migrate.ts`:
  `cd web && node -e 'const ts=require("typescript"),fs=require("fs");const o=ts.transpileModule(fs.readFileSync("lib/note-catalog-migrate.ts","utf8"),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;fs.writeFileSync("../scripts/migrate_note_catalog/plan.js","// SINH TỪ web/lib/note-catalog-migrate.ts\n"+o)'`
