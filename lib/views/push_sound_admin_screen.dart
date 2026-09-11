import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../providers/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/custom_top_bar.dart';
import '../widgets/gradient_scaffold.dart';

class PushSoundAdminScreen extends StatefulWidget {
  const PushSoundAdminScreen({super.key});

  @override
  State<PushSoundAdminScreen> createState() => _PushSoundAdminScreenState();
}

class _PushSoundAdminScreenState extends State<PushSoundAdminScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _tokenController = TextEditingController();
  String? _currentlyPlayingId;
  String? _pushToken;
  String _permissionStatus = "Checking...";
  bool _isFetchingToken = false;
  bool _broadcastToAll = false;
  final Map<String, bool> _isSendingPush = {};
  final List<String> _activityLogs = [];
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  final List<Map<String, dynamic>> _soundItems = [
    {
      'id': 'gig_rquest',
      'title': 'Gig Request',
      'icon': Icons.music_note_rounded,
      'color': const Color(0xFFE94560),
      'channel': 'gig_request_channel',
      'androidSound': 'gig_rquest.mp3',
      'iosSound': 'gig_rquest.wav',
      'duration': '6.86s',
      'assetPath': 'audio/gig_rquest.mp3',
      'description': 'Dispatched when new substitute requests or open calls are broadcast to musicians.',
    },
    {
      'id': 'gig_rquest_response',
      'title': 'Gig Response',
      'icon': Icons.reply_rounded,
      'color': const Color(0xFF00ADB5),
      'channel': 'gig_response_channel',
      'androidSound': 'gig_rquest_response.mp3',
      'iosSound': 'gig_rquest_response.wav',
      'duration': '5.14s',
      'assetPath': 'audio/gig_rquest_response.mp3',
      'description': 'Dispatched when a musician submits an application or response to a gig.',
    },
    {
      'id': 'reminder_rsvp',
      'title': 'RSVP Reminder',
      'icon': Icons.alarm_rounded,
      'color': const Color(0xFFFFB830),
      'channel': 'rsvp_reminder_channel',
      'androidSound': 'reminder_rsvp.mp3',
      'iosSound': 'reminder_rsvp.wav',
      'duration': '8.57s',
      'assetPath': 'audio/reminder_rsvp.mp3',
      'description': 'Dispatched for impending event reminders and RSVP threshold warnings.',
    },
    {
      'id': 'finalized_gig',
      'title': 'Finalized Gig',
      'icon': Icons.check_circle_outline_rounded,
      'color': const Color(0xFF4ECCA3),
      'channel': 'finalized_gig_channel',
      'androidSound': 'finalized_gig.mp3',
      'iosSound': 'finalized_gig.wav',
      'duration': '10.29s',
      'assetPath': 'audio/finalized_gig.mp3',
      'description': 'Dispatched when a substitute is confirmed and the gig is officially booked/locked.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadPushTokenAndPermission();
    _setupAudioPlayerListeners();
    _setupForegroundMessageListener();
  }

  void _setupAudioPlayerListeners() {
    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _currentlyPlayingId = null;
        });
      }
    });
  }

  void _setupForegroundMessageListener() {
    if (kIsWeb) return;
    try {
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (mounted) {
          final timeStr = TimeOfDay.now().format(context);
          setState(() {
            _activityLogs.insert(0, '[$timeStr] Foreground push received: "${message.notification?.title ?? "No title"}" (Sound: ${message.data['soundType'] ?? "N/A"})');
          });
        }
      });
    } catch (e) {
      debugPrint("Foreground message subscription skipped: $e");
    }
  }

  Future<void> _loadPushTokenAndPermission() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _permissionStatus = 'Web Mode';
          _pushToken = null;
          _isFetchingToken = false;
        });
      }
      return;
    }
    setState(() => _isFetchingToken = true);
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.getNotificationSettings();

      String statusStr = 'Not Determined';
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        statusStr = 'Authorized';
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        statusStr = 'Provisional';
      } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
        statusStr = 'Denied';
      }

      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
        String? apnsToken = await messaging.getAPNSToken();
        int attempts = 0;
        while (apnsToken == null && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 500));
          apnsToken = await messaging.getAPNSToken();
          attempts++;
        }
      }

      final token = await messaging.getToken();

      if (mounted) {
        setState(() {
          _permissionStatus = statusStr;
          _pushToken = token;
          if (token != null && token.isNotEmpty) {
            _tokenController.text = token;
          }
          _isFetchingToken = false;
        });

        if (token != null && token.isNotEmpty) {
          final appState = Provider.of<AppState>(context, listen: false);
          await appState.firebaseService.savePushTokenAsync(token);
        }
      }
    } catch (e) {
      debugPrint("Push token fetch error: $e");
      if (mounted) {
        setState(() {
          _permissionStatus = 'Unavailable';
          _pushToken = null;
          _isFetchingToken = false;
        });
      }
    }
  }

  Future<void> _requestPermissionsAgain() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Push notifications are configured for Android and iOS devices."),
            backgroundColor: AppTheme.primaryAccent,
          ),
        );
      }
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      await _loadPushTokenAndPermission();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Permission status: ${settings.authorizationStatus.name}"),
            backgroundColor: AppTheme.primaryAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to request permissions: $e"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _togglePreviewSound(String id, String assetPath) async {
    try {
      if (_currentlyPlayingId == id) {
        await _audioPlayer.stop();
        setState(() {
          _currentlyPlayingId = null;
        });
      } else {
        await _audioPlayer.stop();
        setState(() {
          _currentlyPlayingId = id;
        });
        await _audioPlayer.play(AssetSource(assetPath));
      }
    } catch (e) {
      debugPrint("Audio playback error: $e");
      setState(() {
        _currentlyPlayingId = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error playing audio: $e"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _sendTestPush(String soundType, String soundTitle) async {
    final isBroadcast = _broadcastToAll;
    final tokenToUse = _tokenController.text.trim();
    if (!isBroadcast && kIsWeb && tokenToUse.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              "⚠️ Web cannot receive system tray pushes. To test from Chrome, paste an Android/iOS FCM token above or switch on Broadcast Mode.",
            ),
            backgroundColor: Colors.amber.shade900,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final appState = Provider.of<AppState>(context, listen: false);

    setState(() {
      _isSendingPush[soundType] = true;
    });

    try {
      final timeStr = TimeOfDay.now().format(context);
      final result = await appState.firebaseService.sendTestPushNotificationAsync(
        soundType: soundType,
        customToken: tokenToUse.isNotEmpty ? tokenToUse : null,
        broadcastToAll: isBroadcast,
      );

      if (result['success'] == false) {
        throw Exception(result['error'] ?? 'Unknown error sending push');
      }

      final messageId = result['messageId'] ?? 'OK';
      final isBroadcastResult = result['broadcast'] == true;
      final total = result['total'] ?? 0;
      final successCount = result['successCount'] ?? 0;
      final failureCount = result['failureCount'] ?? 0;

      if (mounted) {
        setState(() {
          if (isBroadcastResult) {
            _activityLogs.insert(
              0,
              '[$timeStr] BROADCAST "$soundTitle": $successCount/$total delivered ($failureCount failed)',
            );
          } else {
            _activityLogs.insert(
              0,
              '[$timeStr] Dispatched "$soundTitle" test push (Msg ID: $messageId)',
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isBroadcastResult
                  ? "🚀 Broadcast \"$soundTitle\" sent to $successCount active device(s)!"
                  : "🚀 Test push for \"$soundTitle\" sent! Lock screen or background app to hear the custom sound.",
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      final timeStr = TimeOfDay.now().format(context);
      if (mounted) {
        setState(() {
          _activityLogs.insert(0, '[$timeStr] FAILED "$soundTitle": $e');
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error sending test push: $e"),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingPush[soundType] = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _audioPlayer.dispose();
    _foregroundSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      appBar: const CustomTopBar(
        title: 'Push Sound Tester',
        showBack: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded, color: AppTheme.primaryAccent, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Push Sound Tester',
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 1. Device Token & Permissions Status Card
              _buildTokenStatusCard(),
              const SizedBox(height: 16),

              // How-to testing banner
              _buildInstructionBanner(),
              const SizedBox(height: 16),

              // Broadcast mode toggle
              _buildBroadcastToggleCard(),
              const SizedBox(height: 16),

              // Header for Sound Cards
              Text(
                'NOTIFICATION SOUNDS (4)',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: AppTheme.primaryAccent,
                ),
              ),
              const SizedBox(height: 12),

              // 2. Sound Cards
              ..._soundItems.map((item) => _buildSoundCard(item)),
              const SizedBox(height: 20),

              // 3. Activity Logs Console
              _buildActivityLogsCard(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenStatusCard() {
    final hasToken = _pushToken != null && _pushToken!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2A4E)),
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
                    const Icon(Icons.notifications_active_outlined, color: AppTheme.primaryAccent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Device Push Token',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _permissionStatus == 'Authorized'
                        ? AppTheme.success.withOpacity(0.2)
                        : Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _permissionStatus,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: _permissionStatus == 'Authorized' ? AppTheme.success : Colors.amber,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_isFetchingToken)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator(color: AppTheme.primaryAccent, strokeWidth: 2)),
            )
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF120E27),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF241F3D)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: kIsWeb
                            ? 'Paste target phone FCM token here to test push...'
                            : 'FCM push token will appear here...',
                        hintStyle: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: AppTheme.textSecondary.withOpacity(0.6),
                        ),
                      ),
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.paste_rounded, size: 18, color: AppTheme.primaryAccent),
                    tooltip: 'Paste Token',
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.trim().isNotEmpty) {
                        setState(() {
                          _tokenController.text = data.text!.trim();
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Token pasted into field!"),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18, color: AppTheme.primaryAccent),
                    tooltip: 'Copy Token',
                    onPressed: () {
                      final val = _tokenController.text.trim();
                      if (val.isNotEmpty) {
                        Clipboard.setData(ClipboardData(text: val));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("Push token copied to clipboard!"),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh Token', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF2E2A4E)),
                  ),
                  onPressed: _loadPushTokenAndPermission,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.security, size: 16),
                  label: const Text('Check Permissions', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primaryAccent,
                    side: const BorderSide(color: AppTheme.primaryAccent),
                  ),
                  onPressed: _requestPermissionsAgain,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryAccent.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primaryAccent.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppTheme.primaryAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '💡 Tip: To hear custom alert sounds from the system tray, tap "Send Test Push" and immediately lock your phone or switch to the Home screen.',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBroadcastToggleCard() {
    return Container(
      decoration: BoxDecoration(
        color: _broadcastToAll ? const Color(0xFF2E1A47) : AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _broadcastToAll ? AppTheme.primaryAccent : const Color(0xFF2E2A4E),
          width: _broadcastToAll ? 1.5 : 1,
        ),
      ),
      child: SwitchListTile(
        activeColor: AppTheme.primaryAccent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Row(
          children: [
            Icon(
              _broadcastToAll ? Icons.campaign_rounded : Icons.person_rounded,
              color: _broadcastToAll ? AppTheme.primaryAccent : Colors.white70,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              _broadcastToAll ? 'Broadcast to ALL Users' : 'Target: Single Device Only',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _broadcastToAll
                ? 'When enabled, pressing Send Push delivers this sound to EVERY registered phone (Android & iOS) simultaneously.'
                : 'Delivers only to the device token in the input box above.',
            style: GoogleFonts.inter(fontSize: 11, color: Colors.white60),
          ),
        ),
        value: _broadcastToAll,
        onChanged: (val) {
          setState(() {
            _broadcastToAll = val;
          });
        },
      ),
    );
  }

  Widget _buildSoundCard(Map<String, dynamic> item) {
    final String id = item['id'];
    final String title = item['title'];
    final IconData icon = item['icon'];
    final Color color = item['color'];
    final String duration = item['duration'];
    final String description = item['description'];
    final String assetPath = item['assetPath'];
    final String androidSound = item['androidSound'];
    final String iosSound = item['iosSound'];
    final String channel = item['channel'];

    final bool isPlaying = _currentlyPlayingId == id;
    final bool isSending = _isSendingPush[id] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPlaying ? color.withOpacity(0.8) : const Color(0xFF2E2A4E),
          width: isPlaying ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            duration,
                            style: GoogleFonts.inter(fontSize: 10, color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Android: $androidSound  •  iOS: $iosSound',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white70,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Channel ID: $channel',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: AppTheme.textSecondary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 14),

          // Action Buttons: Preview Sound & Send Test Push
          Row(
            children: [
              // Preview button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPlaying ? color : const Color(0xFF241F3D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: Icon(
                    isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isPlaying ? 'Playing...' : 'Preview',
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () => _togglePreviewSound(id, assetPath),
                ),
              ),
              const SizedBox(width: 10),

              // Send Push button
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color.withOpacity(0.85),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: isSending
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Icon(_broadcastToAll ? Icons.campaign_rounded : Icons.send_rounded, size: 16),
                  label: Text(
                    isSending
                        ? (_broadcastToAll ? 'Broadcasting...' : 'Sending...')
                        : (_broadcastToAll ? 'Broadcast Push' : 'Send Push'),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  onPressed: isSending ? null : () => _sendTestPush(id, title),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivityLogsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2E2A4E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.terminal_rounded, color: AppTheme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Activity Log',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              if (_activityLogs.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() => _activityLogs.clear()),
                  child: Text('Clear', style: GoogleFonts.inter(fontSize: 11, color: AppTheme.primaryAccent)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_activityLogs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  'No push events sent yet during this session.',
                  style: GoogleFonts.inter(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _activityLogs.length,
                separatorBuilder: (_, __) => const Divider(color: Color(0xFF241F3D), height: 1),
                itemBuilder: (context, index) {
                  final log = _activityLogs[index];
                  final isError = log.contains('FAILED');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      log,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: isError ? AppTheme.danger : Colors.white70,
                      ),
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
