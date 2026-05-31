import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<Map<String, dynamic>> _threads = [];
  bool _isLoading = true;

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
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 20.0, top: 20.0, bottom: 8.0),
            child: Text(
              'MESSAGES',
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadThreads,
              color: AppTheme.primaryAccent,
              backgroundColor: AppTheme.cardBackground,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : _threads.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.2),
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 64,
                              color: AppTheme.textSecondary.withOpacity(0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No conversations yet.',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40),
                              child: Text(
                                'Browse musicians and tap Message on their profile to start a chat.',
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
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: _threads.length,
                    itemBuilder: (context, index) {
                      final thread = _threads[index];
                      final hasUnread = thread['hasUnread'] as bool;
                      final timestamp = thread['timestamp'] as DateTime;
                      final otherUserId = thread['otherUserId'] as String;
                      final otherUserName = thread['otherUserName'] as String;
                      final lastMessage = thread['lastMessageText'] as String;
                      final conversationId = thread['conversationId'] as String;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: hasUnread ? AppTheme.primaryAccent.withOpacity(0.4) : const Color(0xFF231F45),
                            width: hasUnread ? 1.5 : 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () async {
                              // Mark conversation as read
                              await appState.firebaseService.markConversationAsRead(conversationId);
                              
                              // Trigger state update
                              appState.refreshProfile(); // or trigger unread messages state check
                              
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  // Avatar
                                  CircleAvatar(
                                    radius: 24,
                                    backgroundColor: AppTheme.primaryAccent.withOpacity(0.15),
                                    child: Text(
                                      otherUserName.isNotEmpty ? otherUserName.substring(0, 1).toUpperCase() : 'U',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 14),

                                  // Details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              otherUserName,
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            Text(
                                              _formatTimestamp(timestamp),
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: hasUnread ? AppTheme.primaryAccent : AppTheme.textMuted,
                                                fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                lastMessage,
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  color: hasUnread ? Colors.white : AppTheme.textSecondary,
                                                  fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (hasUnread)
                                              Container(
                                                width: 8,
                                                height: 8,
                                                margin: const EdgeInsets.only(left: 8),
                                                decoration: const BoxDecoration(
                                                  color: Colors.redAccent,
                                                  shape: BoxShape.circle,
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
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
