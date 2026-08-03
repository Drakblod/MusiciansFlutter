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

  // Recurring Events State
  bool _isRecurring = false;
  String _recurrencePattern = 'Weekly'; // 'Weekly', 'Bi-weekly', 'Daily', 'Monthly'
  int _occurrenceCount = 3; // default 3 times (e.g. 3 tuesdays in a row)

  final List<String> _eventTypes = [
    'Rehearsal',
    'Concert',
    'Club gig',
    'Private Event',
    'Show',
    'Recording Session',
    'Meeting',
    'Other'
  ];

  DateTime _getCalculatedDate(DateTime baseDate, String pattern, int index) {
    if (index == 0) return baseDate;
    if (pattern == 'Daily') {
      return baseDate.add(Duration(days: index));
    } else if (pattern == 'Weekly') {
      return baseDate.add(Duration(days: index * 7));
    } else if (pattern == 'Bi-weekly') {
      return baseDate.add(Duration(days: index * 14));
    } else if (pattern == 'Monthly') {
      return DateTime(baseDate.year, baseDate.month + index, baseDate.day);
    }
    return baseDate;
  }

  @override
  void initState() {
    super.initState();
    _checkPermission();
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
      if (mounted) {
        if (role != 'Leader' && role != 'Admin') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access Denied: Only band Leaders and Admins can create events.'),
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

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    _customReminderController.dispose();
    super.dispose();
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
      final totalEvents = _isRecurring ? _occurrenceCount : 1;

      for (int i = 0; i < totalEvents; i++) {
        final eventDate = _getCalculatedDate(_selectedDate, _recurrencePattern, i);

        final start = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
          _startTime.hour,
          _startTime.minute,
        );

        var end = DateTime(
          eventDate.year,
          eventDate.month,
          eventDate.day,
          _endTime.hour,
          _endTime.minute,
        );

        if (end.isBefore(start)) {
          end = end.add(const Duration(days: 1));
        }

        final deadline = start.subtract(Duration(hours: _reminderIntervalHours > 0 ? _reminderIntervalHours : 24));

        final newEvent = BandEvent(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          eventType: _eventType,
          location: _locationController.text.trim(),
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
          final dateStr = totalEvents > 1 ? ' (${DateFormat('MMM d').format(start)})' : '';
          await appState.firebaseService.createTemporaryEventRoomAsync(
            bandId: widget.bandId,
            eventId: eventId,
            roomName: '${_titleController.text.trim()}$dateStr Chat',
            createdBy: creatorId,
          );
        }
      }

      if (mounted) {
        final msg = totalEvents > 1
            ? "$totalEvents recurring events published successfully!"
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

                    // Date & Time pickers
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

                    // 🔁 RECURRING / MULTI-EVENT CREATION CARD
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isRecurring ? AppTheme.primaryAccent.withOpacity(0.5) : const Color(0xFF2E2A4E),
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
                                        const Icon(Icons.repeat_rounded, color: AppTheme.primaryAccent, size: 20),
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
                                      'Repeat this event over multiple days/weeks (e.g. 3 Tuesdays in a row).',
                                      style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: _isRecurring,
                                activeColor: AppTheme.primaryAccent,
                                onChanged: (val) {
                                  setState(() {
                                    _isRecurring = val;
                                  });
                                },
                              ),
                            ],
                          ),
                          if (_isRecurring) ...[
                            const SizedBox(height: 16),
                            const Divider(color: Color(0xFF2E2A4E)),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                // Frequency Dropdown
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Frequency',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<String>(
                                        value: _recurrencePattern,
                                        dropdownColor: const Color(0xFF16132D),
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
                                          DropdownMenuItem(value: 'Bi-weekly', child: Text('Bi-weekly')),
                                          DropdownMenuItem(value: 'Daily', child: Text('Daily')),
                                          DropdownMenuItem(value: 'Monthly', child: Text('Monthly')),
                                        ],
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _recurrencePattern = val);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Number of Times Dropdown
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Occurrences',
                                        style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                                      ),
                                      const SizedBox(height: 4),
                                      DropdownButtonFormField<int>(
                                        value: _occurrenceCount,
                                        dropdownColor: const Color(0xFF16132D),
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                                        decoration: const InputDecoration(
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: [2, 3, 4, 5, 6, 8, 10, 12].map((num) {
                                          return DropdownMenuItem<int>(
                                            value: num,
                                            child: Text('$num times'),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _occurrenceCount = val);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Dynamic Dates Preview Box
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141029),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.date_range_rounded, size: 14, color: AppTheme.primaryAccent),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Generated Dates Preview ($_occurrenceCount events):',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.primaryAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...List.generate(_occurrenceCount, (index) {
                                    final dt = _getCalculatedDate(_selectedDate, _recurrencePattern, index);
                                    final dateStr = DateFormat('EEEE, MMM d, yyyy').format(dt);
                                    final timeStr = '${_startTime.format(context)} - ${_endTime.format(context)}';
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        children: [
                                          Text(
                                            'Event ${index + 1}: ',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white70,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              '$dateStr ($timeStr)',
                                              style: GoogleFonts.inter(
                                                fontSize: 11,
                                                color: Colors.white,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
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
                              DropdownMenuItem(value: 48, child: Text('48 hours (From event is published)')),
                              DropdownMenuItem(value: 24, child: Text('24 hours (From event is published)')),
                              DropdownMenuItem(value: 12, child: Text('12 hours (From event is published)')),
                              DropdownMenuItem(value: 0, child: Text('No automatic Reminders')),
                              DropdownMenuItem(value: -1, child: Text('Custom hours...')),
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
                                labelText: 'Custom Reminder Hours',
                                hintText: 'e.g. 36, 72, 96',
                                prefixIcon: Icon(Icons.timer_outlined, color: AppTheme.textSecondary),
                                suffixText: 'hours',
                                suffixStyle: TextStyle(color: AppTheme.textSecondary),
                              ),
                              validator: (value) {
                                if (_isCustomReminderHours) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter custom reminder hours';
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
                            _isRecurring ? "Publish $_occurrenceCount Events" : "Publish Event",
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
