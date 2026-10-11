/**
 * Ghi nhận lượt dùng khuyến mãi khi thanh toán trên Web — cùng hợp đồng dữ liệu với
 * app_flutter/lib/data/services/campaign_service.dart (reservePromotionUsage / rollbackPromotionUsage):
 *   1. voucher:  stores/{s}/vouchers/{campaignId}/{voucherId}  → REDEEMED (transaction, chống dùng 2 lần)
 *   2. bộ đếm:   stores/{s}/campaign_counters/{campaignId}      → spentMoney / committedUseCount (+ maxUses, budgetMoney)
 *   3. khách:    stores/{s}/customer_campaign_counters/{campaignId}_{customerId} → usedCount (+ maxUsesPerCustomer)
 * Nếu bất kỳ bước nào bị từ chối, các bước đã làm được hoàn tác; nếu ghi hóa đơn lỗi thì gọi rollback.
 */
import { get, ref, runTransaction, type Database } from "firebase/database";
import {
  applyCampaignUsage,
  applyCustomerUsage,
  parseCampaign,
  redeemVoucherValue,
  rollbackVoucherValue,
  type AppliedDiscount,
} from "./pricing-engine";

export class PromotionLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PromotionLimitError";
  }
}

export interface PromotionReservation {
  campaignId: string;
  discountMoney: number;
  customerId?: string;
  voucherCode?: string;
  billId: string;
  voucherCampaignId?: string;
  voucherId?: string;
  voucherRedeemed: boolean;
  counterApplied: boolean;
  customerApplied: boolean;
}

export interface PromotionActor {
  username: string;
  staffName?: string;
  billCode?: string;
  tableName?: string;
  customerId?: string | null;
}

/** Đặt giữ lượt dùng cho 1 giảm giá của hóa đơn. Ném PromotionLimitError nếu bị từ chối (đã tự hoàn tác phần của nó). */
export async function reservePromotionUsage(
  db: Database,
  storeCode: string,
  discount: AppliedDiscount,
  billId: string,
  actor: PromotionActor
): Promise<PromotionReservation> {
  const base = `stores/${storeCode}`;
  const code = discount.voucherCode?.trim().toUpperCase() || undefined;
  const r: PromotionReservation = {
    campaignId: discount.campaignId,
    discountMoney: discount.amount,
    customerId: actor.customerId || undefined,
    voucherCode: code,
    billId,
    voucherRedeemed: false,
    counterApplied: false,
    customerApplied: false,
  };

  const campSnap = await get(ref(db, `${base}/campaigns/${discount.campaignId}`));
  const campaign = campSnap.exists() ? parseCampaign(discount.campaignId, campSnap.val()) : null;
  const campaignName = campaign?.name || discount.campaignName || discount.campaignId;

  const fail = async (message: string): Promise<never> => {
    await rollbackPromotionUsage(db, storeCode, r);
    throw new PromotionLimitError(message);
  };

  // 1. Voucher (mã dùng 1 lần)
  if (code) {
    const lookup = await get(ref(db, `${base}/voucher_lookup/${code}`));
    const lv = lookup.val() as { campaignId?: string; voucherId?: string } | null;
    if (!lv?.campaignId || !lv.voucherId) return fail(`Mã voucher ${code} không tồn tại`);
    r.voucherCampaignId = String(lv.campaignId);
    r.voucherId = String(lv.voucherId);
    const rej: { reason: string | null } = { reason: null };
    const res = await runTransaction(
      ref(db, `${base}/vouchers/${r.voucherCampaignId}/${r.voucherId}`),
      (cur) => {
        // Cache cục bộ trống: trả null để server gửi giá trị thật rồi chạy lại
        const out = redeemVoucherValue(cur, { billId, username: actor.username, billCode: actor.billCode, tableName: actor.tableName, staffName: actor.staffName, staffNote: discount.staffNote, now: Date.now() });
        if (out === null) return null;
        if ("reject" in out) {
          rej.reason = out.reject;
          return undefined; // abort
        }
        return out.next;
      },
      { applyLocally: false }
    );
    if (!res.committed || res.snapshot.val() === null) {
      const reason = rej.reason;
      if (reason === "MINE") {
        // Chính hóa đơn này đã đổi từ trước: không hoàn tác voucher
      } else {
        return fail(`${reason ?? "Mã voucher không khả dụng"} (${code})`);
      }
    } else {
      r.voucherRedeemed = true;
    }
  }

  // 2. Bộ đếm tổng của chương trình
  const counterRes = await runTransaction(
    ref(db, `${base}/campaign_counters/${discount.campaignId}`),
    (cur) => applyCampaignUsage(cur, { campaignId: discount.campaignId, spentDelta: discount.amount, useDelta: 1, maxUses: campaign?.maxUses, budgetMoney: campaign?.budgetMoney }) ?? undefined,
    { applyLocally: false }
  );
  if (!counterRes.committed) {
    return fail(`Khuyến mãi "${campaignName}" đã hết lượt sử dụng hoặc hết ngân sách`);
  }
  r.counterApplied = true;

  // 3. Bộ đếm theo khách hàng
  if (r.customerId) {
    const custRes = await runTransaction(
      ref(db, `${base}/customer_campaign_counters/${discount.campaignId}_${r.customerId}`),
      (cur) => applyCustomerUsage(cur, { campaignId: discount.campaignId, customerId: r.customerId as string, delta: 1, maxUsesPerCustomer: campaign?.maxUsesPerCustomer }) ?? undefined,
      { applyLocally: false }
    );
    if (!custRes.committed) {
      return fail(`Khách hàng đã dùng hết số lượt cho phép của khuyến mãi "${campaignName}"`);
    }
    r.customerApplied = true;
  }
  return r;
}

/** Hoàn tác các bước đã áp dụng. Trả về danh sách lỗi (rỗng nếu thành công) — không ném lỗi. */
export async function rollbackPromotionUsage(db: Database, storeCode: string, r: PromotionReservation): Promise<string[]> {
  const base = `stores/${storeCode}`;
  const errors: string[] = [];
  const guard = async (label: string, op: () => Promise<unknown>) => {
    try {
      await op();
    } catch (e) {
      errors.push(`${label}: ${e instanceof Error ? e.message : String(e)}`);
    }
  };
  if (r.customerApplied && r.customerId) {
    await guard("Hoàn tác lượt khách", () =>
      runTransaction(
        ref(db, `${base}/customer_campaign_counters/${r.campaignId}_${r.customerId}`),
        (cur) => (cur === null ? null : applyCustomerUsage(cur, { campaignId: r.campaignId, customerId: r.customerId as string, delta: -1 })),
        { applyLocally: false }
      )
    );
    r.customerApplied = false;
  }
  if (r.counterApplied) {
    await guard("Hoàn tác bộ đếm khuyến mãi", () =>
      runTransaction(
        ref(db, `${base}/campaign_counters/${r.campaignId}`),
        (cur) => (cur === null ? null : applyCampaignUsage(cur, { campaignId: r.campaignId, spentDelta: -r.discountMoney, useDelta: -1 })),
        { applyLocally: false }
      )
    );
    r.counterApplied = false;
  }
  if (r.voucherRedeemed && r.voucherId && r.voucherCampaignId) {
    await guard("Hoàn tác voucher", () =>
      runTransaction(
        ref(db, `${base}/vouchers/${r.voucherCampaignId}/${r.voucherId}`),
        (cur) => (cur === null ? null : (rollbackVoucherValue(cur, r.billId) ?? undefined)),
        { applyLocally: false }
      )
    );
    r.voucherRedeemed = false;
  }
  return errors;
}

/**
 * Giữ lượt cho toàn bộ giảm giá của hóa đơn; một cái bị từ chối thì hoàn tác các cái trước và ném PromotionLimitError.
 * Trả về danh sách reservation để rollback nếu bước ghi hóa đơn thất bại.
 */
export async function reserveAllPromotions(
  db: Database,
  storeCode: string,
  discounts: AppliedDiscount[],
  billId: string,
  actor: PromotionActor
): Promise<PromotionReservation[]> {
  const done: PromotionReservation[] = [];
  try {
    for (const d of discounts) done.push(await reservePromotionUsage(db, storeCode, d, billId, actor));
  } catch (e) {
    for (const r of done) await rollbackPromotionUsage(db, storeCode, r);
    throw e;
  }
  return done;
}

export async function rollbackAllPromotions(db: Database, storeCode: string, list: PromotionReservation[]): Promise<string[]> {
  const errors: string[] = [];
  for (const r of list) errors.push(...(await rollbackPromotionUsage(db, storeCode, r)));
  return errors;
}
