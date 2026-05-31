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
  });

  factory Agreement.fromJson(Map<dynamic, dynamic> json) {
    return Agreement(
      choirLeaderId: json['ChoirLeaderId']?.toString(),
      vocalistId: json['VocalistId']?.toString(),
      voicePart: json['VoicePart']?.toString(),
      date: json['Date']?.toString(),
      startTime: json['StartTime']?.toString(),
      endTime: json['EndTime']?.toString(),
      location: json['Location']?.toString(),
      additionalTerms: json['AdditionalTerms']?.toString(),
      bandName: json['BandName']?.toString(),
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
    };
  }
}
