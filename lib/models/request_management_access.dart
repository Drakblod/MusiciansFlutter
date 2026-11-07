import 'sub_request.dart';

/// A session-scoped result of canonical authorization, never a route credential.
class RequestManagementAccess {
  RequestManagementAccess({
    required this.userId,
    required this.bandId,
    this.request,
    this.headers = const {},
  });
  bool _revoked = false;
  bool get isValid => !_revoked;
  void revoke() => _revoked = true;
  final String userId;
  final String bandId;
  final SubRequest? request;
  final Map<String, Object?> headers;
}
