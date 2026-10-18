import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/build_info.dart';
import '../core/theme/swiss_tokens.dart';
import '../core/theme/tactile_decorations.dart';
import 'service_locator.dart';

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
  static bool isDialogShowing = false;

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

  /// Displays the clean, minimal in-app update popup dialog.
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    if (isDialogShowing) return;
    isDialogShowing = true;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !info.isMandatory,
        builder: (ctx) => _UpdateDialogModal(info: info),
      );
    } finally {
      isDialogShowing = false;
    }
  }
}

enum _UpdateStep {
  prompt,
  downloading,
  ready,
  error,
}

class _UpdateDialogModal extends StatefulWidget {
  final AppUpdateInfo info;

  const _UpdateDialogModal({required this.info});

  @override
  State<_UpdateDialogModal> createState() => _UpdateDialogModalState();
}

class _UpdateDialogModalState extends State<_UpdateDialogModal> {
  _UpdateStep _step = _UpdateStep.prompt;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadedApkPath;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel('Dialog disposed');
    super.dispose();
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _openApk(String path) async {
    try {
      final result = await OpenFilex.open(
        path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type != ResultType.done) {
        debugPrint('OpenFilex response: ${result.type} - ${result.message}');
      }
    } catch (e) {
      debugPrint('Error opening APK: $e');
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
    setState(() {
      _step = _UpdateStep.prompt;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
    });
  }

  Future<void> _startDownload() async {
    setState(() {
      _step = _UpdateStep.downloading;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = 0;
      _errorMessage = null;
    });

    _cancelToken = CancelToken();

    try {
      final targetUrl = widget.info.directApkUrl;
      final dir = await getTemporaryDirectory();
      final fileName = 'musify_v${widget.info.version}.apk';
      final saveFile = File('${dir.path}/$fileName');

      if (await saveFile.exists()) {
        try {
          await saveFile.delete();
        } catch (_) {}
      }

      final dio = locator<Dio>();
      await dio.download(
        targetUrl,
        saveFile.path,
        cancelToken: _cancelToken,
        deleteOnError: true,
        options: Options(
          followRedirects: true,
          maxRedirects: 7,
          receiveTimeout: const Duration(minutes: 5),
          sendTimeout: const Duration(seconds: 30),
        ),
        onReceiveProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _receivedBytes = received;
            _totalBytes = total;
            if (total > 0) {
              _progress = received / total;
            }
          });
        },
      );

      if (!mounted) return;

      _downloadedApkPath = saveFile.path;
      setState(() {
        _step = _UpdateStep.ready;
        _progress = 1.0;
      });

      // Automatically launch native Android package installer
      await _openApk(saveFile.path);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        if (mounted) {
          setState(() => _step = _UpdateStep.prompt);
        }
        return;
      }
      if (mounted) {
        setState(() {
          _step = _UpdateStep.error;
          _errorMessage = e.response?.statusCode == 404
              ? 'Release APK is being prepared on server.'
              : (e.message ?? 'Network connection error.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _step = _UpdateStep.error;
          _errorMessage = 'Could not download update: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = SwissTokens.of(context);

    return PopScope(
      canPop: _step != _UpdateStep.downloading && !widget.info.isMandatory,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _UpdateStep.downloading) {
          _cancelDownload();
        }
      },
      child: Center(
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _buildBody(context, t),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SwissTokens t) {
    switch (_step) {
      case _UpdateStep.prompt:
        return _buildPromptState(context, t);
      case _UpdateStep.downloading:
        return _buildDownloadingState(context, t);
      case _UpdateStep.ready:
        return _buildReadyState(context, t);
      case _UpdateStep.error:
        return _buildErrorState(context, t);
    }
  }

  Widget _buildPromptState(BuildContext context, SwissTokens t) {
    return Column(
      key: const ValueKey('prompt'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // App icon with subtle halo
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.accent.withValues(alpha: 0.12),
              ),
            ),
            Container(
              width: 58,
              height: 58,
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
          'Update Available',
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.hairline, width: 0.8),
          ),
          child: Text(
            'v${widget.info.version} (current v$kAppVersion)',
            style: SwissType.micro.copyWith(
              color: t.inkMuted,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Changelog card
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 160),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 0.8),
          ),
          child: SingleChildScrollView(
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
                  widget.info.releaseNotes,
                  style: SwissType.body.copyWith(
                    color: t.ink,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Actions
        Row(
          children: [
            if (!widget.info.isMandatory)
              Expanded(
                child: TactileKeycap(
                  height: 44,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    locator<UpdateService>().markDismissed();
                    Navigator.of(context).pop();
                  },
                  child: Center(
                    child: Text(
                      'LATER',
                      style: SwissType.label.copyWith(color: t.ink),
                    ),
                  ),
                ),
              ),
            if (!widget.info.isMandatory) const SizedBox(width: 10),
            Expanded(
              child: TactileKeycap(
                height: 44,
                accent: true,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _startDownload();
                },
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt_rounded, size: 16, color: t.accentInk),
                      const SizedBox(width: 4),
                      Text(
                        'UPDATE NOW',
                        style: SwissType.label.copyWith(
                          color: t.accentInk,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadingState(BuildContext context, SwissTokens t) {
    final percentInt = (_progress * 100).clamp(0, 100).toInt();

    return Column(
      key: const ValueKey('downloading'),
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minimal downloading icon with glow
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.accent.withValues(alpha: 0.3), width: 1.2),
          ),
          child: Center(
            child: Icon(
              Icons.download_rounded,
              color: t.accent,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Downloading Update',
          style: SwissType.displaySm.copyWith(
            color: t.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        // Large minimal percentage readout
        Text(
          '$percentInt%',
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: t.accent,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),

        // Bytes indicator
        Text(
          _formatBytes(_receivedBytes) +
              (_totalBytes > 0 ? ' / ${_formatBytes(_totalBytes)}' : ''),
          style: SwissType.micro.copyWith(
            color: t.inkMuted,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 18),

        // Sleek Swiss progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 7,
            width: double.infinity,
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: t.hairline, width: 0.6),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: _progress.clamp(0.02, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: t.accent,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(
                      color: t.accent.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),

        // Cancel button
        TactileKeycap(
          height: 42,
          onPressed: _cancelDownload,
          child: Center(
            child: Text(
              'CANCEL',
              style: SwissType.label.copyWith(color: t.inkMuted),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReadyState(BuildContext context, SwissTokens t) {
    return Column(
      key: const ValueKey('ready'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: t.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.accent.withValues(alpha: 0.35), width: 1.2),
          ),
          child: Center(
            child: Icon(
              Icons.check_circle_rounded,
              color: t.accent,
              size: 32,
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Ready to Install',
          style: SwissType.displaySm.copyWith(
            color: t.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        Text(
          'Musify v${widget.info.version} downloaded.\nPackage installer has been triggered.',
          textAlign: TextAlign.center,
          style: SwissType.body.copyWith(
            color: t.inkMuted,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: TactileKeycap(
                height: 44,
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Center(
                  child: Text(
                    'CLOSE',
                    style: SwissType.label.copyWith(color: t.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TactileKeycap(
                height: 44,
                accent: true,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  if (_downloadedApkPath != null) {
                    _openApk(_downloadedApkPath!);
                  }
                },
                child: Center(
                  child: Text(
                    'INSTALL NOW',
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
    );
  }

  Widget _buildErrorState(BuildContext context, SwissTokens t) {
    return Column(
      key: const ValueKey('error'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1.2),
          ),
          child: const Center(
            child: Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 30,
            ),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Download Failed',
          style: SwissType.displaySm.copyWith(
            color: t.ink,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),

        Text(
          _errorMessage ?? 'Network interrupted. Please try again.',
          textAlign: TextAlign.center,
          style: SwissType.body.copyWith(
            color: t.inkMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: TactileKeycap(
                height: 44,
                onPressed: () async {
                  final uri = Uri.parse(widget.info.downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Center(
                  child: Text(
                    'BROWSER',
                    style: SwissType.label.copyWith(color: t.ink),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TactileKeycap(
                height: 44,
                accent: true,
                onPressed: _startDownload,
                child: Center(
                  child: Text(
                    'RETRY',
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
    );
  }
}
