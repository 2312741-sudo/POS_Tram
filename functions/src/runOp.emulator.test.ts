/**
 * Hồi quy: giao dịch điểm trên server phải dùng số dư THẬT ở lần chạy đầu (Admin SDK gọi callback với cache rỗng).
 * Lỗi cũ: chỉnh điểm kiểu SET về 0 báo "không đổi", SUB báo "không đủ điểm" dù khách còn 20 điểm.
 *
 * Chỉ chạy khi có Realtime Database emulator (firebase emulators:exec --only database ...);
 * không có emulator thì tự bỏ qua để `npm test` thường vẫn xanh.
 */
import { describe, it, expect, beforeAll, beforeEach } from "vitest";
import * as admin from "firebase-admin";

const EMU = process.env.FIREBASE_DATABASE_EMULATOR_HOST;

describe.skipIf(!EMU)("runOp trên emulator — số dư thật ở lần chạy đầu", () => {
  let runOp: typeof import("./sharedLoyaltyHandlers").runOp;
  let db: admin.database.Database;
  const store = "TRAM01";
  const phone = "0865062205";

  beforeAll(async () => {
    process.env.GCLOUD_PROJECT = "demo-tram-pos";
    if (!admin.apps.length) admin.initializeApp({ databaseURL: `http://${EMU}?ns=demo-tram-pos`, projectId: "demo-tram-pos" });
    db = admin.database();
    ({ runOp } = await import("./sharedLoyaltyHandlers"));
  });

  beforeEach(async () => {
    await db.ref("/").set(null);
    await db.ref(`loyalty_members/${phone}`).set({
      name: "NGUYỄN THANH TÂM", phone, points: 20, totalPoints: 44, joinedAt: 1, updatedAt: 1,
      lastStoreCode: store, branches: { [store]: { CUST_1: true } },
    });
  });

  const target = { memberKey: phone, customerId: "CUST_1", name: "NGUYỄN THANH TÂM", phone };
  const extra = { staff: "admin", note: "oke" };
  const now = () => Date.now();

  it("SET về 0 từ 20 điểm → applied, số dư 0", async () => {
    const r = await runOp(target, { type: "adjust", points: 0, setTo: 0, opId: "adj_set0", storeCode: store, now: now() }, extra);
    expect(r.status).toBe("applied");
    expect(r.before).toBe(20);
    expect(r.after).toBe(0);
    expect((await db.ref(`loyalty_members/${phone}/points`).get()).val()).toBe(0);
  });

  it("SUB 5 từ 20 điểm → applied, còn 15", async () => {
    const r = await runOp(target, { type: "adjust", points: -5, opId: "adj_sub5", storeCode: store, now: now() }, extra);
    expect(r.status).toBe("applied");
    expect(r.after).toBe(15);
  });

  it("SUB 30 từ 20 điểm → insufficient (số dư thật là 20, không phải 0)", async () => {
    const r = await runOp(target, { type: "adjust", points: -30, opId: "adj_sub30", storeCode: store, now: now() }, extra);
    expect(r.status).toBe("insufficient");
    expect(r.before).toBe(20);
  });

  it("SET đúng bằng số dư hiện tại → invalid (không đổi)", async () => {
    const r = await runOp(target, { type: "adjust", points: 0, setTo: 20, opId: "adj_same", storeCode: store, now: now() }, extra);
    expect(r.status).toBe("invalid");
    expect(r.before).toBe(20);
  });

  it("ADD 7 vẫn hoạt động", async () => {
    const r = await runOp(target, { type: "adjust", points: 7, opId: "adj_add7", storeCode: store, now: now() }, extra);
    expect(r.status).toBe("applied");
    expect(r.after).toBe(27);
  });

  it("gọi lại cùng opId → alreadyApplied (idempotent)", async () => {
    const req = { type: "adjust" as const, points: -5, opId: "adj_dup", storeCode: store, now: now() };
    await runOp(target, req, extra);
    const r = await runOp(target, req, extra);
    expect(r.status).toBe("alreadyApplied");
    expect((await db.ref(`loyalty_members/${phone}/points`).get()).val()).toBe(15);
  });
});
