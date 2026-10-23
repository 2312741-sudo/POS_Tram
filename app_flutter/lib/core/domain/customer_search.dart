// lib/core/domain/customer_search.dart
//
// Tìm / xếp hạng khách hàng cho ô "Tìm khách" (logic thuần, test được).
// - Rỗng: khách gần đây nhất trước, rồi nhiều điểm nhất.
// - Số điện thoại: đủ số, 3+ số CUỐI (suffix), hoặc một phần bất kỳ (từ 3 số).
// - Tên: không phân biệt dấu/hoa thường, thứ tự từ bất kỳ ("nguyen van a" → "Nguyễn Văn A").
// Bản web tương ứng: web/lib/customer-search.ts (giữ hai bản cùng quy tắc).

class CustomerCandidate {
  final String id;
  final String name;
  final String phone;
  final int points;
  final int totalPoints;

  /// Lần ghé/gắn hóa đơn gần nhất (ms), 0 nếu chưa rõ
  final int lastVisitAt;
  final String gender;
  final String birthday;

  const CustomerCandidate({
    required this.id,
    required this.name,
    required this.phone,
    this.points = 0,
    this.totalPoints = 0,
    this.lastVisitAt = 0,
    this.gender = 'Khác',
    this.birthday = '',
  });
}

/// Khoảng [start, end) trong chuỗi hiển thị cần tô sáng
class MatchRange {
  final int start;
  final int end;
  const MatchRange(this.start, this.end);
  @override
  bool operator ==(Object other) => other is MatchRange && other.start == start && other.end == end;
  @override
  int get hashCode => Object.hash(start, end);
  @override
  String toString() => '[$start,$end)';
}

class CustomerMatch {
  final CustomerCandidate customer;
  final int score;
  final List<MatchRange> nameRanges;
  final MatchRange? phoneRange;
  const CustomerMatch(this.customer, this.score, {this.nameRanges = const [], this.phoneRange});
}

const _from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
const _to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

/// Bỏ dấu tiếng Việt + chữ thường, GIỮ NGUYÊN độ dài (để tô sáng đúng vị trí)
String foldVi(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    final i = _from.indexOf(c);
    b.write(i >= 0 ? _to[i] : c);
  }
  return b.toString();
}

String digitsOf(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

/// 0901234567 → 090****567 (cho người không có quyền xem đủ SĐT)
String maskPhone(String phone) {
  final d = phone.trim();
  if (d.length < 7) return d;
  return '${d.substring(0, 3)}${'*' * (d.length - 6)}${d.substring(d.length - 3)}';
}

List<CustomerMatch> searchCustomers(List<CustomerCandidate> all, String query, {int limit = 10}) {
  final q = query.trim();
  if (q.isEmpty) {
    final list = [...all]..sort((a, b) => b.lastVisitAt != a.lastVisitAt ? b.lastVisitAt.compareTo(a.lastVisitAt) : b.points.compareTo(a.points));
    return [for (final c in list.take(limit)) CustomerMatch(c, 0)];
  }
  final onlyDigits = RegExp(r'^[0-9\s.\-+()]+$').hasMatch(q);
  final qd = digitsOf(q);
  final tokens = foldVi(q).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  final out = <CustomerMatch>[];
  for (final c in all) {
    if (onlyDigits) {
      if (qd.length < 3) continue;
      final p = digitsOf(c.phone);
      final idx = p.indexOf(qd);
      if (idx < 0) continue;
      final score = p == qd ? 100 : p.endsWith(qd) ? 90 : 70;
      out.add(CustomerMatch(c, score, phoneRange: _phoneRange(c.phone, idx, qd.length)));
    } else {
      final name = foldVi(c.name);
      final ranges = <MatchRange>[];
      var ok = tokens.isNotEmpty;
      for (final t in tokens) {
        final i = name.indexOf(t);
        if (i < 0) {
          ok = false;
          break;
        }
        ranges.add(MatchRange(i, i + t.length));
      }
      if (!ok) continue;
      final startsWord = tokens.every((t) => name.startsWith(t) || name.contains(' $t'));
      out.add(CustomerMatch(c, startsWord ? 60 : 40, nameRanges: _merge(ranges)));
    }
  }
  out.sort((a, b) {
    if (a.score != b.score) return b.score.compareTo(a.score);
    if (a.customer.lastVisitAt != b.customer.lastVisitAt) return b.customer.lastVisitAt.compareTo(a.customer.lastVisitAt);
    return b.customer.points.compareTo(a.customer.points);
  });
  return out.take(limit).toList();
}

/// Đổi vị trí trong chuỗi chỉ-số sang vị trí trong SĐT hiển thị (có thể có dấu cách/chấm)
MatchRange? _phoneRange(String phone, int digitIdx, int len) {
  var seen = 0;
  int? start;
  for (var i = 0; i < phone.length; i++) {
    if (RegExp(r'[0-9]').hasMatch(phone[i])) {
      if (seen == digitIdx) start = i;
      if (seen == digitIdx + len - 1 && start != null) return MatchRange(start, i + 1);
      seen++;
    }
  }
  return null;
}

List<MatchRange> _merge(List<MatchRange> r) {
  final s = [...r]..sort((a, b) => a.start.compareTo(b.start));
  final out = <MatchRange>[];
  for (final x in s) {
    if (out.isNotEmpty && x.start <= out.last.end) {
      out[out.length - 1] = MatchRange(out.last.start, x.end > out.last.end ? x.end : out.last.end);
    } else {
      out.add(x);
    }
  }
  return out;
}
