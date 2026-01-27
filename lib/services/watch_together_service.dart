import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synctv_app/models/watch_together_models.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

class WatchTogetherService {
  static String _baseUrl = 'https://tv.test.com/api';
  static String get baseUrl => _baseUrl;
  static const String _tokenKey = 'synctv_token';
  static const String _baseUrlKey = 'synctv_base_url';
  
  static final StreamController<void> _authErrorController = StreamController<void>.broadcast();
  static Stream<void> get onAuthError => _authErrorController.stream;

  // Initialize service
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString(_baseUrlKey);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      _baseUrl = savedUrl;
    }
  }

  // Set base URL
  static Future<void> setBaseUrl(String url) async {
    // Remove trailing slash if present
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // Ensure it has protocol
    if (!url.startsWith('http')) {
      url = 'https://$url';
    }
    _baseUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, url);
  }

  static void _checkResponse(http.Response response) {
    if (response.statusCode == 401) {
      _authErrorController.add(null);
      throw AuthException('认证失效，请重新登录');
    }
  }

  // Helper to check for success status codes (200-299)
  static bool _isSuccess(int statusCode) {
    return statusCode >= 200 && statusCode < 300;
  }

  // Get token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  // Save token
  static Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  // Clear token
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  // Headers
  static Future<Map<String, String>> _getHeaders({String? roomId}) async {
    final token = await getToken();
    final headers = {
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = token;
    }
    if (roomId != null) {
      headers['X-Room-Id'] = roomId;
    }
    return headers;
  }

  // Login
  static Future<WUser> login(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      
      // Try to get token from body or headers
      String? token;
      // Handle nested data structure { "data": { "token": "..." } }
      if (json['data'] != null && json['data'] is Map) {
        token = json['data']['token'];
      }
      // Fallback to root level
      if (token == null) {
        token = json['token'];
      }
      // Fallback to headers
      if (token == null && response.headers['authorization'] != null) {
        token = response.headers['authorization'];
      }

      if (token != null) {
        await _saveToken(token);
        try {
          return await getUserInfo();
        } catch (e) {
          // If getting user info fails, we still want to consider login successful
          // and maybe return a dummy user or retry later.
          // For now, let's construct a user from the login response if available
          int role = 0;
          if (json['data'] != null && json['data']['role'] is int) {
            role = json['data']['role'];
          } else if (json['role'] is int) {
            role = json['role'];
          }
          
          return WUser(
            id: '', 
            username: username, 
            role: role,
            createdAt: 0,
          );
        }
      } else {
        throw Exception('Login failed: No token returned. Headers: ${response.headers}, Body: ${response.body}');
      }
    } else {
      throw Exception('Login failed: ${response.statusCode} ${response.body}');
    }
  }

  // Register
  static Future<WUser> register(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/user/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (_isSuccess(response.statusCode)) {
      final data = jsonDecode(response.body);
      String? token;
      // Handle nested data structure
      if (data['data'] != null && data['data'] is Map) {
        token = data['data']['token'];
      }
      if (token == null) {
        token = data['token'];
      }
      
      if (token != null) {
         await _saveToken(token);
         return await getUserInfo();
      }
      // If no token returned on signup, try login
      return await login(username, password);
    } else {
       throw Exception('Registration failed: ${response.body}');
    }
  }

  // Get User Info
  static Future<WUser> getUserInfo() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/user/me'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      Map<String, dynamic> userMap = {};
      
      if (json['data'] != null && json['data'] is Map) {
        userMap = json['data'];
      } else {
        userMap = json;
      }
      
      return WUser.fromJson(userMap);
    } else {
      throw Exception('Failed to load user info: ${response.body}');
    }
  }

  // Get Rooms
  static Future<List<WRoom>> getRooms() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/room/list'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final data = jsonDecode(response.body);
      
      List list = [];
      // Handle nested data structure
      if (data['data'] != null && data['data']['list'] != null) {
        list = data['data']['list'];
      } else if (data['list'] != null) {
        list = data['list'];
      }
      
      if (list.isNotEmpty) {
        return list.map((e) => WRoom.fromJson(e)).toList();
      }
      return [];
    } else {
      throw Exception('Failed to load rooms: ${response.body}');
    }
  }

  // Get My Rooms
  static Future<List<WRoom>> getMyRooms() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/user/rooms'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final data = jsonDecode(response.body);
      
      List list = [];
      // Handle nested data structure
      if (data['data'] != null && data['data']['list'] != null) {
        list = data['data']['list'];
      } else if (data['list'] != null) {
        list = data['list'];
      } else if (data['data'] is List) {
        list = data['data'];
      }
      
      if (list.isNotEmpty) {
        return list.map((e) => WRoom.fromJson(e)).toList();
      }
      return [];
    } else {
      throw Exception('Failed to load my rooms: ${response.body}');
    }
  }

  // Create Room
  static Future<WRoom> createRoom(String name, {String? password}) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/room/create'),
      headers: headers,
      body: jsonEncode({
        'roomName': name,
        'password': password ?? '',
        'settings': {
          'hidden': false
        }
      }),
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final data = jsonDecode(response.body);
      
      String? roomId;
      if (data['data'] != null && data['data']['roomId'] != null) {
         roomId = data['data']['roomId'];
      } else {
         roomId = data['roomId'];
      }

      if (roomId != null) {
        return WRoom(
          roomId: roomId,
          roomName: name,
          creatorId: '', // Unknown for now
          needPassword: password != null && password.isNotEmpty,
        );
      }
      throw Exception('Failed to create room: No roomId in response');
    } else {
      throw Exception('Failed to create room: ${response.body}');
    }
  }
  
  // Delete Room
  static Future<void> deleteRoom(String roomId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/user/room/delete'),
      headers: headers,
      body: jsonEncode({
        'id': roomId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to delete room: ${response.body}');
    }
  }

  // Join Room (Check password)
  static Future<void> joinRoom(String roomId, String password) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/room/login'),
      headers: headers,
      body: jsonEncode({
        'roomId': roomId,
        'password': password,
      }),
    );
    _checkResponse(response);
    
    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to join room: ${response.body}');
    }
  }

  // Get Current Movie
  static Future<WPlaybackStatus> getCurrentMovie(String roomId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.get(
      Uri.parse('$baseUrl/room/movie/current'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return WPlaybackStatus.fromJson(data['data']);
      }
      return WPlaybackStatus.fromJson(data);
    } else {
      throw Exception('Failed to get current movie: ${response.statusCode} ${response.body}');
    }
  }

  // Get Movies
  static Future<Map<String, dynamic>> getMovies(String roomId, {int page = 1, int max = 20, String? parentId, String? subPath}) async {
    final headers = await _getHeaders(roomId: roomId);
    String url = '$baseUrl/room/movie/movies?page=$page&max=$max';
    if (parentId != null && parentId.isNotEmpty) {
      url += '&id=$parentId';
    }
    if (subPath != null && subPath.isNotEmpty) {
      url += '&subPath=${Uri.encodeComponent(subPath)}';
    }
    
    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      // Try to parse list from various possible structures
      List list = [];
      int total = 0;
      
      if (data['data'] != null) {
        if (data['data'] is List) {
          list = data['data'];
        } else if (data['data']['movies'] != null) {
          list = data['data']['movies'];
          total = data['data']['total'] ?? 0;
        } else if (data['data']['list'] != null) {
          list = data['data']['list'];
          total = data['data']['total'] ?? 0;
        }
      } else if (data['movies'] != null) {
        list = data['movies'];
        total = data['total'] ?? 0;
      } else if (data is List) {
        list = data;
      }
      
      return {
        'movies': list.map((e) => WMovie.fromJson(e)).toList(),
        'total': total,
      };
    } else {
      throw Exception('Failed to get movies: ${response.body}');
    }
  }

  // Get Me
  static Future<WUser> getMe() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/user/me'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return WUser.fromJson(data['data']);
      }
      return WUser.fromJson(data);
    } else {
      throw Exception('Failed to get user info: ${response.body}');
    }
  }

  // Get Room Members
  static Future<List<WUser>> getRoomMembers(String roomId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.get(
      Uri.parse('$baseUrl/room/members'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      List list = [];
      if (data['data'] != null) {
        if (data['data'] is List) {
          list = data['data'];
        } else if (data['data']['list'] != null && data['data']['list'] is List) {
          list = data['data']['list'];
        }
      } else if (data is List) {
        list = data;
      }
      return list.map((e) => WUser.fromJson(e)).toList();
    } else {
      throw Exception('Failed to get room members: ${response.body}');
    }
  }

  // Get Alist Binds (Full Details)
  static Future<List<Map<String, dynamic>>> getAListBindsList() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/vendor/alist/binds'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null && data['data'] is List) {
        return List<Map<String, dynamic>>.from(data['data']);
      } else if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } else {
      throw Exception('Failed to get Alist binds: ${response.body}');
    }
  }

  // Get Emby Binds (Full Details)
  static Future<List<Map<String, dynamic>>> getEmbyBindsList() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/vendor/emby/binds'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null && data['data'] is List) {
        return List<Map<String, dynamic>>.from(data['data']);
      } else if (data is List) {
        return List<Map<String, dynamic>>.from(data);
      }
      return [];
    } else {
      throw Exception('Failed to get Emby binds: ${response.body}');
    }
  }

  // Login Alist
  static Future<void> loginAList(String host, String username, String password) async {
    final headers = await _getHeaders();
    // Hash password: sha256(password + "-https://github.com/alist-org/alist")
    final salt = "-https://github.com/alist-org/alist";
    final hashedPassword = sha256.convert(utf8.encode(password + salt)).toString();

    final response = await http.post(
      Uri.parse('$baseUrl/vendor/alist/login'),
      headers: headers,
      body: jsonEncode({
        'host': host,
        'username': username,
        'hashedPassword': hashedPassword,
      }),
    );
    _checkResponse(response);

    // Accept any 2xx success status code
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to login to Alist: [${response.statusCode}] ${response.body}');
    }
  }

  // Logout Alist
  static Future<void> logoutAList(String serverId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/vendor/alist/logout'),
      headers: headers,
      body: jsonEncode({
        'serverId': serverId,
      }),
    );
    _checkResponse(response);

    // Accept any 2xx success status code
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to logout from Alist: [${response.statusCode}] ${response.body}');
    }
  }

  // Logout Emby
  static Future<void> logoutEmby(String serverId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/vendor/emby/logout'),
      headers: headers,
      body: jsonEncode({
        'serverId': serverId,
      }),
    );
    _checkResponse(response);

    // Accept any 2xx success status code
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to logout from Emby: [${response.statusCode}] ${response.body}');
    }
  }
  
  // Get Alist Account Info
  static Future<Map<String, dynamic>> getAListAccountInfo(String serverId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/vendor/alist/me?serverId=$serverId'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data'] ?? data;
    } else {
      throw Exception('Failed to get Alist account info: ${response.body}');
    }
  }

  // Get Emby Account Info
  static Future<Map<String, dynamic>> getEmbyAccountInfo(String serverId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/vendor/emby/me?serverId=$serverId'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      return data['data'] ?? data;
    } else {
      throw Exception('Failed to get Emby account info: ${response.body}');
    }
  }

  // Get Bound Vendors (Updated to use specific endpoints)
  static Future<List<String>> getBoundVendors() async {
    final headers = await _getHeaders();
    final List<String> vendors = [];
    
    // Check Alist
    try {
      final alistResponse = await http.get(
        Uri.parse('$baseUrl/vendor/alist/binds'),
        headers: headers,
      );
      _checkResponse(alistResponse);
      if (alistResponse.statusCode == 200 || alistResponse.statusCode == 201) {
        final data = jsonDecode(alistResponse.body);
        if (data is List && data.isNotEmpty) {
          vendors.add('alist');
        } else if (data['data'] is List && (data['data'] as List).isNotEmpty) {
          vendors.add('alist');
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
    }

    // Check Emby
    try {
      final embyResponse = await http.get(
        Uri.parse('$baseUrl/vendor/emby/binds'),
        headers: headers,
      );
      _checkResponse(embyResponse);
      if (embyResponse.statusCode == 200 || embyResponse.statusCode == 201) {
        final data = jsonDecode(embyResponse.body);
        if (data is List && data.isNotEmpty) {
          vendors.add('emby');
        } else if (data['data'] is List && (data['data'] as List).isNotEmpty) {
          vendors.add('emby');
        }
      }
    } catch (e) {
      if (e is AuthException) rethrow;
    }

    return vendors;
  }

  // Add Movie (Updated to /api/room/movie/push with flexible payload)
  static Future<void> addMovie(String roomId, dynamic payload) async {
    final headers = await _getHeaders(roomId: roomId);
    
    // Determine endpoint based on payload type
    final String endpoint = payload is List ? '/room/movie/pushs' : '/room/movie/push';
    
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(payload),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to add movie: ${response.body}');
    }
  }

  // Batch Add Movies
  static Future<void> addMovies(String roomId, List<dynamic> movies) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/movie/pushs'),
      headers: headers,
      body: jsonEncode(movies),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to add movies: ${response.body}');
    }
  }

  // Delete Movie
  static Future<void> deleteMovie(String roomId, String movieId) async {
    await deleteMovies(roomId, [movieId]);
  }

  // Batch Delete Movies
  static Future<void> deleteMovies(String roomId, List<String> movieIds) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/movie/delete'),
      headers: headers,
      body: jsonEncode({
        'ids': movieIds,
      }),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to delete movies: ${response.body}');
    }
  }

  // Clear Movies
  static Future<void> clearMovies(String roomId, {String? parentId}) async {
    final headers = await _getHeaders(roomId: roomId);
    final Map<String, dynamic> body = {};
    if (parentId != null) {
      body['parentId'] = parentId;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/room/movie/clear'),
      headers: headers,
      body: jsonEncode(body),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to clear movies: ${response.body}');
    }
  }

  // Switch Movie
  static Future<void> switchMovie(String roomId, String movieId, {String? subPath}) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/movie/current'),
      headers: headers,
      body: jsonEncode({
        'id': movieId,
        'subPath': subPath ?? '',
      }),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to switch movie: ${response.body}');
    }
  }

  // Parse Bilibili
  static Future<Map<String, dynamic>> parseBilibili(String url) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/vendor/bilibili/parse'),
      headers: headers,
      body: jsonEncode({
        'url': url,
      }),
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return data['data'];
      }
      return data;
    } else {
      throw Exception('Failed to parse Bilibili: ${response.body}');
    }
  }

  // List Alist
  static Future<dynamic> listAlist(String path, {String? keyword, int page = 1, int max = 20}) async {
    final headers = await _getHeaders();
    
    // Construct URI with query parameters
    final uri = Uri.parse('$baseUrl/vendor/alist/list').replace(queryParameters: {
      'page': page.toString(),
      'max': max.toString(),
    });

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'path': path == '/' ? '' : path,
        'keyword': keyword ?? '',
      }),
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return data['data'];
      }
      return data;
    } else {
      String errorMessage = response.body;
      try {
        final errorJson = jsonDecode(response.body);
        if (errorJson['error'] != null) {
          errorMessage = errorJson['error'];
        } else if (errorJson['message'] != null) {
          errorMessage = errorJson['message'];
        }
      } catch (_) {}
      throw Exception(errorMessage);
    }
  }

  // Emby Login
  static Future<Map<String, dynamic>> loginEmby(String host, String username, String password) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/vendor/emby/login'),
      headers: headers,
      body: jsonEncode({
        'host': host,
        'username': username,
        'password': password,
      }),
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 204) {
      if (response.body.isEmpty) return {};
      try {
        final data = jsonDecode(response.body);
        if (data['data'] != null) {
          return data['data'];
        }
        return data;
      } catch (e) {
        // Return empty map if parsing fails but status is success (e.g. empty body)
        return {};
      }
    } else {
      throw Exception('Failed to login to Emby: ${response.body}');
    }
  }

  // List Emby
  static Future<dynamic> listEmby(String path, {String? keyword, int page = 1, int max = 20}) async {
    final headers = await _getHeaders();
    
    // Construct URI with query parameters
    final uri = Uri.parse('$baseUrl/vendor/emby/list').replace(queryParameters: {
      'page': page.toString(),
      'max': max.toString(),
    });

    // Emby root path should be empty string, not "/"
    final safePath = path == '/' ? '' : path;

    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'path': safePath,
        if (keyword != null) 'keyword': keyword,
      }),
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return data['data'];
      }
      return data;
    } else {
      throw Exception('Failed to list Emby: ${response.body}');
    }
  }

  // Get Room Info
  static Future<WRoom> getRoomInfo(String roomId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.get(
      Uri.parse('$baseUrl/room/info'),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      if (data['data'] != null) {
        return WRoom.fromJson(data['data']);
      }
      return WRoom.fromJson(data);
    } else {
      throw Exception('Failed to get room info: ${response.body}');
    }
  }

  // Update Room Password
  static Future<void> updateRoomPassword(String roomId, String? password) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/pwd'),
      headers: headers,
      body: jsonEncode({
        'password': password ?? '',
      }),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to update room password: ${response.body}');
    }
  }

  // Get Room Settings
  static Future<WRoomSettings> getRoomSettings(String roomId, {bool isAdmin = false}) async {
    final headers = await _getHeaders(roomId: roomId);
    final url = isAdmin ? '$baseUrl/room/admin/settings' : '$baseUrl/room/settings';
    
    // Using GET as is standard for fetching settings, though some APIs might use POST.
    // Based on Vue code using same URL for update (which is likely POST/PUT), fetch is likely GET.
    final response = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    _checkResponse(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      final data = jsonDecode(response.body);
      // Data might be directly the settings object or wrapped in 'data'
      if (data['data'] != null) {
         return WRoomSettings.fromJson(data['data']);
      }
      return WRoomSettings.fromJson(data);
    } else {
      throw Exception('Failed to get room settings: ${response.body}');
    }
  }

  // Update Room Admin Settings
  static Future<void> updateRoomAdminSettings(String roomId, Map<String, dynamic> settings) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/settings'),
      headers: headers,
      body: jsonEncode(settings),
    );
    _checkResponse(response);

    if (response.statusCode != 200 && response.statusCode != 201 && response.statusCode != 204) {
      throw Exception('Failed to update room settings: ${response.body}');
    }
  }

  // Kick Member (Delete from room)
  static Future<void> kickMember(String roomId, String userId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/members/delete'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to kick member: ${response.body}');
    }
  }

  // Approve Member
  static Future<void> approveMember(String roomId, String userId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/members/approve'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to approve member: ${response.body}');
    }
  }

  // Delete Room Member (Kick without ban)
  static Future<void> deleteRoomMember(String roomId, String userId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/members/delete'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to delete member: ${response.body}');
    }
  }

  // Set Room Admin
  static Future<void> setRoomAdmin(String roomId, String userId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/members/admin'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to set room admin: ${response.body}');
    }
  }

  // Remove Room Admin (Set as Member)
  static Future<void> removeRoomAdmin(String roomId, String userId) async {
    final headers = await _getHeaders(roomId: roomId);
    final response = await http.post(
      Uri.parse('$baseUrl/room/admin/members/member'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to remove room admin: ${response.body}');
    }
  }

  // --- Admin APIs ---

  // Admin Get User List
  static Future<Map<String, dynamic>> adminGetUsers({
    int page = 1,
    int max = 20,
    String? search,
  }) async {
    final headers = await _getHeaders();
    String query = 'page=$page&max=$max';
    if (search != null && search.isNotEmpty) {
      query += '&search=$search&keyword=$search';
    }
    
    final response = await http.get(
      Uri.parse('$baseUrl/admin/user/list?$query'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      // The API returns { data: { list: [...], total: ... } } or just { list: [...], total: ... }
      // We need to handle both cases, favoring the data wrapper.
      if (json['data'] != null && json['data'] is Map) {
        return json['data'];
      }
      return json;
    } else {
      throw Exception('Failed to load users: ${response.body}');
    }
  }

  // Admin Add User
  static Future<void> adminAddUser(String username, String password, int role) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/user/add'),
      headers: headers,
      body: jsonEncode({
        'username': username,
        'password': password,
        'role': role,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to add user: ${response.body}');
    }
  }

  // Admin Delete User
  static Future<void> adminDeleteUser(String userId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/user/delete'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  // Admin Set Role (Add/Remove Admin)
  // Actually the API splits this into /admin/admin/add and /admin/admin/delete
  static Future<void> adminSetAdmin(String userId, bool isAdmin) async {
    final headers = await _getHeaders();
    final endpoint = isAdmin ? '/admin/admin/add' : '/admin/admin/delete';
    
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to set admin role: ${response.body}');
    }
  }

  // Admin Get Settings
  static Future<Map<String, dynamic>> adminGetSettings(String type) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/admin/settings/$type'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      // The API returns { data: { key: value, ... } } or just { key: value, ... }
      if (json['data'] != null && json['data'] is Map) {
        // Vue logic iterates over data[group][setting]
        // If type is 'user', data might be { user: { enable_guest: true, ... } }
        // We need to flatten it or return the inner map if it matches the requested type
        final data = json['data'];
        if (data[type] != null && data[type] is Map) {
          return data[type];
        }
        return data;
      }
      return json;
    } else {
      throw Exception('Failed to load settings: ${response.body}');
    }
  }

  // Change Password (Current User)
  static Future<void> changePassword(String newPassword) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/user/password'),
      headers: headers,
      body: jsonEncode({
        'password': newPassword,
      }),
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      String? token;
      // Handle response structure { data: { token: ... } }
      if (json['data'] != null && json['data']['token'] != null) {
        token = json['data']['token'];
      } else if (json['token'] != null) {
        token = json['token'];
      }

      if (token != null) {
        await _saveToken(token);
      }
    } else {
      throw Exception('Failed to change password: ${response.body}');
    }
  }

  // Admin Approve User
  static Future<void> adminApproveUser(String userId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/user/approve'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to approve user: ${response.body}');
    }
  }

  // Admin Ban/Unban User
  static Future<void> adminBanUser(String userId, bool ban) async {
    final headers = await _getHeaders();
    final endpoint = ban ? '/admin/user/ban' : '/admin/user/unban';
    
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode({
        'id': userId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to ${ban ? 'ban' : 'unban'} user: ${response.body}');
    }
  }

  // Admin Get Room List
  static Future<Map<String, dynamic>> adminGetRooms({
    int page = 1,
    int max = 20,
    String? search,
    String? sort = 'createdAt',
    String? order = 'desc',
    String? status,
  }) async {
    final headers = await _getHeaders();
    String query = 'page=$page&max=$max&sort=$sort&order=$order';
    if (search != null && search.isNotEmpty) {
      query += '&search=all&keyword=$search';
    }
    if (status != null && status.isNotEmpty) {
      query += '&status=$status';
    }
    
    final response = await http.get(
      Uri.parse('$baseUrl/admin/room/list?$query'),
      headers: headers,
    );
    _checkResponse(response);

    if (_isSuccess(response.statusCode)) {
      final json = jsonDecode(response.body);
      if (json['data'] != null && json['data'] is Map) {
        return json['data'];
      }
      return json;
    } else {
      throw Exception('Failed to load admin rooms: ${response.body}');
    }
  }

  // Admin Ban/Unban Room
  static Future<void> adminBanRoom(String roomId, bool ban) async {
    final headers = await _getHeaders();
    final endpoint = ban ? '/admin/room/ban' : '/admin/room/unban';
    
    final response = await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode({
        'id': roomId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to ${ban ? 'ban' : 'unban'} room: ${response.body}');
    }
  }

  // Admin Delete Room
  static Future<void> adminDeleteRoom(String roomId) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/room/delete'),
      headers: headers,
      body: jsonEncode({
        'id': roomId,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to delete room: ${response.body}');
    }
  }

  // Admin Update Setting
  static Future<void> adminUpdateSetting(String key, dynamic value) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/admin/settings'),
      headers: headers,
      body: jsonEncode({
        key: value,
      }),
    );
    _checkResponse(response);

    if (!_isSuccess(response.statusCode)) {
      throw Exception('Failed to update setting: ${response.body}');
    }
  }
}
