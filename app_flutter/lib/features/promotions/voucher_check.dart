import 'dart:math';
import '../../core/domain/pricing_engine.dart';
import '../../core/utils/format_utils.dart';
import '../../data/models/campaign_models.dart';

/// Kết quả tách danh sách mã voucher do chủ quán nhập/dán
class ParsedVoucherCodes {
  final List<String> valid; // đã chuẩn hóa (IN HOA), không trùng
  final List<String> invalid; // chứa ký tự không hợp lệ
  final List<String> duplicated; // trùng trong chính danh sách nhập
  const ParsedVoucherCodes(this.valid, this.invalid, this.duplicated);
}

final RegExp _codePattern = RegExp(r'^[A-Z0-9_-]{3,32}$');

/// Chuẩn hóa mã: bỏ khoảng trắng 2 đầu, IN HOA
String normalizeVoucherCode(String code) => code.trim().toUpperCase();

/// Tách chuỗi nhiều mã (mỗi dòng 1 mã, hoặc cách nhau bởi dấu phẩy / chấm phẩy / khoảng trắng).
/// Mã hợp lệ: 3-32 ký tự A-Z, 0-9, '-', '_' (mã còn được dùng làm khóa Firebase).
ParsedVoucherCodes parseVoucherCodes(String raw) {
  final valid = <String>[];
  final invalid = <String>[];
  final dup = <String>[];
  for (final part in raw.split(RegExp(r'[\s,;]+'))) {
    final code = normalizeVoucherCode(part);
    if (code.isEmpty) continue;
    if (!_codePattern.hasMatch(code)) {
      invalid.add(code);
    } else if (valid.contains(code)) {
      if (!dup.contains(code)) dup.add(code);
    } else {
      valid.add(code);
    }
  }
  return ParsedVoucherCodes(valid, invalid, dup);
}

/// Sinh [qty] mã ngẫu nhiên dạng PREFIX + [length] ký tự (không trùng nhau)
List<String> generateRandomVoucherCodes(int qty, {String prefix = '', int length = 6, Random? random}) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // bỏ I, O, 0, 1 dễ nhầm
  final rnd = random ?? Random.secure();
  final p = normalizeVoucherCode(prefix).replaceAll(RegExp(r'[^A-Z0-9_-]'), '');
  final out = <String>{};
  int guard = 0;
  while (out.length < qty && guard < qty * 20) {
    guard++;
    out.add(p + String.fromCharCodes(Iterable.generate(length, (_) => chars.codeUnitAt(rnd.nextInt(chars.length)))));
  }
  return out.toList();
}

/// Mô tả ngắn lợi ích của chương trình (hiển thị khi nhập mã)
String describeCampaignBenefit(CampaignModel c) {
  String money(int v) => FormatUtils.vnd(v);
  String benefit(String mode, int value) {
    switch (normalizeBenefitMode(mode)) {
      case 'FREE':
        return 'tặng';
      case 'PERCENT':
        final pct = value / 100;
        return 'giảm ${pct == pct.roundToDouble() ? pct.toInt() : pct}%';
      case 'FIXED':
        return 'giảm ${money(value)}';
      case 'FIXEDPRICE':
        return 'đồng giá ${money(value)}';
      default:
        return '';
    }
  }

  final type = c.campaignType.toUpperCase().replaceAll('_', '');
  if (type == 'BUYXGETY') {
    if (c.buyConditions.isEmpty) return c.typeDisplay;
    final b = c.buyConditions.first;
    return 'Mua ${b.requiredBuyQty} món X ${benefit(b.benefitMode, b.value)} ${b.rewardQty} món Y'
        '${b.multiplyByBundle ? " (nhân theo số món X)" : ""}';
  }
  if (c.tiers.isEmpty) return c.typeDisplay;
  final t = c.tiers.first;
  final from = t.threshold > 0 ? ' cho đơn từ ${money(t.threshold)}' : '';
  if (type == 'ORDERVALUEITEMBENEFIT') {
    final qty = t.maxRewardQty > 0 ? t.maxRewardQty : 1;
    return '${benefit(t.benefitMode, t.value)} $qty món$from';
  }
  final cap = t.maxDiscountMoney > 0 ? ', tối đa ${money(t.maxDiscountMoney)}' : '';
  return '${benefit(t.benefitMode, t.value)} hóa đơn$cap$from';
}

enum VoucherCheckStatus {
  valid,
  notFound,
  redeemed,
  cancelled,
  notReleased,
  held,
  campaignInactive,
  notStarted,
  ended,
  outsideSchedule,
  wrongBranch,
  notApplicable,
}

class VoucherCheckResult {
  final VoucherCheckStatus status;
  final String message;
  final VoucherModel? voucher;
  final CampaignModel? campaign;
  final int discount;

  const VoucherCheckResult(this.status, this.message, {this.voucher, this.campaign, this.discount = 0});

  bool get isValid => status == VoucherCheckStatus.valid;
}

String _fmtTime(int ms) => FormatUtils.dateTime(ms);

/// Ánh xạ kết quả tra cứu mã voucher → thông báo rõ ràng cho thu ngân (hàm thuần, dễ test).
/// [quote] là kết quả pricing engine của hóa đơn hiện tại với riêng chương trình của mã.
/// [currentBillId]: mã đã đổi bởi chính hóa đơn này vẫn được coi là hợp lệ.
VoucherCheckResult evaluateVoucher({
  required String code,
  required VoucherModel? voucher,
  required CampaignModel? campaign,
  required int nowMs,
  required String branchId,
  PriceQuoteModel? quote,
  String? currentBillId,
}) {
  final c = normalizeVoucherCode(code);
  if (voucher == null) {
    return VoucherCheckResult(VoucherCheckStatus.notFound, 'Mã $c không tồn tại');
  }
  final state = voucher.state.toUpperCase();
  if (state == VoucherState.redeemed.toMap() &&
      !(currentBillId != null && currentBillId.isNotEmpty && voucher.redeemedBillId == currentBillId)) {
    final bill = voucher.redeemedBillCode ?? voucher.redeemedBillId ?? '?';
    final at = voucher.redeemedAt != null ? _fmtTime(voucher.redeemedAt!) : '?';
    final by = voucher.redeemedByName ?? voucher.redeemedBy ?? '?';
    final table = (voucher.tableName ?? '').isNotEmpty ? ' (${voucher.tableName})' : '';
    return VoucherCheckResult(VoucherCheckStatus.redeemed, 'Mã đã được sử dụng ở đơn $bill$table lúc $at bởi $by',
        voucher: voucher, campaign: campaign);
  }
  if (state == VoucherState.cancelled.toMap()) {
    return VoucherCheckResult(VoucherCheckStatus.cancelled, 'Mã đã hủy', voucher: voucher, campaign: campaign);
  }
  if (state == VoucherState.draft.toMap()) {
    return VoucherCheckResult(VoucherCheckStatus.notReleased, 'Mã chưa được phát hành', voucher: voucher, campaign: campaign);
  }
  if (state == VoucherState.reserved.toMap() && voucher.holdExpiresAt != null && voucher.holdExpiresAt! > nowMs) {
    return VoucherCheckResult(VoucherCheckStatus.held, 'Mã đang được giữ bởi giao dịch khác', voucher: voucher, campaign: campaign);
  }
  if (campaign == null || !campaign.active) {
    return VoucherCheckResult(VoucherCheckStatus.campaignInactive, 'Chương trình của mã đã ngừng hoạt động',
        voucher: voucher, campaign: campaign);
  }
  final s = campaign.schedule;
  if (s.absoluteStart != null && nowMs < s.absoluteStart!) {
    return VoucherCheckResult(VoucherCheckStatus.notStarted,
        'Chương trình "${campaign.name}" chưa bắt đầu (từ ${_fmtTime(s.absoluteStart!)})',
        voucher: voucher, campaign: campaign);
  }
  if (s.absoluteEnd != null && nowMs > s.absoluteEnd!) {
    return VoucherCheckResult(VoucherCheckStatus.ended,
        'Chương trình "${campaign.name}" đã kết thúc (${_fmtTime(s.absoluteEnd!)})',
        voucher: voucher, campaign: campaign);
  }
  if (!campaign.isEligibleAt(nowMs)) {
    return VoucherCheckResult(VoucherCheckStatus.outsideSchedule,
        'Chương trình "${campaign.name}" không áp dụng vào ngày/khung giờ này',
        voucher: voucher, campaign: campaign);
  }
  if (!campaign.isEligibleForBranch(branchId)) {
    return VoucherCheckResult(VoucherCheckStatus.wrongBranch, 'Chương trình "${campaign.name}" không áp dụng tại chi nhánh này',
        voucher: voucher, campaign: campaign);
  }
  if (quote != null) {
    final discount = quote.totalPromotionDiscount;
    if (discount <= 0 || !quote.appliedCampaignIds.contains(campaign.campaignId)) {
      final reason = quote.reasons.where((r) => r.campaignId == campaign.campaignId).map((r) => r.reasonMessage).firstOrNull;
      return VoucherCheckResult(VoucherCheckStatus.notApplicable,
          'Mã hợp lệ nhưng chưa áp dụng được cho đơn này: ${reason ?? "đơn chưa đạt điều kiện"}',
          voucher: voucher, campaign: campaign);
    }
    return VoucherCheckResult(VoucherCheckStatus.valid,
        'Mã hợp lệ - ${campaign.name}: ${describeCampaignBenefit(campaign)}',
        voucher: voucher, campaign: campaign, discount: discount);
  }
  return VoucherCheckResult(VoucherCheckStatus.valid, 'Mã hợp lệ - ${campaign.name}: ${describeCampaignBenefit(campaign)}',
      voucher: voucher, campaign: campaign);
}
