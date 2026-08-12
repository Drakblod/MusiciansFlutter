import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_session.dart';
import '../models/user_profile.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';

class SessionDetailsScreen extends StatefulWidget {
  final CollabSession session;

  const SessionDetailsScreen({super.key, required this.session});

  @override
  State<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends State<SessionDetailsScreen> {
  bool _isLoadingApp = true;
  bool _isActionInProgress = false;
  CollabSessionApplication? _myApplication;
  List<CollabSessionApplication> _allApplications = [];
  Map<String, UserProfile> _loadedProfiles = {};
  UserProfile? _creatorProfile;

  @override
  void initState() {
    super.initState();
    _loadCreatorProfile();
    _loadApplicationsData();
  }

  Future<void> _loadCreatorProfile() async {
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final profile = await appState.firebaseService.getUserProfileAsync(
        widget.session.creatorId,
      );
      if (mounted) {
        setState(() {
          _creatorProfile = profile;
        });
      }
    } catch (e) {
      debugPrint("Error loading creator profile: $e");
    }
  }

  Future<void> _loadApplicationsData() async {
    if (!mounted) return;
    setState(() => _isLoadingApp = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      setState(() => _isLoadingApp = false);
      return;
    }

    try {
      final isCreator = widget.session.creatorId == userId;

      if (isCreator) {
        // Creator loads all applications
        _allApplications = await appState.firebaseService
            .getCollabSessionApplicationsAsync(widget.session.id ?? '');
        // Fetch profiles of applicants in parallel
        for (var app in _allApplications) {
          if (!_loadedProfiles.containsKey(app.userId)) {
            final profile = await appState.firebaseService.getUserProfileAsync(
              app.userId,
            );
            if (profile != null) {
              _loadedProfiles[app.userId] = profile;
            }
          }
        }
      } else {
        // Non-creator loads only their own application
        _myApplication = await appState.firebaseService
            .getCollabSessionApplicationAsync(widget.session.id ?? '', userId);
      }
    } catch (e) {
      debugPrint("Error loading applications: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingApp = false);
      }
    }
  }

  Future<void> _requestToJoin() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;
    if (userId == null) return;

    setState(() => _isActionInProgress = true);
    try {
      final newApp = CollabSessionApplication(
        userId: userId,
        sessionId: widget.session.id ?? '',
        creatorId: widget.session.creatorId,
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'pending',
      );

      await appState.firebaseService.applyToCollabSessionAsync(
        widget.session.id ?? '',
        userId,
        newApp,
      );
      await _loadApplicationsData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request to join sent!'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _cancelRequest() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;
    if (userId == null) return;

    setState(() => _isActionInProgress = true);
    try {
      await appState.firebaseService.cancelCollabSessionApplicationAsync(
        widget.session.id ?? '',
        userId,
      );
      await _loadApplicationsData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Join request cancelled.'),
            backgroundColor: AppTheme.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _updateApplicationStatus(
    String applicantId,
    String newStatus,
  ) async {
    final appState = Provider.of<AppState>(context, listen: false);
    setState(() => _isActionInProgress = true);
    try {
      await appState.firebaseService.updateCollabApplicationStatusAsync(
        widget.session.id ?? '',
        applicantId,
        newStatus,
      );
      await _loadApplicationsData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Request marked as $newStatus'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update request: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _deleteSession() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: Text(
          'Delete Session',
          style: GoogleFonts.outfit(color: Colors.white),
        ),
        content: Text(
          'Are you sure you want to delete this collab session permanently?',
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.inter(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isActionInProgress = true);
      try {
        final appState = Provider.of<AppState>(context, listen: false);
        await appState.firebaseService.deleteCollabSessionAsync(
          widget.session.id ?? '',
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Session deleted successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete session: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isActionInProgress = false);
      }
    }
  }

  Future<void> _closeSession() async {
    setState(() => _isActionInProgress = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final closedSession = CollabSession(
        id: widget.session.id,
        title: widget.session.title,
        description: widget.session.description,
        sessionType: widget.session.sessionType,
        sessionCategory: widget.session.sessionCategory,
        isDateFlexible: widget.session.isDateFlexible,
        startDateTime: widget.session.startDateTime,
        location: widget.session.location,
        genres: widget.session.genres,
        lookingForRoles: widget.session.lookingForRoles,
        lookingForInstruments: widget.session.lookingForInstruments,
        creatorId: widget.session.creatorId,
        createdAt: widget.session.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
        status: 'closed',
      );
      await appState.firebaseService.saveCollabSessionAsync(closedSession);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session closed successfully'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to close session: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _openDirectChat(UserProfile targetUser) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    final otherId = targetUser.userId;

    if (selfId == null || otherId == null) return;

    final convId = await appState.firebaseService
        .getOrCreateDirectConversationAsync(selfId, otherId);

    if (mounted) {
      Navigator.pushNamed(
        context,
        '/chat-detail',
        arguments: {
          'conversationId': convId,
          'receiverId': otherId,
          'receiverName': targetUser.displayName ?? 'Artist',
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selfId = appState.currentUserId;
    final isCreator = widget.session.creatorId == selfId;

    final dateStr = widget.session.isDateFlexible
        ? 'Flexible Date'
        : (widget.session.startDateTime != null
              ? widget.session.startDateTime!
                    .substring(0, 16)
                    .replaceAll('T', ' ')
              : 'Date not set');

    // Filter accepted applicants as participants
    final participants = isCreator
        ? _allApplications.where((a) => a.status == 'accepted').toList()
        : [];

    return GradientScaffold(
      appBar: const CustomTopBar(showBack: true),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Category Tag
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.session.sessionCategory.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Title & Creator Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      widget.session.title,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (isCreator) ...[
                    IconButton(
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: AppTheme.primaryAccent,
                      ),
                      onPressed: () async {
                        final updated = await Navigator.pushNamed(
                          context,
                          '/create-session',
                          arguments: widget.session,
                        );
                        if (updated == true && mounted) {
                          Navigator.pop(
                            context,
                          ); // pop detail view to reload parent lists
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppTheme.warning,
                      ),
                      onPressed: _closeSession,
                      tooltip: 'Close Session',
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppTheme.danger,
                      ),
                      onPressed: _deleteSession,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),

              // Location / Date Time Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF231F45), width: 1),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          color: AppTheme.primaryAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          dateStr,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppTheme.primaryAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.session.location ?? 'Remote Collaboration',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Description
              Text(
                'Session Overview',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF231F45), width: 1),
                ),
                child: Text(
                  widget.session.description,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Looking For Roles Section
              Text(
                'Roles Being Searched For',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.session.lookingForRoles.map((role) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1A3A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E2A4E)),
                    ),
                    child: Text(
                      role[0].toUpperCase() + role.substring(1),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.secondaryAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Creator Profile Details
              if (_creatorProfile != null) ...[
                Text(
                  'Session Host',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/profile-detail',
                      arguments: _creatorProfile!,
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFF231F45),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.primaryAccent.withOpacity(
                            0.2,
                          ),
                          backgroundImage:
                              _creatorProfile!.profilePictureUrl != null &&
                                  _creatorProfile!.profilePictureUrl!.isNotEmpty
                              ? NetworkImage(
                                  _creatorProfile!.profilePictureUrl!,
                                )
                              : null,
                          child:
                              _creatorProfile!.profilePictureUrl == null ||
                                  _creatorProfile!.profilePictureUrl!.isEmpty
                              ? Text(
                                  _creatorProfile!.displayName != null
                                      ? _creatorProfile!.displayName!
                                            .substring(0, 1)
                                            .toUpperCase()
                                      : 'H',
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _creatorProfile!.displayName ?? 'Host',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _creatorProfile!.userType ?? 'Musician',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isCreator)
                          IconButton(
                            icon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: AppTheme.primaryAccent,
                            ),
                            onPressed: () => _openDirectChat(_creatorProfile!),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Participants list
              if (isCreator && participants.isNotEmpty) ...[
                Text(
                  'Participants (${participants.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: participants.length,
                  itemBuilder: (context, index) {
                    final app = participants[index];
                    final profile = _loadedProfiles[app.userId];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF231F45),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppTheme.primaryAccent,
                            child: Text(
                              profile?.displayName
                                      ?.substring(0, 1)
                                      .toUpperCase() ??
                                  'U',
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              profile?.displayName ?? 'Accepted Collaborator',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (profile != null)
                            IconButton(
                              icon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: AppTheme.primaryAccent,
                                size: 16,
                              ),
                              onPressed: () => _openDirectChat(profile),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Participant/Applicant actions based on role
              if (isCreator) ...[
                // Creator view of applications
                Text(
                  'Join Requests (${_allApplications.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                _isLoadingApp
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : _allApplications.isEmpty
                    ? Text(
                        'No join requests submitted yet.',
                        style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _allApplications.length,
                        itemBuilder: (context, index) {
                          final app = _allApplications[index];
                          final profile = _loadedProfiles[app.userId];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.inputBackground,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFF2E2A4E),
                              ),
                            ),
                            child: Row(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    if (profile != null) {
                                      Navigator.pushNamed(
                                        context,
                                        '/profile-detail',
                                        arguments: profile,
                                      );
                                    }
                                  },
                                  child: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppTheme.primaryAccent,
                                    child: Text(
                                      profile?.displayName
                                              ?.substring(0, 1)
                                              .toUpperCase() ??
                                          'U',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        profile?.displayName ?? 'Applicant',
                                        style: GoogleFonts.inter(
                                          fontSize: 13,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Status: ${app.status.toUpperCase()}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: app.status == 'accepted'
                                              ? AppTheme.success
                                              : (app.status == 'declined'
                                                    ? AppTheme.danger
                                                    : AppTheme.warning),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (profile != null)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      color: AppTheme.primaryAccent,
                                      size: 18,
                                    ),
                                    onPressed: () => _openDirectChat(profile),
                                  ),
                                if (app.status == 'pending') ...[
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check_circle_outline_rounded,
                                      color: AppTheme.success,
                                      size: 20,
                                    ),
                                    onPressed: _isActionInProgress
                                        ? null
                                        : () => _updateApplicationStatus(
                                            app.userId,
                                            'accepted',
                                          ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      color: AppTheme.danger,
                                      size: 20,
                                    ),
                                    onPressed: _isActionInProgress
                                        ? null
                                        : () => _updateApplicationStatus(
                                            app.userId,
                                            'declined',
                                          ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ] else ...[
                // Non-creator view of request to join status
                Text(
                  'Your Request',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                _isLoadingApp
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppTheme.primaryAccent,
                        ),
                      )
                    : _myApplication == null
                    ? AnimatedTapDetector(
                        onTap: () {
                          if (!_isActionInProgress) {
                            _requestToJoin();
                          }
                        },
                        child: Container(
                          height: 50,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: _isActionInProgress
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : Text(
                                    'Request to Join Session',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Status: ${_myApplication!.status.toUpperCase()}',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _myApplication!.status == 'accepted'
                                        ? AppTheme.success
                                        : (_myApplication!.status == 'declined'
                                              ? AppTheme.danger
                                              : AppTheme.warning),
                                  ),
                                ),
                                if (_myApplication!.status == 'pending')
                                  TextButton.icon(
                                    onPressed: _isActionInProgress
                                        ? null
                                        : _cancelRequest,
                                    icon: const Icon(
                                      Icons.remove_circle_outline_rounded,
                                      color: AppTheme.danger,
                                      size: 16,
                                    ),
                                    label: Text(
                                      'Cancel Request',
                                      style: GoogleFonts.inter(
                                        color: AppTheme.danger,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _myApplication!.status == 'accepted'
                                  ? 'You have been accepted into this collaboration! Check in with the host via chat.'
                                  : (_myApplication!.status == 'declined'
                                        ? 'Your request was declined by the host.'
                                        : 'Your request is currently under review by the host.'),
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
