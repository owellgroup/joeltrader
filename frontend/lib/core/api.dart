import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Backend URL on the Dokploy server. The Python engine is private; the API proxies it.
/// Override: flutter run --dart-define=API_URL=http://145.241.187.174:8181
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://145.241.187.174:8181');

String errMsg(Object? e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map) {
      final m = d['message'] ?? d['error'];
      if (m != null && m.toString().isNotEmpty) return m.toString();
    }
    if (e.response == null) return 'Cannot reach the server';
    return 'Request failed (${e.response?.statusCode})';
  }
  return e?.toString() ?? 'Unknown error';
}

class Session extends ChangeNotifier {
  final _store = const FlutterSecureStorage();
  late final Dio dio;
  String? token;
  Map<String, dynamic>? user;
  bool ready = false;

  Session() {
    dio = Dio(BaseOptions(baseUrl: apiUrl, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 90)));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) {
        if (token != null) o.headers['Authorization'] = 'Bearer $token';
        h.next(o);
      },
      onError: (e, h) {
        if (e.response?.statusCode == 401 && token != null && !e.requestOptions.path.contains('/auth/login')) logout();
        h.next(e);
      },
    ));
  }

  bool get loggedIn => token != null && user != null;
  bool get isSuper => user?['role'] == 'SUPER_ADMIN';

  /// Called once at start: restores the saved session so the user stays logged in.
  Future<void> init() async {
    token = await _store.read(key: 'jt_token');
    if (token != null) {
      try {
        await _apply((await dio.post('/api/auth/refresh')).data);
      } on DioException catch (e) {
        if (e.response?.statusCode == 401) {
          token = null;
          await _store.delete(key: 'jt_token');
        } else {
          try { user = (await dio.get('/api/auth/me')).data; } catch (_) {}
        }
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _apply(Map d) async {
    token = d['token'];
    user = Map<String, dynamic>.from(d['user']);
    await _store.write(key: 'jt_token', value: token);
  }

  Future<void> login(String email, String password) async {
    final r = await dio.post('/api/auth/login', data: {'email': email, 'password': password});
    await _apply(r.data);
    notifyListeners();
  }

  Future<void> logout() async {
    token = null;
    user = null;
    await _store.delete(key: 'jt_token');
    notifyListeners();
  }

  Future<void> reloadUser() async {
    user = (await dio.get('/api/auth/me')).data;
    notifyListeners();
  }

  Future<dynamic> get(String p, {Map<String, dynamic>? q}) async => (await dio.get(p, queryParameters: q)).data;
  Future<dynamic> post(String p, [Object? body, Map<String, dynamic>? q]) async => (await dio.post(p, data: body, queryParameters: q)).data;
  Future<dynamic> put(String p, [Object? body]) async => (await dio.put(p, data: body)).data;
  Future<dynamic> patch(String p, [Object? body]) async => (await dio.patch(p, data: body)).data;
  Future<dynamic> delete(String p) async => (await dio.delete(p)).data;
}
