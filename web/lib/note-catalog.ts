"use client";
/**
 * Truy cập Firebase cho danh mục note & topping (stores/{s}/note_groups, topping_groups).
 * Logic thuần nằm ở item-options.ts (có test); file này chỉ đọc/ghi.
 */
import { useEffect, useState } from "react";
import { onValue, ref, remove, set, update } from "firebase/database";
import { db } from "./firebase";
import { EMPTY_CATALOG, parseCatalog, type ItemCatalog, type NoteGroup, type ToppingGroup } from "./item-options";

/** Theo dõi danh mục của một chi nhánh. `loaded` = đã nhận dữ liệu lần đầu từ cả hai nút. */
export function useItemCatalog(storeCode: string | null | undefined): { catalog: ItemCatalog; loaded: boolean } {
  const [state, setState] = useState<{ code: string | null; catalog: ItemCatalog; loaded: boolean }>({ code: null, catalog: EMPTY_CATALOG, loaded: false });

  useEffect(() => {
    if (!storeCode) return;
    let notes: unknown = null;
    let tops: unknown = null;
    let got = 0;
    const emit = () => setState({ code: storeCode, catalog: parseCatalog(notes, tops), loaded: got >= 2 });
    let a = false;
    let b = false;
    const unsubA = onValue(
      ref(db, `stores/${storeCode}/note_groups`),
      (s) => {
        notes = s.exists() ? s.val() : null;
        if (!a) {
          a = true;
          got++;
        }
        emit();
      },
      () => {
        if (!a) {
          a = true;
          got++;
        }
        emit();
      }
    );
    const unsubB = onValue(
      ref(db, `stores/${storeCode}/topping_groups`),
      (s) => {
        tops = s.exists() ? s.val() : null;
        if (!b) {
          b = true;
          got++;
        }
        emit();
      },
      () => {
        if (!b) {
          b = true;
          got++;
        }
        emit();
      }
    );
    return () => {
      unsubA();
      unsubB();
    };
  }, [storeCode]);

  if (!storeCode || state.code !== storeCode) return { catalog: EMPTY_CATALOG, loaded: false };
  return { catalog: state.catalog, loaded: state.loaded };
}

const noteGroupBody = (g: NoteGroup) => ({
  name: g.name.trim(),
  sortOrder: g.sortOrder,
  active: g.active,
  items: g.items.filter((i) => i.text.trim()).map((i) => ({ id: i.id, text: i.text.trim() })),
});
const toppingGroupBody = (g: ToppingGroup) => ({
  name: g.name.trim(),
  sortOrder: g.sortOrder,
  active: g.active,
  multi: g.multi,
  max: g.multi ? Math.max(0, Math.trunc(g.max) || 0) : 0,
  items: g.items.filter((i) => i.name.trim()).map((i) => ({ id: i.id, name: i.name.trim(), price: Math.max(0, Math.trunc(i.price) || 0) })),
});

export const saveNoteGroup = (storeCode: string, g: NoteGroup) => set(ref(db, `stores/${storeCode}/note_groups/${g.id}`), noteGroupBody(g));
export const deleteNoteGroup = (storeCode: string, id: string) => remove(ref(db, `stores/${storeCode}/note_groups/${id}`));
export const saveToppingGroup = (storeCode: string, g: ToppingGroup) => set(ref(db, `stores/${storeCode}/topping_groups/${g.id}`), toppingGroupBody(g));
export const deleteToppingGroup = (storeCode: string, id: string) => remove(ref(db, `stores/${storeCode}/topping_groups/${id}`));
/** Ghi nhiều đường dẫn một lần (xếp lại thứ tự, nhập từ cấu hình cũ) */
export const updateStorePaths = (storeCode: string, updates: Record<string, unknown>) => update(ref(db, `stores/${storeCode}`), updates);

export const newGroupId = (prefix: string) => `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
