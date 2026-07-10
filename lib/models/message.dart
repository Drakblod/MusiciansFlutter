class Message {
  final String? id;
  final String? senderId;
  final String? receiverId;
  final String? text;
  final DateTime? timestamp;
  final bool isRead;
  final String? senderName;
  final bool isCurrentUserSender;
  final String? replyToText;
  final String? replyToSenderName;

  Message({
    this.id,
    this.senderId,
    this.receiverId,
    this.text,
    this.timestamp,
    this.isRead = false,
    this.senderName,
    this.isCurrentUserSender = false,
    this.replyToText,
    this.replyToSenderName,
  });

  factory Message.fromJson(Map<dynamic, dynamic> json, String keyId, {String? currentUserId}) {
    final senderIdStr = json['SenderId']?.toString();
    final timestampStr = json['Timestamp']?.toString();
    DateTime? parsedTimestamp;
    if (timestampStr != null) {
      parsedTimestamp = DateTime.tryParse(timestampStr);
    }

    return Message(
      id: keyId,
      senderId: senderIdStr,
      receiverId: json['ReceiverId']?.toString(),
      text: json['Text']?.toString(),
      timestamp: parsedTimestamp,
      isRead: json['IsRead'] == true,
      senderName: json['SenderName']?.toString(),
      isCurrentUserSender: currentUserId != null && senderIdStr == currentUserId,
      replyToText: json['ReplyToText']?.toString(),
      replyToSenderName: json['ReplyToSenderName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      'SenderId': senderId,
      'ReceiverId': receiverId,
      'Text': text,
      'Timestamp': timestamp?.toUtc().toIso8601String(),
      'IsRead': isRead,
      'SenderName': senderName,
    };
    if (replyToText != null) {
      data['ReplyToText'] = replyToText;
    }
    if (replyToSenderName != null) {
      data['ReplyToSenderName'] = replyToSenderName;
    }
    return data;
  }

  bool get isNew => !isRead;
}
