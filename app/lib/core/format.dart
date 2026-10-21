String fmtBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final digits = (i == 0 || v >= 100) ? 0 : 1;
  return '${v.toStringAsFixed(digits)} ${units[i]}';
}

String fmtCount(num n) {
  final s = n.toInt().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String plural(num n, String one, [String? many]) =>
    '${fmtCount(n)} ${n == 1 ? one : (many ?? '${one}s')}';

/// Seconds since epoch -> "5 min ago", "yesterday", "3 Oct".
String fmtAgo(int? secs, {DateTime? now}) {
  if (secs == null || secs <= 0) return 'never';
  final then = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
  final diff = (now ?? DateTime.now()).difference(then);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays == 1) return 'yesterday';
  if (diff.inDays < 7) return '${diff.inDays} days ago';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${then.day} ${months[then.month - 1]} ${then.year}';
}

String fmtDuration(int ms) {
  if (ms < 1000) return '$ms ms';
  final s = ms / 1000;
  if (s < 60) return '${s.toStringAsFixed(1)} s';
  return '${(s ~/ 60)} min ${(s % 60).round()} s';
}

String fmtTemp(int celsius, String unit) =>
    unit == 'f' ? '${(celsius * 9 / 5 + 32).round()} °F' : '$celsius °C';

/// A long stretch of time in the largest sensible unit: "40 days", "7 months", "4.7 years".
String fmtSpan(num hours) {
  final days = hours / 24;
  if (days < 60) return plural(days.round(), 'day');
  final months = days / 30.44;
  if (months < 24) return plural(months.round(), 'month');
  final years = days / 365.25;
  return '${years.toStringAsFixed(years < 10 ? 1 : 0)} years';
}
