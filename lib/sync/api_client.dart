import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiClient {
  ApiClient({
    required this.baseUrl,
    String? token,
  }) : _token = token;

  final String baseUrl;
  String? _token;

  String? get token => _token;

  set token(String? value) {
    _token = value;
  }

  Map<String, String> get _headers {
    final token = _token;

    if (token == null || token.isEmpty) {
      throw ApiException(
        401,
        'Authentification requise.',
      );
    }

    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: query,
    );
  }

  Future<Map<String, dynamic>> getSync(int cursor) async {
    final response = await http.get(
      _uri('/sync', {
        'cursor': cursor.toString(),
      }),
      headers: _headers,
    );

    return _decode(response);
  }

  Future<Map<String, dynamic>> push(
    List<Map<String, dynamic>> changes,
  ) async {
    final response = await http.post(
      _uri('/sync'),
      headers: _headers,
      body: jsonEncode({
        'changes': changes,
      }),
    );

    return _decode(response);
  }

  Future<List<dynamic>> getPainCatalog() async {
    final response = await http.get(
      _uri('/catalog/pain'),
      headers: _headers,
    );

    return _decodeList(response);
  }

  Future<List<dynamic>> getActivityCatalog() async {
    final response = await http.get(
      _uri('/catalog/activity'),
      headers: _headers,
    );

    return _decodeList(response);
  }

  Future<Map<String, dynamic>> getEntry(String date) async {
    final response = await http.get(
      _uri('/entries/$date'),
      headers: _headers,
    );

    return _decode(response);
  }

  List<dynamic> _decodeList(http.Response response) {
    dynamic body;

    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        response.statusCode,
        'Réponse serveur invalide.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final message = body is Map<String, dynamic>
          ? body['message']?.toString() ?? 'Erreur serveur.'
          : 'Erreur serveur.';

      throw ApiException(
        response.statusCode,
        message,
      );
    }

    if (body is! List) {
      throw ApiException(
        response.statusCode,
        'Format de réponse invalide.',
      );
    }

    return body;
  }

  Map<String, dynamic> _decode(http.Response response) {
    dynamic body;

    try {
      body = jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        response.statusCode,
        'Réponse serveur invalide.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      final message = body is Map<String, dynamic>
          ? body['message']?.toString() ?? 'Erreur serveur.'
          : 'Erreur serveur.';

      throw ApiException(
        response.statusCode,
        message,
      );
    }

    if (body is! Map<String, dynamic>) {
      throw ApiException(
        response.statusCode,
        'Format de réponse invalide.',
      );
    }

    return body;
  }
}

class ApiException implements Exception {
  ApiException(
    this.statusCode,
    this.message,
  );

  final int statusCode;
  final String message;

  @override
  String toString() {
    return 'ApiException($statusCode): $message';
  }
}
