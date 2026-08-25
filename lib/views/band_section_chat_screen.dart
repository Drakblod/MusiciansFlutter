import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/band.dart';
import '../models/message.dart';
import '../models/user_profile.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../utils/band_section_utils.dart';
import '../widgets/animated_tap_detector.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class BandSectionChatScreen extends StatefulWidget {
  final String conversationId;
  final String? bandId;
  final String? initialGroupName;

  const BandSectionChatScreen({
    super.key,
    required this.conversationId,
    this.bandId,
    this.initialGroupName,
  });

  @override
  State<BandSectionChatScreen> createState() => _BandSectionChatScreenState();
}

class _BandSectionChatScreenState extends State<BandSectionChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  String? _replyToText;
  String? _replyToSenderName;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Mark as read upon entering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.firebaseService.markBandSectionConversationReadAsync(widget.conversationId);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    final appState = Provider.of<AppState>(context, listen: false);
    setState(() => _isSending = true);

    _messageController.clear();
    final replyText = _replyToText;
    final replySender = _replyToSenderName;
    setState(() {
      _replyToText = null;
      _replyToSenderName = null;
    });

    try {
      await appState.firebaseService.sendBandSectionMessageAsync(
        conversationId: widget.conversationId,
        text: text,
        replyToText: replyText,
        replyToSenderName: replySender,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showGroupInfoModal(Map<String, dynamic> metadata) async {
    final appState = Provider.of<AppState>(context, listen: false);
    final selfId = appState.currentUserId;
    final bandId = metadata['bandId'] as String? ?? widget.bandId ?? '';
    final groupName = metadata['groupName'] as String? ?? 'Section Chat';
    final participantsMap = (metadata['participants'] as Map?) ?? {};
    final adminsMap = (metadata['admins'] as Map?) ?? {};
    final isGroupAdmin = selfId != null && (adminsMap[selfId] == true || metadata['createdBy'] == selfId);

    // Fetch band members to check band admin roles
    List<BandMember> allBandMembers = [];
    bool isBandAdmin = false;
    try {
      allBandMembers = await appState.firebaseService.getBandMembersAsync(bandId);
      final myBandMember = allBandMembers.cast<BandMember?>().firstWhere(
            (m) => m?.userId == selfId,
            orElse: () => null,
          );
      final role = myBandMember?.role;
      isBandAdmin = role == 'Leader' || role == 'Admin' || role == 'MOD';
    } catch (_) {}

    final canManage = isGroupAdmin || isBandAdmin;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16132D),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: Color(0xFF2E2452), width: 1.2),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            groupName,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (canManage)
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppTheme.primaryAccent, size: 20),
                            tooltip: 'Rename Group',
                            onPressed: () async {
                              final nameCtrl = TextEditingController(text: groupName);
                              final newName = await showDialog<String>(
                                context: context,
                                builder: (dCtx) => AlertDialog(
                                  backgroundColor: AppTheme.cardBackground,
                                  title: Text('Rename Group', style: GoogleFonts.outfit(color: Colors.white)),
                                  content: TextField(
                                    controller: nameCtrl,
                                    maxLength: 80,
                                    style: GoogleFonts.inter(color: Colors.white),
                                    decoration: const InputDecoration(hintText: 'Enter new group name'),
                                  ),
                                  actions: [
                                    TextButton(
                                      child: const Text('Cancel'),
                                      onPressed: () => Navigator.pop(dCtx),
                                    ),
                                    ElevatedButton(
                                      child: const Text('Save'),
                                      onPressed: () => Navigator.pop(dCtx, nameCtrl.text.trim()),
                                    ),
                                  ],
                                ),
                              );
                              if (newName != null && newName.isNotEmpty && newName != groupName) {
                                await appState.firebaseService.manageBandSectionConversationAsync(
                                  conversationId: widget.conversationId,
                                  action: 'rename',
                                  groupName: newName,
                                );
                                if (mounted) Navigator.pop(ctx);
                              }
                            },
                          ),
                      ],
                    ),
                    Text(
                      '${metadata['bandName'] ?? "Band"} • ${participantsMap.length} participants',
                      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Participants',
                      style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2E2452)),
                      ),
                      child: ListView(
                        shrinkWrap: true,
                        children: participantsMap.keys.map((uid) {
                          final memberUid = uid.toString();
                          final isUserMe = memberUid == selfId;
                          final isMemberAdmin = adminsMap[memberUid] == true;
                          final memberObj = allBandMembers.cast<BandMember?>().firstWhere(
                                (m) => m?.userId == memberUid,
                                orElse: () => null,
                              );
                          final displayName = memberObj?.nickname ?? 'Musician';

                          return ListTile(
                            dense: true,
                            title: Text(
                              isUserMe ? '$displayName (You)' : displayName,
                              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isMemberAdmin)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryAccent.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Admin',
                                      style: GoogleFonts.inter(color: AppTheme.primaryAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                if (canManage && !isUserMe && participantsMap.length > 2)
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 18),
                                    tooltip: 'Remove from group',
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: AppTheme.cardBackground,
                                          title: Text('Remove Member', style: GoogleFonts.outfit(color: Colors.white)),
                                          content: Text('Remove $displayName from this section group?', style: GoogleFonts.inter(color: Colors.white70)),
                                          actions: [
                                            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(dCtx, false)),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                                              child: const Text('Remove'),
                                              onPressed: () => Navigator.pop(dCtx, true),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await appState.firebaseService.manageBandSectionConversationAsync(
                                          conversationId: widget.conversationId,
                                          action: 'removeParticipants',
                                          participantIds: [memberUid],
                                        );
                                        if (mounted) Navigator.pop(ctx);
                                      }
                                    },
                                  ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (canManage) ...[
                      // Add members button
                      OutlinedButton.icon(
                        icon: const Icon(Icons.person_add_outlined, size: 18),
                        label: const Text('Add Band Members'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.primaryAccent,
                          side: const BorderSide(color: AppTheme.primaryAccent),
                        ),
                        onPressed: () async {
                          final unaddedMembers = allBandMembers.where((m) => m.userId != null && !participantsMap.containsKey(m.userId!)).toList();
                          if (unaddedMembers.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('All band members are already in this group.')),
                            );
                            return;
                          }

                          final selectedToAdd = <String>{};
                          final added = await showDialog<bool>(
                            context: context,
                            builder: (dCtx) => StatefulBuilder(
                              builder: (context, setDialogState) => AlertDialog(
                                backgroundColor: AppTheme.cardBackground,
                                title: Text('Add Members', style: GoogleFonts.outfit(color: Colors.white)),
                                content: SizedBox(
                                  width: double.maxFinite,
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: unaddedMembers.map((m) {
                                      final uid = m.userId!;
                                      final isSelected = selectedToAdd.contains(uid);
                                      return CheckboxListTile(
                                        title: Text(m.nickname ?? 'Member', style: GoogleFonts.inter(color: Colors.white)),
                                        value: isSelected,
                                        activeColor: AppTheme.primaryAccent,
                                        onChanged: (val) {
                                          setDialogState(() {
                                            if (val == true) selectedToAdd.add(uid);
                                            else selectedToAdd.remove(uid);
                                          });
                                        },
                                      );
                                    }).toList(),
                                  ),
                                ),
                                actions: [
                                  TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(dCtx, false)),
                                  ElevatedButton(
                                    child: const Text('Add Selected'),
                                    onPressed: () => Navigator.pop(dCtx, true),
                                  ),
                                ],
                              ),
                            ),
                          );

                          if (added == true && selectedToAdd.isNotEmpty) {
                            await appState.firebaseService.manageBandSectionConversationAsync(
                              conversationId: widget.conversationId,
                              action: 'addParticipants',
                              participantIds: selectedToAdd.toList(),
                            );
                            if (mounted) Navigator.pop(ctx);
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Leave Group button
                    TextButton.icon(
                      icon: const Icon(Icons.exit_to_app, color: Colors.redAccent, size: 18),
                      label: Text('Leave Group', style: GoogleFonts.inter(color: Colors.redAccent)),
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (dCtx) => AlertDialog(
                            backgroundColor: AppTheme.cardBackground,
                            title: Text('Leave Group', style: GoogleFonts.outfit(color: Colors.white)),
                            content: const Text('Are you sure you want to leave this section group?', style: TextStyle(color: Colors.white70)),
                            actions: [
                              TextButton(child: const Text('Cancel'), onPressed: () => Navigator.pop(dCtx, false)),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                                child: const Text('Leave'),
                                onPressed: () => Navigator.pop(dCtx, true),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          await appState.firebaseService.manageBandSectionConversationAsync(
                            conversationId: widget.conversationId,
                            action: 'leave',
                          );
                          if (mounted) {
                            Navigator.pop(ctx); // close sheet
                            Navigator.pop(context); // exit chat screen
                          }
                        }
                      },
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

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final selfId = appState.currentUserId;

    return StreamBuilder<Map<String, dynamic>?>(
      stream: appState.firebaseService.subscribeToBandSectionMetadata(widget.conversationId),
      builder: (context, metaSnap) {
        final metadata = metaSnap.data;

        // Check if access was revoked or user was removed
        if (metadata != null) {
          final participantsMap = (metadata['participants'] as Map?) ?? {};
          if (selfId != null && !participantsMap.containsKey(selfId)) {
            return GradientScaffold(
              appBar: const CustomTopBar(showBack: true),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.lock_outline, color: Colors.redAccent, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'Access Denied',
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You are no longer a participant or active member of this band section group.',
                        style: GoogleFonts.inter(color: AppTheme.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Back to Messages'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
        }

        final groupName = metadata?['groupName'] as String? ?? widget.initialGroupName ?? 'Section Chat';
        final bandName = metadata?['bandName'] as String? ?? 'Band';
        final participantCount = metadata?['participantCount'] is int
            ? metadata!['participantCount'] as int
            : int.tryParse(metadata?['participantCount']?.toString() ?? '0') ?? 0;

        return GradientScaffold(
          appBar: const CustomTopBar(showBack: true),
          body: Column(
            children: [
              // Custom Header Bar
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xCC0F0C22),
                      border: Border(
                        bottom: BorderSide(color: Color(0xFF231F45), width: 1.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.primaryAccent.withOpacity(0.2),
                          child: const Icon(
                            Icons.groups_rounded,
                            color: AppTheme.primaryAccent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                groupName,
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$bandName • $participantCount members',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppTheme.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (metadata != null)
                          IconButton(
                            icon: const Icon(Icons.info_outline, color: Colors.white70),
                            tooltip: 'Group Info & Members',
                            onPressed: () => _showGroupInfoModal(metadata),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // Messages Stream
              Expanded(
                child: StreamBuilder<List<Message>>(
                  stream: appState.firebaseService.subscribeToMessages(widget.conversationId),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryAccent),
                      );
                    }

                    final messages = snapshot.data ?? [];

                    // Auto mark as read when messages update
                    if (messages.isNotEmpty) {
                      appState.firebaseService.markBandSectionConversationReadAsync(widget.conversationId);
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    if (messages.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.groups_outlined,
                              size: 48,
                              color: AppTheme.textSecondary.withOpacity(0.4),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No messages in this group yet.',
                              style: GoogleFonts.inter(color: AppTheme.textSecondary),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.isCurrentUserSender;
                        final senderName = msg.senderName ?? 'Musician';
                        final timestampStr = msg.timestamp != null ? DateFormat('HH:mm').format(msg.timestamp!) : '';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8, bottom: 4),
                                  child: Text(
                                    senderName,
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.primaryAccent,
                                    ),
                                  ),
                                ),
                              Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: isMe ? AppTheme.primaryAccent : const Color(0xFF1E1A3A),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMe ? 16 : 4),
                                          bottomRight: Radius.circular(isMe ? 4 : 16),
                                        ),
                                        border: isMe ? null : Border.all(color: const Color(0xFF2E2452)),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          if (msg.replyToText != null) ...[
                                            Container(
                                              margin: const EdgeInsets.only(bottom: 6),
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.black26,
                                                borderRadius: BorderRadius.circular(6),
                                                border: const Border(
                                                  left: BorderSide(color: Colors.white54, width: 3),
                                                ),
                                              ),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  if (msg.replyToSenderName != null)
                                                    Text(
                                                      msg.replyToSenderName!,
                                                      style: GoogleFonts.inter(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.white70,
                                                      ),
                                                    ),
                                                  Text(
                                                    msg.replyToText!,
                                                    style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          Text(
                                            msg.text ?? '',
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Align(
                                            alignment: Alignment.bottomRight,
                                            child: Text(
                                              timestampStr,
                                              style: GoogleFonts.inter(
                                                fontSize: 9,
                                                color: isMe ? Colors.white70 : AppTheme.textMuted,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // Reply action
                                  IconButton(
                                    icon: const Icon(Icons.reply, size: 16, color: Colors.white30),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'Reply',
                                    onPressed: () {
                                      setState(() {
                                        _replyToText = msg.text;
                                        _replyToSenderName = isMe ? 'You' : senderName;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Reply banner
              if (_replyToText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFF1F1A3F),
                  child: Row(
                    children: [
                      const Icon(Icons.reply, size: 16, color: AppTheme.primaryAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Replying to ${_replyToSenderName ?? "message"}',
                              style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primaryAccent),
                            ),
                            Text(
                              _replyToText!,
                              style: GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.white70),
                        onPressed: () => setState(() {
                          _replyToText = null;
                          _replyToSenderName = null;
                        }),
                      ),
                    ],
                  ),
                ),

              // Composer input
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF130E26),
                  border: Border(
                    top: BorderSide(color: Color(0xFF231F45)),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.cardBackground,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF2E2452)),
                          ),
                          child: TextField(
                            controller: _messageController,
                            style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: 'Message section...',
                              hintStyle: GoogleFonts.inter(color: AppTheme.textMuted, fontSize: 14),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AnimatedTapDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: _isSending
                              ? const Center(
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
