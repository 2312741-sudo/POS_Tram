import { describe, it, expect, vi } from "vitest";

vi.mock("../lib/firebase", () => ({ functions: {} }));
vi.mock("firebase/functions", () => ({ httpsCallable: vi.fn() }));

import { insufficientBalance } from "../lib/loyalty-client";

describe("loyalty-client", () => {
  it("nhận diện lỗi không đủ điểm từ details của callable", () => {
    expect(insufficientBalance({ code: "functions/failed-precondition", details: { code: "insufficient", balance: 12 } })).toEqual({ balance: 12 });
    expect(insufficientBalance({ details: { code: "insufficient" } })).toEqual({ balance: 0 });
    expect(insufficientBalance({ details: { code: "other" } })).toBeNull();
    expect(insufficientBalance(null)).toBeNull();
    expect(insufficientBalance(new Error("x"))).toBeNull();
  });
});
