import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_geocoding_service.dart';
import '../theme/app_theme.dart';
import '../utils/location_age.dart';
import '../widgets/wellscreen_ui.dart';

class GpsMapScreen extends StatefulWidget {
  const GpsMapScreen({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.label,
    required this.updatedAt,
    required this.hasLocation,
  });

  final double latitude;
  final double longitude;
  final String label;
  final String updatedAt;

  // False when latitude/longitude are the "Cebu City, Philippines preview"
  // placeholder point (parent_dashboard_screen.dart's openGpsMap(), when
  // hasSharedLocation() is false) rather than a real GPS fix. Needed
  // because that placeholder sits on real, valid downtown-Cebu coordinates
  // - without this flag, _resolveAddress() reverse-geocodes it to a real
  // street/city name and renders it with nothing marking it a placeholder,
  // unlike GpsMapPreview's "Cebu Preview" pill on the dashboard.
  final bool hasLocation;

  @override
  State<GpsMapScreen> createState() => _GpsMapScreenState();
}

class _GpsMapScreenState extends State<GpsMapScreen> {
  static const Color purple = AppColors.primary;
  static const Color darkText = AppColors.textPrimary;
  static const Color grayText = AppColors.textSecondary;
  static const Color pageBg = AppColors.background;

  final LocationGeocodingService _geocodingService = LocationGeocodingService();

  bool _isResolvingAddress = true;
  String? _resolvedPlaceName;
  Timer? _locationAgeTimer;

  @override
  void initState() {
    super.initState();
    _resolveAddress();

    _locationAgeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _locationAgeTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant GpsMapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve if the parent re-pushes this screen for an updated GPS fix
    // (e.g. after a fresh "Share GPS" sync) rather than showing a stale
    // address for the new coordinates.
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _resolveAddress();
    }
  }

  Future<void> _resolveAddress() async {
    // The "no GPS shared yet" placeholder sits on real, valid coordinates -
    // reverse-geocoding it would return a plausible real address and
    // render it as if it were the child's actual current location, with
    // nothing on screen marking it a placeholder. Skip the lookup entirely
    // and fall back to widget.label (the "Cebu City, Philippines preview"
    // text) instead.
    if (!widget.hasLocation) {
      setState(() {
        _isResolvingAddress = false;
        _resolvedPlaceName = null;
      });
      return;
    }

    setState(() {
      _isResolvingAddress = true;
      _resolvedPlaceName = null;
    });

    final placeName = await _geocodingService.reverseGeocode(
      latitude: widget.latitude,
      longitude: widget.longitude,
    );

    if (!mounted) return;

    setState(() {
      _resolvedPlaceName = placeName;
      _isResolvingAddress = false;
    });
  }

  /// The best available text for "where this pin actually is" - a real
  /// resolved street/area/city when the reverse-geocode lookup succeeds,
  /// falling back to whatever label the caller passed in (parent_dashboard_
  /// screen.dart's openGpsMap() - either the last-known raw coordinate text
  /// or the "Cebu City, Philippines preview" placeholder) if the lookup
  /// fails or is still in flight.
  String get _placeNameText {
    if (_isResolvingAddress) return 'Locating address...';
    return _resolvedPlaceName ?? widget.label;
  }

  @override
  Widget build(BuildContext context) {
    final locationPoint = LatLng(widget.latitude, widget.longitude);

    final locationWarning = locationAgeWarning(
      hasLocation: widget.hasLocation,
      updatedAt: widget.updatedAt,
      now: DateTime.now(),
    );
    final latLabel =
        '${widget.latitude.abs().toStringAsFixed(4)}\u00B0 '
        '${widget.latitude >= 0 ? 'N' : 'S'}';
    final lngLabel =
        '${widget.longitude.abs().toStringAsFixed(4)}\u00B0 '
        '${widget.longitude >= 0 ? 'E' : 'W'}';

    return Scaffold(
      backgroundColor: pageBg,
      appBar: const WellScreenAppBar.subPage(title: 'Live Location'),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: locationPoint,
                initialZoom: 15.5,
                minZoom: 5,
                maxZoom: 18,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wellscreen.app',
                ),
                if (widget.hasLocation)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: locationPoint,
                        radius: 44,
                        color: AppColors.primaryA20,
                        borderColor: AppColors.primaryA33,
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: locationPoint,
                      width: 56,
                      height: 56,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        widget.hasLocation
                            ? Icons.location_on_rounded
                            : Icons.location_searching_rounded,
                        color: purple,
                        size: 48,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              top: false,
              child: BentoCard(
                padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.hasLocation
                                ? _placeNameText
                                : 'No location shared yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppFonts.heading,
                              color: darkText,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$latLabel, $lngLabel',
                            style: const TextStyle(
                              color: darkText,
                              fontSize: 13,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Updated ${widget.updatedAt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: grayText,
                              fontSize: 12,
                            ),
                          ),
                          if (widget.hasLocation && locationWarning != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF7ED),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                locationWarning,
                                style: const TextStyle(
                                  color: Color(0xFF92400E),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Refresh address',
                        onPressed: _isResolvingAddress ? null : _resolveAddress,
                        icon: _isResolvingAddress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.refresh_rounded,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class GpsMapPreview extends StatelessWidget {
  const GpsMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.hasLocation,
  });

  static const Color purple = AppColors.primary;

  final double latitude;
  final double longitude;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final locationPoint = LatLng(latitude, longitude);

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        children: [
          SizedBox(
            height: 170,
            width: double.infinity,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: locationPoint,
                initialZoom: hasLocation ? 15 : 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.wellscreen.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: locationPoint,
                      width: 64,
                      height: 64,
                      child: Icon(
                        hasLocation
                            ? Icons.location_pin
                            : Icons.location_searching_rounded,
                        color: hasLocation ? Colors.redAccent : purple,
                        size: hasLocation ? 54 : 42,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                hasLocation ? 'Shared GPS' : 'No GPS yet',
                style: const TextStyle(
                  color: purple,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
