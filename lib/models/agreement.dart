class Agreement {
  final String? choirLeaderId;
  final String? vocalistId;
  final String? voicePart;
  final String? date;
  final String? startTime;
  final String? endTime;
  final String? location;
  final String? additionalTerms;
  final String? bandName;
  final String? subRequestId;
  final int? payAmount;
  final String? currency;

  // Rich snapshot fields
  final String? bandId;
  final String? requestGroupId;
  final String? eventId;
  final String? requestType;
  final String? eventType;
  final String? description;
  final String? payDetails;
  final String? choirLeaderName;
  final String? vocalistName;
  final String? status;
  final dynamic createdAt;

  Agreement({
    this.choirLeaderId,
    this.vocalistId,
    this.voicePart,
    this.date,
    this.startTime,
    this.endTime,
    this.location,
    this.additionalTerms,
    this.bandName,
    this.subRequestId,
    this.payAmount,
    this.currency,
    this.bandId,
    this.requestGroupId,
    this.eventId,
    this.requestType,
    this.eventType,
    this.description,
    this.payDetails,
    this.choirLeaderName,
    this.vocalistName,
    this.status,
    this.createdAt,
  });

  factory Agreement.fromJson(Map<dynamic, dynamic> json) {
    final rawPay = json['PayAmount'] ?? json['payAmount'];
    final parsedPay = rawPay is int
        ? rawPay
        : (rawPay is num ? rawPay.toInt() : int.tryParse(rawPay?.toString() ?? ''));

    return Agreement(
      choirLeaderId:
          json['ChoirLeaderId']?.toString() ??
          json['choirLeaderId']?.toString() ??
          json['CreatorId']?.toString() ??
          json['creatorId']?.toString(),
      vocalistId:
          json['VocalistId']?.toString() ??
          json['vocalistId']?.toString() ??
          json['ApplicantId']?.toString() ??
          json['applicantId']?.toString(),
      voicePart:
          json['VoicePart']?.toString() ??
          json['voicePart']?.toString() ??
          json['Role']?.toString() ??
          json['role']?.toString() ??
          json['Instrument']?.toString() ??
          json['instrument']?.toString(),
      date: json['Date']?.toString() ?? json['date']?.toString(),
      startTime: json['StartTime']?.toString() ?? json['startTime']?.toString(),
      endTime: json['EndTime']?.toString() ?? json['endTime']?.toString(),
      location: json['Location']?.toString() ?? json['location']?.toString(),
      additionalTerms:
          json['AdditionalTerms']?.toString() ??
          json['additionalTerms']?.toString(),
      bandName: json['BandName']?.toString() ?? json['bandName']?.toString(),
      subRequestId:
          json['SubRequestId']?.toString() ?? json['subRequestId']?.toString(),
      payAmount: parsedPay,
      currency: json['Currency']?.toString() ?? json['currency']?.toString(),
      bandId: json['bandId']?.toString() ?? json['BandId']?.toString(),
      requestGroupId:
          json['requestGroupId']?.toString() ??
          json['RequestGroupId']?.toString(),
      eventId: json['eventId']?.toString() ?? json['EventId']?.toString(),
      requestType:
          json['requestType']?.toString() ?? json['RequestType']?.toString(),
      eventType:
          json['eventType']?.toString() ?? json['EventType']?.toString(),
      description:
          json['description']?.toString() ?? json['Description']?.toString(),
      payDetails:
          json['payDetails']?.toString() ?? json['PayDetails']?.toString(),
      choirLeaderName:
          json['choirLeaderName']?.toString() ??
          json['ChoirLeaderName']?.toString() ??
          json['creatorName']?.toString(),
      vocalistName:
          json['vocalistName']?.toString() ??
          json['VocalistName']?.toString() ??
          json['applicantName']?.toString(),
      status: json['status']?.toString() ?? json['Status']?.toString(),
      createdAt: json['createdAt'] ?? json['CreatedAt'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // Legacy PascalCase keys for backward compatibility
      'ChoirLeaderId': choirLeaderId,
      'VocalistId': vocalistId,
      'VoicePart': voicePart,
      'Date': date,
      'StartTime': startTime,
      'EndTime': endTime,
      'Location': location,
      'AdditionalTerms': additionalTerms,
      'BandName': bandName,
      if (subRequestId != null) 'SubRequestId': subRequestId,
      if (payAmount != null) 'PayAmount': payAmount,
      if (currency != null) 'Currency': currency,

      // CamelCase canonical keys
      'choirLeaderId': choirLeaderId,
      'vocalistId': vocalistId,
      'voicePart': voicePart,
      'date': date,
      'startTime': startTime,
      'endTime': endTime,
      'location': location,
      'additionalTerms': additionalTerms,
      'bandName': bandName,
      if (subRequestId != null) 'subRequestId': subRequestId,
      if (payAmount != null) 'payAmount': payAmount,
      if (currency != null) 'currency': currency,
      if (bandId != null) 'bandId': bandId,
      if (requestGroupId != null) 'requestGroupId': requestGroupId,
      if (eventId != null) 'eventId': eventId,
      if (requestType != null) 'requestType': requestType,
      if (eventType != null) 'eventType': eventType,
      if (description != null) 'description': description,
      if (payDetails != null) 'payDetails': payDetails,
      if (choirLeaderName != null) 'choirLeaderName': choirLeaderName,
      if (vocalistName != null) 'vocalistName': vocalistName,
      if (status != null) 'status': status,
      if (createdAt != null) 'createdAt': createdAt,
    };
  }
}
