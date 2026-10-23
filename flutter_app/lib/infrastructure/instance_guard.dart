import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Atomic per-user process lock. Unlike RandomAccessFile.lock(), which waits
/// for a contested lock, exclusive file creation returns immediately.
/// The owner PID lets the next launch recover a stale lock after a crash.
class InstanceGuard {
  InstanceGuard({Directory? testDirectory}) : _directory = testDirectory;

  final Directory? _directory;
  File? _lockFile;
  int? _ownerPid;

  bool get acquired => _lockFile != null;

  Future<bool> acquire() async {
    if (acquired) return true;
    final directory = _directory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}qingfan.instance.lock');

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await file.create(exclusive: true);
        await file.writeAsString('$pid\n', flush: true);
        _lockFile = file;
        _ownerPid = pid;
        return true;
      } on FileSystemException {
        if (!await file.exists()) {
          if (attempt == 0) continue;
          rethrow;
        }
        var content = (await file.readAsString()).trim();
        // Give a newly created owner a short window to write its PID.
        if (content.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          content = (await file.readAsString()).trim();
        }
        final owner = int.tryParse(content);
        if (owner != null && await _isAlive(owner)) return false;
        // Remove only the stale lock that was actually inspected.
        final current = (await file.readAsString()).trim();
        if (current == content) {
          try {
            await file.delete();
          } on FileSystemException {
            return false;
          }
        }
      }
    }
    return false;
  }

  Future<bool> _isAlive(int processId) async {
    if (processId == pid) return true;
    try {
      if (Platform.isWindows) {
        final result = await Process.run('tasklist', ['/FI', 'PID eq $processId']);
        return result.exitCode == 0 &&
            result.stdout.toString().contains(processId.toString());
      }
      final result = await Process.run('kill', ['-0', processId.toString()]);
      return result.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  Future<void> release() async {
    final file = _lockFile;
    final owner = _ownerPid;
    _lockFile = null;
    _ownerPid = null;
    if (file == null) return;
    try {
      if (await file.exists() && (await file.readAsString()).trim() == '$owner') {
        await file.delete();
      }
    } on FileSystemException {
      // Process exit also makes the PID stale; the next launch recovers it.
    }
  }
}
