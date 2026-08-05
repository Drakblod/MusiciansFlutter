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

class _EventDraft {
  String title;
  String eventType;
  DateTime date;
  TimeOfDay startTime;
  TimeOfDay endTime;
  String location;
  String description;

  _EventDraft({
    required this.title,
    required this.eventType,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.location,
    this.description = '',
  });
}

class CreateEventPage extends StatefulWidget {
  final String bandId;

  const CreateEventPage({super.key, required this.bandId});

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
  final _otherEventTypeController = TextEditingController();

  String _eventType = 'Rehearsal';
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 19, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  bool _requireResponse = true;
  bool _createEventRoom = true;
  int _reminderIntervalHours = 48;
  bool _isCustomReminderHours = false;
  bool _isSaving = false;
  bool _isLoadingRole = true;

  // Multiple Events Batch State
  bool _isMultipleEvents = false;
  final List<_EventDraft> _additionalEvents = [];

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _customReminderController.dispose();
    _otherEventTypeController.dispose();
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
      final r = (role ?? '').toLowerCase();
      if (mounted) {
        if (!r.contains('leader') && !r.contains('admin') && !r.contains('mod')) {
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
      }
    }
  }

  final List<String> _eventTypes = [
    'Rehearsal',
    'Concert',
    'Club gig',
    'Private Event',
    'Show',
    'Recording Session',
    'Tour',
    'Meeting',
    'Other',
  ];

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

  void _showEditEventDraftDialog({int? editIndex}) {
    final isEditing = editIndex != null;
    final draftToEdit = isEditing ? _additionalEvents[editIndex] : null;

    DateTime defaultDate;
    if (isEditing) {
      defaultDate = draftToEdit!.date;
    } else if (_additionalEvents.isNotEmpty) {
      defaultDate = _additionalEvents.last.date.add(const Duration(days: 1));
    } else {
      defaultDate = _selectedDate.add(const Duration(days: 1));
    }

    final draftTitleController = TextEditingController(
      text: isEditing ? draftToEdit!.title : (_titleController.text.trim().isNotEmpty ? _titleController.text.trim() : 'New Event'),
    );
    final draftLocationController = TextEditingController(
      text: isEditing ? draftToEdit!.location : _locationController.text.trim(),
    );
    final draftDescriptionController = TextEditingController(
      text: isEditing ? draftToEdit!.description : '',
    );
    String draftType = isEditing ? draftToEdit!.eventType : 'Concert';
    DateTime draftDate = defaultDate;
    TimeOfDay draftStart = isEditing ? draftToEdit!.startTime : _startTime;
    TimeOfDay draftEnd = isEditing ? draftToEdit!.endTime : _endTime;

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
                    const SizedBox(height: 12),

                    // Event Type Dropdown
                    DropdownButtonFormField<String>(
                      value: draftType,
                      dropdownColor: const Color(0xFF16132D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Event Type'),
                      items: _eventTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => draftType = val);
                      },
                    ),
                    const SizedBox(height: 12),

                    // Event Title
                    TextFormField(
                      controller: draftTitleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(labelText: 'Event Title'),
                    ),
                    const SizedBox(height: 12),

                    // Location
                    TextFormField(
                      controller: draftLocationController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Location (City, Country)',
                        prefixIcon: Icon(Icons.location_on_outlined, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: draftDescriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Description (Optional)',
                        hintText: 'e.g. Warmup rehearsal, Tutti, Soundcheck',
                      ),
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
                                  Text(draftEnd.format(ctx), style: GoogleFonts.inter(color: Colors.white, fontSize: 14)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Save / Add Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAccent),
                        onPressed: () {
                          final title = draftTitleController.text.trim().isEmpty ? 'Event' : draftTitleController.text.trim();
                          final location = draftLocationController.text.trim();
                          final description = draftDescriptionController.text.trim();
                          final newDraft = _EventDraft(
                            title: title,
                            eventType: draftType,
                            date: draftDate,
                            startTime: draftStart,
                            endTime: draftEnd,
                            location: location,
                            description: description,
                          );

                          setState(() {
                            if (isEditing) {
                              _additionalEvents[editIndex!] = newDraft;
                            } else {
                              _additionalEvents.add(newDraft);
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
        final parsed = int.tryParse(_customReminderController.text.trim());
        if (parsed != null && parsed >= 0) {
          _reminderIntervalHours = parsed;
        }
      }

      final allEventsToSave = <_EventDraft>[
        _EventDraft(
          title: _titleController.text.trim(),
          eventType: _eventType,
          date: _selectedDate,
          startTime: _startTime,
          endTime: _endTime,
          location: _locationController.text.trim(),
          description: _descriptionController.text.trim(),
        ),
      ];

      if (_isMultipleEvents) {
        allEventsToSave.addAll(_additionalEvents);
      }

      for (var draft in allEventsToSave) {
        final start = DateTime(
          draft.date.year,
          draft.date.month,
          draft.date.day,
          draft.startTime.hour,
          draft.startTime.minute,
        );

        var end = DateTime(
          draft.date.year,
          draft.date.month,
          draft.date.day,
          draft.endTime.hour,
          draft.endTime.minute,
        );

        if (end.isBefore(start)) {
          end = end.add(const Duration(days: 1));
        }

        final deadline = start.subtract(Duration(hours: _reminderIntervalHours > 0 ? _reminderIntervalHours : 24));

        final newEvent = BandEvent(
          title: draft.title,
          description: draft.description.isNotEmpty ? draft.description : _descriptionController.text.trim(),
          eventType: draft.eventType,
          location: draft.location,
          startDateTime: start.toIso8601String(),
          endDateTime: end.toIso8601String(),
          additionalNotes: _notesController.text.trim(),
          createdBy: appState.currentUserId ?? '',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
          requireResponse: _requireResponse,
          rsvpDeadline: deadline.millisecondsSinceEpoch,
          reminderIntervalHours: _reminderIntervalHours,
          responses: {},
        );

        final eventId = await appState.firebaseService.saveBandEventAsync(widget.bandId, newEvent);

        if (_createEventRoom) {
          final creatorId = appState.currentUserId ?? '';
          final dateStr = allEventsToSave.length > 1 ? ' (${DateFormat('MMM d').format(start)})' : '';
          await appState.firebaseService.createTemporaryEventRoomAsync(
            bandId: widget.bandId,
            eventId: eventId,
            roomName: '${draft.title}$dateStr Chat',
            createdBy: creatorId,
          );
        }
      }

      if (mounted) {
        final count = allEventsToSave.length;
        final msg = count > 1
            ? "$count events published successfully!"
            : "Event published successfully!";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
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
        title: 'Create New Event',
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
                      'CREATE NEW EVENT',
                      style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Event Title
                    TextFormField(
                      controller: _titleController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Event Title',
                        hintText: 'e.g. Choir Rehearsal, Friday Gig',
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter an event title';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Event Type Dropdown
                    DropdownButtonFormField<String>(
                      value: _eventType,
                      dropdownColor: const Color(0xFF16132D),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Event Type',
                      ),
                      items: _eventTypes.map((type) {
                        return DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _eventType = val;
                          });
                        }
                      },
                    ),
                    if (_eventType == 'Other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otherEventTypeController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Specify Event Type',
                          hintText: 'e.g. Workshop, Radio Show, Masterclass',
                        ),
                        validator: (value) {
                          if (_eventType == 'Other' && (value == null || value.trim().isEmpty)) {
                            return 'Please specify the event type';
                          }
                          return null;
                        },
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                        hintText: 'What is this event about?',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Location
                    TextFormField(
                      controller: _locationController,
                      style: const TextStyle(color: Colors.white),
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

                    // Date & Time pickers (Hidden when Multiple Events is ON)
                    if (!_isMultipleEvents) ...[
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
                              'DATE & TIME',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryAccent,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Date picker trigger
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
                                        Text(
                                          'Date',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
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

                            // Start Time picker trigger
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
                                        Text(
                                          'Start Time',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
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

                            // End Time picker trigger
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
                                        Text(
                                          'End Time',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
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

                    // 🔁 MULTI-EVENT BATCH CREATION CARD
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isMultipleEvents ? AppTheme.primaryAccent.withOpacity(0.5) : const Color(0xFF2E2A4E),
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
                                          'Create Multiple Events',
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
                                      'Example: 1 rehearsal and 2 concerts, 2 shows, 3 days of Recording Session, etc',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isMultipleEvents,
                                activeColor: AppTheme.primaryAccent,
                                onChanged: (val) {
                                  setState(() {
                                    _isMultipleEvents = val;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_isMultipleEvents) ...[
                            const SizedBox(height: 16),
                            const Divider(color: Color(0xFF2E2A4E)),
                            const SizedBox(height: 12),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Generated Dates, Summary',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primaryAccent,
                                  ),
                                ),
                                Text(
                                  '${1 + _additionalEvents.length} events',
                                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Event 1 (Primary Event Card)
                            Container(
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
                                      _eventType == 'Other' && _otherEventTypeController.text.trim().isNotEmpty
                                          ? _otherEventTypeController.text.trim()
                                          : _eventType,
                                      style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _titleController.text.trim().isEmpty ? 'Event 1' : _titleController.text.trim(),
                                          style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${DateFormat('EEEE, MMM d').format(_selectedDate)} (${_startTime.format(context)} - ${_endTime.format(context)})',
                                          style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                        ),
                                        if (_locationController.text.trim().isNotEmpty)
                                          Text(
                                            '@ ${_locationController.text.trim()}',
                                            style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                          ),
                                        if (_descriptionController.text.trim().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            _descriptionController.text.trim(),
                                            style: GoogleFonts.inter(fontSize: 11, color: Colors.white70),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Tooltip(
                                    message: 'Event 1',
                                    child: Icon(Icons.info_outline, size: 16, color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            ),

                            // Additional Events List Cards (Fully Clickable)
                            ...List.generate(_additionalEvents.length, (index) {
                              final draft = _additionalEvents[index];
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _showEditEventDraftDialog(editIndex: index),
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141029),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          draft.eventType,
                                          style: GoogleFonts.inter(fontSize: 11, color: Colors.amber, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              draft.title,
                                              style: GoogleFonts.inter(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${DateFormat('EEEE, MMM d').format(draft.date)} (${draft.startTime.format(context)} - ${draft.endTime.format(context)})',
                                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                            ),
                                            if (draft.location.isNotEmpty)
                                              Text(
                                                '@ ${draft.location}',
                                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                              ),
                                            if (draft.description.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                draft.description,
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
                                        onPressed: () => _showEditEventDraftDialog(editIndex: index),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, color: AppTheme.danger, size: 18),
                                        onPressed: () {
                                          setState(() {
                                            _additionalEvents.removeAt(index);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),

                            const SizedBox(height: 8),

                            // "+ Add Tour Date / Event" Button
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppTheme.primaryAccent),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                minimumSize: const Size(double.infinity, 44),
                              ),
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryAccent, size: 18),
                              label: Text(
                                "+ Add Tour Date / Event",
                                style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              onPressed: () => _showEditEventDraftDialog(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // RSVP Deadlines Selector (CEO Page 2)
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
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                            ),
                            child: Text(
                              'The response time for answering a Reminder will be 50% shorter than the initial response time. An initial response time of 48 hours will become 24 hours after the first Reminder, etc.',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Initial Response Window (From event is published):',
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
                              DropdownMenuItem(value: -1, child: Text('Set hours here')),
                              DropdownMenuItem(value: 48, child: Text('48 hours (From event is published)')),
                              DropdownMenuItem(value: 24, child: Text('24 hours (From event is published)')),
                              DropdownMenuItem(value: 12, child: Text('12 hours (From event is published)')),
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
                              style: const TextStyle(color: Colors.white),
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
                                  if (parsed == null || parsed < 0) {
                                    return 'Please enter a valid positive number';
                                  }
                                }
                                return null;
                              },
                              onChanged: (val) {
                                final parsed = int.tryParse(val.trim());
                                if (parsed != null && parsed >= 0) {
                                  setState(() {
                                    _reminderIntervalHours = parsed;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Initial response window will be ${_reminderIntervalHours} hours from when event is published.',
                              style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryAccent),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Temporary Event Chat Switch (Tasks 2831 & 2843-2847)
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
                                    Text(
                                      'Create Event Chat',
                                      style: GoogleFonts.inter(
                                        fontSize: 15,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
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

                    // Save Button
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
                            (_isMultipleEvents && _additionalEvents.isNotEmpty)
                                ? "Publish ${1 + _additionalEvents.length} Events"
                                : "Publish Event",
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
