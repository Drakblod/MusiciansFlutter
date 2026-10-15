import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';
import '../data/genres_taxonomy.dart';
import '../widgets/secondary_skills_badge.dart';
import '../utils/band_section_utils.dart';
import '../widgets/create_band_section_sheet.dart';
import '../widgets/what_is_map_view_dialog.dart';
import 'band_room_chat_screen.dart';

class EditBandInfoScreen extends StatefulWidget {
  final Band band;

  const EditBandInfoScreen({super.key, required this.band});

  @override
  State<EditBandInfoScreen> createState() => _EditBandInfoScreenState();
}

class _EditBandInfoScreenState extends State<EditBandInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _locationController;
  late TextEditingController _rehearsalLocationController;
  late TextEditingController _mapViewLocationController;
  late TextEditingController _aboutController;

  late String _level;
  late String _rehearsalDay;
  
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  
  late List<String> _selectedStyles;
  late bool _hasRegularRehearsal;
  bool _isMapDisclaimerAccepted = false;
  bool _isSaving = false;

  List<BandMember> _members = [];
  final Map<String, UserProfile> _memberProfiles = {};
  bool _isLoadingMembers = false;

  final List<String> _levels = [
    'A = PRO',
    'B = SEMI PRO',
    'C = INTERMEDIATE',
    'D = AMATEUR',
    'E = BEGINNER'
  ];
  final List<String> _daysOfWeek = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];

  static final Map<String, List<String>> _genreCategoryMap = GenresTaxonomy.categoryMap;

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.band.name);
    _locationController = TextEditingController(text: widget.band.location);
    _rehearsalLocationController = TextEditingController(text: widget.band.rehearsalLocation);
    _mapViewLocationController = TextEditingController(text: widget.band.address ?? '');
    _aboutController = TextEditingController(text: widget.band.about ?? widget.band.description);

    _level = _levels.contains(widget.band.level)
        ? widget.band.level!
        : 'C = INTERMEDIATE';
    _rehearsalDay = _daysOfWeek.contains(widget.band.rehearsalDayOfWeek)
        ? widget.band.rehearsalDayOfWeek!
        : 'Monday';

    _startTime = _parseTime(widget.band.rehearsalStartTime, const TimeOfDay(hour: 18, minute: 0));
    _endTime = _parseTime(widget.band.rehearsalEndTime, const TimeOfDay(hour: 21, minute: 0));

    final hasRehearsal = (widget.band.rehearsalDayOfWeek != null && widget.band.rehearsalDayOfWeek!.trim().isNotEmpty) ||
        (widget.band.rehearsalStartTime != null && widget.band.rehearsalStartTime!.trim().isNotEmpty) ||
        (widget.band.rehearsalEndTime != null && widget.band.rehearsalEndTime!.trim().isNotEmpty);
    _hasRegularRehearsal = hasRehearsal;

    _selectedStyles = List<String>.from(widget.band.genres);

    if (widget.band.membersBand.isNotEmpty) {
      _members = widget.band.membersBand.values.toList();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMembers();
    });
  }

  TimeOfDay _parseTime(String? timeStr, TimeOfDay defaultTime) {
    if (timeStr == null || timeStr.isEmpty) return defaultTime;
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint("Error parsing time string $timeStr: $e");
    }
    return defaultTime;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _rehearsalLocationController.dispose();
    _mapViewLocationController.dispose();
    _aboutController.dispose();
    super.dispose();
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
      categoryMap: _genreCategoryMap,
      initialSelected: _selectedStyles,
    );
    if (result != null) {
      setState(() {
        _selectedStyles = result;
      });
    }
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              surface: AppTheme.cardBackground,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  Future<void> _updateBand() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = widget.band.id;

    if (bandId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: Band ID is missing.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    if (_hasRegularRehearsal) {
      final startMinutes = _startTime.hour * 60 + _startTime.minute;
      final endMinutes = _endTime.hour * 60 + _endTime.minute;
      if (endMinutes <= startMinutes) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('End time must be after start time'),
            backgroundColor: AppTheme.danger,
          ),
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final derivedType = _selectedStyles.isNotEmpty
          ? _selectedStyles.first
          : (widget.band.ensembleType ?? 'Band');

      final updated = Band(
        id: bandId,
        name: _nameController.text.trim(),
        ensembleType: derivedType,
        genres: _selectedStyles,
        styleBand: _selectedStyles,
        level: _level,
        location: _locationController.text.trim(),
        rehearsalLocation: _rehearsalLocationController.text.trim(),
        address: _mapViewLocationController.text.trim(),
        rehearsalDayOfWeek: _hasRegularRehearsal ? _rehearsalDay : null,
        rehearsalStartTime: _hasRegularRehearsal ? _formatTime(_startTime) : null,
        rehearsalEndTime: _hasRegularRehearsal ? _formatTime(_endTime) : null,
        about: _aboutController.text.trim(),
        description: _aboutController.text.trim(),
      );

      await appState.firebaseService.updateBandAsync(bandId, updated);
      appState.selectBand(bandId, updated.name ?? bandId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Band info updated successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update band: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _loadMembers() async {
    final bandId = widget.band.id;
    if (bandId == null || bandId.isEmpty) return;

    if (_members.isEmpty) {
      setState(() => _isLoadingMembers = true);
    }
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final members = await appState.firebaseService.getBandMembersAsync(bandId);
      if (mounted) {
        final uniqueMembers = <String, BandMember>{};
        for (final m in members) {
          if (m.userId != null && m.userId!.isNotEmpty) {
            uniqueMembers.putIfAbsent(m.userId!, () => m);
          }
        }
        final cleanMembers = uniqueMembers.isNotEmpty ? uniqueMembers.values.toList() : members;

        setState(() {
          _members = cleanMembers;
        });
        await _loadMemberProfiles(appState, cleanMembers);
      }
    } catch (e) {
      debugPrint('Error loading band members: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  Future<void> _loadMemberProfiles(AppState appState, List<BandMember> members) async {
    for (final m in members) {
      final uid = m.userId;
      if (uid != null && uid.isNotEmpty && !_memberProfiles.containsKey(uid)) {
        try {
          final profile = await appState.firebaseService.getUserProfileAsync(uid);
          if (profile != null && mounted) {
            setState(() {
              _memberProfiles[uid] = profile;
            });
          }
        } catch (e) {
          debugPrint('Error loading profile for $uid: $e');
        }
      }
    }
  }

  String _getMemberName(BandMember member) {
    if (member.userId != null && _memberProfiles.containsKey(member.userId)) {
      final profile = _memberProfiles[member.userId];
      if (profile?.displayName != null && profile!.displayName!.isNotEmpty) {
        return profile.displayName!;
      }
    }
    if (member.nickname != null && member.nickname!.isNotEmpty) {
      return member.nickname!;
    }
    return member.userId ?? 'Member';
  }

  String _getMemberInstrument(String? userId) {
    if (userId == null) return '';
    final profile = _memberProfiles[userId];
    if (profile == null) return '';
    if (profile.primarySkill.isNotEmpty) {
      return profile.primarySkill;
    }
    if (profile.mainInstrument != null && profile.mainInstrument!.isNotEmpty) {
      return profile.mainInstrument!.split(',').first.trim();
    }
    if (profile.instruments.isNotEmpty) {
      return profile.instruments.first;
    }
    return '';
  }

  List<String> _getMemberSecondarySkills(String? userId) {
    if (userId == null) return [];
    final profile = _memberProfiles[userId];
    if (profile == null) return [];
    return profile.secondarySkills;
  }

  String _getMemberInitial(BandMember member) {
    final name = _getMemberName(member);
    if (name.isNotEmpty) {
      return name.substring(0, 1).toUpperCase();
    }
    return 'M';
  }

  void _confirmRemoveMember(BandMember member) async {
    final memberUserId = member.userId;
    final bandId = widget.band.id;
    if (memberUserId == null || bandId == null) return;

    final name = _getMemberName(member);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0F0C20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Remove Member",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          "Are you sure you want to remove $name from the band?",
          style: GoogleFonts.inter(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text("Cancel", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.danger,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text("Remove", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final appState = Provider.of<AppState>(context, listen: false);
      try {
        await appState.firebaseService.removeBandMemberAsync(bandId, memberUserId);
        if (mounted) {
          setState(() {
            _members.removeWhere((m) => m.userId == memberUserId);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$name removed from band"),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Failed to remove member: $e"),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  Future<void> _showAddMemberDialog() async {
    final bandId = widget.band.id;
    if (bandId == null || bandId.isEmpty) return;
    final appState = Provider.of<AppState>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      ),
    );

    List<UserProfile> allUsers = [];
    try {
      allUsers = await appState.firebaseService.getAllUsersAsync();
    } catch (e) {
      debugPrint("Error fetching users: $e");
    } finally {
      if (mounted) {
        Navigator.pop(context); // Dismiss loader
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
            ),
            padding: const EdgeInsets.all(20),
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.6,
            child: AddMemberDialogContent(
              bandId: bandId,
              allUsers: allUsers,
              existingMembers: _members,
              onMemberAdded: () {
                _loadMembers();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _navigateTo1on1Chat(String otherUserId, String otherUserName) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    if (selfId == null || otherUserId == selfId) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      ),
    );

    try {
      final convId = await appState.firebaseService.getOrCreateDirectConversationAsync(selfId, otherUserId);
      if (mounted) {
        Navigator.pop(context); // Dismiss loader
        Navigator.pushNamed(
          context,
          '/chat-detail',
          arguments: {
            'conversationId': convId,
            'receiverId': otherUserId,
            'receiverName': otherUserName,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open chat: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _showMemberChatActions(BandMember member, String bandId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final memberId = member.userId;
    if (memberId == null) return;
    final memberName = _getMemberName(member);

    UserProfile? profile;
    try {
      profile = await appState.firebaseService.getUserProfileAsync(memberId);
    } catch (_) {}

    final instrument = BandSectionUtils.resolveEffectiveInstrument(profile);
    int matchingCount = 0;

    if (instrument != null && instrument.isNotEmpty) {
      final key = BandSectionUtils.normalizeInstrumentKey(instrument);
      for (final m in _members) {
        if (m.userId != null) {
          try {
            final p = await appState.firebaseService.getUserProfileAsync(m.userId!);
            final inst = BandSectionUtils.resolveEffectiveInstrument(p);
            if (inst != null && BandSectionUtils.normalizeInstrumentKey(inst) == key) {
              matchingCount++;
            }
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;

    final canCreateSectionChat = instrument != null && instrument.isNotEmpty && matchingCount >= 2;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16132D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF2E2452), width: 1.2),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primaryAccent),
                title: Text('Message $memberName', style: GoogleFonts.inter(color: Colors.white)),
                onTap: () {
                  Navigator.pop(ctx);
                  _navigateTo1on1Chat(memberId, memberName);
                },
              ),
              if (canCreateSectionChat)
                ListTile(
                  leading: const Icon(Icons.group_add_outlined, color: Colors.greenAccent),
                  title: Text('Create section chat: $instrument', style: GoogleFonts.inter(color: Colors.white)),
                  subtitle: Text('$matchingCount band members match this instrument', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final result = await CreateBandSectionSheet.show(
                      context,
                      initialBandId: bandId,
                      initialInstrument: instrument,
                      initialMemberId: memberId,
                    );
                    if (result != null && mounted) {
                      Navigator.pushNamed(context, '/band-section-chat', arguments: result);
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.groups_rounded, color: Colors.purpleAccent),
                title: const Text('Create custom group', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(ctx);
                  final result = await CreateBandSectionSheet.show(
                    context,
                    initialBandId: bandId,
                    initialMemberId: memberId,
                  );
                  if (result != null && mounted) {
                    Navigator.pushNamed(context, '/band-section-chat', arguments: result);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _viewMemberProfile(String userId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
      ),
    );

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final profile = await appState.firebaseService.getUserProfileAsync(userId);
      if (mounted) {
        Navigator.pop(context); // Dismiss loader
        if (profile != null) {
          Navigator.pushNamed(context, '/profile-detail', arguments: profile);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not load user profile.'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading profile: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _toggleMemberHoldStatus(BandMember member, bool putOnHold) async {
    final memberUserId = member.userId;
    final bandId = widget.band.id;
    if (memberUserId == null || bandId == null) return;

    final name = _getMemberName(member);

    if (putOnHold) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF0F0C20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.pause_circle_outline_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Put Member On Hold",
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            "Are you sure you want to put $name on hold?\n\nThey will be greyed out in the roster and won't be required for event RSVPs until reactivated.",
            style: GoogleFonts.inter(color: AppTheme.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text("Cancel", style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text("Put On Hold", style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) return;
    }

    final appState = Provider.of<AppState>(context, listen: false);
    try {
      final newStatus = putOnHold ? 'on_hold' : 'active';
      await appState.firebaseService.updateBandMemberStatusAsync(bandId, memberUserId, newStatus);
      if (mounted) {
        setState(() {
          final idx = _members.indexWhere((m) => m.userId == memberUserId);
          if (idx != -1) {
            _members[idx] = BandMember(
              userId: _members[idx].userId,
              nickname: _members[idx].nickname,
              role: _members[idx].role,
              status: newStatus,
            );
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(putOnHold ? "$name is now on hold" : "$name is now active"),
            backgroundColor: putOnHold ? Colors.amber.shade800 : AppTheme.success,
          ),
        );
        _loadMembers();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to update status: $e"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Widget _buildBandMembersSection() {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;
    final bandId = widget.band.id;

    final currentMember = _members.firstWhere(
      (m) => m.userId == currentUserId,
      orElse: () => BandMember(role: 'Member'),
    );
    final roleStr = (currentMember.role ?? widget.band.userRole ?? '').toLowerCase();
    final isLeaderOrAdmin = roleStr.contains('leader') || roleStr.contains('admin') || widget.band.canUserEdit(currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLeaderOrAdmin && bandId != null) ...[
          AnimatedTapDetector(
            onTap: _showAddMemberDialog,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      "Add Band Member",
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      'BAND MEMBERS',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (_members.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_members.length}',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, size: 14, color: AppTheme.primaryAccent),
                    const SizedBox(width: 4),
                    Text(
                      'Set Admin Roles',
                      style: GoogleFonts.inter(fontSize: 12, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ] else ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  'BAND MEMBERS',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                if (_members.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_members.length}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (_isLoadingMembers && _members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent)),
          )
        else if (_members.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No band members found. Tap "Add Band Member" to add musicians to your band.',
              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _members.length,
            itemBuilder: (itemCtx, index) {
              final member = _members[index];
              final mRoleStr = (member.role ?? '').toLowerCase();
              final isLeaderRole = mRoleStr.contains('leader');
              final isAdminRole = mRoleStr.contains('admin');
              final isMODRole = mRoleStr.contains('mod');
              final isOnHold = member.isOnHold;

              return AnimatedTapDetector(
                onTap: () {
                  if (member.userId != null) {
                    _viewMemberProfile(member.userId!);
                  }
                },
                child: Opacity(
                  opacity: isOnHold ? 0.6 : 1.0,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isOnHold ? Colors.amber.withValues(alpha: 0.3) : const Color(0xFF231F45), width: 1),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: isOnHold ? Colors.amber.withValues(alpha: 0.2) : AppTheme.primaryAccent.withValues(alpha: 0.3),
                          child: Text(
                            _getMemberInitial(member),
                            style: GoogleFonts.inter(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getMemberName(member),
                                style: GoogleFonts.outfit(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                member.role ?? 'Member',
                                style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                              ),
                              Builder(
                                builder: (context) {
                                  final instrument = _getMemberInstrument(member.userId);
                                  final secondary = _getMemberSecondarySkills(member.userId);
                                  if (instrument.isEmpty && secondary.isEmpty) return const SizedBox.shrink();
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        if (instrument.isNotEmpty)
                                          Text(
                                            instrument,
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              color: AppTheme.primaryAccent,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        if (secondary.isNotEmpty)
                                          SecondarySkillsBadge(
                                            memberName: _getMemberName(member),
                                            secondarySkills: secondary,
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        if (isOnHold)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              'ON HOLD',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        if (isLeaderRole || isAdminRole || isMODRole)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isMODRole
                                  ? Colors.purple.withValues(alpha: 0.2)
                                  : isAdminRole
                                      ? Colors.amber.withValues(alpha: 0.2)
                                      : AppTheme.primaryAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: isMODRole
                                  ? Border.all(color: Colors.purple.withValues(alpha: 0.4))
                                  : isAdminRole
                                      ? Border.all(color: Colors.amber.withValues(alpha: 0.4))
                                      : null,
                            ),
                            child: Text(
                              isLeaderRole ? 'Leader' : isAdminRole ? 'Admin' : 'MOD',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: isMODRole
                                    ? Colors.purpleAccent
                                    : isAdminRole
                                        ? Colors.amber
                                        : AppTheme.primaryAccent,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (member.userId != null && member.userId != currentUserId) ...[
                          GestureDetector(
                            onTap: () {
                              if (bandId != null) {
                                _showMemberChatActions(member, bandId);
                              } else {
                                _navigateTo1on1Chat(member.userId!, _getMemberName(member));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: AppTheme.primaryAccent,
                                size: 18,
                              ),
                            ),
                          ),
                          if (isLeaderOrAdmin) ...[
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _toggleMemberHoldStatus(member, !isOnHold),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: (isOnHold ? Colors.green : Colors.amber).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isOnHold ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                  color: isOnHold ? Colors.greenAccent : Colors.amber,
                                  size: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.shield_outlined, color: AppTheme.primaryAccent, size: 20),
                              tooltip: 'Set Admin Roles',
                              color: const Color(0xFF16132D),
                              onSelected: (newRole) async {
                                if (bandId != null && member.userId != null) {
                                  if (newRole == 'Leader') {
                                    // Enforce 1 Leader limit: Demote previous leader to Admin
                                    for (var m in _members) {
                                      if (m.userId != null && (m.role ?? '').toLowerCase().contains('leader') && m.userId != member.userId) {
                                        await appState.firebaseService.updateBandMemberRoleAsync(bandId, m.userId!, 'Admin');
                                      }
                                    }
                                  }
                                  await appState.firebaseService.updateBandMemberRoleAsync(bandId, member.userId!, newRole);
                                  await _loadMembers();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${_getMemberName(member)}\'s role updated to $newRole'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (menuContext) => [
                                PopupMenuItem(
                                  value: 'Member',
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_outline, color: Colors.white, size: 16),
                                      SizedBox(width: 8),
                                      Text('Set as Member', style: GoogleFonts.inter(color: Colors.white)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'MOD',
                                  child: Row(
                                    children: [
                                      Icon(Icons.security_rounded, color: Colors.purpleAccent, size: 16),
                                      SizedBox(width: 8),
                                      Text('Set as MOD', style: GoogleFonts.inter(color: Colors.purpleAccent)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'Admin',
                                  child: Row(
                                    children: [
                                      Icon(Icons.admin_panel_settings_outlined, color: Colors.amber, size: 16),
                                      SizedBox(width: 8),
                                      Text('Set as Admin', style: GoogleFonts.inter(color: Colors.amber)),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'Leader',
                                  child: Row(
                                    children: [
                                      Icon(Icons.star_outline_rounded, color: AppTheme.primaryAccent, size: 16),
                                      SizedBox(width: 8),
                                      Text('Transfer Leadership', style: GoogleFonts.inter(color: AppTheme.primaryAccent)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => _confirmRemoveMember(member),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.person_remove_outlined,
                                  color: AppTheme.danger,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        showBack: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        physics: const BouncingScrollPhysics(),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit Band',
                style: GoogleFonts.outfit(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Band Name
              Text(
                'Band Name',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Enter band name',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a band name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // About
              Text(
                'About',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _aboutController,
                maxLines: 4,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Provide details about rehearsals, gigs, level, style, etc.',
                ),
              ),
              const SizedBox(height: 20),

              AnimatedTapDetector(
                enableFocus: true,
                semanticLabel: 'GENRES/BAND TYPES',
                onTap: _openGenrePicker,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.music_note_rounded, color: AppTheme.primaryAccent, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'GENRES/BAND TYPES',
                                style: GoogleFonts.outfit(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (_selectedStyles.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedStyles.length}',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                                  ),
                                ),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedStyles.isEmpty)
                        Text(
                          'Tap to select Genres/Band Types',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _selectedStyles.map((genre) {
                            return InputChip(
                              label: Text(genre),
                              selected: false,
                              onDeleted: () => setState(() => _selectedStyles.remove(genre)),
                              deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Colors.white70),
                              backgroundColor: const Color(0xFF1B1735),
                              labelStyle: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Band Level
              Text(
                'Level',
                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.inputBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _level,
                    dropdownColor: AppTheme.cardBackground,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: _levels.map((String val) {
                      return DropdownMenuItem<String>(
                        value: val,
                        child: Text(val),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _level = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Location (City, Country)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Location',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    TextSpan(
                      text: ' (City, Country)',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _locationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Stockholm, Sweden',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter location';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Rehearsal Location (if any)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Rehearsal Location',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    TextSpan(
                      text: ' (if any)',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _rehearsalLocationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'e.g. Studio 3, Stockholm',
                ),
              ),
              const SizedBox(height: 20),

              // Regular Rehearsal Day & Time (if any)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Regular Rehearsal Day & Time',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          TextSpan(
                            text: ' (if any)',
                            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Switch.adaptive(
                    value: _hasRegularRehearsal,
                    activeColor: AppTheme.primaryAccent,
                    onChanged: (val) {
                      setState(() {
                        _hasRegularRehearsal = val;
                      });
                    },
                  ),
                ],
              ),
              if (_hasRegularRehearsal) ...[
                const SizedBox(height: 12),
                Text(
                  'Day',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      value: _rehearsalDay,
                      dropdownColor: AppTheme.cardBackground,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      items: _daysOfWeek.map((String val) {
                        return DropdownMenuItem<String>(
                          value: val,
                          child: Text(val),
                        );
                      }).toList(),
                      onChanged: (newValue) {
                        if (newValue != null) {
                          setState(() {
                            _rehearsalDay = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Start Time',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          AnimatedTapDetector(
                            onTap: () => _pickTime(true),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.inputBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  _formatTime(_startTime),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'End Time',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 8),
                          AnimatedTapDetector(
                            onTap: () => _pickTime(false),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: AppTheme.inputBackground,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                              ),
                              child: Center(
                                child: Text(
                                  _formatTime(_endTime),
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Map View Location (if other than Rehearsal Location)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Map View Location',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    TextSpan(
                      text: ' (if other than Rehearsal Location)',
                      style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Klickbar ruta: "What is Map View?"
              Semantics(
                button: true,
                label: 'What is Map View? Click to read full guide.',
                child: AnimatedTapDetector(
                  onTap: () => showWhatIsMapViewDialog(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0C20).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.5), width: 1.2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.help_outline_rounded, color: AppTheme.primaryAccent, size: 16),
                            const SizedBox(width: 6),
                            Text(
                              'What is Map View?',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.primaryAccent, size: 12),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Explore Map View to discover audio snippets from gigs, rehearsals, recordings and gig promos, as well as requests for band members, subs and paid gigs.',
                          style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFD4CEEB), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _mapViewLocationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Enter FULL address for Map View Pin (Street, City, Country)',
                ),
              ),
              const SizedBox(height: 12),

              // Map Location & Media Permission Disclaimer Container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBackground,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _isMapDisclaimerAccepted,
                      activeColor: AppTheme.primaryAccent,
                      checkColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      side: const BorderSide(color: Colors.white54),
                      onChanged: (val) {
                        setState(() {
                          _isMapDisclaimerAccepted = val ?? false;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _isMapDisclaimerAccepted = !_isMapDisclaimerAccepted;
                          });
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location & Media disclaimer for Map View',
                              style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'By checking this box, you give MUSICIANS permission to display your band’s location in "Map View" and make your uploaded media available through your band’s map icon. You confirm that you have all necessary rights and permissions for the media you upload.',
                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Band Members Section
              _buildBandMembersSection(),
              const SizedBox(height: 30),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : AnimatedTapDetector(
                      onTap: _updateBand,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Save Changes',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 24),

              // Leader-only Danger Zone: Delete Band
              Consumer<AppState>(
                builder: (context, appState, child) {
                  final isLeader = widget.band.isUserLeader(appState.currentUserId);
                  if (!isLeader) return const SizedBox.shrink();

                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFEF4444).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'BAND LEADER ACTIONS',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFFEF4444),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Permanently delete this band, its events, and conversations for all members.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AnimatedTapDetector(
                          onTap: () => _showDeleteBandConfirmation(context, appState),
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFEF4444).withOpacity(0.6),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.delete_forever_rounded,
                                    color: Color(0xFFEF4444),
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Delete Band',
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: const Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _showDeleteBandConfirmation(BuildContext context, AppState appState) {
    final bandId = widget.band.id;
    final bandName = widget.band.name ?? 'this band';

    if (bandId == null || bandId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete band: Invalid band identifier.'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        bool isDeleting = false;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0C20).withOpacity(0.98),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFEF4444).withOpacity(0.5), width: 1.5),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444), size: 40),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Delete Band',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Are you sure you want to permanently delete "$bandName"? This will remove the band, its events, and chat rooms for all band members.',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    if (isDeleting)
                      const Center(
                        child: CircularProgressIndicator(color: Color(0xFFEF4444)),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFF2E2A4E)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => Navigator.pop(dialogCtx),
                              child: Text(
                                'Cancel',
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () async {
                                setDialogState(() {
                                  isDeleting = true;
                                });
                                try {
                                  await appState.deleteBand(bandId);
                                  if (dialogCtx.mounted) {
                                    Navigator.pop(dialogCtx); // Close dialog
                                  }
                                  if (context.mounted) {
                                    Navigator.pop(context); // Pop EditBandInfoScreen
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Band "$bandName" deleted successfully.'),
                                        backgroundColor: AppTheme.warning,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (dialogCtx.mounted) {
                                    setDialogState(() {
                                      isDeleting = false;
                                    });
                                    ScaffoldMessenger.of(dialogCtx).showSnackBar(
                                      SnackBar(
                                        content: Text('Error deleting band: $e'),
                                        backgroundColor: AppTheme.danger,
                                      ),
                                    );
                                  }
                                }
                              },
                              child: Text(
                                'Delete',
                                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
