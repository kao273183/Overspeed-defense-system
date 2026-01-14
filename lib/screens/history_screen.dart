import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import 'trip_detail_screen.dart';
import 'dart:io';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrips();
  }

  Future<void> _loadTrips() async {
    final trips = await _dbHelper.getAllTrips();
    setState(() {
      _trips = trips;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('行車紀錄 (Black Box)'),
        backgroundColor: const Color(0xFF222222),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white),
            onPressed: () => _confirmDeleteAll(context),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
          ? const Center(
              child: Text(
                '尚無行車紀錄',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            )
          : ListView.builder(
              itemCount: _trips.length,
              itemBuilder: (context, index) {
                final trip = _trips[index];
                final startTimeStr = trip['start_time'] as String;
                final endTimeStr = trip['end_time'] as String;

                final startTime = DateTime.tryParse(startTimeStr);
                final endTime = endTimeStr.isNotEmpty
                    ? DateTime.tryParse(endTimeStr)
                    : null;

                final duration = endTime != null
                    ? endTime.difference(startTime!)
                    : null;

                return Card(
                  color: const Color(0xFF333333),
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ListTile(
                    leading: const Icon(
                      Icons.drive_eta,
                      color: Colors.white,
                      size: 36,
                    ),
                    title: Text(
                      startTime != null
                          ? DateFormat('yyyy/MM/dd HH:mm').format(startTime)
                          : '未知時間',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (duration != null)
                          Text(
                            '行駛時間: ${duration.inMinutes} 分 ${duration.inSeconds % 60} 秒',
                            style: const TextStyle(color: Colors.grey),
                          )
                        else
                          const Text(
                            '行駛中...',
                            style: TextStyle(color: Color(0xFF00FF00)),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                          ),
                          onPressed: () =>
                              _confirmDeleteTrip(context, trip['id']),
                        ),
                        Builder(
                          builder: (context) {
                            return IconButton(
                              icon: const Icon(
                                Icons.share,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () {
                                final box =
                                    context.findRenderObject() as RenderBox?;
                                _exportTrip(
                                  context,
                                  trip['id'],
                                  startTimeStr,
                                  box != null
                                      ? box.localToGlobal(Offset.zero) &
                                            box.size
                                      : null,
                                );
                              },
                            );
                          },
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                    onTap: () {
                      // 點擊查看詳情
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => TripDetailScreen(tripId: trip['id']),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  void _confirmDeleteTrip(BuildContext context, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除紀錄'),
        content: const Text('確定要刪除這筆行車紀錄嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _dbHelper.deleteTrip(id);
              _loadTrips(); // Reload
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除全部紀錄'),
        content: const Text('確定要清空所有行車紀錄嗎？此動作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _dbHelper.deleteAllTrips();
              _loadTrips(); // Reload
            },
            child: const Text('全部刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _exportTrip(
    BuildContext context,
    int tripId,
    String startTimeStr,
    Rect? shareOrigin,
  ) async {
    final points = await _dbHelper.getTrajectory(tripId);
    if (points.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('此行程無軌跡資料')));
      }
      return;
    }

    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    sb.writeln(
      '<gpx version="1.1" creator="SpeedDefenseSystem" xmlns="http://www.topografix.com/GPX/1/1">',
    );
    sb.writeln('  <trk>');
    sb.writeln('    <name>Trip $startTimeStr</name>');
    sb.writeln('    <trkseg>');

    for (var p in points) {
      final lat = p['latitude'];
      final lon = p['longitude'];
      final time = p['timestamp'];
      sb.writeln('      <trkpt lat="$lat" lon="$lon">');
      sb.writeln('        <time>$time</time>');
      sb.writeln('      </trkpt>');
    }

    sb.writeln('    </trkseg>');
    sb.writeln('  </trk>');
    sb.writeln('</gpx>');

    final dir = await getTemporaryDirectory();
    final filename =
        "trip_${startTimeStr.replaceAll(RegExp(r'[^0-9]'), '')}.gpx";
    final file = File('${dir.path}/$filename');
    await file.writeAsString(sb.toString());

    if (context.mounted) {
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'GPX Export: $startTimeStr',
        sharePositionOrigin: shareOrigin,
      );
    }
  }
}
