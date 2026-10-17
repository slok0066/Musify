import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/sources/local_store.dart';
import 'settings_service.dart';

/// Portable `.json` backup of everything the user owns.
///
/// The payload is versioned and additive: unknown keys are ignored on import,
/// so a backup taken by an older build still restores what it can instead of
/// failing outright.
class BackupService {
  BackupService({
    required LocalStore store,
    required SettingsService settings,
  })  : _store = store,
        _settings = settings;

  final LocalStore _store;
  final SettingsService _settings;

  static const int schemaVersion = 1;
  static const String _settingsKey = 'musify.settings.v1';

  /// Writes a backup file and returns its path so the UI can surface it.
  Future<String?> exportToFile() async {
    try {
      final payload = {
        ..._store.exportAll(),
        'version': schemaVersion,
        'settings': _settings.value.toMap(),
        'exportedAt': DateTime.now().toIso8601String(),
      };

      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final fileName = 'musify-backup-$stamp.json';
      final jsonString = const JsonEncoder.withIndent('  ').convert(payload);

      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (await downloadDir.exists()) {
          targetDir = downloadDir;
        } else {
          final downloadsDirAlt = Directory('/storage/emulated/0/Downloads');
          if (await downloadsDirAlt.exists()) {
            targetDir = downloadsDirAlt;
          }
        }
      }

      targetDir ??= await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${targetDir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsString(jsonString, flush: true);

      final docsDir = await getApplicationDocumentsDirectory();
      final docsFile = File('${docsDir.path}${Platform.pathSeparator}$fileName');
      if (docsFile.path != file.path) {
        await docsFile.writeAsString(jsonString, flush: true);
      }

      return file.path;
    } catch (e) {
      debugPrint('Backup export failed: $e');
      return null;
    }
  }

  /// Encodes a backup as a string (used when sharing instead of saving).
  Future<String?> exportToJson() async {
    try {
      final payload = {
        ..._store.exportAll(),
        'version': schemaVersion,
        'settings': _settings.value.toMap(),
      };
      return const JsonEncoder.withIndent('  ').convert(payload);
    } catch (e) {
      debugPrint('Backup export failed: $e');
      return null;
    }
  }

  /// Restores from a file path. Returns a human-readable outcome.
  Future<BackupResult> importFromFile(String path) async {
    final file = File(path);
    try {
      if (!await file.exists()) {
        return const BackupResult(success: false, message: 'File not found');
      }
      final raw = await file.readAsString();
      return await importFromJson(raw);
    } catch (e) {
      debugPrint('Backup import failed: $e');
      return BackupResult(success: false, message: 'Unreadable backup: $e');
    }
  }

  Future<BackupResult> importFromJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return const BackupResult(success: false, message: 'Not a Musify backup');
      }
      final payload = decoded.cast<String, dynamic>();

      if (!payload.containsKey('liked') &&
          !payload.containsKey('playlists') &&
          !payload.containsKey('settings')) {
        return const BackupResult(
          success: false,
          message: 'Not a Musify backup',
        );
      }

      await _store.importAll(payload);

      final settings = payload['settings'];
      if (settings is Map) {
        // Restored through the shared key so a fresh launch reads the same
        // values the engine already has in memory.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_settingsKey, jsonEncode(settings));
        _settings.update(MusifySettings.fromMap(settings.cast<String, dynamic>()));
      }

      final liked = (payload['liked'] as List?)?.length ?? 0;
      final playlists = (payload['playlists'] as List?)?.length ?? 0;
      return BackupResult(
        success: true,
        message: 'Restored $liked liked songs and $playlists playlists',
      );
    } catch (e) {
      debugPrint('Backup import failed: $e');
      return BackupResult(success: false, message: 'Corrupt backup: $e');
    }
  }
}

class BackupResult {
  const BackupResult({required this.success, required this.message});

  final bool success;
  final String message;
}
