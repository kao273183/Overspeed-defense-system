import 'dart:io';
import 'package:flutter/material.dart';
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as apple_maps;
import 'package:google_maps_flutter/google_maps_flutter.dart'
    as google_maps; // [New]
import 'package:provider/provider.dart';
import '../providers/speed_provider.dart';
// ignore: library_prefixes
import 'package:latlong2/latlong.dart' as ll;

const List<double> _hudContrastMatrix = <double>[
  1.8, 0, 0, 0, -30,
  0, 1.8, 0, 0, -30,
  0, 0, 1.8, 0, -30,
  0, 0, 0, 1, 0,
];

class MiniMap extends StatefulWidget {
  const MiniMap({super.key});

  @override
  State<MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<MiniMap> {
  apple_maps.AppleMapController? _appleController;
  google_maps.GoogleMapController? _googleController; // [New]
  bool _isMapReady = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<SpeedProvider>(
      builder: (context, provider, child) {
        final ll.LatLng currentCenter =
            provider.currentLocation ?? const ll.LatLng(25.0330, 121.5654);

        // Update Camera Logic
        if (_isMapReady) {
          if (Platform.isIOS && _appleController != null) {
            final apple_maps.LatLng appleCenter = apple_maps.LatLng(
              currentCenter.latitude,
              currentCenter.longitude,
            );
            _appleController!.animateCamera(
              apple_maps.CameraUpdate.newCameraPosition(
                apple_maps.CameraPosition(
                  target: appleCenter,
                  zoom: 20.0,
                  heading: provider.currentHeading,
                  pitch: 0,
                ),
              ),
            );
          } else if (Platform.isAndroid && _googleController != null) {
            // [New] Update Google Maps Camera
            final google_maps.LatLng googleCenter = google_maps.LatLng(
              currentCenter.latitude,
              currentCenter.longitude,
            );
            _googleController!.animateCamera(
              google_maps.CameraUpdate.newCameraPosition(
                google_maps.CameraPosition(
                  target: googleCenter,
                  zoom: 18.0,
                  bearing: provider.currentHeading,
                  tilt: 0,
                ),
              ),
            );
          }
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF444444), width: 2),
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.8), blurRadius: 20),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: provider.isHudMode
                ? ColorFiltered(
                    colorFilter: const ColorFilter.matrix(_hudContrastMatrix),
                    child: Opacity(
                      opacity: 0.98,
                      child: Platform.isAndroid
                          ? _buildGoogleMap(currentCenter, provider)
                          : _buildAppleMap(currentCenter, provider),
                    ),
                  )
                : (Platform.isAndroid
                    ? _buildGoogleMap(currentCenter, provider)
                    : _buildAppleMap(currentCenter, provider)),
          ),
        );
      },
    );
  }

  Widget _buildAppleMap(ll.LatLng currentCenter, SpeedProvider provider) {
    final apple_maps.LatLng appleCenter = apple_maps.LatLng(
      currentCenter.latitude,
      currentCenter.longitude,
    );
    return apple_maps.AppleMap(
      initialCameraPosition: apple_maps.CameraPosition(
        target: appleCenter,
        zoom: 18.0,
      ),
      mapType: apple_maps.MapType.standard,
      onMapCreated: (apple_maps.AppleMapController controller) {
        _appleController = controller;
        setState(() {
          _isMapReady = true;
        });
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomGesturesEnabled: false,
      scrollGesturesEnabled: false,
      rotateGesturesEnabled: false,
      pitchGesturesEnabled: false,
      polylines: {
        if (provider.pathHistory.isNotEmpty)
          apple_maps.Polyline(
            polylineId: apple_maps.PolylineId("trip_path"),
            points: provider.pathHistory
                .map((p) => apple_maps.LatLng(p.latitude, p.longitude))
                .toList(),
            color: const Color(0xFF00E676),
            width: 4,
          ),
      },
    );
  }

  // [New] Google Maps Builder
  Widget _buildGoogleMap(ll.LatLng currentCenter, SpeedProvider provider) {
    final google_maps.LatLng googleCenter = google_maps.LatLng(
      currentCenter.latitude,
      currentCenter.longitude,
    );

    return google_maps.GoogleMap(
      initialCameraPosition: google_maps.CameraPosition(
        target: googleCenter,
        zoom: 18.0,
        bearing: provider.currentHeading,
      ),
      mapType: google_maps.MapType.normal,
      onMapCreated: (google_maps.GoogleMapController controller) {
        _googleController = controller;
        setState(() {
          _isMapReady = true;
        });
      },
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      scrollGesturesEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      zoomGesturesEnabled: false,
      polylines: {
        if (provider.pathHistory.isNotEmpty)
          google_maps.Polyline(
            polylineId: google_maps.PolylineId("trip_path"),
            points: provider.pathHistory
                .map((p) => google_maps.LatLng(p.latitude, p.longitude))
                .toList(),
            color: const Color(0xFF00E676),
            width: 4,
          ),
      },
    );
  }
}
