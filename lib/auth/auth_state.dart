import 'package:flutter/foundation.dart';

import '../sync/sync_config.dart';
import 'auth_client.dart';
import 'auth_storage.dart';

enum AuthStatus {
  loading,
  loggedOut,
  loggedIn,
}

class AuthState extends ChangeNotifier {
  AuthState() : _client = AuthClient(baseUrl: SyncConfig.baseUrl);

  final AuthClient _client;
  final AuthStorage _storage = AuthStorage();

  AuthStatus _status = AuthStatus.loading;
  Map<String, dynamic>? _session;
  String? _error;

  AuthStatus get status => _status;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;
  String? get error => _error;

  String? get token => _session?['token']?.toString();
  String? get userId => _session?['userId']?.toString();
  String? get email => _session?['email']?.toString();
  String? get displayName => _session?['displayName']?.toString();

  Future<void> load() async {
    _error = null;

    try {
      _session = await _storage.loadSession();

      _status = _session == null
          ? AuthStatus.loggedOut
          : AuthStatus.loggedIn;
    } catch (e) {
      _session = null;
      _status = AuthStatus.loggedOut;
      _error = 'Impossible de restaurer la session.';
    }

    notifyListeners();
  }

  Future<bool> login({
    required String email,
    required String password,
    required bool rememberMe,
  }) async {
    _error = null;
    notifyListeners();

    try {
      final response = await _client.login(
        email: email,
        password: password,
      );

      await _storeResponse(
        response,
        rememberMe: rememberMe,
      );

      _status = AuthStatus.loggedIn;
      notifyListeners();

      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Impossible de contacter le serveur.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> register({
    required String email,
    required String password,
    String? displayName,
    required bool rememberMe,
  }) async {
    _error = null;
    notifyListeners();

    try {
      final response = await _client.register(
        email: email,
        password: password,
        displayName: displayName,
      );

      await _storeResponse(
        response,
        rememberMe: rememberMe,
      );

      _status = AuthStatus.loggedIn;
      notifyListeners();

      return true;
    } on AuthException catch (e) {
      _error = e.message;
      notifyListeners();
      return false;
    } catch (_) {
      _error = 'Impossible de contacter le serveur.';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final currentToken = token;

    if (currentToken != null) {
      await _client.logout(currentToken);
    }

    await _storage.clearSession();

    _session = null;
    _status = AuthStatus.loggedOut;
    _error = null;

    notifyListeners();
  }

  Future<void> _storeResponse(
    Map<String, dynamic> response, {
    required bool rememberMe,
  }) async {
    final user = response['user'];

    final session = response['session'];

    if (user is! Map || session is! Map) {
      throw AuthException(
        500,
        'Réponse d’authentification invalide.',
      );
    }

    final token = session['token']?.toString();
    final sessionId = session['id']?.toString();
    final expiresAt = session['expiresAt']?.toString();

    final userId = user['id']?.toString();
    final email = user['email']?.toString();

    if (token == null ||
        sessionId == null ||
        expiresAt == null ||
        userId == null ||
        email == null) {
      throw AuthException(
        500,
        'Session utilisateur incomplète.',
      );
    }

    _session = {
      'token': token,
      'sessionId': sessionId,
      'userId': userId,
      'email': email,
      'displayName': user['displayName']?.toString(),
      'expiresAt': expiresAt,
      'rememberMe': rememberMe,
    };

    await _storage.saveSession(
      token: token,
      userId: userId,
      email: email,
      displayName: user['displayName']?.toString(),
      expiresAt: expiresAt,
      rememberMe: rememberMe,
    );
  }
}
