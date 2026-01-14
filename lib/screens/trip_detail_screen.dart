import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:apple_maps_flutter/apple_maps_flutter.dart' as amap;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/database_helper.dart';
import '../providers/speed_provider.dart';

const List<double> _hudContrastMatrix = <double>[
  1.8, 0, 0, 0, -30,
  0, 1.8, 0, 0, -30,
  0, 0, 1.8, 0, -30,
  0, 0, 0, 1, 0,
];

class TripDetailScreen extends StatefulWidget {
  final int tripId;
  const TripDetailScreen({super.key, required this.tripId});

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Internal neutral representations
  final List<SimplePoint> _points = [];
  final List<SimpleAnnotation> _annos = [];
  bool _isLoading = true;
  SimplePoint? _center;

  bool get _isAndroid => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final trajectoryData = await _dbHelper.getTrajectory(widget.tripId);
    final eventData = await _dbHelper.getEvents(widget.tripId);

    _points.clear();
    for (var row in trajectoryData) {
      _points.add(SimplePoint(row['latitude'], row['longitude']));
    }

    _annos.clear();
    // 起點 / 終點
    if (_points.isNotEmpty) {
      _annos.add(SimpleAnnotation('start', _points.first.lat, _points.first.lng, '起點'));
      _annos.add(SimpleAnnotation('end', _points.last.lat, _points.last.lng, '終點'));
    }

    for (var i = 0; i < eventData.length; i++) {
      final event = eventData[i];
      final lat = event['latitude'];
      final lng = event['longitude'];
      final type = event['type'];
      final speed = event['speed'];

      if (type == 'DANGER') {
        final limit = event['limit_speed'];
        final timestamp = event['timestamp'] as String;
        final time = DateTime.tryParse(timestamp);

        _annos.add(SimpleAnnotation('danger_$i', lat, lng, '超速紀錄', isDanger: true, meta: {
          'time': time,
          'speed': speed,
          'limit': limit,
        }));
      }
    }

    setState(() {
      if (_points.isNotEmpty) {
        _center = _points[_points.length ~/ 2];
      }
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('行程詳情'),
        backgroundColor: const Color(0xFF222222),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _points.isEmpty
              ? const Center(child: Text("沒有軌跡資料"))
              : Consumer<SpeedProvider>(
                          builder: (ctx, provider, child) {
                    final Widget mapWidget = _isAndroid ? _buildGoogleMap() : _buildAppleMap();
                    if (provider.isHudMode) {
                      return ColorFiltered(
                        colorFilter: const ColorFilter.matrix(_hudContrastMatrix),
                        child: Opacity(opacity: 0.98, child: mapWidget),
                      );
                    }
                    return mapWidget;
                  }),
    );
  }

  // Build Google Map widget
  Widget _buildGoogleMap() {
    final center = _center != null
        ? gmap.LatLng(_center!.lat, _center!.lng)
        : const gmap.LatLng(25.0330, 121.5654);

    final gPolylines = <gmap.Polyline>{
      gmap.Polyline(
        polylineId: const gmap.PolylineId('path'),
        points: _points.map((p) => gmap.LatLng(p.lat, p.lng)).toList(),
        color: Colors.blue,
        width: 4,
      ),
    };

    final gMarkers = _annos.map((a) {
      return gmap.Marker(
        markerId: gmap.MarkerId(a.id),
        position: gmap.LatLng(a.lat, a.lng),
        infoWindow: gmap.InfoWindow(title: a.title),
        onTap: () {
          if (a.isDanger && a.meta != null) {
            final dt = a.meta!['time'] as DateTime?;
            final speed = a.meta!['speed'];
            final limit = a.meta!['limit'];
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('超速紀錄'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('時間: ${dt != null ? DateFormat('HH:mm:ss').format(dt) : '未知'}'),
                    const SizedBox(height: 8),
                    Text(
                      '當下時速: ${speed.toStringAsFixed(0)} km/h',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text('該路段速限: $limit km/h'),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
                ],
              ),
            );
          }
        },
      );
    }).toSet();

    return gmap.GoogleMap(
      initialCameraPosition: gmap.CameraPosition(target: center, zoom: 15.0),
      polylines: gPolylines,
      markers: gMarkers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }

  // Build Apple Map widget
  Widget _buildAppleMap() {
    final center = _center != null ? amap.LatLng(_center!.lat, _center!.lng) : const amap.LatLng(25.0330, 121.5654);

    final aPolylines = {
      amap.Polyline(
        polylineId: amap.PolylineId('path'),
        points: _points.map((p) => amap.LatLng(p.lat, p.lng)).toList(),
        color: Colors.blue,
        width: 4,
      ),
    };

    final aAnnos = _annos.map((a) {
      return amap.Annotation(
        annotationId: amap.AnnotationId(a.id),
        position: amap.LatLng(a.lat, a.lng),
        icon: amap.BitmapDescriptor.defaultAnnotation,
        infoWindow: amap.InfoWindow(title: a.title),
        onTap: () {
          if (a.isDanger && a.meta != null) {
            final dt = a.meta!['time'] as DateTime?;
            final speed = a.meta!['speed'];
            final limit = a.meta!['limit'];
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('超速紀錄'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('時間: ${dt != null ? DateFormat('HH:mm:ss').format(dt) : '未知'}'),
                    const SizedBox(height: 8),
                    Text(
                      '當下時速: ${speed.toStringAsFixed(0)} km/h',
                      style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                    Text('該路段速限: $limit km/h'),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('關閉')),
                ],
              ),
            );
          }
        },
      );
    }).toSet();

    return amap.AppleMap(
      initialCameraPosition: amap.CameraPosition(target: center, zoom: 15.0),
      mapType: amap.MapType.standard,
      polylines: aPolylines,
      annotations: aAnnos,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
    );
  }
}

// Simple neutral types to convert between map plugins
class SimplePoint {
  final double lat;
  final double lng;
  SimplePoint(this.lat, this.lng);
}

class SimpleAnnotation {
  final String id;
  final double lat;
  final double lng;
  final String title;
  final bool isDanger;
  final Map<String, dynamic>? meta;
  SimpleAnnotation(this.id, this.lat, this.lng, this.title, {this.isDanger = false, this.meta});
}
