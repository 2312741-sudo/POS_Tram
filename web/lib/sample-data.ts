/**
 * Dữ liệu MẪU để kiểm thử/đào tạo: chương trình khuyến mãi cho từng loại hình và các dạng đơn
 * (đơn thường, giảm giá món, giảm giá đơn, khuyến mãi từng loại, đổi điểm, kết hợp).
 *
 * Mọi bản ghi mẫu đều có `isSample: true` và mã bắt đầu bằng "MAU" để nhận biết / xóa sạch được.
 * Hóa đơn mẫu là hóa đơn PAID thật trong stores/{code}/bills + history ⇒ CÓ tính vào báo cáo
 * cho tới khi xóa mẫu.
 */
import { buildBenefitFields, emptyCampaignForm, type CampaignFormState, type CampaignTypeCode } from "./campaign-form";
import { applyLineDiscount, summarizeOrderLines, type RawOrderLine } from "./order-math";

export interface SampleActor {
  username: string;
  fullName?: string;
}

const SAMPLE_PRODUCTS = [
  { id: 9001, name: "Trà đào cam sả (mẫu)", price: 45000, category: "Trà" },
  { id: 9002, name: "Cà phê sữa (mẫu)", price: 30000, category: "Cà phê" },
  { id: 9003, name: "Bánh waffle (mẫu)", price: 55000, category: "Bánh" },
  { id: 9004, name: "Sữa chua trân châu (mẫu)", price: 38000, category: "Sữa chua" },
];

const line = (idx: number, qty: number, note = ""): RawOrderLine => {
  const p = SAMPLE_PRODUCTS[idx];
  return {
    productId: p.id,
    name: p.name,
    price: p.price,
    quantity: qty,
    category: p.category,
    note,
    isSentKitchen: true,
    discountAmount: 0,
    lineDiscountTotal: 0,
    discountedQuantity: 0,
  };
};

/** Một chương trình mẫu cho mỗi loại hình khuyến mãi */
export function sampleCampaignForms(): { id: string; form: CampaignFormState }[] {
  const base = (patch: Partial<CampaignFormState>): CampaignFormState => ({ ...emptyCampaignForm(), active: true, autoApply: true, ...patch });
  const forms: Record<CampaignTypeCode, CampaignFormState> = {
    BILLDISCOUNT: base({
      name: "MẪU - Giảm 10% đơn từ 100.000đ", programCode: "MAU_BILL", campaignType: "BILLDISCOUNT",
      description: "Giảm 10% tổng đơn từ 100.000đ, tối đa 30.000đ",
      discountType: "PERCENT", discountValue: "10", maxDiscount: "30000", threshold: "100000",
    }),
    ORDERVALUEITEMBENEFIT: base({
      name: "MẪU - Đơn từ 150.000đ tặng 1 Sữa chua", programCode: "MAU_ORDERITEM", campaignType: "ORDERVALUEITEMBENEFIT",
      description: "Đơn từ 150.000đ được tặng 1 Sữa chua trân châu",
      threshold: "150000", rewardItemIds: ["9004"], rewardQty: "1", rewardBenefit: "FREEITEM",
    }),
    BUYXGETY: base({
      name: "MẪU - Mua 2 Trà tặng 1 Bánh", programCode: "MAU_BUYXGETY", campaignType: "BUYXGETY",
      description: "Mua 2 Trà đào cam sả tặng 1 Bánh waffle",
      buyItemIds: ["9001"], buyQty: "2", rewardItemIds: ["9003"], rewardQty: "1", rewardBenefit: "FREEITEM", multiplyByBundle: true,
    }),
    ITEMPRICERULE: base({
      name: "MẪU - Đồng giá Cà phê sữa 25.000đ", programCode: "MAU_PRICE", campaignType: "ITEMPRICERULE",
      description: "Cà phê sữa đồng giá 25.000đ",
      fixedPriceValue: "25000", includedItemIds: ["9002"],
    }),
  };
  return (Object.keys(forms) as CampaignTypeCode[]).map((t) => ({ id: `CAM_SAMPLE_${t}`, form: forms[t] }));
}

export function buildSampleCampaignDoc(storeCode: string, id: string, f: CampaignFormState, now: number, actor: SampleActor) {
  const benefit = buildBenefitFields(f);
  return {
    campaignId: id,
    programCode: f.programCode,
    name: f.name,
    description: f.description,
    campaignType: f.campaignType,
    active: f.active,
    schedule: { timezone: "Asia/Ho_Chi_Minh" },
    branchIds: [storeCode],
    includedItemIds: benefit.includedItemIds,
    includedGroupIds: benefit.includedGroupIds,
    tiers: benefit.tiers,
    buyConditions: benefit.buyConditions,
    budgetMoney: 0,
    maxUses: 0,
    hasCodes: false,
    autoApply: f.autoApply,
    requireStaffNote: false,
    stackingMode: "ENABLED",
    priority: 0,
    createdAt: now,
    updatedAt: now,
    createdBy: actor.fullName || actor.username,
    isSample: true,
  };
}

interface BillSpec {
  key: string;
  label: string;
  lines: RawOrderLine[];
  /** Giảm giá cấp đơn (đ) kèm mô tả theo nhóm */
  orderDiscounts?: { kind: "MANUAL" | "CAMPAIGN" | "VOUCHER"; description: string; amount: number; campaignId?: string; campaignType?: string; programCode?: string; voucherCode?: string }[];
  points?: { used: number; discount: number };
  payment?: "CASH" | "TRANSFER";
}

function billSpecs(): BillSpec[] {
  const discounted = (l: RawOrderLine, percent: number) => applyLineDiscount(l, { percent, discountedQuantity: Number(l.quantity) });
  return [
    { key: "PLAIN", label: "Đơn thường (không giảm giá)", lines: [line(0, 2), line(2, 1)] },
    {
      key: "ITEM_DISCOUNT", label: "Giảm giá món (10% món Trà)",
      lines: [{ ...discounted(line(0, 2), 10), discountReason: "Khách quen" }, line(1, 1)],
    },
    {
      key: "ORDER_DISCOUNT", label: "Giảm giá cả đơn (nhập tay 20.000đ)",
      lines: [line(0, 2), line(1, 2)],
      orderDiscounts: [{ kind: "MANUAL", description: "Giảm giá thủ công", amount: 20000 }],
    },
    {
      key: "PROMO_BILLDISCOUNT", label: "KM giảm % đơn hàng",
      lines: [line(0, 2), line(2, 1)],
      orderDiscounts: [{ kind: "CAMPAIGN", description: "MẪU - Giảm 10% đơn từ 100.000đ", amount: 14500, campaignId: "CAM_SAMPLE_BILLDISCOUNT", campaignType: "BILLDISCOUNT", programCode: "MAU_BILL" }],
    },
    {
      key: "PROMO_ORDERITEM", label: "KM tặng món theo giá trị đơn",
      lines: [line(0, 2), line(2, 1), line(3, 1)],
      orderDiscounts: [{ kind: "CAMPAIGN", description: "MẪU - Đơn từ 150.000đ tặng 1 Sữa chua", amount: 38000, campaignId: "CAM_SAMPLE_ORDERVALUEITEMBENEFIT", campaignType: "ORDERVALUEITEMBENEFIT", programCode: "MAU_ORDERITEM" }],
    },
    {
      key: "PROMO_BUYXGETY", label: "KM mua X tặng Y",
      lines: [line(0, 2), line(2, 1)],
      orderDiscounts: [{ kind: "CAMPAIGN", description: "MẪU - Mua 2 Trà tặng 1 Bánh", amount: 55000, campaignId: "CAM_SAMPLE_BUYXGETY", campaignType: "BUYXGETY", programCode: "MAU_BUYXGETY" }],
    },
    {
      key: "PROMO_ITEMPRICE", label: "KM đồng giá món",
      lines: [line(1, 2)],
      orderDiscounts: [{ kind: "CAMPAIGN", description: "MẪU - Đồng giá Cà phê sữa 25.000đ", amount: 10000, campaignId: "CAM_SAMPLE_ITEMPRICERULE", campaignType: "ITEMPRICERULE", programCode: "MAU_PRICE" }],
    },
    {
      key: "VOUCHER", label: "Dùng mã voucher",
      lines: [line(0, 1), line(1, 1)],
      orderDiscounts: [{ kind: "VOUCHER", description: "Voucher MAUVC01", amount: 15000, campaignId: "CAM_SAMPLE_BILLDISCOUNT", campaignType: "BILLDISCOUNT", programCode: "MAU_BILL", voucherCode: "MAUVC01" }],
      payment: "TRANSFER",
    },
    {
      key: "POINTS", label: "Đổi điểm tích lũy (20 điểm)",
      lines: [line(0, 2), line(3, 1)],
      points: { used: 20, discount: 20000 },
    },
    {
      key: "COMBO", label: "Kết hợp: giảm món + KM + đổi điểm",
      lines: [discounted(line(0, 3), 20), line(2, 2)],
      orderDiscounts: [{ kind: "CAMPAIGN", description: "MẪU - Giảm 10% đơn từ 100.000đ", amount: 30000, campaignId: "CAM_SAMPLE_BILLDISCOUNT", campaignType: "BILLDISCOUNT", programCode: "MAU_BILL" }],
      points: { used: 10, discount: 10000 },
      payment: "TRANSFER",
    },
  ];
}

export const SAMPLE_BILL_LABELS = billSpecs().map((b) => ({ key: b.key, label: b.label }));

export function buildSampleBill(storeCode: string, storeName: string, spec: BillSpec, n: number, now: number, actor: SampleActor) {
  const { subTotal, itemDiscounts } = summarizeOrderLines(spec.lines);
  const orderDiscountList = (spec.orderDiscounts || []).map((d) => ({
    ...(d.campaignId ? { campaignId: d.campaignId, campaignName: d.description, campaignType: d.campaignType, programCode: d.programCode } : { promoName: d.description }),
    description: d.description,
    ...(d.voucherCode ? { voucherCode: d.voucherCode } : {}),
    type: d.kind,
    amount: d.amount,
  }));
  const promoTotal = orderDiscountList.reduce((s, d) => s + d.amount, 0);
  const pointsDiscount = spec.points?.discount ?? 0;
  const billDiscounts = promoTotal + pointsDiscount;
  const totalDiscount = Math.min(subTotal, itemDiscounts + billDiscounts);
  const finalAmount = Math.max(0, subTotal - totalDiscount);
  const ts = now - n * 60_000;
  const id = `SAMPLE_BILL_${now}_${n}`;
  const code = `MAU-${String(n + 1).padStart(4, "0")}`;
  const fullName = actor.fullName || actor.username;
  return {
    id,
    storeCode,
    storeName,
    billCode: code,
    orderCode: code,
    tableName: `Bàn mẫu ${n + 1}`,
    zone: "Khu mẫu",
    guestCount: 2,
    subTotal,
    itemDiscounts,
    billDiscounts,
    discountAmount: totalDiscount,
    totalDiscount,
    discounts: orderDiscountList,
    ...(spec.points ? { pointsUsed: spec.points.used, pointsDiscount, customerId: "CUST_SAMPLE", customerName: "Khách mẫu", customerPhone: "0900000000" } : {}),
    totalAmount: finalAmount,
    finalAmount,
    vatRate: 0,
    vatAmount: 0,
    paymentMethod: spec.payment || "CASH",
    status: "PAID",
    timestamp: ts,
    createdAt: ts - 20 * 60_000,
    closedAt: ts,
    cashierName: fullName,
    staffUsername: actor.username,
    staffFullName: fullName,
    orderStaff: fullName,
    items: spec.lines,
    actionLogs: [{ timestamp: ts, staffUsername: actor.username, staffFullName: fullName, action: "PAY_BILL", details: `Đơn mẫu: ${spec.label}` }],
    isSample: true,
    sampleKind: spec.key,
  };
}

/** Toàn bộ đường dẫn ghi cho bộ dữ liệu mẫu của một chi nhánh (chương trình KM + hóa đơn) */
export function buildSampleDataUpdates(args: { storeCode: string; storeName: string; actor: SampleActor; now: number }): Record<string, unknown> {
  const { storeCode, storeName, actor, now } = args;
  const base = `stores/${storeCode}`;
  const updates: Record<string, unknown> = {};
  for (const c of sampleCampaignForms()) {
    updates[`${base}/campaigns/${c.id}`] = buildSampleCampaignDoc(storeCode, c.id, c.form, now, actor);
  }
  billSpecs().forEach((spec, n) => {
    const bill = buildSampleBill(storeCode, storeName, spec, n, now, actor);
    updates[`${base}/bills/${bill.id}`] = bill;
    updates[`${base}/history/${bill.id}`] = bill;
  });
  updates[`${base}/audit_logs/log_${now}_sample`] = {
    timestamp: now,
    username: actor.username,
    userFullName: actor.fullName || actor.username,
    action: "SAMPLE_DATA_CREATE",
    targetType: "STORE",
    targetId: storeCode,
    storeCode,
    details: `Tạo dữ liệu mẫu: ${sampleCampaignForms().length} chương trình KM + ${billSpecs().length} hóa đơn mẫu`,
  };
  return updates;
}

/** Xóa mọi bản ghi mẫu (nhận biết bằng isSample) từ bản chụp bills / history / campaigns */
export function buildSampleRemovalUpdates(storeCode: string, nodes: { bills?: unknown; history?: unknown; campaigns?: unknown }): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  const scan = (node: string, val: unknown) => {
    if (!val || typeof val !== "object") return;
    for (const [id, raw] of Object.entries(val as Record<string, unknown>)) {
      if (raw && typeof raw === "object" && (raw as { isSample?: unknown }).isSample === true) {
        updates[`stores/${storeCode}/${node}/${id}`] = null;
      }
    }
  };
  scan("bills", nodes.bills);
  scan("history", nodes.history);
  scan("campaigns", nodes.campaigns);
  return updates;
}
