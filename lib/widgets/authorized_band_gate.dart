import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/band.dart';
import '../providers/app_state.dart';
import 'gradient_scaffold.dart';
import 'band_required_prompt.dart';

class NoBandState extends StatelessWidget {
  final bool staffing;
  final bool managerRequired;
  const NoBandState({super.key, this.staffing = false, this.managerRequired = false});

  static const staffingTitle = BandRequiredDialog.title;
  static const staffingBody = BandRequiredDialog.staffingBody;

  @override
  Widget build(BuildContext context) => SafeArea(child: Center(child: SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text(managerRequired ? 'Band leader or admin required' :
        staffing ? staffingTitle : 'You’re not in a band yet', textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      Text(managerRequired ? 'Ask a band leader or admin to manage staffing requests.' :
        staffing ? staffingBody : 'Create a band to start using Band Room, invite members and manage your band.',
        textAlign: TextAlign.center),
      const SizedBox(height: 20),
      if (!managerRequired) FilledButton(
        onPressed: () => Navigator.pushNamed(context, '/create-band'),
        child: const Text('Create a Band')),
      if (staffing) TextButton(onPressed: () => Navigator.maybePop(context), child: const Text('Cancel')),
    ]),
  )));
}

/// Validate before constructing a band-owned screen or any of its draft state.
class AuthorizedBandGate extends StatefulWidget {
  final String? requestedBandId;
  final bool staffing;
  final Widget Function(Band band) builder;
  const AuthorizedBandGate({super.key, this.requestedBandId,
    this.staffing = false, required this.builder});
  @override
  State<AuthorizedBandGate> createState() => _AuthorizedBandGateState();
}

class _AuthorizedBandGateState extends State<AuthorizedBandGate> {
  String? _requestKey;
  int _generation = 0;
  Band? _band;
  bool _loading = true;
  bool _failed = false;
  int? _promptedGeneration;
  bool? _sessionLoading;
  bool _reloadAfterSession = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensureResolved(Provider.of<AppState>(context));
  }

  @override
  void didUpdateWidget(covariant AuthorizedBandGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedBandId != widget.requestedBandId || oldWidget.staffing != widget.staffing) {
      _requestKey = null;
      _ensureResolved(Provider.of<AppState>(context, listen: false));
    }
  }

  void _ensureResolved(AppState state) {
    if (_sessionLoading == false && state.isLoading) {
      _requestKey = null;
      _generation++;
      _band = null;
      _reloadAfterSession = true;
    } else if (_sessionLoading == true && !state.isLoading && _reloadAfterSession) {
      _requestKey = null;
      _reloadAfterSession = false;
    }
    _sessionLoading = state.isLoading;
    // Verify in parallel with initial profile loading; rendering still stays neutral.
    final key = '${state.currentUserId}/${widget.requestedBandId ?? state.activeBandId}/${widget.staffing}';
    if (key == _requestKey) return;
    _requestKey = key;
    _band = null;
    _loading = true;
    _failed = false;
    _resolve(state);
  }

  Future<void> _resolve(AppState state) async {
    final generation = ++_generation;
    final uid = state.currentUserId;
    try {
      final band = await state.resolveAuthorizedBand(widget.requestedBandId,
        requireManager: widget.staffing);
      if (!mounted || generation != _generation || uid != state.currentUserId) return;
      setState(() { _band = band; _loading = false; });
    } catch (_) {
      if (!mounted || generation != _generation || uid != state.currentUserId) return;
      setState(() { _failed = true; _loading = false; });
    }
  }

  void _promptOrLeave(AppState state) {
    if (_promptedGeneration == _generation) return;
    _promptedGeneration = _generation;
    final generation = _generation;
    final uid = state.currentUserId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _generation || state.isLoading || _failed || _band != null) return;
      final create = uid != null && await BandRequiredPrompt.show(context, state, staffing: widget.staffing);
      if (!mounted || generation != _generation || uid != state.currentUserId || state.isLoading) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        if (create) navigator.pushNamed('/create-band');
      } else {
        navigator.pushReplacementNamed(create ? '/create-band' : '/main-nav');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = Provider.of<AppState>(context);
    if (_loading || state.isLoading) {
      return const GradientScaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_failed) {
      return GradientScaffold(body: Center(child: TextButton(
      onPressed: () { setState(() { _loading = true; _failed = false; }); _resolve(state); },
      child: const Text('Could not verify band membership. Retry'),
    )));
    }
    if (_band == null) {
      if (state.hasAuthorizedBand) {
        if (widget.staffing) {
          return const GradientScaffold(body: NoBandState(staffing: true, managerRequired: true));
        }
        return GradientScaffold(body: Center(child: TextButton(
          onPressed: () { setState(() { _loading = true; _failed = false; }); _resolve(state); },
          child: const Text('Could not verify band membership. Retry'),
        )));
      }
      _promptOrLeave(state);
      // Neutral backdrop while the shared prompt is shown; no protected content is built.
      return const GradientScaffold(body: Center(child: CircularProgressIndicator()));
    }
    return KeyedSubtree(key: ValueKey('${state.currentUserId}/${_band!.id}'),
      child: widget.builder(_band!));
  }
}
