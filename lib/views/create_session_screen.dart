import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/collab_session.dart';
import '../data/genres_taxonomy.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/searchable_category_multi_select_sheet.dart';

class _SessionDraft {
  String title;
  String sessionCategory;
  DateTime date;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String location;
  String description;

  _SessionDraft({
    required this.title,
    required this.sessionCategory,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.description = '',
  });
}

class CreateSessionScreen extends StatefulWidget {
  const CreateSessionScreen({super.key});

  @override
  State<CreateSessionScreen> createState() => _CreateSessionScreenState();
}

class _CreateSessionScreenState extends State<CreateSessionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _customReminderController = TextEditingController();

  String _sessionCategory = 'Songwriting';
  String _sessionType = 'Remote';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _isDateFlexible = false;

  List<String> _selectedGenres = [];

  // RSVP state (SESSION-01)
  bool _requireResponse = true;
  int _reminderIntervalHours = 0;
  bool _isCustomReminderHours = true;

  // Multiple Sessions state (SESSION-01)
  bool _isMultipleSessions = false;
  final List<_SessionDraft> _additionalSessions = [];

  // Session Chat state (SESSION-01)
  bool _createSessionChat = true;

  bool _isSaving = false;
  CollabSession? _existingSession;
  bool _initialized = false;

  List<String> get _availableCategories {
    if (CollabSession.standardCategories.contains(_sessionCategory)) {
      return CollabSession.standardCategories;
    }
    return [...CollabSession.standardCategories, _sessionCategory];
  }

  @override
  void initState() {
    super.initState();
    _customReminderController.text = '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is CollabSession) {
        _existingSession = args;
        _titleController.text = args.title;
        _descriptionController.text = args.description;
        _locationController.text = args.location ?? '';
        _sessionType = args.sessionType;
        _sessionCategory = args.sessionCategory;
        _isDateFlexible = args.isDateFlexible;
        _selectedGenres = List<String>.from(args.genres);
        _requireResponse = args.requireResponse;

        // RSVP legacy & preset mapping
        final existingInterval = args.reminderIntervalHours;
        if (existingInterval == 0) {
          _isCustomReminderHours = false;
          _reminderIntervalHours = 0;
          _customReminderController.text = '';
        } else if (existingInterval == 48 || existingInterval == 24 || existingInterval == 12) {
          _isCustomReminderHours = false;
          _reminderIntervalHours = existingInterval!;
          _customReminderController.text = '';
        } else if (existingInterval != null && existingInterval > 0) {
          _isCustomReminderHours = true;
          _reminderIntervalHours = existingInterval;
          _customReminderController.text = '$existingInterval';
        } else {
          _isCustomReminderHours = false;
          _reminderIntervalHours = 48;
          _customReminderController.text = '';
        }

        if (args.startDateTime != null) {
          final dt = DateTime.tryParse(args.startDateTime!)?.toLocal();
          if (dt != null) {
            _selectedDate = DateTime(dt.year, dt.month, dt.day);
            _startTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
          }
        }
        if (args.endDateTime != null) {
          final endDt = DateTime.tryParse(args.endDateTime!)?.toLocal();
          if (endDt != null) {
            _endTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
          }
        }
      } else if (args is String && args == 'Jam') {
        _sessionCategory = 'Jam';
      }
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _customReminderController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _isDateFlexible = false;
      });
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
        _isDateFlexible = false;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
        _isDateFlexible = false;
      });
    }
  }

  Future<void> _openSessionTypePicker() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Session Type',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                ...CollabSession.standardTypes.map((type) {
                  final isSelected = _sessionType == type;
                  return ListTile(
                    title: Text(
                      type,
                      style: GoogleFonts.inter(
                        color: isSelected ? AppTheme.primaryAccent : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: AppTheme.primaryAccent)
                        : null,
                    onTap: () => Navigator.pop(ctx, type),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _sessionType = result;
      });
    }
  }

  Future<void> _openGenrePicker() async {
    final result = await SearchableCategoryMultiSelectSheet.show(
      context: context,
      title: 'Genres/Band Types',
      categoryMap: GenresTaxonomy.createSessionCategoryMap,
      initialSelected: _selectedGenres,
    );
    if (result != null) {
      setState(() {
        _selectedGenres = result;
      });
    }
  }

  void _showAddSessionDraftDialog() {
    String draftTitle = '';
    String draftCategory = _sessionCategory;
    DateTime draftDate = _selectedDate.add(Duration(days: _additionalSessions.length + 1));
    TimeOfDay draftStart = _startTime;
    TimeOfDay draftEnd = _endTime;
    String draftLocation = _locationController.text.trim();
    String draftDescription = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final draftAvailableCategories = CollabSession.standardCategories.contains(draftCategory)
                ? CollabSession.standardCategories
                : [...CollabSession.standardCategories, draftCategory];

            return AlertDialog(
              backgroundColor: AppTheme.cardBackground,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Text(
                'Add Session',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Session Title (optional)',
                        hintText: 'e.g. Day 2 Writing Session',
                      ),
                      onChanged: (val) => draftTitle = val,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: draftCategory,
                      dropdownColor: AppTheme.cardBackground,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Session Category'),
                      items: draftAvailableCategories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => draftCategory = val);
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Date: ${DateFormat('yyyy-MM-dd').format(draftDate)}', style: GoogleFonts.inter(color: Colors.white)),
                      trailing: const Icon(Icons.calendar_today, color: AppTheme.primaryAccent),
                      onTap: () async {
                        final p = await showDatePicker(
                          context: ctx,
                          initialDate: draftDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (p != null) setModalState(() => draftDate = p);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Start: ${draftStart.format(ctx)}', style: GoogleFonts.inter(color: Colors.white)),
                      trailing: const Icon(Icons.access_time, color: AppTheme.primaryAccent),
                      onTap: () async {
                        final p = await showTimePicker(context: ctx, initialTime: draftStart);
                        if (p != null) setModalState(() => draftStart = p);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('End: ${draftEnd.format(ctx)}', style: GoogleFonts.inter(color: Colors.white)),
                      trailing: const Icon(Icons.access_time, color: AppTheme.primaryAccent),
                      onTap: () async {
                        final p = await showTimePicker(context: ctx, initialTime: draftEnd);
                        if (p != null) setModalState(() => draftEnd = p);
                      },
                    ),
                    if (_sessionType != 'Remote') ...[
                      TextField(
                        controller: TextEditingController(text: draftLocation),
                        style: GoogleFonts.inter(color: Colors.white),
                        decoration: const InputDecoration(labelText: 'Location'),
                        onChanged: (val) => draftLocation = val,
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.inter(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                  onPressed: () {
                    final finalTitle = draftTitle.trim().isNotEmpty
                        ? draftTitle.trim()
                        : '${_titleController.text.trim()} (Part ${_additionalSessions.length + 2})';
                    setState(() {
                      _additionalSessions.add(_SessionDraft(
                        title: finalTitle,
                        sessionCategory: draftCategory,
                        date: draftDate,
                        startTime: draftStart,
                        endTime: draftEnd,
                        location: draftLocation.trim(),
                        description: draftDescription.trim(),
                      ));
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text('Add', style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _saveSession() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isCustomReminderHours) {
      final customText = _customReminderController.text.trim();
      final parsed = int.tryParse(customText);
      if (parsed == null || parsed <= 0) {
        return;
      }
      _reminderIntervalHours = parsed;
    }

    final startMinutes = _startTime.hour * 60 + _startTime.minute;
    final endMinutes = _endTime.hour * 60 + _endTime.minute;
    if (!_isMultipleSessions && endMinutes <= startMinutes) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End time must be after start time'),
          backgroundColor: AppTheme.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;

    if (userId == null) {
      setState(() => _isSaving = false);
      return;
    }

    if (_existingSession != null && _existingSession!.creatorId != userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unauthorized: You do not own this session'), backgroundColor: AppTheme.danger),
      );
      setState(() => _isSaving = false);
      return;
    }

    final startDt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );
    final endDt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );
    final startIso = startDt.toUtc().toIso8601String();
    final endIso = endDt.toUtc().toIso8601String();

    final publishedAt = DateTime.now().millisecondsSinceEpoch;
    final int? rsvpDeadline = (_requireResponse && _reminderIntervalHours > 0)
        ? publishedAt + (_reminderIntervalHours * 3600 * 1000)
        : null;

    try {
      if (_isMultipleSessions && _additionalSessions.isNotEmpty) {
        // Multi-Session Group Creation
        final allSessions = <CollabSession>[];

        final primarySession = CollabSession(
          id: _existingSession?.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          sessionType: _sessionType,
          sessionCategory: _sessionCategory,
          isDateFlexible: false,
          startDateTime: startIso,
          endDateTime: endIso,
          location: _sessionType == 'Remote' ? null : _locationController.text.trim(),
          genres: _selectedGenres,
          lookingForRoles: _existingSession?.lookingForRoles ?? [],
          lookingForInstruments: _existingSession?.lookingForInstruments ?? [],
          creatorId: _existingSession?.creatorId ?? userId,
          createdAt: _existingSession?.createdAt ?? publishedAt,
          updatedAt: publishedAt,
          status: _existingSession?.status ?? 'active',
          requireResponse: _requireResponse,
          rsvpDeadline: rsvpDeadline,
          reminderIntervalHours: _reminderIntervalHours,
          responses: _existingSession?.responses ?? {},
          sessionChatId: _existingSession?.sessionChatId,
        );
        allSessions.add(primarySession);

        for (int i = 0; i < _additionalSessions.length; i++) {
          final draft = _additionalSessions[i];
          final draftStartDt = DateTime(
            draft.date.year,
            draft.date.month,
            draft.date.day,
            draft.startTime.hour,
            draft.startTime.minute,
          );
          final draftEndDt = DateTime(
            draft.date.year,
            draft.date.month,
            draft.date.day,
            draft.endTime.hour,
            draft.endTime.minute,
          );

          allSessions.add(CollabSession(
            title: draft.title,
            description: draft.description.isNotEmpty ? draft.description : _descriptionController.text.trim(),
            sessionType: _sessionType,
            sessionCategory: draft.sessionCategory,
            isDateFlexible: false,
            startDateTime: draftStartDt.toUtc().toIso8601String(),
            endDateTime: draftEndDt.toUtc().toIso8601String(),
            location: _sessionType == 'Remote' ? null : (draft.location.isNotEmpty ? draft.location : _locationController.text.trim()),
            genres: _selectedGenres,
            lookingForRoles: [],
            lookingForInstruments: [],
            creatorId: userId,
            createdAt: publishedAt,
            updatedAt: publishedAt,
            status: 'active',
            requireResponse: _requireResponse,
            rsvpDeadline: rsvpDeadline,
            reminderIntervalHours: _reminderIntervalHours,
          ));
        }

        final createdIds = await appState.firebaseService.createCollabSessionGroupAsync(allSessions);

        if (_createSessionChat && createdIds.isNotEmpty && _existingSession?.sessionChatId == null) {
          try {
            await appState.firebaseService.createSessionChatRoomAsync(
              sessionId: createdIds.first,
              sessionTitle: _titleController.text.trim(),
              createdBy: userId,
            );
          } catch (e) {
            debugPrint('Error creating session chat room: $e');
          }
        }
      } else {
        // Single Session Creation / Update
        final session = CollabSession(
          id: _existingSession?.id,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          sessionType: _sessionType,
          sessionCategory: _sessionCategory,
          isDateFlexible: _existingSession != null ? _isDateFlexible : false,
          startDateTime: startIso,
          endDateTime: endIso,
          location: _sessionType == 'Remote' ? null : _locationController.text.trim(),
          genres: _selectedGenres,
          lookingForRoles: _existingSession?.lookingForRoles ?? [],
          lookingForInstruments: _existingSession?.lookingForInstruments ?? [],
          creatorId: _existingSession?.creatorId ?? userId,
          createdAt: _existingSession?.createdAt ?? publishedAt,
          updatedAt: publishedAt,
          status: _existingSession?.status ?? 'active',
          requireResponse: _requireResponse,
          rsvpDeadline: rsvpDeadline,
          reminderIntervalHours: _reminderIntervalHours,
          responses: _existingSession?.responses ?? {},
          parentSessionId: _existingSession?.parentSessionId,
          subSessionSequence: _existingSession?.subSessionSequence,
          sessionChatId: _existingSession?.sessionChatId,
        );

        if (_existingSession == null) {
          final newId = await appState.firebaseService.createCollabSessionAsync(session);
          if (_createSessionChat) {
            try {
              await appState.firebaseService.createSessionChatRoomAsync(
                sessionId: newId,
                sessionTitle: _titleController.text.trim(),
                createdBy: userId,
              );
            } catch (e) {
              debugPrint('Error creating session chat room: $e');
            }
          }
        } else {
          await appState.firebaseService.updateCollabSessionAsync(_existingSession!.id!, session);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session saved successfully!'), backgroundColor: AppTheme.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save session: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = _existingSession != null;

    return GradientScaffold(
      appBar: CustomTopBar(
        title: isEditMode ? 'Edit Session' : 'Create Session',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          physics: const BouncingScrollPhysics(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Heading
                Text(
                  isEditMode ? 'EDIT SESSION' : 'CREATE SESSION',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 20),

                // 2. Session Title
                TextFormField(
                  controller: _titleController,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Session Title',
                    hintText: 'e.g. Pop Songwriting Session in Stockholm',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a title';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 3. Session Category (Above Description!)
                DropdownButtonFormField<String>(
                  value: _sessionCategory,
                  dropdownColor: const Color(0xFF16132D),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Session Category',
                  ),
                  items: _availableCategories.map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() => _sessionCategory = val);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // 4. Session Description
                TextFormField(
                  controller: _descriptionController,
                  maxLines: 3,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: const InputDecoration(
                    labelText: 'Session Description',
                    hintText: 'Explain the goal of the session, what you plan to create, and any requirements...',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a description';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 5. Session Type (Tappable Field)
                InkWell(
                  onTap: _openSessionTypePicker,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Session Type',
                      suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.white70),
                    ),
                    child: Text(
                      _sessionType,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 6. Location (Only for In person or Hybrid)
                if (_sessionType != 'Remote') ...[
                  TextFormField(
                    controller: _locationController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    decoration: const InputDecoration(
                      labelText: 'Location',
                      hintText: 'e.g. Sound Studio 3, Stockholm',
                      prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.textSecondary),
                    ),
                    validator: (value) {
                      if (_sessionType != 'Remote' && (value == null || value.trim().isEmpty)) {
                        return 'Please enter location';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // 7. Genres/Band Types (Tappable Field)
                InkWell(
                  onTap: _openGenrePicker,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Genres/Band Types',
                      suffixIcon: Icon(Icons.arrow_drop_down, color: Colors.white70),
                    ),
                    child: Text(
                      _selectedGenres.isEmpty ? 'Tap to select genres' : _selectedGenres.join(', '),
                      style: GoogleFonts.inter(
                        color: _selectedGenres.isEmpty ? AppTheme.textSecondary : Colors.white,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 8. Date & Time
                if (!_isMultipleSessions) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Date & Time',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Date Trigger
                        GestureDetector(
                          onTap: _selectDate,
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Date', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat('EEEE, MMM d, yyyy').format(_selectedDate),
                                      style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
                            ],
                          ),
                        ),
                        const Divider(height: 24, color: Color(0xFF2E2A4E)),

                        // Start Time Trigger
                        GestureDetector(
                          onTap: _selectStartTime,
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: AppTheme.textSecondary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Start Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _startTime.format(context),
                                      style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
                            ],
                          ),
                        ),
                        const Divider(height: 24, color: Color(0xFF2E2A4E)),

                        // End Time Trigger
                        GestureDetector(
                          onTap: _selectEndTime,
                          child: Row(
                            children: [
                              const Icon(Icons.access_time, color: AppTheme.textSecondary, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('End Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                    const SizedBox(height: 2),
                                    Text(
                                      _endTime.format(context),
                                      style: GoogleFonts.inter(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 9. Create Multiple Sessions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isMultipleSessions ? AppTheme.primaryAccent.withValues(alpha: 0.5) : const Color(0xFF2E2A4E),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.style_rounded, color: AppTheme.primaryAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Create Multiple Sessions',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Example: 1 songwriting session and 2 recording days, workshops, jams, etc',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _isMultipleSessions,
                            activeColor: AppTheme.primaryAccent,
                            onChanged: (val) {
                              setState(() {
                                _isMultipleSessions = val;
                              });
                            },
                          ),
                        ],
                      ),
                      if (_isMultipleSessions) ...[
                        const SizedBox(height: 16),
                        if (_additionalSessions.isNotEmpty) ...[
                          Text(
                            'Additional Sessions (${_additionalSessions.length}):',
                            style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          ..._additionalSessions.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final draft = entry.value;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E1A3A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(draft.title, style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                        Text(
                                          '${draft.sessionCategory} • ${DateFormat('MMM d').format(draft.date)} (${draft.startTime.format(context)} - ${draft.endTime.format(context)})',
                                          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _additionalSessions.removeAt(idx);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 8),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppTheme.primaryAccent),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            icon: const Icon(Icons.add, color: AppTheme.primaryAccent, size: 18),
                            label: Text(
                              '+ Add Session(s)',
                              style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                            ),
                            onPressed: _showAddSessionDraftDialog,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 10. RSVP
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RSVP',
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.primaryAccent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'The response window sets how much time accepted participants have to respond to session invitations.',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: Colors.white70,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Response Time Settings:',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<int>(
                        value: _isCustomReminderHours ? -1 : _reminderIntervalHours,
                        dropdownColor: const Color(0xFF16132D),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: -1, child: Text('Set your own')),
                          DropdownMenuItem(value: 48, child: Text('48 hours (From session is published)')),
                          DropdownMenuItem(value: 24, child: Text('24 hours (From session is published)')),
                          DropdownMenuItem(value: 12, child: Text('12 hours (From session is published)')),
                          DropdownMenuItem(value: 0, child: Text('No automatic Reminders')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              if (val == -1) {
                                _isCustomReminderHours = true;
                              } else {
                                _isCustomReminderHours = false;
                                _reminderIntervalHours = val;
                              }
                            });
                          }
                        },
                      ),
                      if (_isCustomReminderHours) ...[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _customReminderController,
                          keyboardType: TextInputType.number,
                          style: GoogleFonts.inter(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Set hours here',
                            hintText: 'e.g. 48, 24, 12',
                            prefixIcon: Icon(Icons.timer_outlined, color: AppTheme.textSecondary),
                            suffixText: 'hours',
                            suffixStyle: GoogleFonts.inter(color: AppTheme.textSecondary),
                          ),
                          validator: (value) {
                            if (_isCustomReminderHours) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter response window in hours';
                              }
                              final parsed = int.tryParse(value.trim());
                              if (parsed == null || parsed <= 0) {
                                return 'Please enter a valid positive number';
                              }
                            }
                            return null;
                          },
                          onChanged: (val) {
                            final parsed = int.tryParse(val.trim());
                            if (parsed != null && parsed > 0) {
                              setState(() {
                                _reminderIntervalHours = parsed;
                              });
                            }
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Initial response window will be ${_reminderIntervalHours} hours from when session is published.',
                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryAccent),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 11. Create Session Chat
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.forum_outlined, color: AppTheme.primaryAccent, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Create Session Chat',
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Creates a dedicated temporary chat room for accepted session participants',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _createSessionChat,
                        activeColor: AppTheme.primaryAccent,
                        onChanged: (val) {
                          setState(() {
                            _createSessionChat = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 12. Save / Submit Button
                _isSaving
                    ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                    : AnimatedTapDetector(
                        onTap: _saveSession,
                        child: Container(
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Text(
                              isEditMode ? 'Save Changes' : 'Create Session',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
