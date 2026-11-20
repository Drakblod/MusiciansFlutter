import '../models/agreement.dart';

String? conversationText(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

String? conversationType(Map row) =>
    (conversationText(row['conversationType']) ??
            conversationText(row['ConversationType']))
        ?.toLowerCase();

Agreement? conversationAgreement(Map row) {
  for (final value in [row['agreement'], row['Agreement']]) {
    if (value is Map && value.isNotEmpty) return Agreement.fromJson(value);
  }
  return null;
}

bool isAgreementThread(Map row) =>
    row['agreement'] is Agreement || conversationType(row) == 'agreement';

bool isGroupThread(Map row) =>
    !isAgreementThread(row) && conversationType(row) == 'band_section';

bool needsConversationMetadata(Map index) {
  final type = conversationType(index);
  final agreement = conversationAgreement(index);
  if (agreement != null) return false;
  return !const {
        'direct',
        'agreement',
        'band_section',
        'session_chat',
      }.contains(type) ||
      type == 'agreement' ||
      (type == 'direct' && conversationText(index['otherUserId']) == null);
}

Map<String, dynamic> resolveConversationMetadata({
  required Map index,
  required String selfId,
  Map? canonical,
}) {
  final agreement =
      conversationAgreement(index) ??
      (canonical == null ? null : conversationAgreement(canonical));
  final type = agreement != null || conversationType(index) == 'agreement'
      ? 'agreement'
      : (canonical == null ? null : conversationType(canonical)) ??
            conversationType(index);

  var counterpart = conversationText(index['otherUserId']);
  if (selfId == agreement?.choirLeaderId) {
    counterpart = conversationText(agreement?.vocalistId) ?? counterpart;
  } else if (selfId == agreement?.vocalistId) {
    counterpart = conversationText(agreement?.choirLeaderId) ?? counterpart;
  }
  if (counterpart == null && type != 'band_section' && type != 'session_chat') {
    final participants = canonical?['participants'];
    if (participants is Map && participants[selfId] == true) {
      final others = participants.entries
          .where((entry) => entry.key != selfId && entry.value == true)
          .map((entry) => conversationText(entry.key))
          .whereType<String>();
      counterpart = others.singleOrNull;
    }
  }
  return {
    'conversationType': type,
    'agreement': agreement,
    'otherUserId': counterpart,
    'bandId':
        conversationText(agreement?.bandId) ??
        conversationText(canonical?['bandId']) ??
        conversationText(canonical?['BandId']) ??
        conversationText(index['bandId']) ??
        conversationText(index['BandId']),
  };
}
