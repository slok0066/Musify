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

  /// Displays the clean, minimal full-screen in-app update page.
  static Future<void> showUpdateDialog(
    BuildContext context,
    AppUpdateInfo info,
  ) async {
    if (isDialogShowing) return;
    isDialogShowing = true;

    try {
      await Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              UpdateScreen(info: info),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          fullscreenDialog: true,
        ),
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

/// A full-screen, minimal and clean system update screen.
/// Follows Swiss design rules: flat surfaces, no glow, no gradients on buttons.
class UpdateScreen extends StatefulWidget {
  final AppUpdateInfo info;

  const UpdateScreen({required this.info, super.key});

  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  _UpdateStep _step = _UpdateStep.prompt;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  String? _downloadedApkPath;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _cancelToken?.cancel('UpdateScreen disposed');
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
      child: Scaffold(
        backgroundColor: t.bg,
        body: SafeArea(
          child: Column(
            children: [
              // Clean top header bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SwissGrid.gutter,
                  vertical: SwissGrid.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SYSTEM // UPDATE',
                            style: SwissType.label.copyWith(color: t.accent),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'MUSIFY v${widget.info.version}',
                            style: SwissType.displaySm.copyWith(
                              color: t.ink,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.info.isMandatory &&
                        _step != _UpdateStep.downloading)
                      TactileIconKeycap(
                        icon: Icons.close,
                        size: 36,
                        iconSize: 18,
                        tooltip: 'Dismiss',
                        onPressed: () {
                          locator<UpdateService>().markDismissed();
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1),

              // Scrollable body content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(SwissGrid.gutter),
                  children: [
                    const SizedBox(height: SwissGrid.md),

                    // App icon and version identity
                    Center(
                      child: Column(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: t.hairline, width: 1.2),
                              color: t.surfaceRaised,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(19),
                              child: Image.asset(
                                'assets/icon/app_icon.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(height: SwissGrid.md),
                          Text(
                            'New Version Available',
                            style: SwissType.displaySm.copyWith(
                              color: t.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: SwissGrid.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: t.surfaceSunken,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: t.hairline, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'CURRENT v$kAppVersion',
                                  style: SwissType.micro.copyWith(
                                    color: t.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.arrow_forward,
                                  size: 12,
                                  color: t.accent,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'NEW v${widget.info.version}',
                                  style: SwissType.micro.copyWith(
                                    color: t.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: SwissGrid.xl),

                    // Dynamic State Content
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _buildCurrentStateView(context, t),
                    ),
                  ],
                ),
              ),

              // Fixed Bottom Action Dock
              Container(
                padding: const EdgeInsets.all(SwissGrid.gutter),
                decoration: BoxDecoration(
                  color: t.surfaceRaised,
                  border: Border(top: BorderSide(color: t.hairline, width: 1)),
                ),
                child: _buildBottomActions(context, t),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStateView(BuildContext context, SwissTokens t) {
    switch (_step) {
      case _UpdateStep.prompt:
        return _buildPromptContent(t);
      case _UpdateStep.downloading:
        return _buildDownloadingContent(t);
      case _UpdateStep.ready:
        return _buildReadyContent(t);
      case _UpdateStep.error:
        return _buildErrorContent(t);
    }
  }

  Widget _buildPromptContent(SwissTokens t) {
    return Column(
      key: const ValueKey('prompt_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: '01',
          title: "WHAT'S NEW",
          subtitle: 'CHANGELOG // v${widget.info.version}',
        ),
        const SizedBox(height: SwissGrid.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SwissGrid.md),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Text(
            widget.info.releaseNotes.trim().isEmpty
                ? 'Performance improvements, bug fixes and UI updates.'
                : widget.info.releaseNotes,
            style: SwissType.body.copyWith(
              color: t.ink,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: SwissGrid.md),
        Container(
          padding: const EdgeInsets.all(SwissGrid.sm),
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.hairline, width: 0.8),
          ),
          child: Row(
            children: [
              Icon(Icons.security, size: 16, color: t.inkFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verified official release built directly from repository.',
                  style: SwissType.micro.copyWith(color: t.inkMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingContent(SwissTokens t) {
    final percentInt = (_progress * 100).clamp(0, 100).toInt();

    return Column(
      key: const ValueKey('downloading_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: '02',
          title: 'DOWNLOADING',
          subtitle: 'FETCHING PACKAGE // $percentInt%',
        ),
        const SizedBox(height: SwissGrid.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SwissGrid.lg),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$percentInt%',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: t.accent,
                      letterSpacing: -1,
                    ),
                  ),
                  Text(
                    _formatBytes(_receivedBytes) +
                        (_totalBytes > 0
                            ? ' / ${_formatBytes(_totalBytes)}'
                            : ''),
                    style: SwissType.label.copyWith(color: t.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: SwissGrid.md),

              // Flat progress bar - strictly no glow, no gradient
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  height: 8,
                  width: double.infinity,
                  color: t.surfaceSunken,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: _progress.clamp(0.02, 1.0),
                    child: Container(
                      color: t.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: SwissGrid.sm),
              Text(
                'Direct in-app package download. Installer will launch automatically.',
                style: SwissType.micro.copyWith(color: t.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReadyContent(SwissTokens t) {
    return Column(
      key: const ValueKey('ready_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: '03',
          title: 'READY TO INSTALL',
          subtitle: 'PACKAGE DOWNLOADED',
        ),
        const SizedBox(height: SwissGrid.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SwissGrid.lg),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_outline, color: t.positive, size: 28),
                  const SizedBox(width: SwissGrid.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Download Complete',
                          style: SwissType.bodySm.copyWith(
                            color: t.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Musify v${widget.info.version} is ready to install.',
                          style: SwissType.micro.copyWith(color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorContent(SwissTokens t) {
    return Column(
      key: const ValueKey('error_content'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          index: 'ERR',
          title: 'UPDATE FAILED',
          subtitle: 'CONNECTION INTERRUPTED',
        ),
        const SizedBox(height: SwissGrid.xs),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SwissGrid.lg),
          decoration: BoxDecoration(
            color: t.surfaceRaised,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.hairline, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: t.danger, size: 28),
                  const SizedBox(width: SwissGrid.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Could not complete download',
                          style: SwissType.bodySm.copyWith(
                            color: t.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _errorMessage ?? 'Network interrupted. Please try again.',
                          style: SwissType.micro.copyWith(color: t.inkMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(BuildContext context, SwissTokens t) {
    switch (_step) {
      case _UpdateStep.prompt:
        return Row(
          children: [
            if (!widget.info.isMandatory) ...[
              Expanded(
                flex: 2,
                child: TactileKeycap(
                  height: 48,
                  glow: false,
                  onPressed: () {
                    locator<UpdateService>().markDismissed();
                    Navigator.of(context).pop();
                  },
                  child: Center(
                    child: Text(
                      'LATER',
                      style: SwissType.label.copyWith(color: t.inkMuted),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: SwissGrid.sm),
            ],
            Expanded(
              flex: 3,
              child: TactileKeycap(
                height: 48,
                accent: true,
                glow: false,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  _startDownload();
                },
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_rounded, size: 18, color: t.accentInk),
                      const SizedBox(width: 6),
                      Text(
                        'UPDATE NOW',
                        style: SwissType.label.copyWith(
                          color: t.accentInk,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case _UpdateStep.downloading:
        return SizedBox(
          width: double.infinity,
          child: TactileKeycap(
            height: 48,
            glow: false,
            onPressed: _cancelDownload,
            child: Center(
              child: Text(
                'CANCEL DOWNLOAD',
                style: SwissType.label.copyWith(color: t.inkMuted),
              ),
            ),
          ),
        );

      case _UpdateStep.ready:
        return Row(
          children: [
            Expanded(
              child: TactileKeycap(
                height: 48,
                glow: false,
                onPressed: () => Navigator.of(context).pop(),
                child: Center(
                  child: Text(
                    'DISMISS',
                    style: SwissType.label.copyWith(color: t.inkMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SwissGrid.sm),
            Expanded(
              flex: 2,
              child: TactileKeycap(
                height: 48,
                accent: true,
                glow: false,
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  if (_downloadedApkPath != null) {
                    _openApk(_downloadedApkPath!);
                  }
                },
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.system_update_rounded, size: 18, color: t.accentInk),
                      const SizedBox(width: 6),
                      Text(
                        'INSTALL NOW',
                        style: SwissType.label.copyWith(
                          color: t.accentInk,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );

      case _UpdateStep.error:
        return Row(
          children: [
            Expanded(
              child: TactileKeycap(
                height: 48,
                glow: false,
                onPressed: () async {
                  final uri = Uri.parse(widget.info.downloadUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Center(
                  child: Text(
                    'OPEN IN BROWSER',
                    style: SwissType.label.copyWith(color: t.inkMuted),
                  ),
                ),
              ),
            ),
            const SizedBox(width: SwissGrid.sm),
            Expanded(
              child: TactileKeycap(
                height: 48,
                accent: true,
                glow: false,
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
        );
    }
  }
}
