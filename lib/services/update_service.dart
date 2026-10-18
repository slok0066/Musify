import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/build_info.dart';
import '../core/theme/swiss_tokens.dart';
import '../core/theme/tactile_decorations.dart';

/// Metadata for an available application update.
class AppUpdateInfo {
  final String version;
  final int buildNumber;
  final String releaseNotes;
  final String downloadUrl;
  final bool isMandatory;
  final String? publishedAt;

  const AppUpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    this.isMandatory = false,
    this.publishedAt,
  });

  bool get hasUpdate =>
      buildNumber > kAppBuild ||
      (_compareVersions(version, kAppVersion) > 0);

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
    return AppUpdateInfo(
      version: json['version'] as String? ?? json['tag_name'] as String? ?? '1.0.4',
      buildNumber: (json['build'] as num?)?.toInt() ??
          (json['build_number'] as num?)?.toInt() ??
          (kAppBuild + 1),
      releaseNotes: json['release_notes'] as String? ??
          json['body'] as String? ??
          '• Fresh Spotify-class poster dynamic gradients\n• Clean new official app logo\n• Player and audio performance polish',
      downloadUrl: json['download_url'] as String? ??
          json['html_url'] as String? ??
          'https://github.com/slok0066/Musify/releases/latest',
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

  /// Checks for an update without throwing. Returns null if offline or up to date.
  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (_dismissedThisSession && !force) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        updateEndpoint,
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );

      final data = response.data;
      if (data == null) return null;

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

  /// Displays the cute, minimal update popup dialog.
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    final t = SwissTokens.of(context);

    await showDialog<void>(
      context: context,
      barrierDismissible: !info.isMandatory,
      builder: (ctx) {
        return Center(
          child: SingleChildScrollView(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 330,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.hairline, width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Cute Header with Icon Glow
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: t.accent.withValues(alpha: 0.15),
                          ),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: t.hairline, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: Image.asset(
                              'assets/icon/app_icon.png',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Title
                    Text(
                      'Update Available! 🎉',
                      style: SwissType.displaySm.copyWith(
                        color: t.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),

                    // Version badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: t.surfaceSunken,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.hairline, width: 0.8),
                      ),
                      child: Text(
                        'v${info.version} (current v$kAppVersion)',
                        style: SwissType.micro.copyWith(
                          color: t.inkMuted,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Changelog box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surfaceSunken,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.hairline, width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "WHAT'S NEW",
                            style: SwissType.micro.copyWith(
                              color: t.inkFaint,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            info.releaseNotes,
                            style: SwissType.body.copyWith(
                              color: t.ink,
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action buttons
                    Row(
                      children: [
                        if (!info.isMandatory)
                          Expanded(
                            child: TactileKeycap(
                              height: 44,
                              onPressed: () {
                                Navigator.of(ctx).pop();
                              },
                              child: Center(
                                child: Text(
                                  'LATER',
                                  style: SwissType.label.copyWith(color: t.ink),
                                ),
                              ),
                            ),
                          ),
                        if (!info.isMandatory) const SizedBox(width: 10),
                        Expanded(
                          child: TactileKeycap(
                            height: 44,
                            accent: true,
                            onPressed: () async {
                              HapticFeedback.mediumImpact();
                              Navigator.of(ctx).pop();
                              final uri = Uri.parse(info.downloadUrl);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(
                                  uri,
                                  mode: LaunchMode.externalApplication,
                                );
                              }
                            },
                            child: Center(
                              child: Text(
                                'UPDATE NOW',
                                style: SwissType.label.copyWith(
                                  color: t.accentInk,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
