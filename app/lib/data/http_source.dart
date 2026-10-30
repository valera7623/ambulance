import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'snapshot.dart';
import 'sync.dart';

class SnapshotHttpClient implements SnapshotSource {
  SnapshotHttpClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<String> login(String baseUrl, String password) async {
    final response = await _send(
      () => _client.post(
        _uri(baseUrl, '/v1/auth/login'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'password': password}),
      ),
    );
    if (response.statusCode == 401) throw AuthException();
    _expectOk(response);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['token'] as String;
  }

  @override
  Future<ContentManifest> manifest(String baseUrl, String token) async {
    final response = await _authorizedGet(baseUrl, '/v1/content/manifest', token);
    return ContentManifest.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  @override
  Future<Snapshot> download(String baseUrl, String token) async {
    final response = await _authorizedGet(baseUrl, '/v1/content/snapshot', token);
    return Snapshot.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<http.Response> _authorizedGet(String baseUrl, String path, String token) async {
    final response = await _send(
      () => _client.get(
        _uri(baseUrl, path),
        headers: {'authorization': 'Bearer $token'},
      ),
    );
    if (response.statusCode == 401) throw AuthException();
    _expectOk(response);
    return response;
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw SyncTransportException('timeout', offline: true);
    } on SocketException {
      throw SyncTransportException('offline', offline: true);
    } on http.ClientException catch (error) {
      throw SyncTransportException(error.message, offline: true);
    }
  }

  void _expectOk(http.Response response) {
    if (response.statusCode != 200) {
      throw SyncTransportException('HTTP ${response.statusCode}');
    }
  }

  Uri _uri(String baseUrl, String path) {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$trimmed$path');
  }
}
