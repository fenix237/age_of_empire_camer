import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_arch.dart';

void main() {
  test("lib/sim n'importe ni Flutter ni Flame", () {
    expect(findViolations(Directory('lib/sim')), isEmpty);
  });

  test('le détecteur repère bien une violation', () {
    final dir = Directory.systemTemp.createTempSync('arch_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    File(
      '${dir.path}/bad.dart',
    ).writeAsStringSync("import 'package:flutter/material.dart';\n");
    expect(findViolations(dir), hasLength(1));
  });
}
