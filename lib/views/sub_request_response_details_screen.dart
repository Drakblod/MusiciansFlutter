import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/agreement.dart';
import '../models/message.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import 'chat_detail_screen.dart';

class SubRequestResponseDetailsScreen extends StatefulWidget {
  final SubRequest subRequest;

  const SubRequestResponseDetailsScreen({super.key, required this.subRequest});

  @override
  State<SubRequestResponseDetailsScreen> createState() =>
      _SubRequestResponseDetailsScreenState();
}

class _SubRequestResponseDetailsScreenState
    extends State<SubRequestResponseDetailsScreen> {
  List<ResponderItem> _responders = [];
  String? _selectedUserId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResponses();
  }

  Future<void> _loadResponses() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final reqId = widget.subRequest.subRequestId ?? widget.subRequest.id;

      if (reqId == null) {
        throw Exception("Invalid request ID");
      }

      // 1. Fetch targeted SubRequest or fallback to widget.subRequest
      final freshReq = await appState.firebaseService.getSubRequestAsync(reqId);
      final effectiveReq = freshReq ?? widget.subRequest;

      // 2. Collect responder IDs from both the subrequest object and all RTDB paths
      final Map<String, dynamic> responses = Map<String, dynamic>.from(effectiveReq.responses);
      final asyncResponses = await appState.firebaseService.getSubRequestResponsesAsync(reqId);
      responses.addAll(asyncResponses);

      final responderIds = responses.keys.toList();
      final List<ResponderItem> items = [];

      // 3. Fetch profiles for each responder ID
      for (final uid in responderIds) {
        final profile = await appState.firebaseService.getUserProfileAsync(uid);
        if (profile != null) {
          final primarySkill = profile.mainSkills.isNotEmpty
              ? profile.mainSkills.first
              : (profile.mainInstrument != null && profile.mainInstrument!.trim().isNotEmpty
                  ? profile.mainInstrument!.split(',').first.trim()
                  : (profile.instruments.isNotEmpty ? profile.instruments.first : 'Musician'));

          items.add(
            ResponderItem(
              userId: uid,
              name: profile.displayName ?? profile.nickname ?? 'Unknown',
              instruments: primarySkill,
              location: profile.location ?? 'Stockholm, Sweden',
              level: profile.level ?? 'Intermediate',
              about: profile.about ?? 'No description provided.',
            ),
          );
        } else {
          items.add(
            ResponderItem(
              userId: uid,
              name: 'Musician Candidate',
              instruments: 'Musician',
              location: 'Available',
              level: 'Intermediate',
              about: 'Applied to sub request.',
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _responders = items;
          if (items.length == 1) {
            _selectedUserId = items.first.userId;
          }
        });
      }

      // Mark matching response notifications as read so badges clear
      try {
        for (final notif in appState.userNotifications) {
          if (!notif.isRead &&
              (notif.type == 'sub_request_response' || notif.type == 'sub_response') &&
              (notif.data['subRequestId'] == reqId || notif.id.contains(reqId))) {
            appState.firebaseService.markNotificationReadAsync(notif.id);
          }
        }
      } catch (_) {}
    } catch (e) {
      debugPrint("Error loading responses: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load responders: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedUserId == null) return;
    final selectedSub = _responders.firstWhere(
      (r) => r.userId == _selectedUserId,
    );

    setState(() => _isLoading = true);

    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    final reqId = widget.subRequest.subRequestId ?? widget.subRequest.id;

    if (currentUserId == null || reqId == null) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing user ID or request ID"), backgroundColor: AppTheme.danger),
      );
      return;
    }

    final bool isMemberRequest =
        widget.subRequest.role == 'New Member' ||
        widget.subRequest.role == 'Member';

    if (isMemberRequest) {
      // For Member Recruitment: no formal agreement is created.
      try {
        final conversationId = await appState.firebaseService.getOrCreateDirectConversationAsync(
          currentUserId,
          selectedSub.userId,
        );

        final introMessage = Message(
          id: '',
          senderId: currentUserId,
          receiverId: selectedSub.userId,
          text: "Hi ${selectedSub.name}, thank you for your application to join ${widget.subRequest.bandName ?? 'our band'}! Let's connect here to discuss details and arrange an audition.",
          timestamp: DateTime.now(),
          isRead: false,
          senderName: appState.currentUserProfile?.displayName ?? 'Band Leader',
        );

        try {
          await appState.firebaseService.sendConversationMessageAsync(
            conversationId,
            introMessage.text ?? '',
            selectedSub.userId,
            introMessage.senderName ?? 'Band Leader',
          );
        } catch (e) {
          debugPrint("[SubRequestResponseDetailsScreen] sendConversationMessageAsync notice: $e");
        }

        if (mounted) {
          setState(() => _isLoading = false);
          final shouldOpen = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF0F0C20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF2E2A4E)),
              ),
              title: Text(
                'Message Candidate',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Text(
                'You may communicate with several prospective members, arrange a time for an audition, and ultimately make your selection through messaging. MUSICIANS will not create a formal Agreement.',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 13, height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Close', style: GoogleFonts.inter(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                  child: Text(
                    'Open Messages',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );

          if ((shouldOpen == true || shouldOpen == null) && mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  conversationId: conversationId,
                  receiverId: selectedSub.userId,
                  receiverName: selectedSub.name,
                ),
                settings: const RouteSettings(name: '/chat-detail'),
              ),
            );
          }
        }
        return;
      } catch (e) {
        debugPrint("[SubRequestResponseDetailsScreen] member message error: $e");
        setState(() => _isLoading = false);
        return;
      }
    }

    try {

      SubRequest effectiveReq = widget.subRequest;
      try {
        final freshReq = await appState.firebaseService.getSubRequestAsync(reqId);
        if (freshReq != null) {
          effectiveReq = freshReq;
        }
      } catch (_) {}

      // If connected to event and location or date is still missing, enrich from the event
      if ((effectiveReq.location == null || effectiveReq.location!.isEmpty || effectiveReq.date == null || effectiveReq.date!.isEmpty) &&
          effectiveReq.bandId != null &&
          effectiveReq.eventId != null &&
          effectiveReq.bandId!.isNotEmpty &&
          effectiveReq.eventId!.isNotEmpty) {
        try {
          final event = await appState.firebaseService.getBandEventOnceAsync(
            effectiveReq.bandId!,
            effectiveReq.eventId!,
          );
          if (event != null) {
            final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal();
            final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal();
            effectiveReq = effectiveReq.copyWith(
              location: (effectiveReq.location != null && effectiveReq.location!.isNotEmpty)
                  ? effectiveReq.location
                  : event.location,
              date: (effectiveReq.date != null && effectiveReq.date!.isNotEmpty)
                  ? effectiveReq.date
                  : event.startDateTime,
              startTime: (effectiveReq.startTime != null && effectiveReq.startTime!.isNotEmpty)
                  ? effectiveReq.startTime
                  : (startLocal != null ? DateFormat('HH:mm').format(startLocal) : null),
              endTime: (effectiveReq.endTime != null && effectiveReq.endTime!.isNotEmpty)
                  ? effectiveReq.endTime
                  : (endLocal != null ? DateFormat('HH:mm').format(endLocal) : null),
            );
          }
        } catch (_) {}
      }

      // 1. Create the Agreement
      final agreement = Agreement(
        choirLeaderId: currentUserId,
        vocalistId: selectedSub.userId,
        voicePart: effectiveReq.voicePart,
        date: effectiveReq.date,
        startTime: effectiveReq.startTime,
        endTime: effectiveReq.endTime,
        location: effectiveReq.location,
        additionalTerms: effectiveReq.description?.isNotEmpty == true
            ? effectiveReq.description
            : "Substitute staffing agreement.",
        bandName: effectiveReq.bandName,
        subRequestId: reqId,
        payAmount: effectiveReq.payAmount,
        currency: effectiveReq.currency,
      );

      // 2. Create the system message for the conversation
      final message = Message(
        id: '', // key is created dynamically in Firebase push
        senderId: currentUserId,
        receiverId: selectedSub.userId,
        text: "${selectedSub.name} has been chosen to attend the rehearsal.",
        timestamp: DateTime.now(),
        isRead: false,
        senderName: appState.currentUserProfile?.displayName ?? 'System',
      );

      // 3. Save agreement chat (safe non-blocking fallback)
      String conversationId = '';
      try {
        conversationId = await appState.firebaseService
            .createAgreementChatAsync(
              currentUserId,
              selectedSub.userId,
              agreement,
              message,
            );
      } catch (e) {
        debugPrint("[SubRequestResponseDetailsScreen] createAgreementChatAsync notice: $e");
        conversationId = 'conv_${currentUserId}_${selectedSub.userId}';
      }

      // If connected to event, update external invitee status to attending
      if (widget.subRequest.bandId != null &&
          widget.subRequest.eventId != null &&
          widget.subRequest.bandId!.isNotEmpty &&
          widget.subRequest.eventId!.isNotEmpty) {
        final bandId = widget.subRequest.bandId!;
        final eventId = widget.subRequest.eventId!;

        try {
          await appState.firebaseService.updateExternalInviteeResponseAsync(
            bandId,
            eventId,
            selectedSub.userId,
            'attending',
          );
        } catch (e) {
          debugPrint("[SubRequestResponseDetailsScreen] updateExternalInviteeResponseAsync notice: $e");
        }

        try {
          final event = await appState.firebaseService.getBandEventOnceAsync(
            bandId,
            eventId,
          );
          if (event != null) {
            if (event.temporaryRoomId != null &&
                event.temporaryRoomId!.isNotEmpty) {
              await appState.firebaseService.addMemberToEventRoomAsync(
                bandId,
                event.temporaryRoomId!,
                selectedSub.userId,
                'substitute',
              );
            } else if (mounted) {
              // Task 2842: Ask creator if they want to create a temporary event room
              final wantRoom = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF0F0C20),
                  title: Text(
                    "Create Event Room?",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  content: Text(
                    "A substitute has been approved! Would you like to create a temporary event room for this event?",
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(
                        "No thanks",
                        style: GoogleFonts.inter(color: AppTheme.textSecondary),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        "Create Room",
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (wantRoom == true) {
                await appState.firebaseService.createTemporaryEventRoomAsync(
                  bandId: bandId,
                  eventId: eventId,
                  roomName: '${event.title} Room',
                  createdBy: currentUserId,
                  initialMembers: [selectedSub.userId],
                );
              }
            }
          }
        } catch (roomErr) {
          debugPrint("[SubRequestResponseDetailsScreen] Event room step notice: $roomErr");
        }
      }

      // 4. Remove sub request globally and locally
      try {
        await appState.firebaseService.deleteSubRequestAsync(
          currentUserId,
          reqId,
        );
      } catch (delErr) {
        debugPrint("[SubRequestResponseDetailsScreen] deleteSubRequestAsync notice: $delErr");
      }

      // 5. Navigate to Receipt Screen
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/receipt',
          arguments: {
            'name': selectedSub.name,
            'voicePart': agreement.voicePart ?? 'Substitute',
            'date': agreement.date ?? '',
            'startTime': agreement.startTime ?? '',
            'endTime': agreement.endTime ?? '',
            'conversationId': conversationId,
            'receiverUserId': selectedSub.userId,
          },
        );
      }
    } catch (e) {
      debugPrint("Error confirming selection: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to confirm candidate: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  String get _headerTitle {
    final band = widget.subRequest.bandName ?? 'Band';
    final roleOrInst = widget.subRequest.voicePart ?? widget.subRequest.role ?? '';
    final isMember = widget.subRequest.role == 'New Member' || widget.subRequest.role == 'Member';
    if (isMember) {
      return roleOrInst.isNotEmpty
          ? '$band: New Member request for $roleOrInst'
          : '$band: New Member request';
    } else {
      return roleOrInst.isNotEmpty
          ? '$band: Substitute request for $roleOrInst'
          : '$band: Substitute request';
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(title: 'Responses', showBack: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Text(
                _headerTitle,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (widget.subRequest.role == 'New Member' || widget.subRequest.role == 'Member')
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, color: AppTheme.primaryAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'You may communicate with several prospective members, arrange a time for an audition, and ultimately make your selection through messaging. MUSICIANS will not create a formal Agreement.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.9),
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : _responders.isEmpty
                    ? Center(
                        child: Text(
                          'No responses received yet.',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _responders.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          final item = _responders[index];
                          final isSelected = _selectedUserId == item.userId;

                          return AnimatedTapDetector(
                            onTap: () {
                              setState(() {
                                _selectedUserId = isSelected ? null : item.userId;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppTheme.cardBackground,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.primaryAccent
                                    : const Color(0xFF2E2A4E),
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: AppTheme.primaryAccent,
                                        checkColor: Colors.white,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedUserId = item.userId;
                                            } else {
                                              _selectedUserId = null;
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          item.name,
                                          style: GoogleFonts.outfit(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.02),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.05),
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.music_note_rounded,
                                              color: AppTheme.primaryAccent,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.instruments,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.location_on_outlined,
                                              color: AppTheme.textSecondary,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item.location,
                                                style: GoogleFonts.inter(
                                                  color: AppTheme.textSecondary,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.star_outline_rounded,
                                              color: AppTheme.warning,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              'Level: ${item.level}',
                                              style: GoogleFonts.inter(
                                                color: AppTheme.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.about.isNotEmpty) ...[
                                          const Divider(
                                            color: Colors.white10,
                                            height: 16,
                                          ),
                                          Text(
                                            item.about,
                                            style: GoogleFonts.inter(
                                              color: AppTheme.textSecondary,
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                      ),
              ),
              if (_responders.isNotEmpty) ...[
                const SizedBox(height: 16),
                AnimatedTapDetector(
                  onTap: () {
                    if (_selectedUserId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please select a musician candidate to confirm.'),
                          backgroundColor: Colors.amber,
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }
                    _confirmSelection();
                  },
                  child: Container(
                    width: double.infinity,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: _selectedUserId != null
                          ? AppTheme.primaryGradient
                          : null,
                      color: _selectedUserId == null ? Colors.white10 : null,
                      borderRadius: BorderRadius.circular(12),
                      border: _selectedUserId == null
                          ? Border.all(color: Colors.white12)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        (widget.subRequest.role == 'New Member' || widget.subRequest.role == 'Member')
                            ? 'MESSAGE CANDIDATE'
                            : 'CONFIRM SELECTION',
                        style: GoogleFonts.inter(
                          color: _selectedUserId != null
                              ? Colors.white
                              : Colors.white54,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ResponderItem {
  final String userId;
  final String name;
  final String instruments;
  final String location;
  final String level;
  final String about;

  ResponderItem({
    required this.userId,
    required this.name,
    required this.instruments,
    required this.location,
    required this.level,
    required this.about,
  });
}
