import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Versioned, local-only persistence. There are no remote API calls.
class LocalStore {
  LocalStore({Directory? testDirectory}) : _testDirectory = testDirectory;

  final Directory? _testDirectory;

  Future<File> _file() async {
    final directory = _testDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}qingfan_v2.json');
  }

  Future<Map<String, dynamic>?> load() async {
    final target = await _file();
    if (!await target.exists()) return null;
    try {
      final content = await target.readAsString();
      final parsed = jsonDecode(content);
      if (parsed is! Map<String, dynamic> || parsed['schemaVersion'] != 2) {
        throw const FormatException('Unsupported or damaged Qingfan data');
      }
      return parsed;
    } on FileSystemException {
      return null;
    } on FormatException {
      await _quarantine(target);
      return null;
    } on TypeError {
      await _quarantine(target);
      return null;
    }
  }

  Future<void> _quarantine(File target) async {
    if (!await target.exists()) return;
    final broken = File('${target.path}.broken-${DateTime.now().millisecondsSinceEpoch}');
    try {
      await target.rename(broken.path);
    } on FileSystemException {
      // Keep the original rather than clearing unreadable data.
    }
  }

  Future<void> save(Map<String, dynamic> value) async {
    final target = await _file();
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(value), flush: true);
    try {
      await temp.rename(target.path);
    } on FileSystemException {
      // Windows may not atomically replace an existing file. Preserve the
      // old version as .bak until the new version is successfully installed.
      final backup = File('${target.path}.bak');
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      try {
        await temp.rename(target.path);
        if (await backup.exists()) await backup.delete();
      } catch (_) {
        if (await backup.exists() && !await target.exists()) {
          await backup.rename(target.path);
        }
        rethrow;
      }
    }
  }
}
