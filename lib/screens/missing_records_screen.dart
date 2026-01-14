import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart'; // [新增] For Clipboard
import '../services/database_helper.dart';
import '../services/osm_service.dart'; // [新增]

class MissingRecordsScreen extends StatefulWidget {
  const MissingRecordsScreen({super.key});

  @override
  State<MissingRecordsScreen> createState() => _MissingRecordsScreenState();
}

class _MissingRecordsScreenState extends State<MissingRecordsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _dbHelper.getMissingLimits();

    // [New] Deduplicate by address (Keep the latest one)
    final uniqueRecords = <Map<String, dynamic>>[];
    final seenAddresses = <String>{};

    for (var record in records) {
      final address = record['address'] as String;
      // You might want to normalize address string here if needed
      if (!seenAddresses.contains(address)) {
        seenAddresses.add(address);
        uniqueRecords.add(record);
      }
    }

    setState(() {
      _records = uniqueRecords;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(int id) async {
    await _dbHelper.deleteMissingLimit(id);
    _loadRecords();
  }

  Future<void> _deleteAllRecords() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('全部刪除'),
        content: const Text('確定要清空所有缺漏標記嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dbHelper.deleteAllMissingLimits();
      _loadRecords();
    }
  }

  Future<void> _updateSuggestedLimit(int id, int limit) async {
    await _dbHelper.updateMissingLimit(id, limit);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已紀錄在本地端，尚未上傳'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    _loadRecords();
  }

  Future<void> _launchEditor(double lat, double lon) async {
    // Open iD editor focused on the location
    final url = Uri.parse(
      'https://www.openstreetmap.org/edit?editor=id#map=19/$lat/$lon',
    );
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法開啟瀏覽器')));
    }
  }

  Future<void> _copyInfo(
    String address,
    int? suggested,
    double lat,
    double lon,
  ) async {
    final text =
        "缺漏速限回報\n地點: $address\n座標: $lat, $lon\n建議速限: ${suggested ?? '未設定'} km/h";
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已複製資料到剪貼簿')));
    }
  }

  // [新增] 一鍵回報到 OSM
  Future<void> _reportToOsm(
    int id,
    String address,
    int? suggested,
    double lat,
    double lon,
  ) async {
    // 顯示 Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    final text =
        "Speed limit missing report.\nSuggested limit: ${suggested ?? 'Unknown'} km/h\nLocation: $lat, $lon\nReported via Speed Defense System app.";

    final osmId = await OsmService().createNote(lat, lon, text);

    if (mounted) {
      Navigator.pop(context); // 關閉 Loading

      if (osmId != null) {
        // 1. Insert into Upload History
        await DatabaseHelper.instance.insertUploadHistory({
          'osm_id': osmId,
          'latitude': lat,
          'longitude': lon,
          'address': address,
          'description': text,
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'OPEN',
        });

        // 2. Refresh UI (optional: delete from missing list?)
        // await DatabaseHelper.instance.deleteMissingLimit(id);
        // _loadRecords();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OSM 回報成功！案件編號 #$osmId'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('回報失敗，請檢查網路連線'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme background
      appBar: AppBar(
        title: const Text('缺漏標記列表'),
        backgroundColor: const Color(0xFF222222),
        actions: [
          TextButton.icon(
            onPressed: _records.isEmpty ? null : _deleteAllRecords,
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            label: const Text(
              '一鍵刪除',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(
              child: Text(
                '目前沒有缺漏紀錄',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                final id = record['id'];
                final lat = record['latitude'] as double;
                final lon = record['longitude'] as double;
                final address = record['address'] as String;
                final timestamp = record['timestamp'] as String;
                final suggested = record['suggested_limit'] as int?;

                final dt = DateTime.tryParse(timestamp);
                final timeStr = dt != null
                    ? DateFormat('yyyy/MM/dd HH:mm:ss').format(dt)
                    : timestamp;

                return Card(
                  color: const Color(0xFF333333),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timestamp
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Address
                        Text(
                          address,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Quick Set Buttons
                        Row(
                          children: [
                            const Text(
                              '快速設定: ',
                              style: TextStyle(color: Colors.amber),
                            ),
                            const SizedBox(width: 8),
                            ...[30, 40, 50, 60].map((limit) {
                              final isSelected = suggested == limit;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: InkWell(
                                  onTap: () => _updateSuggestedLimit(id, limit),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? Colors.amber
                                          : Colors.grey[800],
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.amber
                                            : Colors.grey,
                                      ),
                                    ),
                                    child: Text(
                                      '$limit',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: Colors.grey),
                        const SizedBox(height: 8),
                        // Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            // [Report Button]
                            ElevatedButton.icon(
                              onPressed: () => _reportToOsm(
                                id,
                                address,
                                suggested,
                                lat,
                                lon,
                              ),
                              icon: const Icon(Icons.cloud_upload, size: 16),
                              label: const Text('一鍵回報'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amber[800],
                                foregroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // [Copy Info Button]
                            IconButton(
                              onPressed: () =>
                                  _copyInfo(address, suggested, lat, lon),
                              icon: const Icon(
                                Icons.copy,
                                color: Colors.orangeAccent,
                                size: 20,
                              ),
                              tooltip: "複製資料",
                            ),
                            // [Fix on OSM Button]
                            IconButton(
                              onPressed: () => _launchEditor(lat, lon),
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.blueAccent,
                                size: 20,
                              ),
                              tooltip: "前往 OSM 修正",
                            ),
                            // [Delete Button]
                            IconButton(
                              onPressed: () => _deleteRecord(id),
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              tooltip: "刪除紀錄",
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
