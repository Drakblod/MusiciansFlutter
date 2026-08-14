import '../utils/date_parser.dart';

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

  factory Message.fromJson(
    Map<dynamic, dynamic> json,
    String keyId, {
    String? currentUserId,
  }) {
    final senderIdStr =
        json['SenderId']?.toString() ?? json['senderId']?.toString();
    final receiverIdStr =
        json['ReceiverId']?.toString() ?? json['receiverId']?.toString();
    final textStr = json['Text']?.toString() ?? json['text']?.toString();
    final rawTimestamp = json['Timestamp'] ?? json['timestamp'];
    final isReadBool = (json['IsRead'] == true) || (json['isRead'] == true);

    final parsedTimestamp = parseDateTime(rawTimestamp);

    return Message(
      id: keyId,
      senderId: senderIdStr,
      receiverId: receiverIdStr,
      text: textStr,
      timestamp: parsedTimestamp,
      isRead: isReadBool,
      senderName:
          json['SenderName']?.toString() ?? json['senderName']?.toString(),
      isCurrentUserSender:
          currentUserId != null && senderIdStr == currentUserId,
      replyToText:
          json['ReplyToText']?.toString() ?? json['replyToText']?.toString(),
      replyToSenderName:
          json['ReplyToSenderName']?.toString() ??
          json['replyToSenderName']?.toString(),
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
