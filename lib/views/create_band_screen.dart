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
import '../widgets/what_is_map_view_dialog.dart';
import '../data/genres_taxonomy.dart';

class CreateBandScreen extends StatefulWidget {
  const CreateBandScreen({super.key});

  @override
  State<CreateBandScreen> createState() => _CreateBandScreenState();
}

class _CreateBandScreenState extends State<CreateBandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _rehearsalLocationController = TextEditingController();
  final _mapViewLocationController = TextEditingController();
  final _aboutController = TextEditingController();

  final List<UserProfile> _selectedMembers = [];
  final Map<String, String> _memberRoles = {};

  String _level = 'C = INTERMEDIATE';
  String _rehearsalDay = 'Monday';
  
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  
  List<String> _selectedGenres = [];
  bool _hasRegularRehearsal = false;
  bool _isMapDisclaimerAccepted = false;
  bool _isSaving = false;

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
      initialSelected: _selectedGenres,
    );
    if (result != null) {
      setState(() {
        _selectedGenres = result;
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

  Future<void> _saveBand() async {
    if (!_formKey.currentState!.validate()) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: No user logged in.'),
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
      final formatTime = (TimeOfDay t) =>
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

      final band = Band(
        name: _nameController.text.trim(),
        ensembleType: _selectedGenres.isNotEmpty ? _selectedGenres.first : 'Band',
        genres: _selectedGenres,
        styleBand: _selectedGenres,
        level: _level,
        location: _locationController.text.trim(),
        rehearsalLocation: _rehearsalLocationController.text.trim(),
        address: _mapViewLocationController.text.trim(),
        rehearsalDayOfWeek: _hasRegularRehearsal ? _rehearsalDay : null,
        rehearsalStartTime: _hasRegularRehearsal ? formatTime(_startTime) : null,
        rehearsalEndTime: _hasRegularRehearsal ? formatTime(_endTime) : null,
        about: _aboutController.text.trim(),
        description: _aboutController.text.trim(),
      );

      await appState.firebaseService.createBandAsync(userId, band);

      final bandId = (band.name ?? 'My Band').replaceAll(' ', '_');
      for (final member in _selectedMembers) {
        if (member.userId != null && member.userId != userId) {
          final role = _memberRoles[member.userId] ?? 'Member';
          try {
            await appState.firebaseService.addBandMemberAsync(
              bandId,
              member.userId!,
              role,
              member.nickname ?? member.displayName ?? role,
            );
          } catch (mErr) {
            debugPrint("Error adding initial band member ${member.userId}: $mErr");
          }
        }
      }

      await appState.refreshProfile(); // refresh local active bands

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Band created successfully!'),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create band: $e'),
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

  Future<void> _showAddMemberDialog() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final currentUserId = appState.currentUserId;

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

    final existingUserIds = {
      if (currentUserId != null) currentUserId,
      ..._selectedMembers.map((m) => m.userId).whereType<String>(),
    };

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0F0C20).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
            ),
            padding: const EdgeInsets.all(20),
            width: MediaQuery.of(ctx).size.width * 0.9,
            height: MediaQuery.of(ctx).size.height * 0.65,
            child: _SelectBandMemberDialog(
              allUsers: allUsers,
              existingUserIds: existingUserIds,
              onUserSelected: (user) {
                setState(() {
                  _selectedMembers.add(user);
                });
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildBandMembersSection() {
    final appState = Provider.of<AppState>(context, listen: false);
    final userProfile = appState.currentUserProfile;
    final leaderName = userProfile?.displayName ?? userProfile?.nickname ?? 'You';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  'Band Members',
                  style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                if (_selectedMembers.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedMembers.length + 1}',
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
            TextButton.icon(
              onPressed: _showAddMemberDialog,
              icon: const Icon(Icons.person_add_rounded, color: AppTheme.primaryAccent, size: 16),
              label: Text(
                'Add Member',
                style: GoogleFonts.inter(
                  color: AppTheme.primaryAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Add members to your band. They will be added to the band room and chat automatically.',
          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, height: 1.3),
        ),
        const SizedBox(height: 6),
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
        const SizedBox(height: 12),

        // Leader card (Creator)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.25),
                child: Text(
                  leaderName.isNotEmpty ? leaderName.substring(0, 1).toUpperCase() : 'L',
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$leaderName (You)',
                      style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    Text(
                      'Leader',
                      style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryAccent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Leader',
                  style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // Added members
        if (_selectedMembers.isNotEmpty)
          ..._selectedMembers.map((member) {
            final name = member.displayName ?? member.nickname ?? 'Unknown';
            final instrumentsStr = member.instruments.isNotEmpty
                ? member.instruments.join(', ')
                : (member.mainInstrument ?? 'Member');
            final role = _memberRoles[member.userId] ?? 'Member';
            final isLeaderRole = role.toLowerCase() == 'leader';
            final isAdminRole = role.toLowerCase() == 'admin';
            final isMODRole = role.toLowerCase() == 'mod';

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF64B5F6).withValues(alpha: 0.2),
                    child: Text(
                      name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'M',
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        Text(
                          role,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                        if (instrumentsStr.isNotEmpty && instrumentsStr != 'Member')
                          Text(
                            instrumentsStr,
                            style: GoogleFonts.inter(color: AppTheme.textSecondary.withValues(alpha: 0.7), fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (isLeaderRole || isAdminRole || isMODRole)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
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
                                : Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.4)),
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.shield_outlined, color: AppTheme.primaryAccent, size: 20),
                    tooltip: 'Set Admin Roles',
                    color: const Color(0xFF16132D),
                    onSelected: (newRole) {
                      if (member.userId != null) {
                        setState(() {
                          _memberRoles[member.userId!] = newRole;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$name\'s role set to $newRole'),
                            backgroundColor: AppTheme.success,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    itemBuilder: (menuContext) => [
                      PopupMenuItem(
                        value: 'Member',
                        child: Row(
                          children: [
                            const Icon(Icons.person_outline, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text('Set as Member', style: GoogleFonts.inter(color: Colors.white)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'MOD',
                        child: Row(
                          children: [
                            const Icon(Icons.security_rounded, color: Colors.purpleAccent, size: 16),
                            const SizedBox(width: 8),
                            Text('Set as MOD', style: GoogleFonts.inter(color: Colors.purpleAccent)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Admin',
                        child: Row(
                          children: [
                            const Icon(Icons.admin_panel_settings_outlined, color: Colors.amber, size: 16),
                            const SizedBox(width: 8),
                            Text('Set as Admin', style: GoogleFonts.inter(color: Colors.amber)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Leader',
                        child: Row(
                          children: [
                            const Icon(Icons.star_outline_rounded, color: AppTheme.primaryAccent, size: 16),
                            const SizedBox(width: 8),
                            Text('Set as Leader', style: GoogleFonts.inter(color: AppTheme.primaryAccent)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Remove',
                    onPressed: () {
                      setState(() {
                        _selectedMembers.removeWhere((m) => m.userId == member.userId);
                        _memberRoles.remove(member.userId);
                      });
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final formatTime = (TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
                'Create Band',
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
                              if (_selectedGenres.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(right: 6),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${_selectedGenres.length}',
                                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                                  ),
                                ),
                              const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_selectedGenres.isEmpty)
                        Text(
                          'Tap to select Genres/Band Types',
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textMuted, fontStyle: FontStyle.italic),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _selectedGenres.map((genre) {
                            return InputChip(
                              label: Text(genre),
                              selected: false,
                              onDeleted: () => setState(() => _selectedGenres.remove(genre)),
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
                                  formatTime(_startTime),
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
                                  formatTime(_endTime),
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
                  onTap: () => showWhatIsMapViewDialog(
                  context,
                  description:
                      'Explore Map View to discover audio snippets from gigs, rehearsals, recordings and gig promos, as well as requests for band members, subs and paid gigs.',
                ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F0C20).withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.5), width: 1.2),
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
              const SizedBox(height: 24),

              // Band Members Section
              _buildBandMembersSection(),
              const SizedBox(height: 30),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : AnimatedTapDetector(
                      onTap: _saveBand,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Save Band',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _SelectBandMemberDialog extends StatefulWidget {
  final List<UserProfile> allUsers;
  final Set<String> existingUserIds;
  final Function(UserProfile) onUserSelected;

  const _SelectBandMemberDialog({
    required this.allUsers,
    required this.existingUserIds,
    required this.onUserSelected,
  });

  @override
  State<_SelectBandMemberDialog> createState() => _SelectBandMemberDialogState();
}

class _SelectBandMemberDialogState extends State<_SelectBandMemberDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late final Set<String> _addedIds;

  @override
  void initState() {
    super.initState();
    _addedIds = Set<String>.from(widget.existingUserIds);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = widget.allUsers.where((user) {
      if (user.userId == null) return false;
      final name = (user.displayName ?? user.nickname ?? '').toLowerCase();
      final instruments = user.instruments.join(' ').toLowerCase();
      final q = _searchQuery.toLowerCase();
      return name.contains(q) || instruments.contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "Add Band Member",
              style: GoogleFonts.outfit(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white70),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          style: GoogleFonts.inter(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search name or instrument...",
            hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
            prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            fillColor: const Color(0xFF141029),
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
        ),
        const SizedBox(height: 16),
        Expanded(
          child: filteredUsers.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty ? "No users available." : "No matching users found.",
                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final name = user.displayName ?? user.nickname ?? 'Unknown';
                    final isAlreadyAdded = _addedIds.contains(user.userId);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppTheme.primaryAccent.withValues(alpha: 0.2),
                              child: Text(
                                name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  ),
                                  if (user.instruments.isNotEmpty)
                                    Text(
                                      user.instruments.join(', '),
                                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (isAlreadyAdded)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Added',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.success,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: AppTheme.primaryAccent, size: 24),
                                onPressed: () {
                                  setState(() {
                                    _addedIds.add(user.userId!);
                                  });
                                  widget.onUserSelected(user);
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

