import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_notification.dart';
import '../models/band_event.dart';
import '../models/sub_request.dart';
import '../models/collab_session.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import 'chat_detail_screen.dart';
import 'band_section_chat_screen.dart';
import 'event_details_page.dart';
import 'sub_request_details_screen.dart';
import 'session_details_screen.dart';

/// Shows the compact notification panel as an overlay/dialog on desktop/tablet (>600px)
/// or a modal bottom sheet on mobile (<=600px).
Future<void> showNotificationPanel(
  BuildContext context, {
  void Function(AppNotification notification)? onNotificationTapForTest,
}) async {
  final mediaQuery = MediaQuery.of(context);
  final isDesktop = mediaQuery.size.width > 600;
  final appState = Provider.of<AppState>(context, listen: false);

  if (isDesktop) {
    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (dialogContext) {
        return ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: const EdgeInsets.only(top: 68, right: 24, bottom: 24),
              width: min(420.0, mediaQuery.size.width - 32),
              constraints: const BoxConstraints(
                maxHeight: 620,
                minHeight: 320,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0C20).withValues(alpha: 0.98),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Material(
                color: Colors.transparent,
                child: NotificationPanelContent(
                  isCompact: true,
                  onClose: () => Navigator.of(dialogContext).pop(),
                  onNotificationTapForTest: onNotificationTapForTest,
                ),
              ),
            ),
          ),
        );
      },
    );
  } else {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return ChangeNotifierProvider<AppState>.value(
          value: appState,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.75,
              minHeight: 300,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20).withValues(alpha: 0.98),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              border: const Border(
                top: BorderSide(color: Color(0xFF2E2A4E), width: 1.5),
                left: BorderSide(color: Color(0xFF2E2A4E), width: 1.5),
                right: BorderSide(color: Color(0xFF2E2A4E), width: 1.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: NotificationPanelContent(
                      isCompact: true,
                      onClose: () => Navigator.of(sheetContext).pop(),
                      onNotificationTapForTest: onNotificationTapForTest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Fallback full-screen route for '/notifications'
class NotificationCenterScreen extends StatelessWidget {
  final void Function(AppNotification notification)? onNotificationTapForTest;

  const NotificationCenterScreen({
    super.key,
    this.onNotificationTapForTest,
  });

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'NOTIFICATIONS',
        showBack: true,
      ),
      body: SafeArea(
        child: NotificationPanelContent(
          isCompact: false,
          onNotificationTapForTest: onNotificationTapForTest,
        ),
      ),
    );
  }
}

/// Standalone panel content managing notification data, mark-as-read, and deep-linking
class NotificationPanelContent extends StatefulWidget {
  final bool isCompact;
  final VoidCallback? onClose;
  final void Function(AppNotification notification)? onNotificationTapForTest;

  const NotificationPanelContent({
    super.key,
    this.isCompact = false,
    this.onClose,
    this.onNotificationTapForTest,
  });

  @override
  State<NotificationPanelContent> createState() => _NotificationPanelContentState();
}

class _NotificationPanelContentState extends State<NotificationPanelContent> {
  bool _isMarkingAll = false;

  Future<void> _handleNotificationTap(
    BuildContext context,
    AppState appState,
    AppNotification notification,
  ) async {
    // 1. Close compact panel if present
    if (widget.onClose != null) {
      widget.onClose!();
    }

    // 2. Invoke test hook if provided
    if (widget.onNotificationTapForTest != null) {
      widget.onNotificationTapForTest!(notification);
      return;
    }

    final navigator = Navigator.of(context, rootNavigator: true);

    // 3. Attempt to mark as read asynchronously without blocking navigation on failure
    if (!notification.isRead) {
      try {
        await appState.firebaseService.markNotificationReadAsync(notification.id);
      } catch (e) {
        debugPrint('[NotificationCenter] Error marking notification read: $e');
      }
    }

    if (!mounted) return;

    // 4. Deep-link routing based on payload & type
    final type = notification.type;
    final data = notification.data;
    final currentUserId = appState.currentUserId;

    try {
      switch (type) {
        case 'direct_message':
          final convId = (data['conversationId'] ?? '').toString();
          final senderId = (data['senderId'] ?? '').toString();
          final receiverId = (data['receiverId'] ?? '').toString();
          final otherUserId = senderId == currentUserId ? receiverId : senderId;
          final otherUserName = notification.title.isNotEmpty ? notification.title : 'Chat';

          if (convId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  conversationId: convId,
                  receiverId: otherUserId,
                  receiverName: otherUserName,
                ),
              ),
            );
          }
          break;

        case 'session_message':
          final convId = (data['conversationId'] ?? '').toString();
          final otherUserName = notification.title.isNotEmpty ? notification.title : 'Session Chat';

          if (convId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  conversationId: convId,
                  receiverId: '',
                  receiverName: otherUserName,
                ),
              ),
            );
          }
          break;

        case 'band_room_message':
          final bandId = (data['bandId'] ?? '').toString();
          final bandName = (data['bandName'] ?? 'Band Room').toString();
          if (bandId.isNotEmpty) {
            appState.selectBand(bandId, bandName);
          }
          navigator.pushNamed('/band-room');
          break;

        case 'band_section_chat':
          final bandId = (data['bandId'] ?? '').toString();
          final sectionId = (data['sectionId'] ?? '').toString();
          final sectionName = (data['sectionName'] ?? 'Section Chat').toString();
          final convId = (data['conversationId'] ?? '').toString();

          if (convId.isNotEmpty || (bandId.isNotEmpty && sectionId.isNotEmpty)) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => BandSectionChatScreen(
                  conversationId: convId.isNotEmpty ? convId : '${bandId}_$sectionId',
                  bandId: bandId.isNotEmpty ? bandId : null,
                  initialGroupName: sectionName,
                ),
              ),
            );
          }
          break;

        case 'event_invite':
        case 'event_reminder':
        case 'event_threshold':
        case 'event_milestone':
          final bandId = (data['bandId'] ?? '').toString();
          final eventId = (data['eventId'] ?? '').toString();

          if (bandId.isNotEmpty && eventId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => EventDetailsPage(
                  bandId: bandId,
                  eventId: eventId,
                  initialEvent: BandEvent(
                    id: eventId,
                    title: notification.title.isNotEmpty ? notification.title : 'Event',
                    description: '',
                    location: '',
                    startDateTime: '',
                    endDateTime: '',
                    additionalNotes: '',
                    createdBy: '',
                    createdAt: 0,
                    updatedAt: 0,
                    requireResponse: false,
                  ),
                ),
              ),
            );
          }
          break;

        case 'sub_request_invite':
        case 'sub_request':
          final subRequestId = (data['subRequestId'] ?? '').toString();
          final bandId = (data['bandId'] ?? '').toString();
          final eventId = (data['eventId'] ?? '').toString();
          if (subRequestId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => SubRequestDetailsScreen(
                  subRequest: SubRequest(
                    id: subRequestId,
                    subRequestId: subRequestId,
                    bandId: bandId.isNotEmpty ? bandId : null,
                    eventId: eventId.isNotEmpty ? eventId : null,
                  ),
                ),
              ),
            );
          } else {
            navigator.pushNamed('/find-gigs');
          }
          break;

        case 'grouped_sub_request':
        case 'gig_finalized':
          final bandId = (data['bandId'] ?? '').toString();
          final eventId = (data['eventId'] ?? '').toString();
          final subRequestId = (data['subRequestId'] ?? '').toString();

          if (bandId.isNotEmpty && eventId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => EventDetailsPage(
                  bandId: bandId,
                  eventId: eventId,
                  initialEvent: BandEvent(
                    id: eventId,
                    title: notification.title.isNotEmpty ? notification.title : 'Event',
                    description: '',
                    location: '',
                    startDateTime: '',
                    endDateTime: '',
                    additionalNotes: '',
                    createdBy: '',
                    createdAt: 0,
                    updatedAt: 0,
                    requireResponse: false,
                  ),
                ),
              ),
            );
          } else if (subRequestId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => SubRequestDetailsScreen(
                  subRequest: SubRequest(
                    id: subRequestId,
                    subRequestId: subRequestId,
                    bandId: bandId.isNotEmpty ? bandId : null,
                    eventId: eventId.isNotEmpty ? eventId : null,
                  ),
                ),
              ),
            );
          } else {
            navigator.pushNamed('/find-gigs');
          }
          break;

        case 'session_application':
        case 'session_application_status':
          final sessionId = (data['sessionId'] ?? '').toString();
          if (sessionId.isNotEmpty) {
            navigator.push(
              MaterialPageRoute(
                builder: (context) => SessionDetailsScreen(
                  session: CollabSession(
                    id: sessionId,
                    title: 'Session',
                    description: '',
                    sessionType: 'In person',
                    sessionCategory: 'Other',
                    creatorId: '',
                    createdAt: 0,
                    updatedAt: 0,
                    isDateFlexible: true,
                    genres: const [],
                    lookingForRoles: const [],
                    lookingForInstruments: const [],
                  ),
                ),
              ),
            );
          } else {
            navigator.pushNamed('/collabs');
          }
          break;

        default:
          break;
      }
    } catch (routingErr) {
      debugPrint('[NotificationCenter] Deep link navigation error: $routingErr');
    }
  }

  Future<void> _markAllAsRead(AppState appState) async {
    if (_isMarkingAll) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isMarkingAll = true);
    try {
      await appState.firebaseService.markAllNotificationsReadAsync();
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read.'),
            backgroundColor: AppTheme.success,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NotificationCenter] Error marking all read: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to mark all as read: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final uid = appState.currentUserId;

    return StreamBuilder<List<AppNotification>>(
      stream: appState.firebaseService.subscribeToUserNotifications(uid),
      builder: (context, snapshot) {
        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => !n.isRead).length;

        return NotificationCenterView(
          notifications: notifications,
          isLoading: snapshot.connectionState == ConnectionState.waiting && notifications.isEmpty,
          unreadCount: unreadCount,
          isMarkingAll: _isMarkingAll,
          onClose: widget.onClose,
          onMarkAllRead: () => _markAllAsRead(appState),
          onNotificationTap: (notification) => _handleNotificationTap(context, appState, notification),
        );
      },
    );
  }
}

/// Standalone, reusable notification view widget
class NotificationCenterView extends StatefulWidget {
  final List<AppNotification> notifications;
  final bool isLoading;
  final int unreadCount;
  final bool isMarkingAll;
  final VoidCallback? onClose;
  final VoidCallback onMarkAllRead;
  final void Function(AppNotification notification) onNotificationTap;

  const NotificationCenterView({
    super.key,
    required this.notifications,
    this.isLoading = false,
    required this.unreadCount,
    this.isMarkingAll = false,
    this.onClose,
    required this.onMarkAllRead,
    required this.onNotificationTap,
  });

  @override
  State<NotificationCenterView> createState() => _NotificationCenterViewState();
}

class _NotificationCenterViewState extends State<NotificationCenterView> {
  String _selectedFilter = 'all'; // 'all' | 'messages' | 'events' | 'requests' | 'system'

  final List<Map<String, String>> _filterOptions = const [
    {'id': 'all', 'label': 'All'},
    {'id': 'messages', 'label': 'Messages'},
    {'id': 'events', 'label': 'Events'},
    {'id': 'requests', 'label': 'Requests'},
    {'id': 'system', 'label': 'System'},
  ];

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'messages':
        return Icons.chat_bubble_outline_rounded;
      case 'events':
        return Icons.event_available_rounded;
      case 'requests':
        return Icons.work_outline_rounded;
      case 'system':
      default:
        return Icons.notifications_none_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'messages':
        return const Color(0xFF8B5CF6); // Violet
      case 'events':
        return const Color(0xFFF59E0B); // Amber/Orange
      case 'requests':
        return const Color(0xFF10B981); // Emerald Green
      case 'system':
      default:
        return AppTheme.primaryAccent;
    }
  }

  String _formatTimestamp(int epochMs) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final diff = now.difference(date);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else {
      final hour = date.hour.toString().padLeft(2, '0');
      final min = date.minute.toString().padLeft(2, '0');
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} $hour:$min';
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredNotifications = _selectedFilter == 'all'
        ? widget.notifications
        : widget.notifications.where((n) => n.category.toLowerCase() == _selectedFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Bar: Page title summary & Mark all as read
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'NOTIFICATIONS',
                        style: GoogleFonts.outfit(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.unreadCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.unreadCount > 0) ...[
                const SizedBox(width: 8),
                AnimatedTapDetector(
                  onTap: widget.isMarkingAll ? () {} : widget.onMarkAllRead,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppTheme.primaryAccent.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: widget.isMarkingAll
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.primaryAccent,
                            ),
                          )
                        : Text(
                            'Mark all as read',
                            style: GoogleFonts.inter(
                              color: AppTheme.primaryAccent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
              if (widget.onClose != null) ...[
                const SizedBox(width: 8),
                AnimatedTapDetector(
                  onTap: widget.onClose!,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Category Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: _filterOptions.map((opt) {
              final isSelected = _selectedFilter == opt['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AnimatedTapDetector(
                  onTap: () {
                    setState(() => _selectedFilter = opt['id']!);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryAccent
                          : AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryAccent
                            : const Color(0xFF2E2A4E),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      opt['label']!,
                      style: GoogleFonts.inter(
                        color: isSelected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        // Notification Items List or Empty State
        Expanded(
          child: widget.isLoading && widget.notifications.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                )
              : filteredNotifications.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      itemCount: filteredNotifications.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = filteredNotifications[index];
                        return _buildNotificationCard(context, item);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFF2E2A4E),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 40,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "You're all caught up!",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _selectedFilter == 'all'
                  ? 'No notifications at the moment.'
                  : 'No notifications in this category.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    BuildContext context,
    AppNotification item,
  ) {
    final catColor = _getCategoryColor(item.category);
    final catIcon = _getCategoryIcon(item.category);
    final isUnread = !item.isRead;

    return AnimatedTapDetector(
      onTap: () => widget.onNotificationTap(item),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? AppTheme.cardBackground.withValues(alpha: 0.95)
              : AppTheme.cardBackground.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread
                ? catColor.withValues(alpha: 0.4)
                : const Color(0xFF2E2A4E),
            width: isUnread ? 1.5 : 1,
          ),
          boxShadow: isUnread
              ? [
                  BoxShadow(
                    color: catColor.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category Icon Badge
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: isUnread ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: catColor.withValues(alpha: isUnread ? 0.5 : 0.2),
                  width: 1,
                ),
              ),
              child: Icon(
                catIcon,
                color: isUnread ? catColor : catColor.withValues(alpha: 0.7),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: GoogleFonts.outfit(
                            color: isUnread ? Colors.white : Colors.white70,
                            fontSize: 15,
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTimestamp(item.createdAt),
                        style: GoogleFonts.inter(
                          color: isUnread ? AppTheme.textSecondary : AppTheme.textSecondary.withValues(alpha: 0.7),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.body,
                    style: GoogleFonts.inter(
                      color: isUnread ? Colors.white.withValues(alpha: 0.85) : AppTheme.textSecondary,
                      fontSize: 13,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Unread Dot & Navigation Chevron
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isUnread)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(bottom: 6, top: 4),
                    decoration: BoxDecoration(
                      color: catColor,
                      shape: BoxShape.circle,
                    ),
                  )
                else
                  const SizedBox(height: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isUnread ? Colors.white70 : Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

