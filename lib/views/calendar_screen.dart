import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/calendar_event.dart';
import '../widgets/gradient_scaffold.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/animated_tap_detector.dart';

class CalendarScreen extends StatefulWidget {
  final String? bandId;

  const CalendarScreen({
    super.key,
    this.bandId,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  List<CalendarEvent> _events = [];
  bool _isLoading = true;
  String? _resolvedBandId;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      _resolvedBandId = widget.bandId ?? appState.activeBandId;

      if (_resolvedBandId != null) {
        final list = await appState.firebaseService.getBandEventsAsync(_resolvedBandId!);
        if (mounted) {
          setState(() {
            _events = list;
          });
        }
      }
    } catch (e) {
      debugPrint("Error loading calendar events: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddEventBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.backgroundEnd,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return _AddEventForm(
          bandId: _resolvedBandId!,
          onEventAdded: () {
            Navigator.pop(context);
            _loadEvents();
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final hasBand = _resolvedBandId != null || appState.activeBandId != null;

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Band Calendar',
        showBack: true,
      ),
      body: !hasBand
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_month_outlined, size: 64, color: AppTheme.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'No Active Band Room',
                      style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please enter a Band Room first to access the calendar features.',
                      style: GoogleFonts.inter(fontSize: 14, color: AppTheme.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
              : Column(
                  children: [
                    // Header / Controls Row
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Band Schedule',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          AnimatedTapDetector(
                            onTap: _showAddEventBottomSheet,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.add, color: Colors.white, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Add Event',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Events List
                    Expanded(
                      child: _events.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.event_busy_outlined,
                                    size: 48,
                                    color: AppTheme.textSecondary.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No events scheduled yet.',
                                    style: GoogleFonts.inter(color: AppTheme.textSecondary),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              physics: const BouncingScrollPhysics(),
                              itemCount: _events.length,
                              itemBuilder: (context, index) {
                                final event = _events[index];
                                final date = event.date ?? DateTime.now();

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: AppTheme.cardBackground,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF231F45), width: 1),
                                  ),
                                  child: Row(
                                    children: [
                                      // Date Badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryAccent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              DateFormat('MMM').format(date).toUpperCase(),
                                              style: GoogleFonts.inter(
                                                fontSize: 10,
                                                color: AppTheme.primaryAccent,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              DateFormat('dd').format(date),
                                              style: GoogleFonts.outfit(
                                                fontSize: 20,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // Details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              event.title ?? 'Band Session',
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                                                const SizedBox(width: 4),
                                                Text(
                                                  event.location ?? 'TBD',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 12,
                                                    color: AppTheme.textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                const Icon(Icons.access_time_outlined, color: AppTheme.textMuted, size: 14),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${event.startTime ?? "18:00"} - ${event.endTime ?? "21:00"}',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    color: AppTheme.textMuted,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Event Type Chip Tag
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1E1A3A),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          event.type == CalendarEventType.rehearsal
                                              ? 'REHEARSAL'
                                              : event.type == CalendarEventType.concert
                                                  ? 'GIG'
                                                  : event.type == CalendarEventType.tour
                                                      ? 'TOUR'
                                                      : 'OTHER',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            color: AppTheme.secondaryAccent,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _AddEventForm extends StatefulWidget {
  final String bandId;
  final VoidCallback onEventAdded;

  const _AddEventForm({
    required this.bandId,
    required this.onEventAdded,
  });

  @override
  State<_AddEventForm> createState() => _AddEventFormState();
}

class _AddEventFormState extends State<_AddEventForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descriptionController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 21, minute: 0);
  String _eventType = 'Rehearsal';
  bool _isSaving = false;

  final List<String> _types = ['Rehearsal', 'Gig', 'Studio Session', 'Jam'];

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppTheme.primaryAccent,
              onPrimary: Colors.white,
              surface: AppTheme.cardBackground,
              onSurface: Colors.white,
            ),
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

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    final appState = Provider.of<AppState>(context, listen: false);
    final userProfile = appState.currentUserProfile;

    try {
      CalendarEventType eventTypeEnum = CalendarEventType.other;
      if (_eventType == 'Rehearsal') {
        eventTypeEnum = CalendarEventType.rehearsal;
      } else if (_eventType == 'Gig') {
        eventTypeEnum = CalendarEventType.concert;
      } else if (_eventType == 'Studio Session') {
        eventTypeEnum = CalendarEventType.tour;
      }

      final event = CalendarEvent(
        bandId: widget.bandId,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        type: eventTypeEnum,
        location: _locationController.text.trim(),
        creatorId: appState.currentUserId,
        creatorName: userProfile?.displayName ?? 'Alex',
        isFinalized: true,
        date: _selectedDate,
        startTime: '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
        endTime: '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
      );

      await appState.firebaseService.addBandEventAsync(event);
      widget.onEventAdded();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save event: $e'),
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
    final formatTime = (TimeOfDay t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Schedule Band Event',
                style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),

              // Title
              TextFormField(
                controller: _titleController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Event Title',
                  hintText: 'e.g. Weekly Rehearsal',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Location
              TextFormField(
                controller: _locationController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'e.g. Studio A, Stockholm',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a location';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Event Type Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.inputBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButtonFormField<String>(
                    value: _eventType,
                    decoration: const InputDecoration(
                      labelText: 'Event Type',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    dropdownColor: AppTheme.cardBackground,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppTheme.textSecondary),
                    items: _types.map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        setState(() {
                          _eventType = newValue;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Date Picker Button
              AnimatedTapDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.inputBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('dd MMMM yyyy').format(_selectedDate),
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      ),
                      const Icon(Icons.calendar_month_outlined, color: AppTheme.textSecondary, size: 20),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Times Row
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
              const SizedBox(height: 24),

              // Save Button
              _isSaving
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
                  : AnimatedTapDetector(
                      onTap: _saveEvent,
                      child: Container(
                        height: 55,
                        decoration: BoxDecoration(
                          gradient: AppTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(
                            'Schedule Event',
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}
