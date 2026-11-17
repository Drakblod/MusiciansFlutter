import '../models/sub_request.dart';

/// Preserves feed order so the existing active policy can deduplicate positions.
Iterable<SubRequest> manageRequestCandidates({
  required Iterable<SubRequest> ownRequests,
  required Iterable<SubRequest> visibleRequests,
  required String bandId,
}) sync* {
  yield* ownRequests.where((request) => request.bandId == bandId);
  yield* visibleRequests.where((request) => request.bandId == bandId);
}

/// Recruitment includes the canonical request type and older role-only rows.
bool isManageMemberRecruitment(SubRequest request) =>
    request.isNewMember || request.role == 'New Member' || request.role == 'Member';
