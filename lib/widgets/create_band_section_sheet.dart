import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/band_section_utils.dart';
import 'animated_tap_detector.dart';

class CreateBandSectionSheet extends StatefulWidget {
  final String? initialBandId;
  final String? initialInstrument;
  final String? initialMemberId;

  const CreateBandSectionSheet({
    super.key,
    this.initialBandId,
    this.initialInstrument,
    this.initialMemberId,
  });

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    String? initialBandId,
    String? initialInstrument,
    String? initialMemberId,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: CreateBandSectionSheet(
          initialBandId: initialBandId,
          initialInstrument: initialInstrument,
          initialMemberId: initialMemberId,
        ),
      ),
    );
  }

  @override
  State<CreateBandSectionSheet> createState() => _CreateBandSectionSheetState();
}

class _CreateBandSectionSheetState extends State<CreateBandSectionSheet> {
  bool _isLoadingBands = true;
  bool _isLoadingMembers = false;
  bool _isSubmitting = false;

  Map<String, String> _userBands = {};
  String? _selectedBandId;

  List<BandMember> _bandMembers = [];
  Map<String, UserProfile> _memberProfiles = {};
  List<BandSectionSuggestion> _suggestions = [];

  BandSectionSuggestion? _selectedSuggestion;
  bool _isCustomMode = false;

  final Set<String> _selectedMemberIds = {};
  final TextEditingController _groupNameController = TextEditingController();
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBands();
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    super.dispose();
  }

  Future<void> _loadBands() async {
    setState(() => _isLoadingBands = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    if (selfId == null) {
      setState(() => _isLoadingBands = false);
      return;
    }

    try {
      final bands = await appState.firebaseService.getUserBandsAsync(selfId);
      if (mounted) {
        setState(() {
          _userBands = bands;
          _isLoadingBands = false;

          if (widget.initialBandId != null && bands.containsKey(widget.initialBandId)) {
            _selectedBandId = widget.initialBandId;
          } else if (bands.length == 1) {
            _selectedBandId = bands.keys.first;
          }
        });

        if (_selectedBandId != null) {
          _loadBandMembers(_selectedBandId!);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingBands = false;
          _errorMessage = 'Failed to load bands: $e';
        });
      }
    }
  }

  Future<void> _loadBandMembers(String bandId) async {
    setState(() {
      _isLoadingMembers = true;
      _errorMessage = null;
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;

    try {
      final members = await appState.firebaseService.getBandMembersAsync(bandId);
      final Map<String, UserProfile> profiles = {};

      for (final m in members) {
        final uid = m.userId;
        if (uid != null && uid.isNotEmpty) {
          final p = await appState.firebaseService.getUserProfileAsync(uid);
          if (p != null) profiles[uid] = p;
        }
      }

      final suggestions = BandSectionUtils.generateSectionSuggestions(
        members: members,
        userProfiles: profiles,
      );

      if (mounted) {
        setState(() {
          _bandMembers = members;
          _memberProfiles = profiles;
          _suggestions = suggestions;
          _isLoadingMembers = false;

          _selectedMemberIds.clear();
          if (selfId != null) _selectedMemberIds.add(selfId);

          if (widget.initialInstrument != null && widget.initialInstrument!.isNotEmpty) {
            final key = BandSectionUtils.normalizeInstrumentKey(widget.initialInstrument!);
            final match = suggestions.cast<BandSectionSuggestion?>().firstWhere(
                  (s) => s?.sectionKey == key,
                  orElse: () => null,
                );
            if (match != null) {
              _applySuggestion(match);
            } else {
              _isCustomMode = true;
              _groupNameController.text = '${widget.initialInstrument} Section';
              if (widget.initialMemberId != null) {
                _selectedMemberIds.add(widget.initialMemberId!);
              }
            }
          } else if (widget.initialMemberId != null) {
            _isCustomMode = true;
            _selectedMemberIds.add(widget.initialMemberId!);
            _groupNameController.text = 'Custom Section';
          } else if (suggestions.isNotEmpty) {
            _applySuggestion(suggestions.first);
          } else {
            _isCustomMode = true;
            _groupNameController.text = 'Band Section';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingMembers = false;
          _errorMessage = 'Failed to load band members: $e';
        });
      }
    }
  }

  void _applySuggestion(BandSectionSuggestion suggestion) {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;

    _selectedSuggestion = suggestion;
    _isCustomMode = false;
    _selectedMemberIds.clear();
    if (selfId != null) _selectedMemberIds.add(selfId);
    _selectedMemberIds.addAll(suggestion.memberUserIds);
    _groupNameController.text = '${suggestion.sectionName} Section';
  }

  Future<void> _handleCreateGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      setState(() => _errorMessage = 'Please enter a group name.');
      return;
    }
    if (groupName.length > 80) {
      setState(() => _errorMessage = 'Group name must be 80 characters or fewer.');
      return;
    }
    if (_selectedMemberIds.length < 2) {
      setState(() => _errorMessage = 'Please select at least 2 members for the group.');
      return;
    }
    if (_selectedBandId == null) {
      setState(() => _errorMessage = 'Please select a band.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final appState = Provider.of<AppState>(context, listen: false);

    try {
      final convId = await appState.firebaseService.createBandSectionConversationAsync(
        bandId: _selectedBandId!,
        groupName: groupName,
        participantIds: _selectedMemberIds.toList(),
        sectionKey: _isCustomMode ? null : _selectedSuggestion?.sectionKey,
        sourceInstrument: _isCustomMode ? null : _selectedSuggestion?.sectionName,
      );

      if (mounted) {
        Navigator.pop(context, {
          'conversationId': convId,
          'bandId': _selectedBandId,
          'groupName': groupName,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorMessage = 'Failed to create group: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selfId = appState.currentUserId;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF16132D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: Color(0xFF2E2452), width: 1.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: _isLoadingBands
            ? const SizedBox(
                height: 250,
                child: Center(
                  child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                ),
              )
            : _userBands.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.info_outline, color: Colors.amber, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'No Bands Found',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You must be a member of at least one band to create a section group chat.',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header & Handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(top: 12, bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'NEW SECTION GROUP',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 1.0,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white70),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Color(0xFF2E2452), height: 1),

                      // Content
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Band Picker if multiple bands
                              if (_userBands.length > 1) ...[
                                Text(
                                  'Select Band',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF2E2452)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedBandId,
                                      isExpanded: true,
                                      dropdownColor: const Color(0xFF1F1A3F),
                                      items: _userBands.entries.map((e) {
                                        return DropdownMenuItem(
                                          value: e.key,
                                          child: Text(
                                            e.value,
                                            style: GoogleFonts.inter(color: Colors.white),
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (newBandId) {
                                        if (newBandId != null && newBandId != _selectedBandId) {
                                          setState(() => _selectedBandId = newBandId);
                                          _loadBandMembers(newBandId);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],

                              if (_isLoadingMembers)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24.0),
                                    child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                                  ),
                                )
                              else ...[
                                // Section suggestions
                                Text(
                                  'Section Choice',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ..._suggestions.map((s) {
                                      final isSelected = !_isCustomMode && _selectedSuggestion?.sectionKey == s.sectionKey;
                                      return Semantics(
                                        button: true,
                                        label: 'Suggested section: ${s.sectionName}, ${s.memberCount} members',
                                        child: FocusableActionDetector(
                                          mouseCursor: SystemMouseCursors.click,
                                          shortcuts: {
                                            LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
                                            LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
                                          },
                                          actions: {
                                            ActivateIntent: CallbackAction<ActivateIntent>(
                                              onInvoke: (_) => setState(() => _applySuggestion(s)),
                                            ),
                                          },
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(10),
                                            onTap: () => setState(() => _applySuggestion(s)),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected ? AppTheme.primaryAccent : const Color(0xFF231F45),
                                                borderRadius: BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isSelected ? AppTheme.primaryAccent : const Color(0xFF3B336B),
                                                ),
                                              ),
                                              child: Text(
                                                '${s.sectionName} (${s.memberCount})',
                                                style: GoogleFonts.inter(
                                                  fontSize: 13,
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                                  color: isSelected ? Colors.white : Colors.white70,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                    Semantics(
                                      button: true,
                                      label: 'Custom group',
                                      child: FocusableActionDetector(
                                        mouseCursor: SystemMouseCursors.click,
                                        shortcuts: {
                                          LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
                                          LogicalKeySet(LogicalKeyboardKey.space): const ActivateIntent(),
                                        },
                                        actions: {
                                          ActivateIntent: CallbackAction<ActivateIntent>(
                                            onInvoke: (_) => setState(() {
                                              _isCustomMode = true;
                                              _selectedSuggestion = null;
                                              if (_groupNameController.text.isEmpty ||
                                                  _suggestions.any((s) => _groupNameController.text == '${s.sectionName} Section')) {
                                                _groupNameController.text = 'Custom Group';
                                              }
                                            }),
                                          ),
                                        },
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(10),
                                          onTap: () => setState(() {
                                            _isCustomMode = true;
                                            _selectedSuggestion = null;
                                            if (_groupNameController.text.isEmpty ||
                                                _suggestions.any((s) => _groupNameController.text == '${s.sectionName} Section')) {
                                              _groupNameController.text = 'Custom Group';
                                            }
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: _isCustomMode ? AppTheme.primaryAccent : const Color(0xFF231F45),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: _isCustomMode ? AppTheme.primaryAccent : const Color(0xFF3B336B),
                                              ),
                                            ),
                                            child: Text(
                                              'Custom group',
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                fontWeight: _isCustomMode ? FontWeight.bold : FontWeight.w500,
                                                color: _isCustomMode ? Colors.white : Colors.white70,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Suggested from profile skills. Review the members before creating the group.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Group Name Input
                                Text(
                                  'Group Name',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: _groupNameController,
                                  maxLength: 80,
                                  style: GoogleFonts.inter(color: Colors.white),
                                  decoration: InputDecoration(
                                    hintText: 'e.g. Trumpet Section',
                                    hintStyle: GoogleFonts.inter(color: AppTheme.textMuted),
                                    filled: true,
                                    fillColor: AppTheme.cardBackground,
                                    counterStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 10),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFF2E2452)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: Color(0xFF2E2452)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: const BorderSide(color: AppTheme.primaryAccent),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Member Review List
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Review Members (${_selectedMemberIds.length})',
                                      style: GoogleFonts.outfit(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'Min 2 required',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBackground,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: const Color(0xFF2E2452)),
                                  ),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: _bandMembers.length,
                                    separatorBuilder: (_, __) => const Divider(color: Color(0xFF2E2452), height: 1),
                                    itemBuilder: (context, idx) {
                                      final member = _bandMembers[idx];
                                      final uid = member.userId ?? '';
                                      final isMe = uid == selfId;
                                      final isSelected = _selectedMemberIds.contains(uid);
                                      final profile = _memberProfiles[uid];
                                      final name = profile?.displayName ?? profile?.nickname ?? member.nickname ?? 'Musician';
                                      final inst = BandSectionUtils.resolveEffectiveInstrument(profile) ?? 'Musician';

                                      return CheckboxListTile(
                                        value: isSelected,
                                        activeColor: AppTheme.primaryAccent,
                                        checkColor: Colors.white,
                                        title: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                isMe ? '$name (You)' : name,
                                                style: GoogleFonts.inter(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF231F45),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                inst,
                                                style: GoogleFonts.inter(
                                                  fontSize: 10,
                                                  color: AppTheme.textSecondary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onChanged: isMe
                                            ? null // Creator is always included
                                            : (checked) {
                                                setState(() {
                                                  if (checked == true) {
                                                    _selectedMemberIds.add(uid);
                                                  } else {
                                                    _selectedMemberIds.remove(uid);
                                                  }
                                                });
                                              },
                                      );
                                    },
                                  ),
                                ),
                              ],

                              if (_errorMessage != null) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _errorMessage!,
                                          style: GoogleFonts.inter(color: Colors.redAccent, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 20),

                              // Confirm Button
                              AnimatedTapDetector(
                                onTap: _isSubmitting || _isLoadingMembers ? () {} : _handleCreateGroup,
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: AppTheme.primaryGradient,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: _isSubmitting
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            'Create Group Chat',
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
