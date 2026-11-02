import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/message.dart';
import '../models/agreement.dart';
import '../utils/sub_request_card_helper.dart';
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
  String? _resolvedReceiverId;

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
    final senderName =
        userProfile?.displayName ?? userProfile?.nickname ?? 'Alex';

    // Clear input first for responsive feel
    _messageController.clear();

    try {
      await appState.firebaseService.sendConversationMessageAsync(
        widget.conversationId,
        text,
        _resolvedReceiverId ?? widget.receiverId,
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
      appBar: const CustomTopBar(showBack: true),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: appState.firebaseService.subscribeToConversationMetadata(
          widget.conversationId,
        ),
        builder: (context, metaSnapshot) {
          final metadata = metaSnapshot.data;
          final agreement = metadata?['agreement'] as Agreement?;
          final isAgreement = agreement != null;

          // Participant authority: derive counterpart strictly from agreement when available
          final currentUserId = appState.currentUserId;
          String displayName = widget.receiverName;
          if (isAgreement && currentUserId != null) {
            if (currentUserId == agreement.choirLeaderId &&
                agreement.vocalistId != null &&
                agreement.vocalistId!.isNotEmpty) {
              _resolvedReceiverId = agreement.vocalistId;
              if (agreement.vocalistName != null &&
                  agreement.vocalistName!.trim().isNotEmpty) {
                displayName = agreement.vocalistName!.trim();
              }
            } else if (currentUserId == agreement.vocalistId &&
                agreement.choirLeaderId != null &&
                agreement.choirLeaderId!.isNotEmpty) {
              _resolvedReceiverId = agreement.choirLeaderId;
              if (agreement.choirLeaderName != null &&
                  agreement.choirLeaderName!.trim().isNotEmpty) {
                displayName = agreement.choirLeaderName!.trim();
              }
            }
          }

          return Column(
            children: [
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                          backgroundColor: isAgreement
                              ? const Color(0xFF0D3A20).withOpacity(0.5)
                              : AppTheme.primaryAccent.withOpacity(0.2),
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName.substring(0, 1).toUpperCase()
                                : 'U',
                            style: GoogleFonts.inter(
                              color: isAgreement ? Colors.greenAccent : Colors.white,
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
                                isAgreement ? 'AGREEMENT' : 'DIRECT CHAT',
                                style: GoogleFonts.outfit(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: isAgreement
                                      ? Colors.greenAccent
                                      : AppTheme.primaryAccent,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                displayName,
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
              if (isAgreement)
                AnimatedContainer(
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 12.0,
                    ),
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
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'CONFIRMED AGREEMENT',
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
                                    _isAgreementExpanded
                                        ? 'Hide Details'
                                        : 'Show Details',
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

                        if (_isAgreementExpanded) ...[
                          const SizedBox(height: 12),

                          // Details block
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: MediaQuery.of(context).size.height * 0.35,
                            ),
                            child: SingleChildScrollView(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFF0F4D25).withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: () {
                              final rows = <Widget>[];

                              // 1. Band / Project
                              final rawBand = agreement.bandName?.trim();
                              if (rawBand != null &&
                                  rawBand.isNotEmpty &&
                                  rawBand.toLowerCase() != 'null' &&
                                  rawBand.toLowerCase() != 'n/a' &&
                                  rawBand.toLowerCase() != 'gig agreement' &&
                                  rawBand.toLowerCase() != 'band / project' &&
                                  rawBand.toLowerCase() != 'unknown band' &&
                                  rawBand.toLowerCase() != 'band') {
                                rows.add(_buildAgreementRow(
                                  Icons.music_note_rounded,
                                  'Band / Project',
                                  rawBand,
                                ));
                              }

                              // 2. Request Type
                              final reqType = agreement.requestType?.trim();
                              if (reqType != null &&
                                  reqType.isNotEmpty &&
                                  reqType.toLowerCase() != 'null') {
                                rows.add(_buildAgreementRow(
                                  Icons.category_rounded,
                                  'Request Type',
                                  reqType,
                                ));
                              }

                              // 3. Event Type
                              final evType = agreement.eventType?.trim();
                              if (evType != null &&
                                  evType.isNotEmpty &&
                                  evType.toLowerCase() != 'null') {
                                rows.add(_buildAgreementRow(
                                  Icons.event_note_rounded,
                                  'Event Type',
                                  evType,
                                ));
                              }

                              // 4. Role / Instrument
                              final role = agreement.voicePart?.trim();
                              if (role != null && role.isNotEmpty) {
                                rows.add(_buildAgreementRow(
                                  Icons.person_search_rounded,
                                  'Role / Instrument',
                                  role,
                                ));
                              }

                              // 5. Date & Time
                              final dt = _formatAgreementDateTime(agreement);
                              if (dt != null && dt.isNotEmpty) {
                                rows.add(_buildAgreementRow(
                                  Icons.calendar_today_rounded,
                                  'Date & Time',
                                  dt,
                                ));
                              }

                              // 6. Location / Venue
                              final loc = agreement.location?.trim();
                              if (loc != null &&
                                  loc.isNotEmpty &&
                                  loc.toLowerCase() != 'null') {
                                rows.add(_buildAgreementRow(
                                  Icons.location_on_rounded,
                                  'Location / Venue',
                                  loc,
                                ));
                              }

                              // 7. Description / Details
                              final desc = agreement.description?.trim();
                              final terms = agreement.additionalTerms?.trim();
                              final effectiveDesc = (desc != null &&
                                      desc.isNotEmpty &&
                                      desc.toLowerCase() != 'null')
                                  ? desc
                                  : ((terms != null &&
                                          terms.isNotEmpty &&
                                          terms.toLowerCase() != 'null' &&
                                          terms !=
                                              'Substitute staffing assignment.')
                                      ? terms
                                      : null);
                              if (effectiveDesc != null &&
                                  effectiveDesc.isNotEmpty) {
                                rows.add(_buildAgreementRow(
                                  Icons.description_rounded,
                                  'Description / Details',
                                  effectiveDesc,
                                ));
                              }
                              if (terms != null &&
                                  terms.isNotEmpty &&
                                  terms.toLowerCase() != 'null' &&
                                  terms != effectiveDesc &&
                                  terms != 'Substitute staffing assignment.') {
                                rows.add(_buildAgreementRow(
                                  Icons.rule_rounded,
                                  'Additional Terms',
                                  terms,
                                ));
                              }

                              // 8. Compensation
                              final payment = formatAgreementPayment(agreement);
                              if (payment != null && payment.isNotEmpty) {
                                rows.add(_buildAgreementRow(
                                  Icons.payments_rounded,
                                  'Compensation',
                                  payment,
                                ));
                              }

                              // 9. Payment Details
                              final payDetails = agreement.payDetails?.trim();
                              if (payDetails != null &&
                                  payDetails.isNotEmpty &&
                                  payDetails.toLowerCase() != 'null') {
                                rows.add(_buildAgreementRow(
                                  Icons.info_outline_rounded,
                                  'Payment Details',
                                  payDetails,
                                ));
                              }

                              return Column(
                                children: [
                                  for (int i = 0; i < rows.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 8),
                                    rows[i],
                                  ],
                                ],
                              );
                            }(),
                              ),
                            ),
                          ),
                        ] else ...[
                          // Collapsed Quick Summary
                          const SizedBox(height: 6),
                          Text(
                            _formatAgreementCollapsed(agreement),
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
                ),

              // Message Thread List
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: appState.firebaseService.subscribeToMessages(
                    widget.conversationId,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error loading messages: ${snapshot.error}',
                          style: GoogleFonts.inter(color: AppTheme.danger),
                        ),
                      );
                    }

                    final allMessages = snapshot.data ?? [];

                    // Filter out legacy chosen system message only in agreement conversations
                    final messages = isAgreement
                        ? allMessages.where((msg) {
                            final t = msg.text ?? '';
                            return !RegExp(
                              r'has been chosen (to attend the rehearsal|as substitute for )',
                              caseSensitive: false,
                            ).hasMatch(t);
                          }).toList()
                        : allMessages;

                    // Mark conversation as read upon receiving messages
                    if (messages.isNotEmpty) {
                      appState.firebaseService.markConversationAsRead(
                        widget.conversationId,
                      );
                    }

                    // Scroll to bottom on load/new message
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _scrollToBottom(),
                    );

                    if (messages.isEmpty) {
                      return Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
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
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Say hello to $displayName!',
                              style: GoogleFonts.inter(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                            ],
                          ),
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
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              if (!isMe) ...[
                                CircleAvatar(
                                  radius: 15,
                                  backgroundColor: AppTheme.primaryAccent
                                      .withOpacity(0.12),
                                  child: Text(
                                    displayName.isNotEmpty
                                        ? displayName
                                            .substring(0, 1)
                                            .toUpperCase()
                                        : 'U',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? AppTheme.primaryAccent
                                        : const Color(0xFF1E1A3A),
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft:
                                          Radius.circular(isMe ? 16 : 4),
                                      bottomRight:
                                          Radius.circular(isMe ? 4 : 16),
                                    ),
                                    border: isMe
                                        ? null
                                        : Border.all(
                                            color: const Color(0xFF2E2A4E),
                                            width: 1,
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: isMe
                                        ? CrossAxisAlignment.end
                                        : CrossAxisAlignment.start,
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
                                            ? DateFormat(
                                                'HH:mm',
                                              ).format(msg.timestamp!.toLocal())
                                            : '',
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          color: isMe
                                              ? Colors.white70
                                              : AppTheme.textMuted,
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
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Type your message...',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            hintStyle: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
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
                          child: const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String? _formatAgreementDateTime(Agreement agreement) {
    return formatSubRequestDateTime(
      date: agreement.date,
      startTime: agreement.startTime,
      endTime: agreement.endTime,
    );
  }

  String _formatAgreementCollapsed(Agreement agreement) {
    final parts = <String>[];
    if (agreement.bandName != null &&
        agreement.bandName!.trim().isNotEmpty &&
        agreement.bandName!.toLowerCase() != 'null' &&
        agreement.bandName!.toLowerCase() != 'n/a' &&
        agreement.bandName!.toLowerCase() != 'gig agreement' &&
        agreement.bandName!.toLowerCase() != 'band / project') {
      parts.add(agreement.bandName!.trim());
    }
    if (agreement.requestType != null &&
        agreement.requestType!.trim().isNotEmpty &&
        agreement.voicePart != null &&
        agreement.voicePart!.trim().isNotEmpty) {
      parts.add('${agreement.requestType!.trim()} · ${agreement.voicePart!.trim()}');
    } else if (agreement.voicePart != null &&
        agreement.voicePart!.trim().isNotEmpty) {
      parts.add(agreement.voicePart!.trim());
    }
    final dt = _formatAgreementDateTime(agreement);
    if (dt != null && dt.isNotEmpty) {
      parts.add(dt);
    }
    final pay = formatAgreementPayment(agreement);
    if (pay != null && pay.isNotEmpty) {
      parts.add(pay);
    }
    return parts.join(' · ');
  }

  Widget _buildAgreementRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.greenAccent.withOpacity(0.7)),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label:  ',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.greenAccent.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
