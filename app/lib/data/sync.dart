import 'snapshot.dart';

class AuthException implements Exception {}

class SyncTransportException implements Exception {
  SyncTransportException(this.message, {this.offline = false});

  final String message;
  final bool offline;
}

enum SyncOutcome { upToDate, updated, offline, authRequired, error }

abstract class SnapshotSource {
  Future<String> login(String baseUrl, String password);
  Future<ContentManifest> manifest(String baseUrl, String token);
  Future<Snapshot> download(String baseUrl, String token);
}

class ContentSync {
  ContentSync(this.source);

  final SnapshotSource source;

  Future<SyncOutcome> run({
    required String baseUrl,
    required String? token,
    required String? localFingerprint,
    required Future<void> Function(Snapshot snapshot) replace,
    required Future<void> Function() clearToken,
  }) async {
    if (token == null || token.isEmpty) return SyncOutcome.authRequired;
    try {
      final manifest = await source.manifest(baseUrl, token);
      if (localFingerprint != null && localFingerprint == manifest.fingerprint) {
        return SyncOutcome.upToDate;
      }
      final snapshot = await source.download(baseUrl, token);
      await replace(snapshot);
      return SyncOutcome.updated;
    } on AuthException {
      await clearToken();
      return SyncOutcome.authRequired;
    } on SyncTransportException catch (error) {
      return error.offline ? SyncOutcome.offline : SyncOutcome.error;
    }
  }
}
