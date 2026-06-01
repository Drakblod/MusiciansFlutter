import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../models/agreement.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String receiverId;
  final String receiverName;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isAgreementExpanded = true;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userProfile = appState.currentUserProfile;
    final senderName = userProfile?.displayName ?? userProfile?.nickname ?? 'Alex';

    // Clear input first for responsive feel
    _messageController.clear();

    try {
      await appState.firebaseService.sendConversationMessageAsync(
        widget.conversationId,
        text,
        widget.receiverId,
        senderName,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: Column(
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xCC0F0C22), // 80% opacity dark-violet
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF231F45), width: 1.5),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                      child: Text(
                        widget.receiverName.isNotEmpty
                            ? widget.receiverName.substring(0, 1).toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.receiverName,
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppTheme.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Online',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Confirmed Gig Agreement Banner
          StreamBuilder<Map<String, dynamic>?>(
            stream: appState.firebaseService.subscribeToConversationMetadata(widget.conversationId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }
              final metadata = snapshot.data!;
              final agreement = metadata['agreement'] as Agreement?;
              if (agreement == null) {
                return const SizedBox.shrink();
              }

              return AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xEB0A1E13), // Deep translucent emerald green
                  border: Border(
                    bottom: BorderSide(color: Color(0xFF0F4D25), width: 1.5),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.handshake_rounded, 
                                color: Colors.greenAccent, 
                                size: 20
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'CONFIRMED GIG AGREEMENT',
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.greenAccent,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isAgreementExpanded = !_isAgreementExpanded;
                              });
                            },
                            child: Row(
                              children: [
                                Text(
                                  _isAgreementExpanded ? 'Hide Details' : 'Show Details',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: Colors.greenAccent.withOpacity(0.8),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  _isAgreementExpanded 
                                      ? Icons.keyboard_arrow_up_rounded 
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: Colors.greenAccent,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      // Details Area
                      if (_isAgreementExpanded) ...[
                        const SizedBox(height: 12),
                        
                        // Details block
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.25),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF0F4D25).withOpacity(0.4), 
                              width: 1
                            ),
                          ),
                          child: Column(
                            children: [
                              _buildAgreementRow(
                                Icons.music_note_rounded,
                                'Band / Project',
                                agreement.bandName ?? 'N/A'
                              ),
                              const SizedBox(height: 8),
                              _buildAgreementRow(
                                Icons.person_search_rounded,
                                'Vocalist Role / Part',
                                agreement.voicePart ?? 'N/A'
                              ),
                              const SizedBox(height: 8),
                              _buildAgreementRow(
                                Icons.calendar_today_rounded,
                                'Date & Time',
                                '${agreement.date ?? "N/A"} (${agreement.startTime ?? "—"} to ${agreement.endTime ?? "—"})'
                              ),
                              const SizedBox(height: 8),
                              _buildAgreementRow(
                                Icons.location_on_rounded,
                                'Location',
                                agreement.location ?? 'N/A'
                              ),
                              if (agreement.additionalTerms != null && 
                                  agreement.additionalTerms!.trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                _buildAgreementRow(
                                  Icons.description_rounded,
                                  'Additional Terms',
                                  agreement.additionalTerms!
                                ),
                              ]
                            ],
                          ),
                        ),
                      ] else ...[
                        // Collapsed Quick Summary
                        const SizedBox(height: 6),
                        Text(
                          '${agreement.bandName ?? "Band"} • ${agreement.voicePart ?? "Sub"} • ${agreement.date ?? "No Date"}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          // Message Thread List
          Expanded(
            child: StreamBuilder<List<Message>>(
              stream: appState.firebaseService.subscribeToMessages(widget.conversationId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading messages: ${snapshot.error}',
                      style: GoogleFonts.inter(color: AppTheme.danger),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                
                // Mark conversation as read upon receiving messages
                if (messages.isNotEmpty) {
                  appState.firebaseService.markConversationAsRead(widget.conversationId);
                }

                // Scroll to bottom on load/new message
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: AppTheme.textSecondary.withOpacity(0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet.',
                          style: GoogleFonts.inter(color: AppTheme.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Say hello to ${widget.receiverName}!',
                          style: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.isCurrentUserSender;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: AppTheme.primaryAccent.withOpacity(0.12),
                              child: Text(
                                widget.receiverName.isNotEmpty ? widget.receiverName.substring(0, 1).toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.primaryAccent : const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                                border: isMe ? null : Border.all(color: const Color(0xFF2E2A4E), width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.text ?? '',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      color: Colors.white,
                                      height: 1.3,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    msg.timestamp != null
                                        ? DateFormat('HH:mm').format(msg.timestamp!.toLocal())
                                        : '',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: isMe ? Colors.white70 : AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Message Input Bar at Bottom
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0C091D),
              border: Border(
                top: BorderSide(color: Color(0xFF1E1A3C), width: 1.5),
              ),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  // Text input field
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type your message...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                        fillColor: const Color(0xFF141029),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send Action Button
                  AnimatedTapDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgreementRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.greenAccent.withOpacity(0.7)),
        const SizedBox(width: 8),
        Text(
          '$label:  ',
          style: GoogleFonts.inter(
            fontSize: 12,
            color: Colors.greenAccent.withOpacity(0.7),
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
