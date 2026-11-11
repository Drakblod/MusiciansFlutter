import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sub_request.dart';
import '../services/firebase_service.dart';
import '../views/band_room_chat_screen.dart';
import '../views/band_section_chat_screen.dart';
import '../views/chat_detail_screen.dart';
import '../views/event_details_page.dart';
import '../views/session_details_screen.dart';
import '../views/sub_request_details_screen.dart';
import '../views/sub_request_response_details_screen.dart';
import 'sub_request_card_helper.dart';

class NotificationRouter {
  NotificationRouter(this.service, this.navigator, {
    required this.selectBand, this.isReady,
  });

  final FirebaseService service;
  final NavigatorState? Function() navigator;
  final void Function(String id) selectBand;
  final bool Function()? isReady;
  String? _pendingNativeId;
  String? _pendingOwner;
  bool _pendingUnavailable = false;
  final _opening = <(String, String, String?)>{};
  final _openedNative = <(String, String)>{};
  final _foregroundSeen = <(String, String)>{};
  StreamSubscription<String?>? _foregroundIdentity;
  OverlayEntry? _foregroundBanner;
  Timer? _foregroundTimeout;

  String? _nativeId(Map<String, dynamic> payload) {
    final id = payload['notificationId'];
    return payload['schemaVersion'] == '2' &&
            id is String &&
            RegExp(r'^[a-f0-9]{64}$').hasMatch(id)
        ? id
        : null;
  }

  void receiveNativeOpen(Map<String, dynamic> payload) {
    _pendingNativeId = _nativeId(payload);
    _pendingOwner = service.currentUserId;
    _pendingUnavailable = _pendingNativeId == null;
    resumeNativeOpen();
  }

  void resumeNativeOpen() {
    final uid = service.currentUserId;
    if (uid == null || navigator() == null || isReady?.call() == false) return;
    final id = _pendingNativeId;
    final owner = _pendingOwner;
    final unavailable = _pendingUnavailable;
    _pendingNativeId = null;
    _pendingOwner = null;
    _pendingUnavailable = false;
    if (unavailable || (owner != null && owner != uid)) {
      _unavailable();
    } else if (id != null && _remember(_openedNative, (uid, id))) {
      unawaited(open(id));
    }
  }

  bool _remember(Set<(String, String)> entries, (String, String) key) {
    if (!entries.add(key)) return false;
    if (entries.length > 100) entries.remove(entries.first);
    return true;
  }

  Future<void> receiveForeground(Map<String, dynamic> payload) async {
    final uid = service.currentUserId;
    final id = _nativeId(payload);
    if (uid == null || id == null || isReady?.call() == false ||
        !_remember(_foregroundSeen, (uid, id))) {
      return;
    }
    try {
      final result = await service.resolveNotificationAsync(id, preview: true);
      final nav = navigator();
      if (nav == null || uid != service.currentUserId) return;
      final title = result['title'];
      final body = result['body'];
      if (title is! String || title.isEmpty) return;
      final overlay = nav.overlay;
      if (overlay == null || !overlay.mounted) return;
      clearForeground();
      final banner = OverlayEntry(builder: (context) => SafeArea(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              elevation: 6,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: ListTile(
                  title: Text(body is String && body.isNotEmpty ? '$title\n$body' : title),
                  trailing: TextButton(onPressed: () {
                    clearForeground();
                    if (service.currentUserId == uid) unawaited(open(id));
                  }, child: const Text('Open')),
                ),
              ),
            ),
          ),
        ),
      ));
      overlay.insert(banner);
      _foregroundBanner = banner;
      _foregroundTimeout = Timer(const Duration(seconds: 4), clearForeground);
      _foregroundIdentity = service.catalogueIdentityChanges.listen((next) {
        if (next != uid) clearForeground();
      }, onError: (Object _) => clearForeground());
    } catch (_) {
      // Foreground previews are optional and require current authorization.
    }
  }

  void clearForeground() {
    final banner = _foregroundBanner;
    _foregroundBanner = null;
    banner?.remove();
    banner?.dispose();
    _foregroundTimeout?.cancel();
    _foregroundTimeout = null;
    unawaited(_foregroundIdentity?.cancel());
    _foregroundIdentity = null;
  }

  Future<void> open(String id, {String? slotId}) async {
    final uid = service.currentUserId;
    if (uid == null) {
      _unavailable();
      return;
    }
    final key = (uid, id, slotId);
    if (!_opening.add(key)) return;
    try {
      final route = await service.resolveNotificationAsync(id, slotId: slotId);
      if (service.currentUserId != uid) return;
      final nav = navigator();
      if (nav == null) return;
      final destination = await _destination(uid, id, route);
      if (!nav.mounted || service.currentUserId != uid) return;
      if (destination == null) {
        _unavailable();
        return;
      }
      unawaited(service.markNotificationReadAsync(id).catchError((Object _) {}));
      unawaited(nav.push(MaterialPageRoute<void>(
        builder: (_) => _NotificationSession(
          service: service,
          uid: uid,
          child: destination,
        ),
      )));
    } catch (_) {
      if (service.currentUserId == uid) _unavailable();
    } finally {
      _opening.remove(key);
    }
  }

  Future<Widget?> _destination(
    String uid, String id, Map<String, dynamic> route,
  ) async {
    final bandId = route['bandId'] as String?;
    switch (route['kind']) {
      case 'request':
      case 'response':
        final raw = route['request'];
        if (raw is! Map || raw['id'] is! String) return null;
        final request = SubRequest.fromJson(raw, raw['id'] as String);
        if (isSubRequestExpired(request)) return null;
        if (route['kind'] == 'response') {
          final responder = route['responderId'];
          if (responder is! String || responder.isEmpty) return null;
          return SubRequestResponseDetailsScreen(
            subRequest: request, initialResponderId: responder,
          );
        }
        return SubRequestDetailsScreen(subRequest: request);
      case 'group':
        final matches = route['matches'];
        if (matches is! List || matches.length < 2) return null;
        return Scaffold(
          appBar: AppBar(title: const Text('Matching gig requests')),
          body: ListView(
            children: [
              for (final item in matches.whereType<Map>())
                if (item['id'] is String && item['label'] is String)
                  ListTile(
                    title: Text(item['label'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (service.currentUserId == uid) {
                        unawaited(open(id, slotId: item['id'] as String));
                      }
                    },
                  ),
            ],
          ),
        );
      case 'event':
        final eventId = route['eventId'] as String?;
        if (bandId == null || eventId == null) return null;
        final event = await service.getNotificationEventAsync(
          bandId, eventId, memberAccess: route['memberAccess'] == true,
        );
        if (event == null) return null;
        return EventDetailsPage(bandId: bandId, eventId: eventId, initialEvent: event);
      case 'other':
        final conversationId = route['conversationId'] as String?;
        switch (route['type']) {
          case 'band_section_chat':
            if (conversationId == null || bandId == null) return null;
            return BandSectionChatScreen(conversationId: conversationId, bandId: bandId);
          case 'direct_message':
          case 'session_message':
            if (conversationId == null) return null;
            return ChatDetailScreen(
              conversationId: conversationId,
              receiverId: route['otherUserId'] as String? ?? '',
              receiverName: route['title'] as String,
            );
          case 'session_application':
          case 'session_application_status':
            final sessionId = route['sessionId'] as String?;
            if (sessionId == null) return null;
            final session = await service.getNotificationSessionAsync(sessionId);
            return session == null ? null : SessionDetailsScreen(session: session);
          case 'band_room_message':
          case 'band_file_uploaded':
            if (bandId == null || service.currentUserId != uid) return null;
            selectBand(bandId);
            return const BandRoomChatScreen();
        }
    }
    return null;
  }

  void _unavailable() {
    final nav = navigator();
    if (nav == null) return;
    ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
      const SnackBar(content: Text('This notification is unavailable.')),
    );
  }
}

class _NotificationSession extends StatefulWidget {
  const _NotificationSession({
    required this.service, required this.uid, required this.child,
  });

  final FirebaseService service;
  final String uid;
  final Widget child;

  @override
  State<_NotificationSession> createState() => _NotificationSessionState();
}

class _NotificationSessionState extends State<_NotificationSession> {
  late final StreamSubscription<String?> _identity;
  bool _revoked = false;

  @override
  void initState() {
    super.initState();
    _identity = widget.service.catalogueIdentityChanges.listen((uid) {
      if (mounted && !_revoked && uid != widget.uid) {
        setState(() => _revoked = true);
      }
    });
  }

  @override
  void dispose() {
    unawaited(_identity.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_revoked || widget.service.currentUserId != widget.uid) {
      return const Scaffold(body: Center(child: Text('This notification is unavailable.')));
    }
    return widget.child;
  }
}
