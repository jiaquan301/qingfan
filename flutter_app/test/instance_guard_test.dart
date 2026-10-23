import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qingfan/infrastructure/instance_guard.dart';

void main() {
  test('only one process owns an instance lock and release permits restart', () async {
    final directory = await Directory.systemTemp.createTemp('qingfan-lock-');
    addTearDown(() => directory.delete(recursive: true));
    final first = InstanceGuard(testDirectory: directory);
    final second = InstanceGuard(testDirectory: directory);

    expect(await first.acquire(), isTrue);
    expect(await second.acquire(), isFalse);
    await first.release();
    expect(await second.acquire(), isTrue);
    await second.release();
  });

  test('stale PID lock is recovered after owner exits', () async {
    final directory = await Directory.systemTemp.createTemp('qingfan-stale-lock-');
    addTearDown(() => directory.delete(recursive: true));
    final lock = File('${directory.path}${Platform.pathSeparator}qingfan.instance.lock');
    await lock.writeAsString('99999999\n');
    final guard = InstanceGuard(testDirectory: directory);
    expect(await guard.acquire(), isTrue);
    expect((await lock.readAsString()).trim(), pid.toString());
    await guard.release();
    expect(await lock.exists(), isFalse);
  });
}
