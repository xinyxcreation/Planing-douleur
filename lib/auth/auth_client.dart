import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthClient {
  AuthClient({
    required this.baseUrl,
  });

  final String baseUrl;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return _post('/auth/login', {
      'email': email.trim(),
      'password': password,
    });
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    return _post('/auth/register', {
      'email': email.trim(),
      'password': password,
      'displayName': displayName?.trim(),
    });
  }

  Future<void> logout(String token) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
    } catch (_) {
      // La session locale sera supprimée même si le serveur est inaccessible.
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: const {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw AuthException(
        response.statusCode,
        'Réponse serveur invalide.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map<String, dynamic>
          ? decoded['message']?.toString() ?? 'Erreur d’authentification.'
          : 'Erreur d’authentification.';

      throw AuthException(response.statusCode, message);
    }

    if (decoded is! Map<String, dynamic>) {
      throw AuthException(
        response.statusCode,
        'Format de réponse invalide.',
      );
    }

    return decoded;
  }
}

class AuthException implements Exception {
  AuthException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'AuthException($statusCode): $message';
}
