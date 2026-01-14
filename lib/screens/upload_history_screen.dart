import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/database_helper.dart';

class UploadHistoryScreen extends StatefulWidget {
  const UploadHistoryScreen({super.key});

  @override
  State<UploadHistoryScreen> createState() => _UploadHistoryScreenState();
}

class _UploadHistoryScreenState extends State<UploadHistoryScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final history = await _dbHelper.getUploadHistory();
    setState(() {
      _history = history;
      _isLoading = false;
    });
  }

  Future<void> _openOsmNote(int osmId) async {
    final url = Uri.parse("https://www.openstreetmap.org/note/$osmId");
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法開啟瀏覽器')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // Dark theme
      appBar: AppBar(
        title: const Text('上傳紀錄'),
        backgroundColor: const Color(0xFF222222),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
          ? const Center(
              child: Text(
                '尚無上傳紀錄',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _history.length,
              itemBuilder: (context, index) {
                final item = _history[index];
                final osmId = item['osm_id'];
                final timestamp = item['timestamp'];
                final address = item['address'] ?? '未知地點';
                final status = item['status'] ?? 'OPEN';

                final dt = DateTime.tryParse(timestamp);
                final timeStr = dt != null
                    ? DateFormat('yyyy/MM/dd HH:mm').format(dt)
                    : timestamp;

                return Card(
                  color: const Color(0xFF333333),
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    onTap: () => _openOsmNote(osmId),
                    leading: CircleAvatar(
                      backgroundColor: status == 'CLOSED'
                          ? Colors.grey
                          : Colors.green,
                      child: Icon(
                        status == 'CLOSED' ? Icons.check : Icons.cloud_done,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          "案件編號: #$osmId",
                          style: const TextStyle(color: Colors.amberAccent),
                        ),
                        Text(
                          timeStr,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.open_in_new,
                      color: Colors.blueAccent,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
