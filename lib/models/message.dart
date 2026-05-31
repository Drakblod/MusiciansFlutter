class Message {
  final String? id;
  final String? senderId;
  final String? receiverId;
  final String? text;
  final DateTime? timestamp;
  final bool isRead;
  final String? senderName;
  final bool isCurrentUserSender;

  Message({
    this.id,
    this.senderId,
    this.receiverId,
    this.text,
    this.timestamp,
    this.isRead = false,
    this.senderName,
    this.isCurrentUserSender = false,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'SenderId': senderId,
      'ReceiverId': receiverId,
      'Text': text,
      'Timestamp': timestamp?.toUtc().toIso8601String(),
      'IsRead': isRead,
      'SenderName': senderName,
    };
  }

  bool get isNew => !isRead;
}
