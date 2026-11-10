import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/city_location.dart';
import '../services/city_search_service.dart';

/// Supplies an in-memory provider in widget/form tests without changing forms.
class CitySearchProviderScope extends InheritedWidget {
  final CitySearchProvider provider;
  const CitySearchProviderScope({super.key, required this.provider, required super.child});
  static CitySearchProvider? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CitySearchProviderScope>()?.provider;
  @override
  bool updateShouldNotify(CitySearchProviderScope oldWidget) => provider != oldWidget.provider;
}

/// Shared profile/band city picker. Raw search text is never a saved location.
class CityLocationPickerField extends StatefulWidget {
  final CityLocation? initialLocation;
  final bool requiredSelection;
  final String purpose;
  final String Function() targetId;
  final ValueChanged<CityLocation?> onChanged;
  final CitySearchProvider? provider;
  const CityLocationPickerField({
    super.key,
    this.initialLocation,
    this.requiredSelection = false,
    required this.purpose,
    required this.targetId,
    required this.onChanged,
    this.provider,
  });

  @override
  State<CityLocationPickerField> createState() =>
      CityLocationPickerFieldState();
}

class CityLocationPickerFieldState extends State<CityLocationPickerField> {
  late final TextEditingController _text;
  Timer? _debounce;
  Future<String>? _session;
  int _generation = 0;
  bool _programmatic = false, _loading = false;
  String? _error;
  CityLocation? _confirmed;
  List<CityCandidate> _suggestions = [];
  int _highlight = 0;
  CitySearchProvider get _provider => widget.provider ??
      CitySearchProviderScope.maybeOf(context) ?? const GooglePlacesCitySearchProvider();

  CityLocation? get confirmedLocation => _confirmed;
  Future<String> _getSession() => _session ??= _provider.createSession();

  @override
  void initState() {
    super.initState();
    _confirmed = widget.initialLocation;
    _text = TextEditingController(text: _confirmed?.label ?? '')
      ..addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(CityLocationPickerField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLocation != widget.initialLocation &&
        widget.initialLocation?.label != _confirmed?.label) {
      _confirmed = widget.initialLocation;
      _setText(_confirmed?.label ?? '');
      _suggestions = [];
    }
  }

  void _setText(String value) {
    _programmatic = true;
    _text.text = value;
    _programmatic = false;
  }

  void _onTextChanged() {
    if (_programmatic) return;
    _generation++;
    _debounce?.cancel();
    if (_confirmed != null) {
      _confirmed = null;
      widget.onChanged(null);
      _session = null;
    }
    final query = _text.text.trim();
    setState(() {
      _suggestions = [];
      _error = null;
      _loading = query.length >= 2;
      _highlight = 0;
    });
    if (query.length < 2) return;
    final generation = _generation;
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _search(query, generation),
    );
  }

  Future<void> _search(String query, int generation) async {
    try {
      final token=await _getSession();
      if(!mounted || generation != _generation)return;
      final result = await _provider.search(query, token);
      if (!mounted || generation != _generation) return;
      final seen = <String>{};
      setState(() {
        _suggestions = result.where((c) => seen.add(c.placeId)).toList();
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'City search unavailable. Try again.';
      });
    }
  }

  Future<void> _select(CityCandidate candidate) async {
    final generation = ++_generation;
    _debounce?.cancel();
    final authored = await _askForAuthoredCity(candidate);
    if (!mounted || generation != _generation || authored == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token=await _getSession();
      final result = await _provider.resolve(candidate, token,
        purpose:widget.purpose,targetId:widget.targetId(),
        city:authored['city']!,country:authored['country']!);
      if (!mounted || generation != _generation) return;
      if (result == null) {
        setState(() {
          _loading = false;
          _error = 'Select a city-level result.';
        });
        return;
      }
      _session = null;
      _confirmed = result;
      _setText(result.label);
      setState(() {
        _loading = false;
        _suggestions = [];
        _error = null;
      });
      widget.onChanged(result);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      _session = null;
      setState(() {
        _loading = false;
        _suggestions = [];
        _error = 'Could not confirm this city. Search again.';
      });
    }
  }

  Future<Map<String,String>?> _askForAuthoredCity(CityCandidate candidate) async {
    var city=candidate.city,country=candidate.country,missing=false;
    return showDialog<Map<String,String>>(
      context:context,
      builder:(dialogContext)=>StatefulBuilder(builder:(context,refresh){
        return AlertDialog(
          title:const Text('Confirm your city'),
          content:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text('Google Maps suggestion: ${candidate.label}'),
              Text('Google Maps',softWrap:false,style:TextStyle(
                fontFamily:'Roboto',fontSize:12,fontWeight:FontWeight.w400,
                color:Theme.of(context).brightness==Brightness.dark
                    ? Colors.white : const Color(0xFF1F1F1F))),
              const SizedBox(height:12),
              const Text('Confirm the city and country for your public location.'),
              TextFormField(initialValue:candidate.city,decoration:const InputDecoration(labelText:'City'),
                onChanged:(value)=>city=value),
              TextFormField(initialValue:candidate.country,decoration:const InputDecoration(labelText:'Country'),
                onChanged:(value)=>country=value),
              if(missing)const Text('Enter both city and country.'),
            ],
          )),
          actions:[TextButton(onPressed:()=>Navigator.pop(dialogContext),child:const Text('Cancel')),
            FilledButton(onPressed:(){
              if(city.trim().isEmpty||country.trim().isEmpty){
                refresh(()=>missing=true);return;
              }
              Navigator.pop(dialogContext,{'city':city.trim(),'country':country.trim()});
            },child:const Text('Confirm city'))],
        );
      }),
    );
  }

  void _clear() {
    _debounce?.cancel();
    _generation++;
    _session = null;
    _confirmed = null;
    _setText('');
    setState(() {
      _suggestions = [];
      _error = null;
      _loading = false;
    });
    widget.onChanged(null);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.removeListener(_onTextChanged);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || _suggestions.isEmpty) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          setState(() => _highlight = (_highlight + 1) % _suggestions.length);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          setState(
            () => _highlight =
                (_highlight - 1 + _suggestions.length) % _suggestions.length,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _text,
            decoration: InputDecoration(
              labelText: 'City / Location',
              hintText: 'Search for your city',
              suffixIcon: _text.text.isNotEmpty
                  ? IconButton(
                      onPressed: _clear,
                      tooltip: 'Clear city',
                      icon: const Icon(Icons.clear),
                    )
                  : null,
            ),
            onFieldSubmitted: (_) {
              if (_suggestions.isNotEmpty) {
                unawaited(_select(_suggestions[_highlight]));
              }
            },
            validator: (_) => _confirmed == null &&
                    (_text.text.trim().isNotEmpty || widget.requiredSelection)
                ? 'Select and confirm a city.'
                : null,
          ),
          const SizedBox(height: 4),
          const Text(
            'Only your city and country will be shown publicly.',
            style: TextStyle(fontSize: 12),
          ),
          if (_confirmed != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Confirmed: ${_confirmed!.label}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.green),
              ),
            ),
          if (_confirmed?.attributions.isNotEmpty == true)
            Padding(
              padding:const EdgeInsets.only(top:4),
              child:Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
                const Text('Place data: '),
                for(final credit in _confirmed!.attributions)
                  if(credit.providerUri==null)
                    Text(credit.provider)
                  else
                    TextButton(onPressed:()=>launchUrl(credit.providerUri!,
                      mode:LaunchMode.externalApplication),
                      child:Text(credit.provider)),
              ]),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Row(
              children: [
                Expanded(child: Text(_error!, overflow: TextOverflow.ellipsis)),
                TextButton(
                  onPressed: () => _search(_text.text.trim(), _generation),
                  child: const Text('Retry'),
                ),
              ],
            ),
          if (!_loading &&
              _error == null &&
              _text.text.trim().length >= 2 &&
              _confirmed == null &&
              _suggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text('No cities found.'),
            ),
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  label: 'Google Maps',
                  child: Text(
                    'Google Maps',
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).brightness==Brightness.dark
                          ? Colors.white : const Color(0xFF1F1F1F),
                    ),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < _suggestions.length; i++)
            ListTile(
              dense: true,
              selected: i == _highlight,
              title: Text(
                _suggestions[i].city,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _suggestions[i].country,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => _select(_suggestions[i]),
            ),
        ],
      ),
    );
  }
}
