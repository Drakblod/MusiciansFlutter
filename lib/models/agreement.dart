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
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    };
  }
}
