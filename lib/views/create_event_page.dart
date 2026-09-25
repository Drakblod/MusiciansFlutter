import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band_event.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class CreateEventPage extends StatefulWidget {
  final String bandId;
  final BandEvent? existingEvent;
  final List<BandEvent>? existingGroupEvents;

  const CreateEventPage({
    super.key,
    required this.bandId,
    this.existingEvent,
    this.existingGroupEvents,
  });

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();
  final _customReminderController = TextEditingController();

  String _eventType = 'Event';
  String? _existingEventId;
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  DateTime _endDate = DateTime.now().add(const Duration(days: 1));
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _requireResponse = true;
  bool _createEventRoom = true;
  int _reminderIntervalHours = 48;
  bool _isCustomReminderHours = false;
  bool _isSaving = false;
  bool _isLoadingRole = true;

  // Attached Rehearsals
  List<EventRehearsal> _rehearsals = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().add(const Duration(days: 1));
    _startDate = DateTime(now.year, now.month, now.day);
    _endDate = DateTime(now.year, now.month, now.day);
    _customReminderController.text = '';
    _initFromExisting();
    _checkPermission();
  }

  void _initFromExisting() {
    final existing = widget.existingEvent ??
        (widget.existingGroupEvents != null && widget.existingGroupEvents!.isNotEmpty
            ? widget.existingGroupEvents!.first
            : null);

    if (existing != null) {
      _existingEventId = existing.id;
      _titleController.text = existing.title;
      _descriptionController.text = existing.description;
      _locationController.text = existing.location;
      _notesController.text = existing.additionalNotes;
      _eventType = existing.eventType;
      _requireResponse = existing.requireResponse;
      _rehearsals = List<EventRehearsal>.from(existing.rehearsals);

      // Existing event RSVP compatibility
      final existingInterval = existing.reminderIntervalHours;
      if (existingInterval == 0) {
        // Explicit 0 means No automatic Reminders
        _isCustomReminderHours = false;
        _reminderIntervalHours = 0;
        _customReminderController.text = '';
      } else if (existingInterval == 48 || existingInterval == 24 || existingInterval == 12) {
        _isCustomReminderHours = false;
        _reminderIntervalHours = existingInterval!;
        _customReminderController.text = '';
      } else if (existingInterval != null && existingInterval > 0) {
        // Other positive integer (e.g. 36) -> Custom mode
        _isCustomReminderHours = true;
        _reminderIntervalHours = existingInterval;
        _customReminderController.text = '$existingInterval';
      } else {
        // null or missing key -> Verified historical default fallback (48 hours)
        _isCustomReminderHours = false;
        _reminderIntervalHours = 48;
        _customReminderController.text = '';
      }

      final startLocal = DateTime.tryParse(existing.startDateTime)?.toLocal() ?? DateTime.now();
      final endLocal = DateTime.tryParse(existing.endDateTime)?.toLocal() ?? startLocal;

      _startDate = DateTime(startLocal.year, startLocal.month, startLocal.day);
      _endDate = DateTime(endLocal.year, endLocal.month, endLocal.day);
      _selectedDate = _startDate;
      _startTime = TimeOfDay(hour: startLocal.hour, minute: startLocal.minute);
      _endTime = TimeOfDay(hour: endLocal.hour, minute: endLocal.minute);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _customReminderController.dispose();
    super.dispose();
  }

  void _checkPermission() async {
    final appState = Provider.of<AppState>(context, listen: false);
    final userId = appState.currentUserId;
    if (userId == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    try {
      final role = await appState.firebaseService.getUserBandRoleAsync(widget.bandId, userId);
      final r = (role ?? '').trim().toLowerCase();
      final isAuthorized = r == 'leader' || r == 'admin' || r == 'mod';
      if (mounted) {
        if (!isAuthorized) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access Denied: Only band Leaders, Admins, and MODs can create events.'),
              backgroundColor: AppTheme.danger,
            ),
          );
          Navigator.pop(context);
        } else {
          setState(() {
            _isLoadingRole = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Error checking permission: $e");
      if (mounted) {
        setState(() {
          _isLoadingRole = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission check failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  Future<void> _selectStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF16132D),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0C20),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
        _selectedDate = picked;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: Color(0xFF16132D),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0C20),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endDate = picked;
        if (_startDate.isAfter(_endDate)) {
          _startDate = _endDate;
          _selectedDate = _endDate;
        }
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: const Color(0xFF16132D),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0C20),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: const Color(0xFF16132D),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0C20),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }

  Future<void> _selectEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: const Color(0xFF16132D),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0C20),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _endTime = picked;
      });
    }
  }

  TimeOfDay _parseTimeOfDay(String timeStr, TimeOfDay defaultTime) {
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }
    } catch (_) {}
    return defaultTime;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  IconData _getSessionTypeIcon(String type) {
    if (type == 'Club gig') return Icons.nightlife_rounded;
    if (type == 'Concert') return Icons.stadium_rounded;
    if (type == 'Show') return Icons.theater_comedy_rounded;
    if (type == 'Tour') return Icons.flight_takeoff_rounded;
    if (type == 'Festival') return Icons.festival_rounded;
    if (type == 'Private Event') return Icons.celebration_rounded;
    if (type == 'Other') return Icons.more_horiz_rounded;
    return Icons.music_note_rounded;
  }

  void _showRehearsalDialog({int? editIndex}) {
    final isEditing = editIndex != null;
    final rehearsalToEdit = isEditing ? _rehearsals[editIndex] : null;

    DateTime draftDate;
    if (isEditing) {
      draftDate = DateTime.tryParse(rehearsalToEdit!.date) ?? _selectedDate;
    } else if (_rehearsals.isNotEmpty) {
      final lastDate = DateTime.tryParse(_rehearsals.last.date);
      draftDate = lastDate != null ? lastDate.add(const Duration(days: 1)) : _selectedDate;
    } else {
      draftDate = _selectedDate;
    }

    TimeOfDay draftStart = isEditing
        ? _parseTimeOfDay(rehearsalToEdit!.startTime, _startTime)
        : _startTime;
    TimeOfDay draftEnd = isEditing
        ? _parseTimeOfDay(rehearsalToEdit!.endTime, _endTime)
        : _endTime;

    String draftType = isEditing ? rehearsalToEdit!.type : 'Rehearsal';

    final draftTitleController = TextEditingController(
      text: isEditing ? rehearsalToEdit!.title : '',
    );
    final draftLocationController = TextEditingController(
      text: isEditing
          ? rehearsalToEdit!.location
          : _locationController.text.trim(),
    );
    final draftDescriptionController = TextEditingController(
      text: isEditing ? rehearsalToEdit!.description : '',
    );

    final availableTypes = EventRehearsal.standardSessionTypes.contains(draftType)
        ? EventRehearsal.standardSessionTypes
        : [draftType, ...EventRehearsal.standardSessionTypes];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0C20),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isEditing ? "Edit Event" : "Add Event",
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppTheme.textSecondary),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 1. Name of Event / Sub-Event Title (Optional)
                    TextFormField(
                      controller: draftTitleController,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Name of Event (Optional)',
                        hintText: 'e.g. Warmup Rehearsal, Stockholm Gig, Show 1',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. Event Type Dropdown (Single combined list)
                    DropdownButtonFormField<String>(
                      value: availableTypes.contains(draftType)
                          ? draftType
                          : (availableTypes.isNotEmpty ? availableTypes.first : draftType),
                      dropdownColor: const Color(0xFF16132D),
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Event Type',
                        prefixIcon: Icon(_getSessionTypeIcon(draftType), color: AppTheme.primaryAccent),
                      ),
                      items: availableTypes.map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Row(
                            children: [
                              Icon(_getSessionTypeIcon(type), color: AppTheme.primaryAccent, size: 16),
                              const SizedBox(width: 8),
                              Text(type, style: GoogleFonts.inter(color: Colors.white)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() => draftType = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Date Picker Row
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: draftDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                        );
                        if (picked != null) {
                          setModalState(() => draftDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141029),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF2E2A4E)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined, color: AppTheme.primaryAccent, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, MMM d, yyyy').format(draftDate),
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                              ),
                            ),
                            const Icon(Icons.edit, color: AppTheme.textSecondary, size: 16),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Times Row
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(context: ctx, initialTime: draftStart);
                              if (picked != null) setModalState(() => draftStart = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141029),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Start Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                  const SizedBox(height: 2),
                                  Text(draftStart.format(ctx), style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () async {
                              final picked = await showTimePicker(context: ctx, initialTime: draftEnd);
                              if (picked != null) setModalState(() => draftEnd = picked);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141029),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('End Time', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary)),
                                  const SizedBox(height: 2),
                                  Text(draftEnd.format(ctx), style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Location
                    TextFormField(
                      controller: draftLocationController,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Location (City, Country)',
                        hintText: 'e.g. Studio A, Globen',
                        prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: draftDescriptionController,
                      style: GoogleFonts.inter(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'e.g. Load-in at 16:00, Soundcheck at 17:30...',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Save / Add Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        onPressed: () {
                          final title = draftTitleController.text.trim();
                          final dateStr = DateFormat('yyyy-MM-dd').format(draftDate);
                          final startStr = _formatTimeOfDay(draftStart);
                          final endStr = _formatTimeOfDay(draftEnd);
                          final location = draftLocationController.text.trim();
                          final description = draftDescriptionController.text.trim();

                          final rehearsalId = isEditing
                              ? rehearsalToEdit!.id
                              : 'reh_${DateTime.now().millisecondsSinceEpoch}';

                          final updatedRehearsal = EventRehearsal(
                            id: rehearsalId,
                            title: title,
                            date: dateStr,
                            startTime: startStr,
                            endTime: endStr,
                            location: location,
                            description: description,
                            type: draftType,
                          );

                          setState(() {
                            if (isEditing) {
                              _rehearsals[editIndex] = updatedRehearsal;
                            } else {
                              _rehearsals.add(updatedRehearsal);
                            }
                          });

                          Navigator.pop(ctx);
                        },
                        child: Text(
                          isEditing ? "Save Changes" : "Add Event",
                          style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
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

  void _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      if (_isCustomReminderHours) {
        final customText = _customReminderController.text.trim();
        final parsed = int.tryParse(customText);
        if (parsed == null || parsed <= 0) {
          return;
        }
        _reminderIntervalHours = parsed;
      }

      final start = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        0,
        0,
        0,
      );

      final end = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      );

      final publishedAt = DateTime.now().millisecondsSinceEpoch;
      final int? rsvpDeadline = (_requireResponse && _reminderIntervalHours > 0)
          ? publishedAt + (_reminderIntervalHours * 3600 * 1000)
          : null;

      final newEvent = BandEvent(
        id: _existingEventId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        eventType: _eventType,
        location: _locationController.text.trim(),
        startDateTime: start.toIso8601String(),
        endDateTime: end.toIso8601String(),
        additionalNotes: _notesController.text.trim(),
        createdBy: appState.currentUserId ?? '',
        createdAt: _existingEventId != null ? 0 : publishedAt,
        updatedAt: publishedAt,
        requireResponse: _requireResponse,
        rsvpDeadline: rsvpDeadline,
        reminderIntervalHours: _reminderIntervalHours,
        responses: {},
        rehearsals: _rehearsals,
      );

      final eventId = await appState.firebaseService.saveBandEventAsync(widget.bandId, newEvent);

      if (_createEventRoom && (_existingEventId == null || _existingEventId!.isEmpty)) {
        final creatorId = appState.currentUserId ?? '';
        await appState.firebaseService.createTemporaryEventRoomAsync(
          bandId: widget.bandId,
          eventId: eventId,
          roomName: '${newEvent.title} Chat',
          createdBy: creatorId,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Event published successfully!"),
            backgroundColor: AppTheme.success,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint("Error saving band event: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to create event: $e"),
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

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Create Event',
        showBack: true,
      ),
      body: SafeArea(
        child: _isLoadingRole
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
            : _isSaving
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      'CREATE EVENT',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 1. Main Event Name
                    TextFormField(
                      controller: _titleController,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Main Event Name',
                        hintText: 'e.g. Club gig – Summer Tour',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an event title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2. Event Description (Describe ALL parts of Main Event here)
                    TextFormField(
                      controller: _descriptionController,
                      style: GoogleFonts.inter(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Event Description (Describe ALL parts of Main Event here)',
                        hintText: 'What is this event about?',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Location
                    TextFormField(
                      controller: _locationController,
                      style: GoogleFonts.inter(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Location (City, Country)',
                        hintText: 'e.g. Globen, Stockholm',
                        prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.textSecondary),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a location';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // 4. Date Range
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
                            'DATE RANGE',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryAccent,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Start Date picker trigger
                          GestureDetector(
                            onTap: _selectStartDate,
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Start Date',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('EEEE, MMM d, yyyy').format(_startDate),
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

                          // End Date picker trigger
                          GestureDetector(
                            onTap: _selectEndDate,
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today_outlined, color: AppTheme.textSecondary, size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'End Date',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        DateFormat('EEEE, MMM d, yyyy').format(_endDate),
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

                    // 5 & 6. Attached Events / Event Schedule Section
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded, color: AppTheme.primaryAccent, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'EVENT SCHEDULE',
                                        style: GoogleFonts.outfit(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryAccent,
                                          letterSpacing: 1.1,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (_rehearsals.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryAccent.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${_rehearsals.length} Event${_rehearsals.length == 1 ? '' : 's'}',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Attach scheduled events, rehearsals, soundchecks, gigs, or meetings.',
                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                          const SizedBox(height: 12),

                          // Name of "Main event" on top of the schedule items
                          AnimatedBuilder(
                            animation: _titleController,
                            builder: (context, _) {
                              final entered = _titleController.text.trim();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  entered.isEmpty ? '"Main Event Name"' : '"$entered"',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              );
                            },
                          ),

                          // List of attached events
                          if (_rehearsals.isNotEmpty) ...[
                            ...List.generate(_rehearsals.length, (index) {
                              final rehearsal = _rehearsals[index];
                              final parsedDate = DateTime.tryParse(rehearsal.date);
                              final dateFormatted = parsedDate != null
                                  ? DateFormat('EEEE, MMM d').format(parsedDate)
                                  : rehearsal.date;
                              final sessionType = rehearsal.type.isNotEmpty ? rehearsal.type : 'Event';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF141029),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF2E2A4E)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryAccent.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'EVENT ${index + 1}',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppTheme.primaryAccent,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (rehearsal.title.isNotEmpty) ...[
                                            Text(
                                              rehearsal.title,
                                              style: GoogleFonts.inter(
                                                fontSize: 13,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '$sessionType • $dateFormatted (${rehearsal.startTime} - ${rehearsal.endTime})',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: AppTheme.textSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ] else ...[
                                            Text(
                                              '$sessionType • $dateFormatted (${rehearsal.startTime} - ${rehearsal.endTime})',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          if (rehearsal.location.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              '@ ${rehearsal.location}',
                                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                            ),
                                          ],
                                          if (rehearsal.description.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              rehearsal.description,
                                              style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryAccent, size: 18),
                                      onPressed: () => _showRehearsalDialog(editIndex: index),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                      onPressed: () {
                                        setState(() {
                                          _rehearsals.removeAt(index);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const SizedBox(height: 8),
                          ],

                          // + Add Event Button or Limit Warning
                          if (_rehearsals.length < 6)
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.primaryAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryAccent, size: 18),
                              label: Text(
                                "+ Add Event",
                                style: GoogleFonts.inter(
                                  color: AppTheme.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              onPressed: () => _showRehearsalDialog(),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1B1838),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFF2E2A4E)),
                              ),
                              child: Center(
                                child: Text(
                                  "Maximum 6 events per Event Schedule.",
                                  style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 7. RSVP Deadlines Selector
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
                            'RSVP Deadlines',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
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
                            isExpanded: true,
                            dropdownColor: const Color(0xFF16132D),
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            decoration: const InputDecoration(
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 48, child: Text('48 hours (From event is published)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 24, child: Text('24 hours (From event is published)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 12, child: Text('12 hours (From event is published)', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: -1, child: Text('Set your own', overflow: TextOverflow.ellipsis)),
                              DropdownMenuItem(value: 0, child: Text('No automatic Reminders', overflow: TextOverflow.ellipsis)),
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
                              decoration: const InputDecoration(
                                labelText: 'Set hours here',
                                hintText: 'e.g. 48, 24, 12',
                                prefixIcon: Icon(Icons.timer_outlined, color: AppTheme.textSecondary),
                                suffixText: 'hours',
                                suffixStyle: TextStyle(color: AppTheme.textSecondary),
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
                              'Initial response window will be $_reminderIntervalHours hours from when event is published.',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryAccent),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 8. Temporary Event Chat Switch
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _createEventRoom ? AppTheme.primaryAccent.withOpacity(0.5) : const Color(0xFF2E2A4E),
                          width: 1,
                        ),
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
                                    const Icon(Icons.forum_outlined, color: AppTheme.primaryAccent, size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'Create Event Chat',
                                        style: GoogleFonts.inter(
                                          fontSize: 15,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Create a temporary chat room for attending members & approved subs.',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _createEventRoom,
                            activeColor: AppTheme.primaryAccent,
                            onChanged: (val) {
                              setState(() {
                                _createEventRoom = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // 9. Save Button
                    AnimatedTapDetector(
                      onTap: _saveEvent,
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            "Publish Event",
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }
}
