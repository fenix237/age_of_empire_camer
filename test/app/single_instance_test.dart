import 'dart:io';

import 'package:age_of_empire_camer/app/lifecycle/single_instance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('le second verrou est refusé tant que le premier est tenu', () {
    final dir = Directory.systemTemp.createTempSync('lock_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final first = SingleInstanceLock(dir);
    final second = SingleInstanceLock(dir);
    expect(first.tryAcquire(), isTrue);
    expect(second.tryAcquire(), isFalse);
    first.release();
    expect(second.tryAcquire(), isTrue);
    second.release();
  });
}
