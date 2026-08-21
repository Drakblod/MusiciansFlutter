import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/sub_request.dart';
import '../models/agreement.dart';
import '../models/message.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

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

      // Fetch the responses snapshot directly from root SubRequests
      final list = await appState.firebaseService.getAllSubRequestsAsync();
      final matchingReq = list.firstWhere(
        (r) => (r.subRequestId ?? r.id) == reqId,
        orElse: () => widget.subRequest,
      );

      final responderIds = matchingReq.responses.keys.toList();
      final List<ResponderItem> items = [];

      // Fetch profiles for each responder ID
      for (final uid in responderIds) {
        final profile = await appState.firebaseService.getUserProfileAsync(uid);
        if (profile != null) {
          items.add(
            ResponderItem(
              userId: uid,
              name: profile.displayName ?? profile.nickname ?? 'Unknown',
              instruments: profile.instruments.join(', '),
              location: profile.location ?? 'Stockholm, Sweden',
              level: profile.level ?? 'Intermediate',
              about: profile.about ?? 'No description provided.',
            ),
          );
        }
      }

      setState(() {
        _responders = items;
      });
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmSelection() async {
    if (_selectedUserId == null) return;
    final selectedSub = _responders.firstWhere(
      (r) => r.userId == _selectedUserId,
    );

    setState(() => _isLoading = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final currentUserId = appState.currentUserId;
      final reqId = widget.subRequest.subRequestId ?? widget.subRequest.id;

      if (currentUserId == null || reqId == null) {
        throw Exception("Missing user ID or request ID");
      }

      // 1. Create the Agreement
      final agreement = Agreement(
        choirLeaderId: currentUserId,
        vocalistId: selectedSub.userId,
        voicePart: widget.subRequest.voicePart,
        date: widget.subRequest.date,
        startTime: widget.subRequest.startTime,
        endTime: widget.subRequest.endTime,
        location: widget.subRequest.location,
        additionalTerms: "Rehearsal replacement agreement.",
        bandName: widget.subRequest.bandName,
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

      // 3. Save agreement chat
      final conversationId = await appState.firebaseService
          .createAgreementChatAsync(
            currentUserId,
            selectedSub.userId,
            agreement,
            message,
          );

      // If connected to event, update external invitee status to attending
      if (widget.subRequest.bandId != null &&
          widget.subRequest.eventId != null &&
          widget.subRequest.bandId!.isNotEmpty &&
          widget.subRequest.eventId!.isNotEmpty) {
        final bandId = widget.subRequest.bandId!;
        final eventId = widget.subRequest.eventId!;

        await appState.firebaseService.updateExternalInviteeResponseAsync(
          bandId,
          eventId,
          selectedSub.userId,
          'attending',
        );

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
          } else {
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
      }

      // 4. Remove sub request globally and locally
      await appState.firebaseService.deleteSubRequestAsync(
        currentUserId,
        reqId,
      );

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
                'Responses for ${widget.subRequest.bandName ?? "Rehearsal"}',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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

                          return Container(
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
                          );
                        },
                      ),
              ),
              if (_responders.isNotEmpty) ...[
                const SizedBox(height: 16),
                AnimatedTapDetector(
                  onTap: _selectedUserId != null ? _confirmSelection : () {},
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
                        'CONFIRM SELECTION',
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
