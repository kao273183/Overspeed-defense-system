import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/database_helper.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // Stats Data
  double totalDistance = 0.0;
  double maxSpeed = 0.0;
  int totalTrips = 0;
  List<Map<String, dynamic>> weeklyData = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final db = DatabaseHelper.instance;
    final trips = await db.getWeeklyStats(); // Get last 7 days

    double dist = 0;
    double maxSpd = 0;

    // Process data for chart
    // We want to group by day.
    // Map: DateTime(yyyy,mm,dd) -> totalDistance
    Map<DateTime, double> dailyDistances = {};

    final now = DateTime.now();
    // Initialize last 7 days with 0
    for (int i = 6; i >= 0; i--) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: i));
      dailyDistances[day] = 0.0;
    }

    for (var trip in trips) {
      if (trip['distance'] != null) {
        dist += (trip['distance'] as num).toDouble();
      }
      if (trip['max_speed'] != null) {
        double spd = (trip['max_speed'] as num).toDouble();
        if (spd > maxSpd) maxSpd = spd;
      }

      // Chart Data Grouping
      if (trip['start_time'] != null) {
        final startTime = DateTime.parse(trip['start_time'] as String);
        final dateKey = DateTime(
          startTime.year,
          startTime.month,
          startTime.day,
        );

        if (dailyDistances.containsKey(dateKey)) {
          double current = dailyDistances[dateKey]!;
          double tripDist = (trip['distance'] as num?)?.toDouble() ?? 0.0;
          dailyDistances[dateKey] = current + tripDist;
        }
      }
    }

    setState(() {
      totalDistance = dist;
      maxSpeed = maxSpd;
      totalTrips = trips.length;

      // Convert Map to List for Chart
      weeklyData = dailyDistances.entries.map((e) {
        return {
          'day': "${e.key.month}/${e.key.day}",
          'distance': e.value / 1000.0, // Convert to km
          'weekday': _getWeekdayName(e.key.weekday),
        };
      }).toList();

      isLoading = false;
    });
  }

  String _getWeekdayName(int weekday) {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    return days[weekday - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        title: const Text("行程統計 (7天)", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Summary Cards
                    Row(
                      children: [
                        _buildSummaryCard(
                          "累積里程",
                          "${(totalDistance / 1000).toStringAsFixed(1)} km",
                          Icons.directions_car,
                          Colors.blueAccent,
                        ),
                        const SizedBox(width: 12),
                        _buildSummaryCard(
                          "最高時速",
                          "${maxSpeed.toStringAsFixed(0)} km/h",
                          Icons.speed,
                          Colors.redAccent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSummaryCard(
                          "行程總數",
                          "$totalTrips 次",
                          Icons.history,
                          Colors.greenAccent,
                        ),
                        const SizedBox(width: 12),
                        // Placeholder for score or other stats
                        _buildSummaryCard(
                          "安全評分",
                          "A+", // Placeholder
                          Icons.verified_user,
                          Colors.amber,
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    const Text(
                      "每日行駛里程 (km)",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Bar Chart
                    SizedBox(
                      height: 300,
                      child: BarChart(
                        BarChartData(
                            barTouchData: BarTouchData(
                              enabled: true,
                              touchTooltipData: BarTouchTooltipData(
                                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                  final value = rod.toY;
                                  final text = value.toStringAsFixed(2); // two decimals, rounded
                                  return BarTooltipItem(
                                    '$text\n',
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  );
                                },
                              ),
                            ),
                          backgroundColor: Colors.transparent,
                          barGroups: _generateBarGroups(),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: false,
                              ), // Optional values
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  final index = value.toInt();
                                  if (index >= 0 && index < weeklyData.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        weeklyData[index]['day'],
                                        style: const TextStyle(
                                          color: Colors.grey,
                                          fontSize: 10,
                                        ),
                                      ),
                                    );
                                  }
                                  return const Text('');
                                },
                              ),
                            ),
                          ),
                          gridData: const FlGridData(show: false),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<BarChartGroupData> _generateBarGroups() {
    List<BarChartGroupData> groups = [];
    for (int i = 0; i < weeklyData.length; i++) {
      double value = weeklyData[i]['distance'] as double;
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: value,
              color: Colors.cyanAccent,
              width: 16,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 100, // Max scale assumption, logic can be improved
                color: Colors.white10,
              ),
            ),
          ],
        ),
      );
    }
    return groups;
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
