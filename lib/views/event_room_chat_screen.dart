import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/event_room.dart';
import '../models/message.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';

class EventRoomChatScreen extends StatefulWidget {
  final String bandId;
  final EventRoom eventRoom;

  const EventRoomChatScreen({
    super.key,
    required this.bandId,
    required this.eventRoom,
  });

  @override
  State<EventRoomChatScreen> createState() => _EventRoomChatScreenState();
}

class _EventRoomChatScreenState extends State<EventRoomChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Message> _messages = [];
  bool _isLoading = true;
  StreamSubscription? _chatSubscription;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    super.dispose();
  }

  void _initChat() {
    final appState = Provider.of<AppState>(context, listen: false);
    _chatSubscription = appState.firebaseService
        .subscribeToBandMessages(
          '${widget.bandId}_room_${widget.eventRoom.roomId}',
        )
        .listen((msgs) {
          if (mounted) {
            setState(() {
              _messages = msgs;
              _isLoading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _scrollToBottom(),
            );
          }
        });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _messageController.clear();
    final appState = Provider.of<AppState>(context, listen: false);
    final userProfile = appState.currentUserProfile;
    final senderName =
        userProfile?.displayName ?? userProfile?.nickname ?? 'Member';

    await appState.firebaseService.sendBandMessageAsync(
      '${widget.bandId}_room_${widget.eventRoom.roomId}',
      text,
      senderName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final currentUserId = appState.currentUserId;
    final isLeader = widget.eventRoom.createdBy == currentUserId;

    return GradientScaffold(
      appBar: CustomTopBar(title: widget.eventRoom.name, showBack: true),
      body: SafeArea(
        child: Column(
          children: [
            // Event Room Header Banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: AppTheme.cardBackground,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.forum_rounded,
                      color: AppTheme.primaryAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              widget.eventRoom.name,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'EVENT ROOM',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: AppTheme.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Members & substitutes attending this event',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isLeader)
                    PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white70,
                      ),
                      color: const Color(0xFF16132D),
                      onSelected: (val) async {
                        if (val == 'close') {
                          await appState.firebaseService
                              .closeOrDeleteEventRoomAsync(
                                widget.bandId,
                                widget.eventRoom.roomId,
                                false,
                              );
                          if (mounted) Navigator.pop(context);
                        } else if (val == 'delete') {
                          await appState.firebaseService
                              .closeOrDeleteEventRoomAsync(
                                widget.bandId,
                                widget.eventRoom.roomId,
                                true,
                              );
                          if (mounted) Navigator.pop(context);
                        }
                      },
                      itemBuilder: (ctx) => [
                        PopupMenuItem(
                          value: 'close',
                          child: Text(
                            'Close Event Room',
                            style: GoogleFonts.inter(color: Colors.white),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Delete Room',
                            style: GoogleFonts.inter(color: Colors.redAccent),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),

            // Messages List
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryAccent,
                      ),
                    )
                  : _messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages in this event room yet.\nStart the conversation!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.senderId == currentUserId;
                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75,
                            ),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? AppTheme.primaryAccent
                                  : AppTheme.cardBackground,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isMe
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFF2E2A4E),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                if (!isMe)
                                  Text(
                                    msg.senderName ?? 'Member',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryAccent,
                                    ),
                                  ),
                                Text(
                                  msg.text ?? '',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat(
                                    'HH:mm',
                                  ).format(msg.timestamp ?? DateTime.now()),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: Colors.white60,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),

            // Input Bar
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF0F0C20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Type a message in event room...',
                        hintStyle: GoogleFonts.inter(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppTheme.cardBackground,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: AppTheme.primaryAccent,
                    ),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
