import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/request_management_access.dart';
import '../providers/app_state.dart';
import '../services/firebase_service.dart';

class RequestManagementGate extends StatefulWidget {
  const RequestManagementGate({
    super.key,
    this.bandId,
    this.requestId,
    this.expectedCreatorId,
    this.hideWhenDenied = false,
    required this.builder,
  });
  final String? bandId, requestId, expectedCreatorId;
  final bool hideWhenDenied;
  final Widget Function(RequestManagementAccess access) builder;
  @override
  State<RequestManagementGate> createState() => _RequestManagementGateState();
}

class _RequestManagementGateState extends State<RequestManagementGate> {
  AppState? _state;
  String? _uid, _selectedBand;
  int _generation = 0;
  bool _checking = true;
  bool _lookupFailed = false;
  RequestManagementAccess? _access;
  StreamSubscription<bool>? _permission;
  StreamSubscription<String?>? _identity;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = Provider.of<AppState>(context, listen: false);
    if (identical(state, _state)) return;
    _state?.removeListener(_contextChanged);
    _state = state;
    _uid = state.currentUserId;
    _selectedBand = state.activeBandId;
    state.addListener(_contextChanged);
    unawaited(_identity?.cancel());
    try {
      _identity = state.firebaseService.catalogueIdentityChanges.listen((uid) {
        if (uid != _uid) _deny();
      }, onError: (Object _) => _deny());
    } catch (_) {
      _deny(lookupFailed: true);
      return;
    }
    unawaited(_authorize());
  }

  @override
  void didUpdateWidget(RequestManagementGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bandId != widget.bandId ||
        oldWidget.requestId != widget.requestId ||
        oldWidget.expectedCreatorId != widget.expectedCreatorId) {
      unawaited(_authorize());
    }
  }

  void _contextChanged() {
    final state = _state!;
    if (state.currentUserId == _uid && state.activeBandId == _selectedBand) {
      if (widget.hideWhenDenied && !_checking && _access == null) {
        unawaited(_authorize());
      }
      return;
    }
    _uid = state.currentUserId;
    _selectedBand = state.activeBandId;
    _deny();
    if (widget.hideWhenDenied) unawaited(_authorize());
  }

  void _deny({bool lookupFailed = false}) {
    _access?.revoke();
    _generation++;
    unawaited(_permission?.cancel());
    _permission = null;
    if (mounted) {
      setState(() {
        _access = null;
        _checking = false;
        _lookupFailed = lookupFailed;
      });
    }
  }

  Future<void> _authorize() async {
    _access?.revoke();
    final generation = ++_generation;
    unawaited(_permission?.cancel());
    _permission = null;
    setState(() {
      _access = null;
      _checking = true;
      _lookupFailed = false;
    });
    final state = _state!;
    final uid = state.currentUserId, selectedBand = state.activeBandId;
    bool current() =>
        mounted &&
        generation == _generation &&
        uid == state.currentUserId &&
        selectedBand == state.activeBandId;
    try {
      final access = await state.firebaseService.authorizeRequestManagement(
        bandId: widget.bandId,
        requestId: widget.requestId,
        expectedCreatorId: widget.expectedCreatorId,
        isCurrent: current,
      );
      if (!current()) return;
      if (uid == null || access.userId != uid) {
        _deny();
        return;
      }
      _permission = state.firebaseService
          .watchRequestManagementAccess(access)
          .listen(
            (allowed) {
              if (current() && !allowed) _deny();
            },
            onError: (Object _) {
              if (current()) _deny();
            },
          );
      if (current()) {
        setState(() {
          _access = access;
          _checking = false;
        });
      }
    } on PrivateDataAccessException {
      if (current()) _deny();
    } catch (_) {
      if (current()) _deny(lookupFailed: true);
    }
  }

  @override
  void dispose() {
    _access?.revoke();
    _generation++;
    _state?.removeListener(_contextChanged);
    unawaited(_permission?.cancel());
    unawaited(_identity?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_access != null) {
      return KeyedSubtree(
        key: ValueKey(_generation),
        child: widget.builder(_access!),
      );
    }
    if (widget.hideWhenDenied) {
      if (!_lookupFailed) return const SizedBox.shrink();
      return const Tooltip(
        message: 'Request management is unavailable. Please try again.',
        child: Icon(
          Icons.info_outline,
          semanticLabel: 'Request management is unavailable. Please try again.',
        ),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _checking
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        liveRegion: true,
                        child: const Text(
                          'Request management is unavailable for your current access.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
