import 'package:firebase_auth/firebase_auth.dart';

String loginFailureMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
      case 'invalid-login-credentials':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'Unable to connect. Check your internet connection.';
      case 'user-disabled':
        return 'This account has been disabled.';
    }
  }
  return 'Unable to sign in right now. Please try again.';
}
