/// Formatting helpers (YouTube style).
library;

String formatDuration(Duration? d) {
  if (d == null) return '';
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// 1234 -> 1.2K, 3400000 -> 3.4M
String compactNumber(int? n) {
  if (n == null) return '';
  if (n < 1000) return '$n';
  String f(double v) => v >= 10 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.0', '');
  if (n < 1000000) return '${f(n / 1000)}K';
  if (n < 1000000000) return '${f(n / 1000000)}M';
  return '${f(n / 1000000000)}B';
}

/// "3 days ago" style relative date (English/Russian/Uzbek short forms).
String timeAgo(DateTime? date, {String lang = 'en'}) {
  if (date == null) return '';
  final diff = DateTime.now().difference(date);
  final (int n, String unit) = switch (diff) {
    _ when diff.inDays >= 365 => (diff.inDays ~/ 365, 'y'),
    _ when diff.inDays >= 30 => (diff.inDays ~/ 30, 'mo'),
    _ when diff.inDays >= 7 => (diff.inDays ~/ 7, 'w'),
    _ when diff.inDays >= 1 => (diff.inDays, 'd'),
    _ when diff.inHours >= 1 => (diff.inHours, 'h'),
    _ => (diff.inMinutes.clamp(1, 59), 'min'),
  };
  switch (lang) {
    case 'ru':
      const ru = {'y': 'г.', 'mo': 'мес.', 'w': 'нед.', 'd': 'дн.', 'h': 'ч', 'min': 'мин.'};
      return '$n ${ru[unit]} назад';
    case 'uz':
      const uz = {'y': 'yil', 'mo': 'oy', 'w': 'hafta', 'd': 'kun', 'h': 'soat', 'min': 'daqiqa'};
      return '$n ${uz[unit]} oldin';
    default:
      const en = {'y': 'year', 'mo': 'month', 'w': 'week', 'd': 'day', 'h': 'hour', 'min': 'minute'};
      return '$n ${en[unit]}${n == 1 ? '' : 's'} ago';
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// 31.5 -> "31.5", 1250 -> "1.25k", 10000 -> "10k", 12500 -> "12.5k".
String formatHz(double hz) {
  // Strip trailing zeros only after a decimal point ("10" must stay "10").
  String trim(String s) => s.contains('.') ? s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '') : s;
  if (hz >= 1000) return '${trim((hz / 1000).toStringAsFixed(2))}k';
  return trim(hz.toStringAsFixed(1));
}
