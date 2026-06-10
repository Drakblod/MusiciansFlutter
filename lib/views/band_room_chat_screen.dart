import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
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
  Map<String, String> _files = {};
  List<Message> _chatMessages = [];
  List<BandEvent> _bandEvents = [];
  bool _isLoading = true;

  StreamSubscription<List<Message>>? _chatSubscription;
  StreamSubscription<List<BandEvent>>? _bandEventsSubscription;
  String? _loadedBandId;

  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this);
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
    super.dispose();
  }

  Future<void> _initBand(String? bandId) async {
    _loadedBandId = bandId;
    _chatSubscription?.cancel();
    _chatSubscription = null;
    _bandEventsSubscription?.cancel();
    _bandEventsSubscription = null;

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
      }
    } catch (e) {
      debugPrint("Error loading band details: $e");
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId == null) return;

    final userProfile = appState.currentUserProfile;
    final senderName = userProfile?.displayName ?? userProfile?.nickname ?? 'Unknown';

    _messageController.clear();

    try {
      await appState.firebaseService.sendBandMessageAsync(bandId, text, senderName);
    } catch (e) {
      debugPrint("Error sending band message: $e");
    }
  }

  Future<void> _showAddFileDialog(String bandId) async {
    final controller = TextEditingController();
    final appState = Provider.of<AppState>(context, listen: false);

    await showDialog(
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
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Share a File",
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: "Enter file name (e.g. Setlist.pdf)",
                    hintStyle: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel", style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        final name = controller.text.trim();
                        if (name.isNotEmpty) {
                          await appState.firebaseService.addBandFileAsync(bandId, name);
                          final files = await appState.firebaseService.getBandFilesAsync(bandId);
                          setState(() {
                            _files = files;
                          });
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text("Share", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
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
                    Navigator.pushNamed(
                      context,
                      '/sub-request-responses',
                      arguments: {'bandId': bandId},
                    );
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
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primaryAccent.withOpacity(0.3),
                    child: Text(
                      (m.nickname ?? 'M').substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
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
            Tab(text: 'Members'),
            Tab(text: 'Events'),
          ],
        ),

        // 4. Tab View Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildChatTab(),
              _buildFilesTab(),
              _buildMembersTab(),
              _buildEventsTab(),
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
          child: Row(
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
        ),
      ],
    );
  }

  Widget _buildChatBubble(Message msg) {
    final isMe = msg.isCurrentUserSender;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryAccent.withOpacity(0.3),
              child: Text(
                (msg.senderName ?? 'M').substring(0, 1).toUpperCase(),
                style: const TextStyle(fontSize: 11, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      msg.senderName ?? 'Member',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: AppTheme.primaryAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Container(
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
                  child: Text(
                    msg.text ?? '',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.3,
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
                      const SizedBox(width: 8),
                      // Small Heart Reaction Like Mockup
                      if (!isMe)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141029),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.favorite, color: Colors.redAccent, size: 10),
                              const SizedBox(width: 2),
                              Text(
                                '2',
                                style: GoogleFonts.inter(fontSize: 9, color: Colors.white),
                              )
                            ],
                          ),
                        )
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab() {
    final appState = Provider.of<AppState>(context, listen: false);
    final bandId = appState.activeBandId;
    if (bandId == null) return const Center(child: Text("No band selected"));

    return Column(
      children: [
        Expanded(
          child: _files.isEmpty
              ? const Center(
                  child: Text(
                    "No files shared yet.",
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _files.length,
                  itemBuilder: (context, index) {
                    final fileId = _files.keys.elementAt(index);
                    final fileName = _files[fileId];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF231F45), width: 1),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.insert_drive_file_outlined, color: AppTheme.primaryAccent, size: 28),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              fileName ?? 'Shared File',
                              style: GoogleFonts.inter(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w500),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              await appState.firebaseService.removeBandFileAsync(bandId, fileId);
                              final files = await appState.firebaseService.getBandFilesAsync(bandId);
                              setState(() {
                                _files = files;
                              });
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: AnimatedTapDetector(
            onTap: () => _showAddFileDialog(bandId),
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
                      "Share a File",
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
              return Container(
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
                  ],
                ),
              );
            },
          ),
        ),
      ],
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
