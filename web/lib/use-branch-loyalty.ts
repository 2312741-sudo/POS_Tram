"use client";
import { useEffect, useMemo, useState } from "react";
import { onValue, ref } from "firebase/database";
import { db } from "./firebase";
import { parseStoreCustomers, type StoreCustomer } from "./customers";
import { DEFAULT_LOYALTY_TIERS, parseChainConfig, type ChainLoyaltyConfig, type LoyaltyTier } from "./loyalty";
import { applyLoyaltyEarn, lookupMember } from "./loyalty-client";
import { listEarnQueueKeys, processEarnQueue } from "./loyalty-earn-queue";
import { resolveRates, type LoyaltyRates } from "./loyalty-checkout";

/**
 * Khách của chi nhánh (realtime) + cấu hình tích điểm TOÀN CHUỖI (loyalty_config, thiếu thì storeInfo).
 * Chỉ lắng nghe khi `enabled` (quyền đủ + đang mở bàn) để không tốn băng thông.
 */
export function useBranchLoyalty(args: {
  storeCode: string;
  enabled: boolean;
  store?: { pointEarnRate?: unknown; pointRedeemRate?: unknown; loyaltyTiers?: LoyaltyTier[] };
}) {
  const { storeCode, enabled, store } = args;
  const [raw, setRaw] = useState<{ store: string; val: unknown; denied: boolean } | null>(null);
  const [chain, setChain] = useState<ChainLoyaltyConfig>({});

  useEffect(() => {
    if (!enabled || !storeCode) return;
    return onValue(
      ref(db, `stores/${storeCode}/customers`),
      (snap) => setRaw({ store: storeCode, val: snap.val(), denied: false }),
      () => setRaw({ store: storeCode, val: null, denied: true })
    );
  }, [enabled, storeCode]);

  useEffect(() => {
    if (!enabled) return;
    return onValue(
      ref(db, "loyalty_config"),
      (snap) => setChain(parseChainConfig(snap.val())),
      () => setChain({})
    );
  }, [enabled]);

  const tiers = chain.loyaltyTiers ?? store?.loyaltyTiers ?? DEFAULT_LOYALTY_TIERS;
  const current = raw && raw.store === storeCode ? raw : null;
  const customers = useMemo<StoreCustomer[]>(() => (current ? parseStoreCustomers(storeCode, current.val, tiers) : []), [current, storeCode, tiers]);
  const rates = useMemo<LoyaltyRates>(() => resolveRates(chain, store), [chain, store]);

  return { customers, loading: enabled && !current, denied: !!current?.denied, rates, tiers };
}

/** Số dư điểm DÙNG CHUNG toàn chuỗi của khách (lookupMember); lỗi → dùng bản sao tại chi nhánh */
export function useMemberBalance(storeCode: string, customerId: string, fallbackPoints: number, fallbackTotal: number, refreshKey = 0) {
  const [res, setRes] = useState<{ key: string; points: number; total: number } | null>(null);
  const key = `${storeCode}/${customerId}/${refreshKey}`;
  useEffect(() => {
    if (!storeCode || !customerId) return;
    let cancelled = false;
    lookupMember(storeCode, { customerId })
      .then((m) => {
        if (cancelled) return;
        if (m.found) setRes({ key, points: Math.max(0, Math.trunc(m.points ?? 0)), total: Math.max(0, Math.trunc(m.totalPoints ?? m.points ?? 0)) });
        else setRes({ key, points: fallbackPoints, total: fallbackTotal });
      })
      .catch(() => !cancelled && setRes({ key, points: fallbackPoints, total: fallbackTotal }));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key]);
  if (!customerId) return { points: 0, total: 0, shared: false };
  if (res && res.key === key) return { points: res.points, total: Math.max(res.total, res.points), shared: true };
  return { points: fallbackPoints, total: Math.max(fallbackTotal, fallbackPoints), shared: false };
}

/**
 * Thử lại tích điểm lỗi (hàng đợi localStorage): chạy khi mở trang và mỗi 3 phút.
 * applyLoyaltyEarn idempotent theo hóa đơn nên an toàn khi thử lại.
 */
export function useLoyaltyEarnRetry(username: string | undefined, onDone?: (count: number) => void) {
  useEffect(() => {
    if (!username || typeof window === "undefined") return;
    let stopped = false;
    const run = async () => {
      let storage: Storage;
      try {
        storage = window.localStorage;
      } catch {
        return;
      }
      let count = 0;
      for (const { key, storeCode } of listEarnQueueKeys(storage, username)) {
        const r = await processEarnQueue(storage, key, (billId) => applyLoyaltyEarn(storeCode, billId));
        count += r.done.length;
      }
      if (count > 0 && !stopped) onDone?.(count);
    };
    void run();
    const t = setInterval(() => void run(), 3 * 60_000);
    return () => {
      stopped = true;
      clearInterval(t);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [username]);
}
