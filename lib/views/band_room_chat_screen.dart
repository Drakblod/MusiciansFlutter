import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../models/band.dart';
import '../models/user_profile.dart';
import '../models/message.dart';
import '../models/band_event.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';
import 'create_event_page.dart';
import 'event_details_page.dart';
import 'edit_band_info_screen.dart';

class BandRoomChatScreen extends StatefulWidget {
  const BandRoomChatScreen({super.key});

  @override
  State<BandRoomChatScreen> createState() => _BandRoomChatScreenState();
}

class _BandRoomChatScreenState extends State<BandRoomChatScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  Band? _activeBand;
  List<BandMember> _members = [];
  Map<String, UserProfile> _memberProfiles = {};
  Map<String, Map<String, String>> _files = {};
  List<Message> _chatMessages = [];
  List<BandEvent> _bandEvents = [];
  bool _isLoading = true;
  Message? _replyToMessage;

  StreamSubscription<List<Message>>? _chatSubscription;
  StreamSubscription<List<BandEvent>>? _bandEventsSubscription;
  StreamSubscription? _gigsNewsSubscription;
  List<Map<String, dynamic>> _gigsNews = [];
  String _gigsTabFilter = 'All';
  String? _loadedBandId;

  @override
  void initState() {
    _tabController = TabController(length: 5, vsync: this);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final appState = Provider.of<AppState>(context);
    final bandId = appState.activeBandId;
    if (bandId != _loadedBandId) {
      _initBand(bandId);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();
    _bandEventsSubscription?.cancel();
    _gigsNewsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initBand(String? bandId) async {
    _loadedBandId = bandId;
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _bandEventsSubscription?.cancel();
    _bandEventsSubscription = null;
    _gigsNewsSubscription?.cancel();
    _gigsNewsSubscription = null;

    if (bandId == null) {
      // If still no band selected, try to load user bands to see if we can set one
      final appState = Provider.of<AppState>(context, listen: false);
      final userId = appState.currentUserId;
      if (userId != null) {
        final userBands = await appState.firebaseService.getUserBandsAsync(userId);
        if (userBands.isNotEmpty) {
          appState.selectBand(userBands.keys.first, userBands.values.first);
          return;
        }
      }

      setState(() {
        _activeBand = null;
        _members = [];
        _files = {};
        _chatMessages = [];
        _bandEvents = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final appState = Provider.of<AppState>(context, listen: false);
      final bandInfo = await appState.firebaseService.getBandInfoAsync(bandId);
      final members = await appState.firebaseService.getBandMembersAsync(bandId);
      final files = await appState.firebaseService.getBandFilesAsync(bandId);

      if (mounted) {
        setState(() {
          _activeBand = bandInfo;
          _members = members;
          _files = files;
        });

        _loadMemberProfiles(appState, members);

        _chatSubscription = appState.firebaseService
            .subscribeToBandMessages(bandId)
            .listen((messages) {
          if (mounted) {
            setState(() {
              _chatMessages = messages;
              _isLoading = false;
            });
            WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
          }
        });

        _bandEventsSubscription = appState.firebaseService
            .subscribeToBandEvents(bandId)
            .listen((events) {
          if (mounted) {
            setState(() {
              _bandEvents = events;
            });
          }
        });

        _gigsNewsSubscription = appState.firebaseService
            .subscribeToGigsNews(bandId)
            .listen((gigsNews) {
          if (mounted) {
            setState(() {
              _gigsNews = gigsNews;
            });
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading band details: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMemberProfiles(AppState appState, List<BandMember> members) async {
    final Map<String, UserProfile> profilesMap = {};
    for (final m in members) {
      if (m.userId != null) {
        try {
          final profile = await appState.firebaseService.getUserProfileAsync(m.userId!);
          if (profile != null) {
            profilesMap[m.userId!] = profile;
          }
        } catch (e) {
          debugPrint("Error loading profile for ${m.userId}: $e");
        }
      }
    }
    if (mounted) {
      setState(() {
        _memberProfiles = profilesMap;
      });
    }
  }

  String _getMemberInstrument(String? userId) {
    if (userId == null) return '';
    final profile = _memberProfiles[userId];
    if (profile == null) return '';
    if (profile.mainInstrument != null && profile.mainInstrument!.isNotEmpty) {
      return profile.mainInstrument!;
    }
    if (profile.instruments.isNotEmpty) {
      return profile.instruments.first;
    }
    return '';
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showLeaderSettingsSheet(BuildContext context, String bandId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C20).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: const Border(
              top: BorderSide(color: Color(0xFF2E2A4E), width: 1.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Band Room Settings',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Edit Band Info option
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: AppTheme.primaryAccent),
                  title: Text(
                    'Edit Band Info',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Change band name, rehearsal times, details',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () async {
                    Navigator.pop(context); // Close bottom sheet
                    if (_activeBand != null) {
                      final updated = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EditBandInfoScreen(band: _activeBand!),
                        ),
                      );
                      if (updated == true) {
                        _initBand(bandId); // reload updated details in band room
                      }
                    }
                  },
                ),
                const Divider(color: Color(0xFF2E2A4E), height: 16),

                // Manage Sub Requests option
                ListTile(
                  leading: const Icon(Icons.people_outline, color: AppTheme.primaryAccent),
                  title: Text(
                    'Manage Sub Requests',
                    style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'View and post substitute requests',
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onTap: () {
                    Navigator.pop(context); // Close bottom sheet
                    Navigator.pushNamed(
                      context,
                      '/sub-request-responses',
                      arguments: {'bandId': bandId},
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId == null) return;

    final userProfile = appState.currentUserProfile;
    final senderName = userProfile?.displayName ?? userProfile?.nickname ?? 'Unknown';

    final replyText = _replyToMessage?.text;
    final replySenderName = _replyToMessage?.senderName;

    _messageController.clear();
    setState(() {
      _replyToMessage = null;
    });

    try {
      await appState.firebaseService.sendBandMessageAsync(
        bandId,
        text,
        senderName,
        replyToText: replyText,
        replyToSenderName: replySenderName,
      );
    } catch (e) {
      debugPrint("Error sending band message: $e");
    }
  }

  Future<void> _pickAndUploadBandFile(String bandId) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: true,
      );

      if (result != null) {
        final file = result.files.single;
        Uint8List? bytes = file.bytes;
        if (bytes == null && file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        }
        
        // Show loader dialog
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primaryAccent),
                  const SizedBox(height: 16),
                  Text(
                    'Uploading ${file.name}...',
                    style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),
        );

        final appState = Provider.of<AppState>(context, listen: false);
        
        // Upload to storage
        final url = await appState.firebaseService.uploadBandFileAsync(
          bandId,
          bytes,
          file.path,
          file.name,
        );

        // Save metadata to RTDB
        await appState.firebaseService.addBandFileAsync(bandId, file.name, url);
        
        // Refresh files list
        final files = await appState.firebaseService.getBandFilesAsync(bandId);

        if (mounted) {
          Navigator.pop(context); // Dismiss loader
          setState(() {
            _files = files;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('File "${file.name}" uploaded successfully!'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // Attempt to dismiss dialog if showing
        try { Navigator.pop(context); } catch (_) {}
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload file: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _showBandSelectorBottomSheet(
    BuildContext context,
    AppState appState,
    Map<String, String> bands,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C22).withOpacity(0.95),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
          ),
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'SELECT A BAND',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose which band room you would like to switch to.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.4,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: bands.length,
                  itemBuilder: (context, index) {
                    final bandId = bands.keys.elementAt(index);
                    final bandName = bands[bandId]!;
                    final isSelected = appState.activeBandId == bandId;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AnimatedTapDetector(
                        onTap: () {
                          appState.selectBand(bandId, bandName);
                          Navigator.pop(context); // Close bottom sheet
                          _initBand(bandId);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryAccent.withOpacity(0.12)
                                : AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryAccent
                                  : const Color(0xFF2E2A4E),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppTheme.primaryAccent.withOpacity(0.2)
                                      : Colors.white.withOpacity(0.05),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.groups_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  bandName,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.primaryAccent,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Band Room',
        showBack: true,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
            : _activeBand == null
                ? _buildNoActiveBandView()
                : _buildBandRoomContent(appState),
      ),
    );
  }

  Widget _buildNoActiveBandView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_outlined, size: 64, color: AppTheme.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No Active Band',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create or join a band to start sharing messages, files, and calendar events.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            AnimatedTapDetector(
              onTap: () {
                Navigator.pushNamed(context, '/create-band');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Create a Band',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBandRoomContent(AppState appState) {
    final bandName = _activeBand?.name ?? 'Band Room';

    return Column(
      children: [
        // 1. Room Header Info
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final userId = appState.currentUserId;
                      if (userId == null) return;

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                        ),
                      );

                      try {
                        final bands = await appState.firebaseService.getUserBandsAsync(userId);
                        if (context.mounted) {
                          Navigator.pop(context); // Dismiss loader
                        }

                        if (bands.length > 1) {
                          if (context.mounted) {
                            _showBandSelectorBottomSheet(context, appState, bands);
                          }
                        } else if (bands.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('You are not a member of any band rooms.')),
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('You only belong to one band room.')),
                            );
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Dismiss loader
                        }
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          bandName,
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: AppTheme.primaryAccent,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_members.length} members online',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              AnimatedTapDetector(
                onTap: () {
                  final appState = Provider.of<AppState>(context, listen: false);
                  final bandId = appState.activeBandId;
                  if (bandId != null) {
                    final currentUserId = appState.currentUserId;
                    final currentUserMember = _members.firstWhere(
                      (m) => m.userId == currentUserId,
                      orElse: () => BandMember(role: 'Member'),
                    );
                    final userRole = currentUserMember.role;
                    if (userRole == 'Leader') {
                      _showLeaderSettingsSheet(context, bandId);
                    } else {
                      Navigator.pushNamed(
                        context,
                        '/sub-request-responses',
                        arguments: {'bandId': bandId},
                      );
                    }
                  }
                },
                child: const Icon(Icons.settings_outlined, color: Colors.white, size: 24),
              ),
            ],
          ),
        ),

        // 2. Member Avatars Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              ..._members.take(3).map((m) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () {
                      if (m.userId != null) {
                        _navigateTo1on1Chat(m.userId!, m.nickname ?? 'Member');
                      }
                    },
                    child: CircleAvatar(
                      radius: 16,
                      backgroundColor: AppTheme.primaryAccent.withOpacity(0.3),
                      child: Text(
                        (m.nickname ?? 'M').substring(0, 1).toUpperCase(),
                        style: const TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ),
                  ),
                );
              }),
              if (_members.length > 3)
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.cardBackground,
                  child: Text(
                    '+${_members.length - 3}',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppTheme.secondaryAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 3. Tab Bar
        TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.primaryAccent,
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Chat'),
            Tab(text: 'Files'),
            Tab(text: 'Calendar'),
            Tab(text: 'Gigs/Info'),
            Tab(text: 'Members'),
          ],
        ),

        // 4. Tab View Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildChatTab(),
              _buildFilesTab(),
              _buildEventsTab(),
              _buildGigsNewsTab(),
              _buildMembersTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatTab() {
    return Column(
      children: [
        // Message thread
        Expanded(
          child: _chatMessages.isEmpty
              ? const Center(
                  child: Text(
                    "No messages in band room yet.",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _chatMessages.length,
                  physics: const BouncingScrollPhysics(),
                  itemBuilder: (context, index) {
                    final message = _chatMessages[index];
                    return _buildChatBubble(message);
                  },
                ),
        ),

        // Text input field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            color: Color(0xFF0C091D),
            border: Border(top: BorderSide(color: Color(0xFF1E1A3C), width: 1)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_replyToMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A153A),
                    borderRadius: BorderRadius.circular(8),
                    border: const Border(
                      left: BorderSide(color: AppTheme.primaryAccent, width: 4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Replying to ${_replyToMessage!.senderName ?? "Member"}',
                              style: GoogleFonts.inter(
                                color: AppTheme.primaryAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _replyToMessage!.text ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppTheme.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _replyToMessage = null;
                          });
                        },
                        child: const Icon(
                          Icons.close,
                          color: AppTheme.textSecondary,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // Plus/Add Button
                  Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF231F45), width: 1),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 20),
                  ),

                  // Message Input
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        hintStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                        fillColor: const Color(0xFF141029),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Send Button
                  AnimatedTapDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _getSenderName(Message msg) {
    if (msg.senderName != null && msg.senderName!.isNotEmpty && msg.senderName != 'Unknown') {
      return msg.senderName!;
    }
    final senderId = msg.senderId;
    if (senderId != null) {
      final member = _members.firstWhere(
        (m) => m.userId == senderId,
        orElse: () => BandMember(),
      );
      if (member.nickname != null && member.nickname!.isNotEmpty) {
        return member.nickname!;
      }
    }
    return 'Member';
  }

  Widget _buildChatBubble(Message msg) {
    final isMe = msg.isCurrentUserSender;
    final senderName = _getSenderName(msg);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            GestureDetector(
              onTap: () {
                if (msg.senderId != null) {
                  _navigateTo1on1Chat(msg.senderId!, senderName);
                }
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: AppTheme.primaryAccent.withOpacity(0.3),
                child: Text(
                  senderName.isNotEmpty ? senderName.substring(0, 1).toUpperCase() : 'M',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          if (isMe) ...[
            IconButton(
              icon: const Icon(Icons.reply, size: 16, color: AppTheme.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  _replyToMessage = msg;
                });
              },
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  GestureDetector(
                    onTap: () {
                      if (msg.senderId != null) {
                        _navigateTo1on1Chat(msg.senderId!, senderName);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            senderName,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_getMemberInstrument(msg.senderId).isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _getMemberInstrument(msg.senderId),
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                color: AppTheme.textSecondary.withOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                GestureDetector(
                  onDoubleTap: () {
                    setState(() {
                      _replyToMessage = msg;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isMe ? AppTheme.primaryAccent : const Color(0xFF1E1A3A),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.replyToText != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(6),
                              border: Border(
                                left: BorderSide(
                                  color: isMe ? Colors.white70 : AppTheme.primaryAccent,
                                  width: 3,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.replyToSenderName ?? 'Member',
                                  style: GoogleFonts.inter(
                                    color: isMe ? Colors.white : AppTheme.primaryAccent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  msg.replyToText!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Text(
                          msg.text ?? '',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        msg.timestamp != null
                            ? DateFormat('HH:mm').format(msg.timestamp!.toLocal())
                            : '12:00',
                        style: GoogleFonts.inter(fontSize: 10, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (!isMe) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.reply, size: 16, color: AppTheme.textMuted),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                setState(() {
                  _replyToMessage = msg;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _launchUrl(String urlString) async {
    final uri = Uri.parse(urlString.trim());
    try {
      final success = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!success) {
        // Fallback to default launching mode
        await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Could not launch $urlString: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening file: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Widget _buildFilesTab() {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId == null) return const Center(child: Text("No band selected"));

    // Categorize files
    final pdfs = <String, Map<String, String>>{};
    final audio = <String, Map<String, String>>{};
    final images = <String, Map<String, String>>{};
    final other = <String, Map<String, String>>{};

    _files.forEach((fileId, fileData) {
      final fileName = (fileData['FileName'] ?? '').toLowerCase();
      if (fileName.endsWith('.pdf')) {
        pdfs[fileId] = fileData;
      } else if (fileName.endsWith('.mp3') ||
          fileName.endsWith('.wav') ||
          fileName.endsWith('.m4a') ||
          fileName.endsWith('.aac') ||
          fileName.endsWith('.ogg')) {
        audio[fileId] = fileData;
      } else if (fileName.endsWith('.png') ||
          fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.gif') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.heic')) {
        images[fileId] = fileData;
      } else {
        other[fileId] = fileData;
      }
    });

    return Column(
      children: [
        Expanded(
          child: _files.isEmpty
              ? const Center(
                  child: Text(
                    "No files uploaded yet.",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildFileCategorySection('PDF Documents', Icons.picture_as_pdf_outlined, Colors.redAccent, pdfs, bandId, appState),
                    _buildFileCategorySection('Audio Files', Icons.audiotrack_outlined, Colors.orangeAccent, audio, bandId, appState),
                    _buildFileCategorySection('Images', Icons.image_outlined, Colors.greenAccent, images, bandId, appState),
                    _buildFileCategorySection('Other Files', Icons.insert_drive_file_outlined, Colors.blueAccent, other, bandId, appState),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: AnimatedTapDetector(
            onTap: () => _pickAndUploadBandFile(bandId),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, color: Colors.white),
                    SizedBox(width: 8),
                    Text(
                      "Upload a File",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFileCategorySection(
    String title,
    IconData icon,
    Color color,
    Map<String, Map<String, String>> categoryFiles,
    String bandId,
    AppState appState,
  ) {
    if (categoryFiles.isEmpty) return const SizedBox.shrink();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2E2A4E), width: 1.2),
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          leading: Icon(icon, color: color, size: 24),
          title: Text(
            '$title (${categoryFiles.length})',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          iconColor: Colors.white,
          collapsedIconColor: AppTheme.textSecondary,
          children: categoryFiles.entries.map((entry) {
            final fileId = entry.key;
            final fileData = entry.value;
            final fileName = fileData['FileName'] ?? 'Uploaded File';
            final fileUrl = fileData['FileUrl'] ?? '';

            return AnimatedTapDetector(
              onTap: () {
                if (fileUrl.isNotEmpty) {
                  _launchUrl(fileUrl);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This file has no download URL.'),
                      backgroundColor: AppTheme.warning,
                    ),
                  );
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF130E26).withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF2E2A4E).withOpacity(0.5), width: 1),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: AppTheme.cardBackground,
                            title: const Text('Delete File', style: TextStyle(color: Colors.white)),
                            content: Text('Are you sure you want to delete "$fileName"?', style: const TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(
                                child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                                onPressed: () => Navigator.pop(context, false),
                              ),
                              TextButton(
                                child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                onPressed: () => Navigator.pop(context, true),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await appState.firebaseService.removeBandFileAsync(bandId, fileId);
                          final files = await appState.firebaseService.getBandFilesAsync(bandId);
                          if (mounted) {
                            setState(() {
                              _files = files;
                            });
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
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

  Widget _buildMembersTab() {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    final selfId = appState.currentUserId;

    final currentMember = _members.firstWhere(
      (m) => m.userId == selfId,
      orElse: () => BandMember(role: 'Member'),
    );
    final isLeaderOrAdmin = currentMember.role == 'Leader' || currentMember.role == 'Admin';

    return Column(
      children: [
        if (isLeaderOrAdmin && bandId != null)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: AnimatedTapDetector(
              onTap: () => _showAddMemberDialog(bandId),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_add_alt_1_outlined, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        "Add Band Member",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              return AnimatedTapDetector(
                onTap: () {
                  if (member.userId != null) {
                    _viewMemberProfile(member.userId!);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF231F45), width: 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: AppTheme.primaryAccent.withOpacity(0.3),
                        child: Text(
                          (member.nickname ?? 'M').substring(0, 1).toUpperCase(),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.nickname ?? 'Unknown Member',
                              style: GoogleFonts.outfit(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              member.role ?? 'Member',
                              style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                            ),
                            if (_getMemberInstrument(member.userId).isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                _getMemberInstrument(member.userId),
                                style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryAccent, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (member.role == 'Leader')
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAccent.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Leader',
                            style: GoogleFonts.inter(fontSize: 10, color: AppTheme.primaryAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                      if (member.userId != null && member.userId != selfId) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            _navigateTo1on1Chat(member.userId!, member.nickname ?? 'Member');
                          },
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryAccent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: AppTheme.primaryAccent,
                              size: 18,
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildGigsNewsTab() {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    final selfId = appState.currentUserId;

    final currentMember = _members.firstWhere(
      (m) => m.userId == selfId,
      orElse: () => BandMember(role: 'Member'),
    );
    final isLeaderOrAdmin = currentMember.role == 'Leader' || currentMember.role == 'Admin';

    // 1. Prepare feed items
    final feedItems = <Map<String, dynamic>>[];
    final now = DateTime.now();

    // Add News/Gigs
    if (_gigsTabFilter == 'All' || _gigsTabFilter == 'News') {
      for (var post in _gigsNews) {
        feedItems.add({
          'id': post['id'] ?? '',
          'feedType': post['type'] ?? 'News', // 'Gig' or 'News'
          'title': post['title'] ?? 'Untitled',
          'content': post['content'] ?? '',
          'authorName': post['authorName'] ?? 'Leader',
          'timestamp': post['timestamp'] as int? ?? 0,
          'location': post['location'] ?? '',
          'originalData': post,
        });
      }
    }

    // Add Events
    if (_gigsTabFilter == 'All' || _gigsTabFilter == 'Events') {
      for (var event in _bandEvents) {
        final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? now;
        final isUpcoming = endLocal.isAfter(now);
        final timestamp = event.createdAt > 0
            ? event.createdAt
            : (DateTime.tryParse(event.startDateTime)?.millisecondsSinceEpoch ?? 0);

        feedItems.add({
          'id': event.id ?? '',
          'feedType': isUpcoming ? 'UpcomingEvent' : 'PastEvent',
          'title': event.title,
          'content': event.description,
          'authorName': event.createdBy,
          'timestamp': timestamp,
          'location': event.location,
          'originalData': event,
        });
      }
    }

    // Sort by timestamp descending
    feedItems.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter Chips Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All', Icons.feed_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('News', Icons.campaign_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Events', Icons.event_rounded),
                const SizedBox(width: 8),
                _buildFilterChip('Roster', Icons.groups_rounded),
              ],
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            physics: const BouncingScrollPhysics(),
            children: [
              // Welcome Roster Board (rendered at the top of 'All' or 'Roster')
              if ((_gigsTabFilter == 'All' || _gigsTabFilter == 'Roster') && _members.isNotEmpty) ...[
                _buildWelcomeRosterSection(),
                const SizedBox(height: 20),
              ],

              // Post Button for Leaders/Admins (under News filter, or top of feed when appropriate)
              if (isLeaderOrAdmin && bandId != null && (_gigsTabFilter == 'All' || _gigsTabFilter == 'News')) ...[
                AnimatedTapDetector(
                  onTap: () => _showPostGigsNewsDialog(bandId),
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryAccent.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_circle_outline_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            "Create Gig or News Update",
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Feed list content
              if (_gigsTabFilter == 'Roster') ...[
                _buildDetailedRosterList(),
              ] else if (feedItems.isEmpty) ...[
                SizedBox(
                  height: 200,
                  child: Center(
                    child: Text(
                      "No posts or events found.",
                      style: GoogleFonts.inter(color: AppTheme.textSecondary),
                    ),
                  ),
                ),
              ] else ...[
                ...feedItems.map((item) {
                  final feedType = item['feedType'] as String;
                  if (feedType == 'Gig' || feedType == 'News') {
                    return _buildNewsFeedCard(item, isLeaderOrAdmin, bandId);
                  } else {
                    return _buildEventFeedCard(item, bandId);
                  }
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String filterVal, IconData icon) {
    final isSelected = _gigsTabFilter == filterVal;
    return AnimatedTapDetector(
      onTap: () {
        setState(() {
          _gigsTabFilter = filterVal;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAccent : AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              filterVal == 'News' ? 'Gigs & News' : filterVal,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeRosterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'BAND ROSTER',
              style: GoogleFonts.outfit(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
            Text(
              '${_members.length} members',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _members.length,
            itemBuilder: (context, index) {
              final member = _members[index];
              final instrument = _getMemberInstrument(member.userId);
              return GestureDetector(
                onTap: () {
                  if (member.userId != null) {
                    _viewMemberProfile(member.userId!);
                  }
                },
                child: Container(
                  width: 85,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                        child: Text(
                          (member.nickname ?? 'M').substring(0, 1).toUpperCase(),
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        member.nickname ?? 'Member',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (instrument.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          instrument,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            color: AppTheme.primaryAccent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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

  Widget _buildDetailedRosterList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'BAND MEMBERS',
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _members.length,
          itemBuilder: (context, index) {
            final member = _members[index];
            final instrument = _getMemberInstrument(member.userId);
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2E2A4E), width: 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                    child: Text(
                      (member.nickname ?? 'M').substring(0, 1).toUpperCase(),
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          member.nickname ?? 'Member',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          member.role ?? 'Member',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (instrument.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            instrument,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppTheme.primaryAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 16),
                    onPressed: () {
                      if (member.userId != null) {
                        _viewMemberProfile(member.userId!);
                      }
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildNewsFeedCard(Map<String, dynamic> item, bool isLeaderOrAdmin, String? bandId) {
    final isGig = item['feedType'] == 'Gig';
    final dateStr = item['timestamp'] > 0
        ? DateTime.fromMillisecondsSinceEpoch(item['timestamp'] as int).toLocal().toString().substring(0, 16)
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isGig ? AppTheme.warning.withOpacity(0.3) : const Color(0xFF2E2A4E),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isGig ? AppTheme.warning : AppTheme.primaryAccent).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isGig ? 'GIG' : 'NEWS',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isGig ? AppTheme.warning : AppTheme.secondaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item['title'] ?? 'Untitled',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              if (isLeaderOrAdmin && bandId != null && item['id'].toString().isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 20),
                  onPressed: () => _deleteGigsNewsPost(bandId, item['id']!),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            item['content'] ?? '',
            style: GoogleFonts.inter(
              fontSize: 13.5,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'By: ${item['authorName'] ?? 'Leader'}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                dateStr,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventFeedCard(Map<String, dynamic> item, String? bandId) {
    final event = item['originalData'] as BandEvent;
    final isUpcoming = item['feedType'] == 'UpcomingEvent';
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final formattedTime = DateFormat('EEEE, MMM d - HH:mm').format(startLocal);

    final totalResponses = event.responses.length;
    final yesResponses = event.responses.values.where((r) => r.status == 'Yes').length;

    IconData eventIcon;
    switch (event.eventType.toLowerCase()) {
      case 'rehearsal':
        eventIcon = Icons.music_note_rounded;
        break;
      case 'concert':
      case 'gig':
        eventIcon = Icons.campaign_rounded;
        break;
      case 'recording session':
        eventIcon = Icons.mic_rounded;
        break;
      case 'meeting':
        eventIcon = Icons.forum_rounded;
        break;
      default:
        eventIcon = Icons.event_available_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isUpcoming ? AppTheme.success.withOpacity(0.3) : const Color(0xFF2E2A4E),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isUpcoming ? AppTheme.success : AppTheme.textSecondary).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  eventIcon,
                  color: isUpcoming ? AppTheme.success : AppTheme.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isUpcoming ? AppTheme.success : AppTheme.textSecondary).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isUpcoming ? 'UPCOMING EVENT' : 'PAST EVENT',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: isUpcoming ? AppTheme.success : AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (event.description.isNotEmpty) ...[
            Text(
              event.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded, color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formattedTime,
                        style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: AppTheme.textSecondary, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(fontSize: 12.5, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$yesResponses Attending ($totalResponses responses)',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppTheme.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: () {
                  if (bandId != null && event.id != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => EventDetailsPage(
                          bandId: bandId,
                          eventId: event.id!,
                          initialEvent: event,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isUpcoming ? AppTheme.primaryAccent.withOpacity(0.15) : const Color(0xFF2E2A4E),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isUpcoming ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                    ),
                  ),
                  child: Row(
                    children: [
                      Text(
                        isUpcoming ? 'RSVP / Details' : 'View Details',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: isUpcoming ? AppTheme.primaryAccent : Colors.white70,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: isUpcoming ? AppTheme.primaryAccent : Colors.white70,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGigsNewsPost(String bandId, String postId) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBackground,
        title: const Text('Delete Post?'),
        content: const Text('Are you sure you want to delete this post?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await appState.firebaseService.deleteGigsNewsAsync(bandId, postId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post deleted successfully.'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete post: $e'),
              backgroundColor: AppTheme.danger,
            ),
          );
        }
      }
    }
  }

  void _showPostGigsNewsDialog(String bandId) {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    String type = 'News';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0F0C20).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
                ),
                padding: const EdgeInsets.all(20),
                width: MediaQuery.of(context).size.width * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POST GIG / NEWS',
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Post Type',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => type = 'News'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: type == 'News' ? AppTheme.primaryAccent.withOpacity(0.15) : AppTheme.inputBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: type == 'News' ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'News Update',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => setDialogState(() => type = 'Gig'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: type == 'Gig' ? AppTheme.warning.withOpacity(0.15) : AppTheme.inputBackground,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: type == 'Gig' ? AppTheme.warning : const Color(0xFF2E2A4E),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Gig / Booking',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Title',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: titleController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'e.g. Rehearsal Update or Gig Booking',
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Content',
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: contentController,
                        style: const TextStyle(color: Colors.white),
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: 'Provide all the details for the members...',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: type == 'Gig' ? AppTheme.warning : AppTheme.primaryAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () async {
                              final title = titleController.text.trim();
                              final content = contentController.text.trim();
                              if (title.isEmpty || content.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please fill out all fields'),
                                    backgroundColor: AppTheme.danger,
                                  ),
                                );
                                return;
                              }

                              final appState = Provider.of<AppState>(context, listen: false);
                              final authorName = appState.currentUserProfile?.displayName ?? 'Leader';

                              try {
                                await appState.firebaseService.postGigsNewsAsync(
                                  bandId,
                                  {
                                    'title': title,
                                    'content': content,
                                    'type': type,
                                    'authorName': authorName,
                                  },
                                );
                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Post added successfully!'),
                                      backgroundColor: AppTheme.success,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to post: $e'),
                                      backgroundColor: AppTheme.danger,
                                    ),
                                  );
                                }
                              }
                            },
                            child: const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddMemberDialog(String bandId) async {
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
              color: const Color(0xFF0F0C20).withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF2E2A4E), width: 1.5),
            ),
            padding: const EdgeInsets.all(20),
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.6,
            child: _AddMemberDialogContent(
              bandId: bandId,
              allUsers: allUsers,
              existingMembers: _members,
              onMemberAdded: () {
                _initBand(bandId);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _getEventTypeBadge(String type) {
    String emoji = '📅';
    switch (type) {
      case 'Rehearsal':
        emoji = '🎼';
        break;
      case 'Concert':
        emoji = '🎺';
        break;
      case 'Gig':
        emoji = '🎸';
        break;
      case 'Recording Session':
        emoji = '🎙️';
        break;
      case 'Meeting':
        emoji = '👥';
        break;
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primaryAccent.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 20)),
    );
  }

  Widget _buildEventCard(BandEvent event, String bandId) {
    final startLocal = DateTime.tryParse(event.startDateTime)?.toLocal() ?? DateTime.now();
    final formattedTime = DateFormat('EEEE HH:mm').format(startLocal);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventDetailsPage(
              bandId: bandId,
              eventId: event.id!,
              initialEvent: event,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF231F45), width: 1),
        ),
        child: Row(
          children: [
            _getEventTypeBadge(event.eventType),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time_outlined, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        formattedTime,
                        style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 12, color: AppTheme.textSecondary),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.location,
                          style: GoogleFonts.inter(fontSize: 12, color: AppTheme.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (event.requireResponse) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${event.responses.length}/${_members.length} responded',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, color: AppTheme.textSecondary, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildEventsTab() {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId == null) {
      return const Center(child: Text("No band selected"));
    }

    final selfId = appState.currentUserId;
    final currentMember = _members.firstWhere(
      (m) => m.userId == selfId,
      orElse: () => BandMember(role: 'Member'),
    );
    final isLeaderOrAdmin = currentMember.role == 'Leader' || currentMember.role == 'Admin';

    // Separate upcoming and past events
    final now = DateTime.now();
    final upcomingEvents = <BandEvent>[];
    final pastEvents = <BandEvent>[];

    for (var event in _bandEvents) {
      final endLocal = DateTime.tryParse(event.endDateTime)?.toLocal() ?? DateTime.now();
      if (endLocal.isAfter(now)) {
        upcomingEvents.add(event);
      } else {
        pastEvents.add(event);
      }
    }

    // Sort upcoming chronologically ascending (earliest first)
    upcomingEvents.sort((a, b) {
      final aTime = DateTime.tryParse(a.startDateTime) ?? DateTime.now();
      final bTime = DateTime.tryParse(b.startDateTime) ?? DateTime.now();
      return aTime.compareTo(bTime);
    });

    // Sort past chronologically descending (latest first)
    pastEvents.sort((a, b) {
      final aTime = DateTime.tryParse(a.startDateTime) ?? DateTime.now();
      final bTime = DateTime.tryParse(b.startDateTime) ?? DateTime.now();
      return bTime.compareTo(aTime);
    });

    return Column(
      children: [
        // Create Event Button for Leaders/Admins
        if (isLeaderOrAdmin)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: AnimatedTapDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CreateEventPage(bandId: bandId),
                  ),
                );
              },
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        "Create Event",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        Expanded(
          child: _bandEvents.isEmpty
              ? const Center(
                  child: Text(
                    "No events planned yet.",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    if (upcomingEvents.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 12),
                        child: Text(
                          "UPCOMING EVENTS",
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryAccent,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      ...upcomingEvents.map((event) => _buildEventCard(event, bandId)),
                    ],

                    if (pastEvents.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          title: Text(
                            "Past Events (${pastEvents.length})",
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          iconColor: AppTheme.textSecondary,
                          collapsedIconColor: AppTheme.textSecondary,
                          children: pastEvents.map((event) => _buildEventCard(event, bandId)).toList(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
        ),
      ],
    );
  }
}

class _AddMemberDialogContent extends StatefulWidget {
  final String bandId;
  final List<UserProfile> allUsers;
  final List<BandMember> existingMembers;
  final VoidCallback onMemberAdded;

  const _AddMemberDialogContent({
    required this.bandId,
    required this.allUsers,
    required this.existingMembers,
    required this.onMemberAdded,
  });

  @override
  State<_AddMemberDialogContent> createState() => _AddMemberDialogContentState();
}

class _AddMemberDialogContentState extends State<_AddMemberDialogContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isAdding = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final existingUserIds = widget.existingMembers.map((m) => m.userId).toSet();

    final filteredUsers = widget.allUsers.where((user) {
      if (user.userId == null || existingUserIds.contains(user.userId)) {
        return false;
      }
      final name = (user.displayName ?? user.nickname ?? '').toLowerCase();
      return name.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Add Band Member",
          style: GoogleFonts.outfit(
            fontSize: 18,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Search by name...",
            prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            fillColor: const Color(0xFF141029),
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
          child: _isAdding
              ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent))
              : filteredUsers.isEmpty
                  ? Center(
                      child: Text(
                        _searchQuery.isEmpty ? "No other users found." : "No matching users found.",
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final user = filteredUsers[index];
                        final name = user.displayName ?? user.nickname ?? 'Unknown';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                                child: Text(
                                  name.substring(0, 1).toUpperCase(),
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                              IconButton(
                                icon: const Icon(Icons.add_circle, color: AppTheme.primaryAccent, size: 24),
                                onPressed: () async {
                                  setState(() => _isAdding = true);
                                  try {
                                    await appState.firebaseService.addBandMemberAsync(
                                      widget.bandId,
                                      user.userId!,
                                      'Member',
                                      user.nickname ?? name,
                                    );
                                    widget.onMemberAdded();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("$name added to the band!"),
                                          backgroundColor: AppTheme.success,
                                        ),
                                      );
                                      Navigator.pop(context); // Close dialog
                                    }
                                  } catch (e) {
                                    debugPrint("Error adding band member: $e");
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text("Failed to add $name: $e"),
                                          backgroundColor: AppTheme.danger,
                                        ),
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() => _isAdding = false);
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
