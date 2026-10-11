/**
 * Nhập / điều chỉnh số lượng tồn kho của một mặt hàng (kiểm kê, tồn đầu kỳ).
 * Ghi stock_balances/{store}_{itemId} + một stock_events để thẻ kho truy vết được.
 * Rules: chỉ Chủ quán / Quản lý ghi stock_balances & stock_events.
 */

export interface StockBalanceLike {
  onHandQty: number;
  reservedQty: number;
  inventoryValue: number;
  averageCostScaled: number;
}

export type StockAdjustResult =
  | { ok: false; error: string }
  | { ok: true; delta: number; updates: Record<string, unknown>; eventId: string };

export function buildStockAdjustment(args: {
  storeCode: string;
  item: { itemId: string; name: string; costPrice: number };
  current: StockBalanceLike | undefined;
  newQty: number;
  reason: string;
  actor: { username: string; fullName?: string; role?: string };
  now: number;
  nonce?: string;
}): StockAdjustResult {
  const { storeCode, item, current, newQty } = args;
  const reason = args.reason.trim();
  if (!Number.isFinite(newQty) || newQty < 0) return { ok: false, error: "Số lượng tồn phải là số ≥ 0" };
  if (newQty > 1_000_000_000) return { ok: false, error: "Số lượng quá lớn" };
  if (!reason) return { ok: false, error: "Vui lòng nhập lý do / ghi chú kiểm kê" };

  const oldQty = current?.onHandQty ?? 0;
  const reserved = current?.reservedQty ?? 0;
  const delta = Math.round((newQty - oldQty) * 1000) / 1000;
  if (delta === 0) return { ok: false, error: "Số lượng không thay đổi" };

  // Giá vốn bình quân: ưu tiên giá đang có trên số dư; chưa có thì dùng giá vốn khai báo ở danh mục
  const avgScaled = current?.averageCostScaled && current.averageCostScaled > 0
    ? current.averageCostScaled
    : Math.round((item.costPrice || 0) * 100);
  const newValue = Math.round((newQty * avgScaled) / 100);
  const valueDelta = newValue - (current?.inventoryValue ?? 0);

  const balanceKey = `${storeCode}_${item.itemId}`;
  const eventId = `EVT_${args.now}_${args.nonce ?? Math.random().toString(36).slice(2, 6)}`;
  const base = `stores/${storeCode}`;
  const updates: Record<string, unknown> = {
    [`${base}/stock_balances/${balanceKey}`]: {
      balanceId: balanceKey,
      branchId: storeCode,
      itemId: item.itemId,
      onHandQty: newQty,
      reservedQty: reserved,
      inventoryValue: newValue,
      averageCostScaled: avgScaled,
      updatedAt: args.now,
    },
    [`${base}/stock_events/${eventId}`]: {
      eventId,
      commandId: `ADJ_${args.now}_${item.itemId}`,
      documentId: `ADJ_${args.now}`,
      documentType: current ? "STOCK_ADJUSTMENT" : "OPENING",
      documentLineId: `LINE_${item.itemId}`,
      branchId: storeCode,
      itemId: item.itemId,
      qtyDeltaBase: delta,
      valueDeltaMoney: valueDelta,
      unitCostSnapshot: avgScaled,
      note: reason,
      occurredAt: args.now,
      committedAt: args.now,
      actorId: args.actor.username,
      sequence: args.now,
    },
    [`${base}/audit_logs/log_${args.now}_stk_${args.nonce ?? Math.floor(Math.random() * 1e5)}`]: {
      timestamp: args.now,
      username: args.actor.username,
      userFullName: args.actor.fullName ?? args.actor.username,
      userRole: args.actor.role ?? "",
      action: "STOCK_SET_ONHAND",
      targetType: "ITEM",
      targetId: item.itemId,
      storeCode,
      details: `Nhập tồn "${item.name}": ${oldQty} → ${newQty} (${delta > 0 ? "+" : ""}${delta}). ${reason}`,
      beforeState: { onHandQty: oldQty },
      afterState: { onHandQty: newQty },
    },
  };
  return { ok: true, delta, updates, eventId };
}

/** Danh sách nhóm hàng đang dùng (không trùng, sắp theo tên) để chọn nhanh khi tạo / sửa hàng */
export function collectItemGroups(items: { managementGroup?: string; groupIds?: string[] }[]): string[] {
  const set = new Set<string>();
  for (const it of items) {
    const g = (it.managementGroup || "").trim();
    if (g) set.add(g);
    for (const id of it.groupIds || []) if (id && id.trim()) set.add(id.trim());
  }
  return [...set].sort((a, b) => a.localeCompare(b, "vi"));
}
