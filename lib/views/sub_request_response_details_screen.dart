import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/request_management_access.dart';
import '../models/message.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import 'chat_detail_screen.dart';
import '../utils/sub_request_card_helper.dart';
import '../widgets/request_management_gate.dart';

class SubRequestResponseDetailsScreen extends StatelessWidget {
  const SubRequestResponseDetailsScreen({super.key,required this.subRequest});
  final SubRequest subRequest;
  @override
  Widget build(BuildContext context) => RequestManagementGate(
    requestId:subRequest.subRequestId ?? subRequest.id ?? '',
    bandId:subRequest.bandId,
    expectedCreatorId:subRequest.creatorUserId ?? subRequest.userId,
    builder:(access) => _AuthorizedSubRequestResponseDetailsScreen(subRequest:access.request!,access:access),
  );
}

class _AuthorizedSubRequestResponseDetailsScreen extends StatefulWidget {
  final SubRequest subRequest;

  final RequestManagementAccess access;
  const _AuthorizedSubRequestResponseDetailsScreen({required this.subRequest,required this.access});

  @override
  State<_AuthorizedSubRequestResponseDetailsScreen> createState() =>
      __AuthorizedSubRequestResponseDetailsScreenState();
}

class __AuthorizedSubRequestResponseDetailsScreenState
    extends State<_AuthorizedSubRequestResponseDetailsScreen> {
  bool get _current => mounted && widget.access.isValid;
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

      // The outer destination guard supplied the canonical authorized request.
      final responses = await appState.firebaseService.getSubRequestResponsesAsync(reqId);
      if (!mounted || !_current) return;

      final responderIds = responses.keys.toList();
      final List<ResponderItem> items = [];

      // 3. Fetch profiles for each responder ID
      for (final uid in responderIds) {
        if (!mounted || !_current) return;
        final profile = await appState.firebaseService.getUserProfileAsync(uid);
        if (!mounted || !_current) return;
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

      if (mounted && _current) {
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
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request management is unavailable for your current access.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted && _current) {
        if (mounted && _current) setState(() => _isLoading = false);
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
      if (mounted && _current) setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Missing user ID or request ID"), backgroundColor: AppTheme.danger),
      );
      return;
    }

    try {
      await appState.firebaseService.authorizeRequestManagement(
        requestId: reqId,
        bandId: widget.subRequest.bandId,
        expectedCreatorId: widget.subRequest.creatorUserId ?? widget.subRequest.userId,
        isCurrent: () => _current && appState.currentUserId == currentUserId,
      );
    } catch (_) {
      if (mounted && _current) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request management is unavailable for your current access.'),
        ));
      }
      return;
    }
    if (!mounted || !_current) return;
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
        if (!mounted || !_current) return;

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
          debugPrint("[_AuthorizedSubRequestResponseDetailsScreen] sendConversationMessageAsync notice: $e");
        }

        if (mounted && _current) {
          if (mounted && _current) setState(() => _isLoading = false);
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

          if ((shouldOpen == true || shouldOpen == null) && mounted && _current) {
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
        debugPrint("[_AuthorizedSubRequestResponseDetailsScreen] member message error: $e");
        if (mounted && _current) setState(() => _isLoading = false);
        return;
      }
    }

    try {

      final access = await appState.firebaseService.authorizeRequestManagement(
        requestId:reqId,bandId:widget.subRequest.bandId,
        expectedCreatorId:widget.subRequest.creatorUserId ?? widget.subRequest.userId,
        isCurrent: () => _current && appState.currentUserId == currentUserId);
      if (!mounted || !_current) return;
      SubRequest effectiveReq = access.request!;

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
          if (!mounted || !_current) return;
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

      // Server-authoritative assignment & Agreement creation
      if (!mounted || !_current) return;
      String conversationId = '';
      try {
        await appState.firebaseService.assignSubstituteCandidateAsync(
          subRequestId: reqId,
          candidateUserId: selectedSub.userId,
          bandId: effectiveReq.bandId ?? '',
          eventId: effectiveReq.eventId ?? '',
          roleOrInstrument: effectiveReq.voicePart ?? effectiveReq.role ?? '',
          candidateName: selectedSub.name,
        );
        if (!mounted || !_current) return;
        conversationId = appState.firebaseService.lastAssignedAgreementConversationId ?? '';
      } catch (e) {
        rethrow;
      }

      // If connected to event, add substitute to temporary event room when present
      if (widget.subRequest.bandId != null &&
          widget.subRequest.eventId != null &&
          widget.subRequest.bandId!.isNotEmpty &&
          widget.subRequest.eventId!.isNotEmpty) {
        final bandId = widget.subRequest.bandId!;
        final eventId = widget.subRequest.eventId!;

        try {
          final event = await appState.firebaseService.getBandEventOnceAsync(
            bandId,
            eventId,
          );
          if (!mounted || !_current) return;
          if (event != null) {
            if (event.temporaryRoomId != null &&
                event.temporaryRoomId!.isNotEmpty) {
              await appState.firebaseService.addMemberToEventRoomAsync(
                bandId,
                event.temporaryRoomId!,
                selectedSub.userId,
                'substitute',
              );
            }
          }
        } catch (roomErr) {
          debugPrint("[_AuthorizedSubRequestResponseDetailsScreen] Event room step notice: $roomErr");
        }
      }

      // 4. SubRequest is marked assigned by the server operation

      // 5. Navigate to Receipt Screen
      if (mounted && _current) {
        Navigator.pushReplacementNamed(
          context,
          '/receipt',
          arguments: {
            'name': selectedSub.name,
            'voicePart': effectiveReq.voicePart ?? 'Substitute',
            'date': effectiveReq.date ?? '',
            'startTime': effectiveReq.startTime ?? '',
            'endTime': effectiveReq.endTime ?? '',
            'conversationId': conversationId,
            'receiverUserId': selectedSub.userId,
          },
        );
      }
    } catch (e) {
      debugPrint("Error confirming selection: $e");
      if (mounted && _current) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to complete this request. Please try again.'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      if (mounted && _current) setState(() => _isLoading = false);
    }
  }

  Widget _buildRequestSummaryHeader() {
    final presentation = SubRequestCardPresentation.fromSubRequest(widget.subRequest);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF231F45), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Band / Project
          Text(
            presentation.bandName,
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),

          // 2. Request Type + Role / Instrument
          Text(
            '${presentation.requestType} · ${presentation.roleInstrument}',
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: presentation.requestType == 'New Band Member'
                  ? AppTheme.primaryAccent
                  : const Color(0xFF90CAF9),
            ),
          ),

          // 3. Event Type + Paid status/payment amount
          if (presentation.eventTypeAndPaymentLine != null) ...[
            const SizedBox(height: 6),
            Text(
              presentation.eventTypeAndPaymentLine!,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: presentation.isPaid ? AppTheme.primaryAccent : Colors.white70,
              ),
            ),
          ],

          // 4. Date & Time
          if (presentation.formattedDateTime != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.access_time_rounded, color: AppTheme.textSecondary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    presentation.formattedDateTime!,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // 5. full Location / Venue
          if (presentation.locationVenue != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Location / Venue: ${presentation.locationVenue!}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // 6. Description / Details
          if (presentation.description != null) ...[
            const SizedBox(height: 10),
            Text(
              'Description / Details',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              presentation.description!,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ],

          // 7. Payment Details, when present
          if (presentation.payDetails != null) ...[
            const SizedBox(height: 10),
            Text(
              'Payment Details',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              presentation.payDetails!,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
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
              _buildRequestSummaryHeader(),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CANDIDATES & RESPONSES',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (widget.subRequest.role == 'New Member' || widget.subRequest.role == 'Member')
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
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
                            color: Colors.white.withValues(alpha: 0.9),
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
                                      color: Colors.white.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.05),
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
