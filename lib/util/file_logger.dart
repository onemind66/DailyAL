import 'dart:io';

import 'package:dal_commons/dal_commons.dart' as dal;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Opt-in logger for collecting diagnostic output. It prefers
/// /storage/emulated/0/dailyal/ when Android grants broad storage access and
/// falls back to app-owned external/documents storage otherwise.
class DailyALFileLogger {
  static bool _enabled = false;
  static bool _rootPermissionGranted = false;
  static File? _activeFile;
  static Future<void> _pendingWrites = Future<void>.value();

  static void configure({required bool enabled}) {
    dal.logDalFileWriter = _enqueue;
    _enabled = enabled;
    if (!enabled) {
      _activeFile = null;
      _rootPermissionGranted = false;
    }
  }

  /// Request broad storage permission only after the user turns logging on.
  static Future<bool> setEnabled(
    bool enabled, {
    bool requestRootPermission = false,
  }) async {
    _enabled = enabled;
    dal.logDalFileWriter = _enqueue;

    if (!enabled) {
      await _pendingWrites;
      _activeFile = null;
      _rootPermissionGranted = false;
      return false;
    }

    _activeFile = null;
    if (Platform.isAndroid && requestRootPermission) {
      try {
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
        }
        _rootPermissionGranted = status.isGranted;
      } catch (_) {
        _rootPermissionGranted = false;
      }

      if (!_rootPermissionGranted) {
        try {
          var status = await Permission.storage.status;
          if (!status.isGranted) {
            status = await Permission.storage.request();
          }
          _rootPermissionGranted = status.isGranted;
        } catch (_) {
          _rootPermissionGranted = false;
        }
      }
    }

    _enqueue(
      '=== DailyAL diagnostic logging enabled '
      '${DateTime.now().toIso8601String()} ===',
    );
    await _pendingWrites;
    return _activeFile?.parent.path == '/storage/emulated/0/dailyal';
  }

  static void _enqueue(String line) {
    if (!_enabled) return;
    _pendingWrites = _pendingWrites
        .then((_) async {
          final file = await _getLogFile();
          if (file == null) return;
          await file.writeAsString(
            '$line\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object _) {
          // Do not recurse into logDal if storage is unavailable.
        });
  }

  static Future<File?> _getLogFile() async {
    if (_activeFile != null) return _activeFile;

    final fileName = 'dailyal_${_timestamp(DateTime.now())}.log';

    if (Platform.isAndroid) {
      var canUseRoot = _rootPermissionGranted;
      try {
        canUseRoot = canUseRoot ||
            await Permission.manageExternalStorage.isGranted ||
            await Permission.storage.isGranted;
      } catch (_) {
        // A permission API failure means app-owned fallback below.
      }

      if (canUseRoot) {
        try {
          final directory = Directory('/storage/emulated/0/dailyal');
          await directory.create(recursive: true);
          final file = File('${directory.path}/$fileName');
          await file.create(recursive: true);
          _activeFile = file;
          return file;
        } catch (_) {
          // Scoped storage/OEM restrictions can still deny root writes.
        }
      }
    }

    try {
      final externalDirectory = await getExternalStorageDirectory();
      final baseDirectory =
          externalDirectory ?? await getApplicationDocumentsDirectory();
      final directory = Directory('${baseDirectory.path}/dailyal');
      await directory.create(recursive: true);
      final file = File('${directory.path}/$fileName');
      await file.create(recursive: true);
      _activeFile = file;
      return file;
    } catch (_) {
      return null;
    }
  }

  static String _timestamp(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}_'
        '${two(value.hour)}-${two(value.minute)}-${two(value.second)}';
  }
}
