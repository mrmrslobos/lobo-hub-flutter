// lib/utils/error_messages.dart
// Maps raw exceptions to user-friendly messages.

String friendlyErrorMessage(dynamic error) {
  final msg = error.toString().toLowerCase();

  // Network errors
  if (msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('network is unreachable') ||
      msg.contains('connection refused')) {
    return 'No internet connection. Please check your network and try again.';
  }
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return 'Request timed out. Please try again.';
  }
  if (msg.contains('handshake') || msg.contains('certificate')) {
    return 'Secure connection failed. Please try again later.';
  }

  // Auth errors
  if (msg.contains('invalid login credentials') ||
      msg.contains('invalid_credentials')) {
    return 'Incorrect email or password. Please try again.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please check your inbox and confirm your email address.';
  }
  if (msg.contains('user already registered') ||
      msg.contains('already been registered')) {
    return 'An account with this email already exists. Try signing in instead.';
  }
  if (msg.contains('email rate limit') || msg.contains('rate limit')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (msg.contains('weak password') || msg.contains('password')) {
    if (msg.contains('at least')) {
      return 'Password is too short. Use at least 6 characters.';
    }
  }
  if (msg.contains('invalid email') || msg.contains('invalid_email')) {
    return 'Please enter a valid email address.';
  }
  if (msg.contains('user not found') || msg.contains('no user')) {
    return 'No account found with that email. Please sign up.';
  }
  if (msg.contains('session expired') || msg.contains('jwt expired')) {
    return 'Your session has expired. Please sign in again.';
  }

  // Supabase / server errors
  if (msg.contains('500') || msg.contains('internal server')) {
    return 'Something went wrong on our end. Please try again later.';
  }
  if (msg.contains('503') || msg.contains('service unavailable')) {
    return 'Service temporarily unavailable. Please try again later.';
  }

  // Fallback: strip exception prefix and return
  return error
      .toString()
      .replaceAll('Exception: ', '')
      .replaceAll('AuthException: ', '')
      .replaceAll('PostgrestException: ', '');
}
