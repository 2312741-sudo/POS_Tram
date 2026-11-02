/**
 * Đối chiếu khuyến mãi app ↔ web: chạy docs/pricing_parity.json qua engine web, so với docs/pricing_parity_expected.json.
 * app_flutter/test/pricing_parity_test.dart chạy CÙNG bộ tình huống qua engine Dart và so với CÙNG file mong đợi
 * → hai bên lệch nhau ở đâu là test bên đó đỏ. Cập nhật mong đợi (khi cố ý đổi luật): UPDATE_PARITY=1 npx vitest run test/pricing-parity.test.ts
 */
import { describe, it, expect } from "vitest";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";
import { parseCampaign, quoteStacked, type PricingLine, type PriceQuote } from "../lib/pricing-engine";

const docs = resolve(__dirname, "../../docs");
const scenarios = JSON.parse(readFileSync(resolve(docs, "pricing_parity.json"), "utf8")) as {
  cases: Array<{
    name: string;
    campaigns: Array<Record<string, unknown>>;
    lines: PricingLine[];
    nowMs: number;
    branchId: string;
    guestCount?: number | null;
    customerBirthday?: string | null;
    ignoreScheduleFor: string[];
    dedicatedOnlyFor: string[];
  }>;
};

export function snapshot(q: PriceQuote) {
  const lines: Record<string, number> = {};
  for (const lb of q.lineBenefits) if (lb.discountMoney) lines[lb.lineId] = lb.discountMoney;
  return {
    total: q.totalPromotionDiscount,
    applied: q.appliedCampaignIds.length > 0,
    lines,
    rewards: q.rewardBenefits.map((r) => [r.lineId, r.discountMoney, r.quantity ?? 0]),
    bill: q.billBenefits.map((b) => [b.tierId, b.discountMoney, Object.fromEntries(Object.entries(b.lineAllocations).filter(([, v]) => v).sort())]),
    reasons: q.reasons.map((r) => r.reasonCode),
  };
}

const actual: Record<string, Record<string, ReturnType<typeof snapshot>>> = {};
for (const c of scenarios.cases) {
  const camps = c.campaigns.map((raw) => parseCampaign(String(raw.campaignId), raw));
  const res = quoteStacked(
    camps,
    c.lines,
    { branchId: c.branchId, nowMs: c.nowMs, guestCount: c.guestCount ?? null, customerBirthday: c.customerBirthday ?? null },
    { ignoreScheduleFor: new Set(c.ignoreScheduleFor), dedicatedOnlyFor: new Set(c.dedicatedOnlyFor) }
  );
  actual[c.name] = Object.fromEntries(camps.map((k) => [k.campaignId, snapshot(res[k.campaignId])]));
}

const expectedPath = resolve(docs, "pricing_parity_expected.json");
if (process.env.UPDATE_PARITY === "1" || !existsSync(expectedPath)) {
  writeFileSync(expectedPath, JSON.stringify(actual, null, 1) + "\n");
}
const expected = JSON.parse(readFileSync(expectedPath, "utf8"));

describe("Đối chiếu khuyến mãi app ↔ web (docs/pricing_parity.json)", () => {
  for (const c of scenarios.cases) {
    it(c.name, () => expect(actual[c.name]).toEqual(expected[c.name]));
  }
});
