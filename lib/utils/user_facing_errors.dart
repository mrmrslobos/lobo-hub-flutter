/// Short, user-safe copy for sync and network failures (avoid raw stack traces in UI).

String humanizeCloudSyncError(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '';

  final lower = s.toLowerCase();

  if (lower.contains('failed host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('network is unreachable')) {
    return 'Check your internet connection and try again.';
  }
  if (lower.contains('connection refused') ||
      lower.contains('connection reset') ||
      lower.contains('clientexception')) {
    return 'Couldn’t reach the server. Try again in a moment.';
  }
  if (lower.contains('timeout') || lower.contains('timed out')) {
    return 'The request timed out. Try again when your connection is stable.';
  }
  if (lower.contains('jwt expired') ||
      (lower.contains('401') && lower.contains('auth')) ||
      lower.contains('invalid refresh')) {
    return 'Your session may have expired. Sign out and sign back in if this keeps happening.';
  }
  if (lower.contains('403') ||
      lower.contains('row-level security') ||
      lower.contains('permission denied')) {
    return 'Some data couldn’t be loaded due to permissions. If this persists, contact support.';
  }
  if (lower.contains('column') &&
      (lower.contains('does not exist') || lower.contains('pgrst'))) {
    return 'The server responded with an unexpected data shape. An app update may be required.';
  }

  if (s.length > 220) {
    return 'Something went wrong while syncing. Check your connection and tap Retry.';
  }
  return s;
}

String humanizeForSnackBar(Object error) {
  return humanizeCloudSyncError(error.toString());
}
