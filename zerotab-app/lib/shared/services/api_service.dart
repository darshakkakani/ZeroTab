import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/constants/api_constants.dart';

/// Singleton Dio client that auto-attaches the Supabase JWT and apikey header.
/// Now points to Supabase Edge Functions instead of a separate backend.
class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  late final Dio _dio;

  void init() {
    _dio = Dio(BaseOptions(
      baseUrl:        ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          options.headers['Authorization'] = 'Bearer ${session.accessToken}';
        }
        // Supabase Edge Functions require the anon key as apikey header
        options.headers['apikey'] = ApiConstants.supabaseAnonKey;
        return handler.next(options);
      },
      onError: (error, handler) {
        if (error.response?.statusCode == 401) {
          Supabase.instance.client.auth.signOut();
        }
        return handler.next(error);
      },
    ));
  }

  Dio get dio => _dio;

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? params}) =>
      _dio.get<T>(path, queryParameters: params);

  Future<Response<T>> post<T>(String path, {dynamic data}) =>
      _dio.post<T>(path, data: data);

  Future<Response<T>> put<T>(String path, {dynamic data}) =>
      _dio.put<T>(path, data: data);

  Future<Response<T>> patch<T>(String path, {dynamic data}) =>
      _dio.patch<T>(path, data: data);

  Future<Response<T>> delete<T>(String path) =>
      _dio.delete<T>(path);
}

final api = ApiService();

String apiErrorMessage(dynamic e) {
  if (e is DioException) {
    final body = e.response?.data;
    if (body is Map) {
      final msg = body['error'] ?? body['message'];
      if (msg != null) return msg.toString();
    }
    if (e.response?.statusCode != null) {
      return 'Server error ${e.response!.statusCode}';
    }
    return e.message ?? e.toString();
  }
  return e.toString();
}
