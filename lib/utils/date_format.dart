/// Small dependency-free date formatting helpers (avoids adding `intl`).
///
/// Output examples: `24 Sep 2026, 14:30` and `24 Sep 2026`.
String formatDueDate(DateTime date) {
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day ${months[date.month - 1]} ${date.year}, $hour:$minute';
}

String formatCreatedAt(DateTime date) {
  return formatDueDate(date);
}
