import 'dart:convert';
import 'package:http/http.dart' as http;

class OsmService {
  // Singleton Pattern
  static final OsmService _instance = OsmService._internal();
  factory OsmService() => _instance;
  OsmService._internal();

  /// 從 OSM 取得該座標附近的速限 (回傳 km/h)
  /// 如果找不到或發生錯誤，回傳 null
  Future<int?> getMaxSpeed(double lat, double lon) async {
    try {
      // 搜尋半徑 20 公尺內的道路
      final String query =
          """
        [out:json];
        way(around:20, $lat, $lon)["maxspeed"];
        out tags;
      """;

      final Uri url = Uri.parse("https://overpass-api.de/api/interpreter");

      // 因為 Overpass API 限制較多，建議加上 User-Agent
      final response = await http.post(
        url,
        body: query,
        headers: {"User-Agent": "SpeedDefenseSystem/1.0"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final elements = data['elements'] as List;

        if (elements.isNotEmpty) {
          // 找第一個有 maxspeed 的標籤
          for (var element in elements) {
            if (element['tags'] != null &&
                element['tags']['maxspeed'] != null) {
              String maxSpeedStr = element['tags']['maxspeed'];

              // 處理 "50" 或 "50 mph" 等格式，這裡假設台灣大部分是純數字 (km/h)
              // 比較複雜的字串處理可以之後優化
              return int.tryParse(
                maxSpeedStr.replaceAll(RegExp(r'[^0-9]'), ''),
              );
            }
          }
        }
      } else {
        print("OSM API Error: ${response.statusCode}");
      }
    } catch (e) {
      print("OSM Fetch Error: $e");
    }
    return null;
  }

  // [新增] 取得當前地址 (反向地理編碼)
  Future<String?> getAddress(double lat, double lon) async {
    try {
      // 使用 OpenStreetMap Nominatim API
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lon&zoom=18&addressdetails=1',
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'SpeedDefenseSystem/1.0', // 必須要有 User-Agent
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        // 優先取路名，沒有的話取完整地址
        final address = data['address'];
        if (address != null) {
          return address['road'] ?? data['display_name'];
        }
        return data['display_name'];
      }
    } catch (e) {
      print("Nominatim Error: $e");
    }
    return null;
  }

  // [新增] 建立 OSM Note (匿名回報)
  Future<int?> createNote(double lat, double lon, String text) async {
    try {
      final url = Uri.parse(
        "https://api.openstreetmap.org/api/0.6/notes.json",
      ); // Use .json for easier parsing

      final response = await http.post(
        url,
        body: {'lat': lat.toString(), 'lon': lon.toString(), 'text': text},
        headers: {"User-Agent": "SpeedDefenseSystem/1.0"},
      );

      if (response.statusCode == 200) {
        // 成功建立 Note
        final data = jsonDecode(response.body);
        print("OSM Note Created: ${response.body}");
        return data['properties']['id']; // Return the Note ID
      } else {
        print("Failed to create note: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("OSM Note Error: $e");
      return null;
    }
  }
}
