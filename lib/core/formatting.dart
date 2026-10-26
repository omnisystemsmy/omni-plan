import 'package:intl/intl.dart';

/// Shared formatting helpers for money, dates and relative times.
class Fmt {
  const Fmt._();

  static final NumberFormat _amount = NumberFormat('#,##0.00', 'en_US');
  static final NumberFormat _plain = NumberFormat('#,##0.##', 'en_US');
  static final DateFormat _isoDate = DateFormat('yyyy-MM-dd');
  static final DateFormat _longDate = DateFormat('d MMMM yyyy', 'en_US');
  static final DateFormat _shortDate = DateFormat('d MMM yyyy', 'en_US');

  /// Cents -> "1,234.50".
  static String cents(int cents) => _amount.format(cents / 100);

  /// Cents -> "RM 1,234.50".
  static String money(int cents, String symbol) {
    final s = symbol.trim();
    final body = Fmt.cents(cents);
    return s.isEmpty ? body : '$s $body';
  }

  /// Quantities: 2 -> "2", 1.5 -> "1.5".
  static String quantity(double q) => _plain.format(q);

  static String isoDate(DateTime d) => _isoDate.format(d);

  static DateTime? parseIso(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return _isoDate.parseStrict(s.trim());
    } catch (_) {
      return null;
    }
  }

  /// "2026-10-20" -> "20 October 2026"; unparsable input is returned as is.
  static String longDate(String? iso) {
    final d = parseIso(iso);
    return d == null ? (iso ?? '') : _longDate.format(d);
  }

  static String shortDate(DateTime d) => _shortDate.format(d);

  /// "just now", "5 min ago", "Yesterday", "12 Oct 2026".
  static String relative(DateTime t, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final diff = n.difference(t);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(t.year, t.month, t.day);
    final days = today.difference(day).inDays;
    if (days == 0) return '${diff.inHours} h ago';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    return shortDate(t);
  }
}
