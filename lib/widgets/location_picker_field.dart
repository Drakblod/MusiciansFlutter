import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/canonical_location.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// Interactive location input field with provider-independent map confirmation.
///
/// Features:
/// - User enters a readable location label.
/// - User confirms the position by tapping or moving a marker on the existing Google Map.
/// - Coordinates are saved ONLY after explicit user confirmation.
/// - Any editing of the text label immediately invalidates previously confirmed coordinates.
/// - City-level privacy protection for New Member searches (obscures exact residential coords).
/// - ZERO external autocomplete/typeahead requests to public OSM Nominatim.
class LocationPickerField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final String? hintText;
  final bool cityOnly;
  final bool cityPrecisionOnly;
  final CanonicalLocation? initialLocation;
  final ValueChanged<CanonicalLocation>? onLocationChanged;
  final FormFieldValidator<String>? validator;
  final LocationResolver resolver;

  const LocationPickerField({
    super.key,
    required this.controller,
    this.label = 'Location',
    this.hint = 'e.g. Fasching, Kungsgatan 63, Stockholm',
    this.hintText,
    this.cityOnly = false,
    this.cityPrecisionOnly = false,
    this.initialLocation,
    this.onLocationChanged,
    this.validator,
    this.resolver = LocationService.defaultResolver,
  });

  bool get effectiveCityOnly => cityOnly || cityPrecisionOnly;

  @override
  State<LocationPickerField> createState() => LocationPickerFieldState();
}

class LocationPickerFieldState extends State<LocationPickerField> {
  CanonicalLocation? _currentLocation;
  String _lastConfirmedText = '';

  CanonicalLocation? get currentLocation => _currentLocation;
  bool get isConfirmed => _currentLocation != null && _currentLocation!.hasValidCoordinates;

  @override
  void initState() {
    super.initState();
    if (widget.initialLocation != null && widget.initialLocation!.hasValidCoordinates) {
      _currentLocation = widget.initialLocation;
      _lastConfirmedText = widget.controller.text;
    }
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    final currentText = widget.controller.text.trim();
    // Invalidate previously confirmed coordinates if the user changed the text
    if (_currentLocation != null && currentText != _lastConfirmedText) {
      setState(() {
        _currentLocation = CanonicalLocation.unresolved(currentText);
      });
      widget.onLocationChanged?.call(_currentLocation!);
    }
  }

  void _confirmLocation(CanonicalLocation location) {
    setState(() {
      _currentLocation = location;
      _lastConfirmedText = widget.controller.text.trim();
    });
    widget.onLocationChanged?.call(location);
  }

  void _useKnownCityCentroid(CanonicalLocation cityLoc) {
    widget.controller.text = cityLoc.locationLabel;
    _confirmLocation(cityLoc);
  }

  Future<void> _openMapLocationPicker(BuildContext context) async {
    final initialPos = (_currentLocation != null && _currentLocation!.hasValidCoordinates)
        ? LatLng(_currentLocation!.latitude!, _currentLocation!.longitude!)
        : const LatLng(59.3293, 18.0686);

    LatLng selectedPos = initialPos;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isCity = widget.effectiveCityOnly;
            final title = isCity
                ? 'Select Approximate City Area'
                : 'Confirm Venue Location on Map';
            final subtitle = isCity
                ? 'Residential privacy protected: exact street address is never published.'
                : 'Tap on the map or drag the pin to set the exact position.';

            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isCity ? Colors.amber.shade200 : AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: initialPos,
                          zoom: isCity ? 11 : 14,
                        ),
                        onTap: (latLng) {
                          setSheetState(() {
                            selectedPos = latLng;
                          });
                        },
                        markers: {
                          Marker(
                            markerId: const MarkerId('picked_location'),
                            position: selectedPos,
                            draggable: true,
                            onDragEnd: (newPos) {
                              setSheetState(() {
                                selectedPos = newPos;
                              });
                            },
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selected: ${selectedPos.latitude.toStringAsFixed(4)}, ${selectedPos.longitude.toStringAsFixed(4)}',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () {
                          final nearestCity = widget.resolver.findClosestKnownCity(selectedPos.latitude, selectedPos.longitude);
                          String label = widget.controller.text.trim();
                          if (label.isEmpty || label == 'Map Location' || label == 'City Area') {
                            label = nearestCity != null ? '${nearestCity.locationLabel}, Sweden' : (isCity ? 'City Area' : 'Map Location');
                            widget.controller.text = label;
                          } else {
                            final oldCity = widget.resolver.resolveKnownCity(label);
                            if (oldCity != null && nearestCity != null && oldCity.locationLabel.toLowerCase() != nearestCity.locationLabel.toLowerCase()) {
                              label = '${nearestCity.locationLabel}, Sweden';
                              widget.controller.text = label;
                            }
                          }

                          final candidate = isCity
                              ? CanonicalLocation.city(
                                  cityName: label,
                                  latitude: selectedPos.latitude,
                                  longitude: selectedPos.longitude,
                                )
                              : CanonicalLocation.exact(
                                  locationLabel: label,
                                  latitude: selectedPos.latitude,
                                  longitude: selectedPos.longitude,
                                );

                          final finalLoc = isCity
                              ? widget.resolver.toCityLevelLocation(candidate)
                              : candidate;

                          _confirmLocation(finalLoc);
                          Navigator.pop(sheetContext);
                        },
                        child: Text(
                          'Confirm Location',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = _currentLocation != null && _currentLocation!.hasValidCoordinates;
    final knownCity = widget.resolver.resolveKnownCity(widget.controller.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: widget.controller,
          style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hintText ?? widget.hint,
            labelStyle: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13),
            hintStyle: GoogleFonts.inter(color: AppTheme.textMuted.withValues(alpha: 0.7), fontSize: 13),
            prefixIcon: Icon(
              widget.effectiveCityOnly ? Icons.location_city : Icons.location_on_outlined,
              color: hasCoords ? AppTheme.success : AppTheme.primaryAccent,
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                hasCoords ? Icons.check_circle : Icons.map_outlined,
                color: hasCoords ? AppTheme.success : AppTheme.primaryAccent,
                size: 20,
              ),
              tooltip: hasCoords ? 'Coordinates confirmed' : 'Confirm on Map',
              onPressed: () => _openMapLocationPicker(context),
            ),
            filled: true,
            fillColor: AppTheme.cardBackground.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.textMuted.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: hasCoords
                    ? AppTheme.success.withValues(alpha: 0.7)
                    : AppTheme.textMuted.withValues(alpha: 0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppTheme.primaryAccent),
            ),
          ),
          validator: widget.validator,
        ),

        const SizedBox(height: 6),

        // Confirmation badge or action button
        if (hasCoords) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      widget.effectiveCityOnly ? Icons.location_city : Icons.pin_drop,
                      color: AppTheme.success,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.effectiveCityOnly
                            ? 'City-level location confirmed (${_currentLocation!.latitude!.toStringAsFixed(2)}, ${_currentLocation!.longitude!.toStringAsFixed(2)})'
                            : 'Map coordinates confirmed (${_currentLocation!.latitude!.toStringAsFixed(4)}, ${_currentLocation!.longitude!.toStringAsFixed(4)})',
                        style: GoogleFonts.inter(
                          color: AppTheme.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => _openMapLocationPicker(context),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    'Change on Map',
                    style: GoogleFonts.inter(
                      color: AppTheme.primaryAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.controller.text.trim().isNotEmpty
                      ? 'Location unconfirmed - tap "Set on Map" to confirm coordinates'
                      : 'Enter location and confirm coordinates on map',
                  style: GoogleFonts.inter(
                    color: Colors.amber.shade300,
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: const Size(0, 28),
                  side: const BorderSide(color: AppTheme.primaryAccent, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.pin_drop, size: 14, color: AppTheme.primaryAccent),
                label: Text(
                  'Set on Map',
                  style: GoogleFonts.inter(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600),
                ),
                onPressed: () => _openMapLocationPicker(context),
              ),
            ],
          ),
          if (knownCity != null) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _useKnownCityCentroid(knownCity),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 12, color: AppTheme.secondaryAccent),
                  const SizedBox(width: 4),
                  Text(
                    'Use approximate ${knownCity.locationLabel} centroid (${knownCity.latitude!.toStringAsFixed(2)}, ${knownCity.longitude!.toStringAsFixed(2)})',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppTheme.secondaryAccent,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
