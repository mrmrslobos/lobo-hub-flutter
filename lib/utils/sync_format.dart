import 'package:intl/intl.dart';

/// Short label for “last successful sync” in banners and tooltips.
String formatRelativeSyncTime(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inSeconds < 45) return 'Just updated';
  if (d.inMinutes < 1) return 'Updated moments ago';
  if (d.inHours < 1) return 'Updated ${d.inMinutes}m ago';
  if (d.inHours < 24) return 'Updated ${d.inHours}h ago';
  if (d.inDays < 7) return 'Updated ${d.inDays}d ago';
  return 'Updated ${DateFormat('MMM d, h:mm a').format(at)}';
}
