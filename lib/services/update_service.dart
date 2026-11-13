import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/build_info.dart';

/// Metadata for an available application update.
class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final String? apkUrl;
  final bool isMandatory;
  final String? publishedAt;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    this.apkUrl,
    this.isMandatory = false,
    this.publishedAt,
  });

  bool get hasUpdate =>
      buildNumber > kAppBuild ||
      (_compareVersions(version, kAppVersion) > 0);

  String get directApkUrl {
    if (apkUrl != null && apkUrl!.trim().isNotEmpty && apkUrl!.endsWith('.apk')) {
      return apkUrl!.trim();
    }
    if (downloadUrl.trim().endsWith('.apk')) {
      return downloadUrl.trim();
    }
    final cleanVersion = version.startsWith('v') ? version : 'v$version';
    return 'https://github.com/slok0066/Musify/releases/download/$cleanVersion/app-arm64-v8a-release.apk';
  }

  static int _compareVersions(String v1, String v2) {
    try {
      final p1 = v1.split('.').map(int.tryParse).whereType<int>().toList();
      final p2 = v2.split('.').map(int.tryParse).whereType<int>().toList();
      final len = p1.length > p2.length ? p1.length : p2.length;
      for (int i = 0; i < len; i++) {
        final a = i < p1.length ? p1[i] : 0;
        final b = i < p2.length ? p2[i] : 0;
        if (a != b) return a.compareTo(b);
      }
      return 0;
    } catch (_) {
      return 0;
    }
  }

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    final v = json['version'] as String? ?? json['tag_name'] as String? ?? '1.0.5';
    final rawDownload = json['download_url'] as String? ?? json['html_url'] as String?;
    final rawApk = json['apk_url'] as String?;

    return AppUpdateInfo(
      version: v,
      buildNumber: (json['build'] as num?)?.toInt() ??
          (json['build_number'] as num?)?.toInt() ??
          (kAppBuild + 1),
      releaseNotes: json['release_notes'] as String? ??
          json['body'] as String? ??
          '• Direct in-app update installation\n• Performance optimizations and UI polish',
      downloadUrl: rawDownload ?? 'https://github.com/slok0066/Musify/releases/latest',
      apkUrl: rawApk,
      isMandatory: json['mandatory'] as bool? ?? false,
      publishedAt: json['published_at'] as String?,
    );
  }
}

/// Service that checks for remote updates and renders the update modal.
class UpdateService {
  final Dio _dio;
  bool _dismissedThisSession = false;

  /// Default endpoint pointing to your GitHub repository's version.json.
  String updateEndpoint =
      'https://raw.githubusercontent.com/slok0066/Musify/main/version.json';

  UpdateService(this._dio);

  /// GitHub's raw CDN keeps a copy of `version.json` for five minutes, so a
  /// release published moments ago can stay invisible to the very next check.
  /// Every request carries a unique stamp and `no-cache`, which makes the edge
  /// hand back what is on the branch right now instead of its cached copy.
  String _freshEndpoint() {
    final millis = DateTime.now().millisecondsSinceEpoch;
    final separator = updateEndpoint.contains('?') ? '&' : '?';
    return '$updateEndpoint${separator}t=$millis';
  }

  /// Checks for an update without throwing. Returns null if offline or up to date.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (_dismissedThisSession && !force) return null;

    try {
      final response = await _dio.get<dynamic>(
        _freshEndpoint(),
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          headers: const {'Cache-Control': 'no-cache'},
        ),
      );

      final dynamic raw = response.data;
      if (raw == null) return null;

      final Map<String, dynamic> data;
      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else {
          return null;
        }
      } else {
        return null;
      }

      final info = AppUpdateInfo.fromJson(data);
      if (info.hasUpdate || force) {
        return info;
      }
      return null;
    } catch (_) {
      // Offline or endpoint unavailable: silent degradation
      return null;
    }
  }

  void markDismissed() {
    _dismissedThisSession = true;
  }
}
