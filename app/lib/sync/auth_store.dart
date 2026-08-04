import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A signed-in session.
class Session {
  final String accessToken;
  final String refreshToken;

  const Session({required this.accessToken, required this.refreshToken});
}

/// Holds the reader's tokens.
///
/// Tokens go in the platform keystore rather than the app's database. A
/// refresh token is a two-month credential: anyone who reads it can act as
/// the reader until it expires. The database holds book files and reading
/// positions, which are private but not credentials, and it is readable by
/// anyone with the device's filesystem.
///
/// On Android that means the Keystore, on Windows the credential locker, on
/// iOS the Keychain. Web falls back to local storage, which is weaker, and
/// is why the web build should be treated as the least trusted target.
class AuthStore {
  static const _accessKey = 'hereader.access_token';
  static const _refreshKey = 'hereader.refresh_token';
  static const _deviceKey = 'hereader.device_id';

  final FlutterSecureStorage _storage;

  /// Broadcast so the app can react to sign-out from anywhere: an expired
  /// refresh token means every screen holding data is now showing something
  /// the reader is no longer entitled to sync.
  final _sessions = StreamController<Session?>.broadcast();

  Session? _current;

  AuthStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  Stream<Session?> get sessions => _sessions.stream;

  Session? get current => _current;

  bool get isSignedIn => _current != null;

  /// Reads any stored session back into memory. Call once at startup.
  Future<Session?> restore() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);

    if (access == null || refresh == null) {
      _current = null;
      return null;
    }

    _current = Session(accessToken: access, refreshToken: refresh);
    return _current;
  }

  Future<void> save(Session session) async {
    _current = session;

    await _storage.write(key: _accessKey, value: session.accessToken);
    await _storage.write(key: _refreshKey, value: session.refreshToken);

    _sessions.add(session);
  }

  Future<void> clear() async {
    _current = null;

    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);

    _sessions.add(null);
  }

  String? _deviceId;

  /// A stable identifier for this installation.
  ///
  /// Generated once and kept, because it is part of every clock stamp: a
  /// device that changed its id would look like a new device to the server,
  /// and its own writes would start appearing as conflicts against itself.
  ///
  /// Not tied to any hardware identifier. Those are restricted on modern
  /// platforms, and a random value serves the purpose exactly as well.
  Future<String> deviceId() async {
    final cached = _deviceId;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _deviceKey);
    if (stored != null && stored.isNotEmpty) {
      _deviceId = stored;
      return stored;
    }

    final generated = _generateDeviceId();
    await _storage.write(key: _deviceKey, value: generated);
    _deviceId = generated;
    return generated;
  }

  void dispose() => _sessions.close();

  /// 16 characters from the alphabet the server's stamp format allows.
  /// 16 characters from the alphabet the server's stamp format allows.
  static String _generateDeviceId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();

    return List.generate(
      16,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }
}
