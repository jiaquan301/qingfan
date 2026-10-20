import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Cooperative cross-platform, crash-safe lock per local user.
///
/// The OS releases an advisory file lock when its process exits, including
/// abnormal termination. This prevents duplicate Qingfan native windows.
/// Raising an existing window is best-effort and cannot be guaranteed on
/// Linux Wayland; it is intentionally not conflated with singleton correctness.
class InstanceGuard {
  InstanceGuard({Directory? testDirectory}) : _directory = testDirectory;

  final Directory? _directory;
  RandomAccessFile? _heldFile;

  bool get acquired => _heldFile != null;

  Future<bool> acquire() async {
    if (_heldFile != null) return true;
    final directory = _directory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    final path = '${directory.path}${Platform.pathSeparator}qingfan.instance.lock';
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.lock(FileLock.exclusive, 0, 1);
      _heldFile = file;
      return true;
    } on FileSystemException {
      await file.close();
      return false;
    }
  }

  Future<void> release() async {
    final file = _heldFile;
    _heldFile = null;
    if (file == null) return;
    try {
      await file.unlock(0, 1);
    } finally {
      await file.close();
    }
  }
}
