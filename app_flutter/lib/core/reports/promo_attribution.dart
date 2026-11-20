// KHUYẾN MÃI TÍNH CHO NGƯỜI BẤM MÓN (không phải người thu tiền).
//
// Lúc thanh toán: mỗi khuyến mãi (combo, giảm món, tặng món, giảm hóa đơn…) được chia theo NGƯỜI BẤM các món nhận ưu đãi
// → lưu vào BillDiscountModel.staffShares = [{u, n, amount, combo}] (tổng amount = discount.amount).
//   - Tiền giảm từng dòng = phần chương trình đó giảm trên dòng (đã trừ giảm tay); giảm hóa đơn chia theo dòng như engine.
//   - Số combo = số phần món được thưởng (rewardBenefits) trên dòng của người đó.
// Báo cáo: lọc / gom theo nhân viên dùng staffShares. Hóa đơn cũ chưa có: cả đơn do 1 người bấm → người đó; còn lại → thu ngân.
// Bản TS song song: web/lib/promo-attribution.ts (test đối chiếu: docs/promo_attribution_parity.json).
import '../../data/models/bill_model.dart';
import '../../data/models/campaign_models.dart';
import '../../data/models/promotion_model.dart';
import '../domain/pricing_engine.dart';

class LineStaff {
  final String u;
  final String n;
  const LineStaff(this.u, this.n);

  String get key => (u.isNotEmpty ? u : n).trim().toLowerCase();
}

class PromoAttribution {
  PromoAttribution._();

  /// Chia [total] theo trọng số (phần dư cho phần lẻ lớn nhất, hòa theo thứ tự) — khớp apportion (web)
  static List<int> _apportion(List<int> weights, int total) {
    final sum = weights.fold<int>(0, (a, b) => a + b);
    if (sum <= 0) return [for (final _ in weights) 0];
    final raw = [for (final w in weights) w * total / sum];
    final out = [for (final r in raw) r.floor()];
    var left = total - out.fold<int>(0, (a, b) => a + b);
    final order = [for (var i = 0; i < raw.length; i++) (i: i, f: raw[i] - raw[i].floor())]
      ..sort((a, b) {
        final c = b.f.compareTo(a.f);
        return c != 0 ? c : a.i.compareTo(b.i);
      });
    for (var k = 0; left > 0 && k < order.length; k++, left--) {
      out[order[k].i] += 1;
    }
    return out;
  }

  /// Chia một khuyến mãi theo người bấm món từ báo giá cộng dồn của chương trình đó (quoteStacked[campaignId]).
  /// [staffOfLine]: người bấm dòng; dòng không rõ → [fallback] (thu ngân). [storedAmount]: tiền đã lưu, làm tròn khớp.
  static List<PromoStaffShare> shares(
    PriceQuoteModel quote,
    List<PricingLineItem> lines,
    String campaignId,
    LineStaff? Function(String lineId) staffOfLine,
    LineStaff fallback, {
    int? storedAmount,
  }) {
    final byLine = {for (final l in lines) l.lineId: l};
    final keys = <String>[];
    final who = <String, LineStaff>{};
    final amount = <String, int>{};
    final combo = <String, int>{};
    void add(String lineId, int amt, int cnt) {
      if (amt <= 0 && cnt <= 0) return;
      final s = staffOfLine(lineId);
      final w = (s != null && s.key.isNotEmpty) ? s : fallback;
      final k = w.key.isEmpty ? '?' : w.key;
      if (!who.containsKey(k)) {
        who[k] = w;
        keys.add(k);
      }
      amount[k] = (amount[k] ?? 0) + (amt > 0 ? amt : 0);
      combo[k] = (combo[k] ?? 0) + (cnt > 0 ? cnt : 0);
    }

    for (final lb in quote.lineBenefits) {
      if (lb.campaignId.isNotEmpty) continue;
      final manual = byLine[lb.lineId]?.manualLineDiscount ?? 0;
      add(lb.lineId, lb.discountMoney - manual, 0);
    }
    for (final rb in quote.rewardBenefits) {
      if (rb.campaignId.isNotEmpty && rb.campaignId != campaignId) continue;
      add(rb.lineId, 0, rb.quantity);
    }
    var amts = [for (final k in keys) amount[k] ?? 0];
    if (storedAmount != null && storedAmount >= 0) {
      final sum = amts.fold<int>(0, (a, b) => a + b);
      if (sum != storedAmount) {
        if (sum <= 0) {
          final c = combo.values.fold<int>(0, (a, b) => a + b);
          return storedAmount > 0 || c > 0
              ? [PromoStaffShare(u: fallback.u, n: fallback.n.isEmpty ? fallback.u : fallback.n, amount: storedAmount, combo: c)]
              : const [];
        }
        amts = _apportion(amts, storedAmount);
      }
    }
    return [
      for (var i = 0; i < keys.length; i++)
        if (amts[i] > 0 || (combo[keys[i]] ?? 0) > 0)
          PromoStaffShare(
            u: who[keys[i]]!.u,
            n: who[keys[i]]!.n.isEmpty ? who[keys[i]]!.u : who[keys[i]]!.n,
            amount: amts[i],
            combo: combo[keys[i]] ?? 0,
          ),
    ];
  }

  static LineStaff cashierOf(BillModel b) => LineStaff(b.staffUsername.trim(), b.staffFullName.trim().isEmpty ? b.staffUsername.trim() : b.staffFullName.trim());

  /// Người bấm món duy nhất của hóa đơn (cả đơn do 1 người bấm), không thì null
  static LineStaff? soleOrderer(BillModel b) {
    final seen = <String, LineStaff>{};
    for (final it in b.items) {
      final u = it.orderedBy.trim();
      final n = it.orderedByName.trim();
      final s = LineStaff(u, n.isEmpty ? u : n);
      if (s.key.isNotEmpty) seen[s.key] = s;
    }
    return seen.length == 1 ? seen.values.first : null;
  }

  /// Phần chia theo người bấm món của một khuyến mãi (hóa đơn cũ: người bấm duy nhất / thu ngân)
  static List<PromoStaffShare> discountShares(BillModel b, BillDiscountModel d) {
    final saved = d.staffShares;
    if (saved != null && saved.isNotEmpty) return saved;
    final w = soleOrderer(b) ?? cashierOf(b);
    final combo = d.comboCount ?? 0;
    return d.amount > 0 || combo > 0 ? [PromoStaffShare(u: w.u, n: w.n, amount: d.amount, combo: combo)] : const [];
  }

  /// Số combo của một khuyến mãi: có staffShares thì lấy tổng từ đó (cùng nguồn bảng "theo nhân viên" → luôn khớp),
  /// hóa đơn cũ: comboCount. Khớp discountComboCount (web).
  static int comboCountOf(BillDiscountModel d) {
    final saved = d.staffShares;
    if (saved != null && saved.any((s) => s.amount > 0 || s.combo > 0)) {
      return saved.fold<int>(0, (a, s) => a + (s.combo > 0 ? s.combo : 0));
    }
    final c = d.comboCount ?? 0;
    return c > 0 ? c : 0;
  }

  /// Hóa đơn chỉ giữ phần khuyến mãi của nhân viên [matches] (theo người bấm món) — cho báo cáo khuyến mãi / chương trình
  /// lọc theo nhân viên. Đổi điểm (cả hóa đơn) tính cho thu ngân; giảm tay trên món tính cho người bấm món đó.
  static List<BillModel> attributeBillsToStaff(List<BillModel> bills, bool Function(LineStaff) matches) {
    final out = <BillModel>[];
    for (final b in bills) {
      final discounts = <BillDiscountModel>[];
      for (final d in b.discounts) {
        final mine = discountShares(b, d).where((s) => matches(LineStaff(s.u, s.n))).toList();
        final amt = mine.fold<int>(0, (a, s) => a + s.amount);
        final cnt = mine.fold<int>(0, (a, s) => a + s.combo);
        if (amt <= 0 && cnt <= 0) continue;
        final copy = BillDiscountModel.fromMap({...d.toMap(), 'amount': amt, 'comboCount': cnt > 0 ? cnt : null});
        discounts.add(copy.copyWith(staffShares: mine));
      }
      final cashierMine = matches(cashierOf(b));
      final items = b.items.where((it) {
        final u = it.orderedBy.trim();
        final n = it.orderedByName.trim();
        return (u.isNotEmpty || n.isNotEmpty) ? matches(LineStaff(u, n.isEmpty ? u : n)) : cashierMine;
      }).toList();
      final points = cashierMine && (b.pointsDiscount > 0 || b.pointsUsed > 0);
      if (discounts.isEmpty && !points && items.isEmpty) continue;
      final copy = BillModel.fromMap(b.toMap(), b.id)
        ..items = items
        ..discounts = discounts
        ..pointsDiscount = points ? b.pointsDiscount : 0
        ..pointsUsed = points ? b.pointsUsed : 0;
      out.add(copy);
    }
    return out;
  }

  /// So khớp nhân viên theo username / tên / bí danh (giống lọc nhân viên của Trung tâm báo cáo)
  static bool Function(LineStaff) matcher(String staff, [Iterable<String>? aliases]) {
    final targets = <String>{
      for (final t in [staff, ...?aliases])
        if (t.trim().isNotEmpty) t.trim().toLowerCase(),
    };
    return (s) => targets.contains(s.u.trim().toLowerCase()) || targets.contains(s.n.trim().toLowerCase());
  }
}
