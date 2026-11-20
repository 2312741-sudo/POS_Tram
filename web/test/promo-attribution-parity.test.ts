/** Đối chiếu chia khuyến mãi theo người bấm món: web sinh kết quả mong đợi, app (test/promo_attribution_parity_test.dart) phải khớp. */
import { describe, it, expect } from "vitest";
import { readFileSync, writeFileSync, existsSync } from "fs";
import { resolve } from "path";
import { parseCampaign, quoteStacked, type PricingLine } from "../lib/pricing-engine";
import { promoStaffShares, type LineStaff } from "../lib/promo-attribution";

const docs = resolve(__dirname, "../../docs");
const data = JSON.parse(readFileSync(resolve(docs, "promo_attribution_parity.json"), "utf8")) as {
  nowMs: number;
  cashier: LineStaff;
  cases: Array<{
    name: string;
    campaigns: Array<Record<string, unknown>>;
    lines: Array<{ line: PricingLine; staff: LineStaff | null }>;
    dedicated?: string[];
    storedDelta?: Record<string, number>;
  }>;
};

const actual: Record<string, Record<string, Array<{ u: string; n: string; amount: number; combo: number }>>> = {};
for (const c of data.cases) {
  const camps = c.campaigns.map((raw) => parseCampaign(String(raw.campaignId), raw));
  const lines = c.lines.map((x) => x.line);
  const staff = new Map(c.lines.map((x) => [x.line.lineId, x.staff]));
  const quotes = quoteStacked(camps, lines, { branchId: "TRAM01", nowMs: data.nowMs }, {
    ignoreScheduleFor: new Set(camps.map((k) => k.campaignId)),
    dedicatedOnlyFor: new Set(c.dedicated ?? []),
  });
  actual[c.name] = Object.fromEntries(
    camps.map((k) => {
      const q = quotes[k.campaignId];
      const stored = q.totalPromotionDiscount + (c.storedDelta?.[k.campaignId] ?? 0);
      return [k.campaignId, promoStaffShares(q, lines, k.campaignId, (id) => staff.get(id) ?? null, data.cashier, stored)];
    }),
  );
}

const expectedPath = resolve(docs, "promo_attribution_parity_expected.json");
if (process.env.UPDATE_PARITY === "1" || !existsSync(expectedPath)) writeFileSync(expectedPath, JSON.stringify(actual, null, 1) + "\n");
const expected = JSON.parse(readFileSync(expectedPath, "utf8"));

describe("Đối chiếu chia khuyến mãi theo người bấm món app ↔ web", () => {
  for (const c of data.cases) it(c.name, () => expect(actual[c.name]).toEqual(expected[c.name]));
});
