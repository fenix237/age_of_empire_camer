import 'dart:io';

import 'package:age_of_empire_camer/app/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('log_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('écrit dans le fichier et en mémoire', () async {
    final log = AppLogger.forDirectory(dir, maxBytes: 100000)..info('bonjour');
    await log.flush();
    expect(
      File('${dir.path}/game.log').readAsStringSync(),
      contains('bonjour'),
    );
    expect(log.recent.single, contains('[INFO] bonjour'));
  });

  test('rotation quand le fichier dépasse la limite', () async {
    final log = AppLogger.forDirectory(dir);
    for (var i = 0; i < 60; i++) {
      log.info('ligne numéro $i avec du remplissage pour grossir le fichier');
    }
    await log.flush();
    expect(File('${dir.path}/game.1.log').existsSync(), isTrue);
    expect(File('${dir.path}/game.log').lengthSync(), lessThan(4096));
  });

  test('erreur avec pile', () async {
    final log = AppLogger.forDirectory(dir, maxBytes: 100000)
      ..error('échec', StateError('x'), StackTrace.current);
    await log.flush();
    expect(log.recent.single, contains('Bad state: x'));
  });

  test('dossier inutilisable : ne plante pas', () async {
    final log = AppLogger.forDirectory(Directory('Z:/inexistant/dossier'))
      ..info('test');
    await log.flush();
    expect(log.recent, isNotEmpty);
  });
}
