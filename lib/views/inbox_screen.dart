import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../models/agreement.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = true;
  int _activeTab = 0; // 0: Direct Chats, 1: Gigs & Agreements

  @override
  void initState() {
    super.initState();
    _loadThreads();
  }

  Future<void> _loadThreads() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final list = await appState.firebaseService.getActiveConversationsAsync();
      if (mounted) {
        setState(() {
          _threads = list;
        });
      }
    } catch (e) {
      debugPrint("Error loading conversations: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateToCheck = DateTime(dt.year, dt.month, dt.day);

    if (dateToCheck == today) {
      return DateFormat('HH:mm').format(dt);
    } else if (dateToCheck == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('MMM dd').format(dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return GradientScaffold(
      appBar: const CustomTopBar(showBack: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, top: 20.0, bottom: 8.0),
            child: Text(
              'MESSAGES / AGREEMENTS',
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),

          // Custom Tab Switcher
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF130E26).withOpacity(0.6),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF2E2452), width: 1.2),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _activeTab == 0
                            ? AppTheme.primaryAccent
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          'Messages',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _activeTab == 0
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _activeTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _activeTab == 1
                            ? const Color(0xFF0F4D25)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          'Agreements',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: _activeTab == 1
                                ? Colors.white
                                : AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadThreads,
              color: AppTheme.primaryAccent,
              backgroundColor: AppTheme.cardBackground,
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryAccent,
                      ),
                    )
                  : () {
                      final filteredThreads = _threads.where((t) {
                        final hasAgreement = t['agreement'] != null;
                        return _activeTab == 0 ? !hasAgreement : hasAgreement;
                      }).toList();

                      if (filteredThreads.isEmpty) {
                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.2,
                            ),
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    _activeTab == 0
                                        ? Icons.chat_bubble_outline_rounded
                                        : Icons.handshake_outlined,
                                    size: 64,
                                    color: _activeTab == 0
                                        ? AppTheme.textSecondary.withOpacity(
                                            0.5,
                                          )
                                        : Colors.greenAccent.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _activeTab == 0
                                        ? 'No direct conversations.'
                                        : 'No active gig agreements.',
                                    style: GoogleFonts.outfit(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 40,
                                    ),
                                    child: Text(
                                      _activeTab == 0
                                          ? 'Start a chat by tapping Message on a musician\'s profile.'
                                          : 'Agreements are started when a sub request is accepted.',
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filteredThreads.length,
                        itemBuilder: (context, index) {
                          final thread = filteredThreads[index];
                          final hasUnread = thread['hasUnread'] as bool;
                          final timestamp = thread['timestamp'] as DateTime;
                          final otherUserId = thread['otherUserId'] as String;
                          final otherUserName =
                              thread['otherUserName'] as String;
                          final lastMessage =
                              thread['lastMessageText'] as String;
                          final conversationId =
                              thread['conversationId'] as String;
                          final agreement = thread['agreement'] as Agreement?;

                          final isAgreement = agreement != null;
                          final cardBorderColor = hasUnread
                              ? AppTheme.primaryAccent.withOpacity(0.5)
                              : isAgreement
                              ? const Color(0xFF0F4D25).withOpacity(0.6)
                              : const Color(0xFF231F45);
                          final cardBgColor = isAgreement
                              ? const Color(
                                  0xFF0A1C12,
                                ) // Low-opacity forest green background
                              : AppTheme.cardBackground;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: cardBgColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: cardBorderColor,
                                width: hasUnread ? 1.5 : 1.0,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () async {
                                  // Mark conversation as read
                                  await appState.firebaseService
                                      .markConversationAsRead(conversationId);

                                  // Trigger state update
                                  appState.refreshProfile();

                                  if (context.mounted) {
                                    await Navigator.pushNamed(
                                      context,
                                      '/chat-detail',
                                      arguments: {
                                        'conversationId': conversationId,
                                        'receiverId': otherUserId,
                                        'receiverName': otherUserName,
                                      },
                                    );
                                    // Reload thread list on pop back
                                    _loadThreads();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 14,
                                  ),
                                  child: Row(
                                    children: [
                                      // Avatar
                                      CircleAvatar(
                                        radius: 24,
                                        backgroundColor: isAgreement
                                            ? const Color(
                                                0xFF0D3A20,
                                              ).withOpacity(0.3)
                                            : AppTheme.primaryAccent
                                                  .withOpacity(0.15),
                                        child: Text(
                                          otherUserName.isNotEmpty
                                              ? otherUserName
                                                    .substring(0, 1)
                                                    .toUpperCase()
                                              : 'U',
                                          style: GoogleFonts.inter(
                                            color: isAgreement
                                                ? Colors.greenAccent
                                                : Colors.white,
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 14),

                                      // Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          otherUserName,
                                                          style:
                                                              GoogleFonts.outfit(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Colors
                                                                    .white,
                                                              ),
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      if (isAgreement) ...[
                                                        const SizedBox(
                                                          width: 6,
                                                        ),
                                                        Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color: const Color(
                                                              0xFF0F4D25,
                                                            ),
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  6,
                                                                ),
                                                            border: Border.all(
                                                              color: Colors
                                                                  .greenAccent
                                                                  .withOpacity(
                                                                    0.3,
                                                                  ),
                                                              width: 0.8,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            'Agreement',
                                                            style: GoogleFonts.inter(
                                                              color: Colors
                                                                  .greenAccent,
                                                              fontSize: 9,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  _formatTimestamp(timestamp),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: hasUnread
                                                        ? AppTheme.primaryAccent
                                                        : AppTheme.textMuted,
                                                    fontWeight: hasUnread
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),

                                            // Context info for agreements
                                            if (isAgreement) ...[
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.music_note_rounded,
                                                    size: 13,
                                                    color: Colors.greenAccent,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Expanded(
                                                    child: Text(
                                                      '${agreement.bandName ?? "Unknown Band"} • Sub: ${agreement.voicePart ?? "Musician"}',
                                                      style: GoogleFonts.inter(
                                                        color: Colors
                                                            .greenAccent
                                                            .withOpacity(0.8),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                            ],

                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    lastMessage,
                                                    style: GoogleFonts.inter(
                                                      fontSize: 13,
                                                      color: hasUnread
                                                          ? Colors.white
                                                          : AppTheme
                                                                .textSecondary,
                                                      fontWeight: hasUnread
                                                          ? FontWeight.bold
                                                          : FontWeight.normal,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (hasUnread)
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    margin:
                                                        const EdgeInsets.only(
                                                          left: 8,
                                                        ),
                                                    decoration:
                                                        const BoxDecoration(
                                                          color:
                                                              Colors.redAccent,
                                                          shape:
                                                              BoxShape.circle,
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
                          );
                        },
                      );
                    }(),
            ),
          ),
        ],
      ),
    );
  }
}
