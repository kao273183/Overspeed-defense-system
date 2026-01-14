import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';

class LocalRecordsScreen extends StatefulWidget {
  const LocalRecordsScreen({super.key});

  @override
  State<LocalRecordsScreen> createState() => _LocalRecordsScreenState();
}

class _LocalRecordsScreenState extends State<LocalRecordsScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final records = await _dbHelper.getLocalRecords();
    setState(() {
      _records = records;
      _isLoading = false;
    });
  }

  Future<void> _deleteRecord(int id) async {
    // 移除本地設定 (但在缺漏紀錄中保留)
    await _dbHelper.removeLocalLimit(id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已移除本地速限設定 (保留於缺漏紀錄中)')));
    }
    _loadRecords();
  }

  Future<void> _updateSuggestedLimit(int id, int limit) async {
    await _dbHelper.updateMissingLimit(id, limit);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('速限已更新'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
    _loadRecords();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('本地端紀錄 (Local Records)'),
        backgroundColor: const Color(0xFF222222),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
          ? const Center(
              child: Text(
                '目無本地設定紀錄',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _records.length,
              itemBuilder: (context, index) {
                final record = _records[index];
                final id = record['id'];
                final address = record['address'] as String;
                final timestamp = record['timestamp'] as String;
                final suggested =
                    record['suggested_limit'] as int; // Should be non-null

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
                        // Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green[800],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "已設定: $suggested km/h",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
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
                        // Edit Interface
                        Row(
                          children: [
                            const Text(
                              '修改速限: ',
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              onPressed: () => _deleteRecord(id),
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              label: const Text(
                                '刪除',
                                style: TextStyle(color: Colors.redAccent),
                              ),
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
