import 'dart:convert';
import 'dart:io';

import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';

/// Résultat conservé d'une mission réussie.
class MissionRecord {
  const MissionRecord({
    required this.stars,
    required this.bestSeconds,
    required this.difficulty,
    required this.ending,
  });

  final int stars;
  final int bestSeconds;

  /// Plus haute difficulté réussie (0 facile, 1 normal, 2 difficile).
  final int difficulty;
  final String ending;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'stars': stars,
    'best': bestSeconds,
    'diff': difficulty,
    'ending': ending,
  };

  static MissionRecord fromJson(Map<String, dynamic> j) => MissionRecord(
    stars: j['stars'] as int,
    bestSeconds: j['best'] as int,
    difficulty: j['diff'] as int,
    ending: (j['ending'] as String?) ?? '',
  );
}

/// Progression de la campagne et du défi du jour (profil local).
///
/// Immuable : chaque modification renvoie un nouvel état à sauvegarder.
class CampaignProgress {
  const CampaignProgress({
    this.missions = const <String, MissionRecord>{},
    this.daily = const <String, int>{},
  });

  final Map<String, MissionRecord> missions;

  /// Défi du jour : date (`aaaa-mm-jj`) → meilleur temps de victoire (s).
  final Map<String, int> daily;

  bool isDone(String id) => missions.containsKey(id);

  int totalStars() => missions.values.fold(0, (a, m) => a + m.stars);

  /// Une mission est jouable quand toutes celles qu'elle requiert sont
  /// réussies.
  bool isAvailable(MissionDef m) => m.requires.every(isDone);

  /// Identifiants débloqués par les récompenses des missions réussies.
  Set<String> unlocked(CampaignDef campaign) => <String>{
    for (final m in campaign.missions)
      if (isDone(m.id)) ...m.rewards,
  };

  CampaignProgress withWin(
    MissionDef m, {
    required int stars,
    required int seconds,
    required int difficulty,
    required String ending,
  }) {
    final old = missions[m.id];
    final merged = MissionRecord(
      stars: old == null ? stars : (stars > old.stars ? stars : old.stars),
      bestSeconds: old == null || seconds < old.bestSeconds
          ? seconds
          : old.bestSeconds,
      difficulty: old == null || difficulty > old.difficulty
          ? difficulty
          : old.difficulty,
      ending: ending.isNotEmpty ? ending : (old?.ending ?? ''),
    );
    return CampaignProgress(
      missions: <String, MissionRecord>{...missions, m.id: merged},
      daily: daily,
    );
  }

  CampaignProgress withDaily(String date, int seconds) {
    final best = daily[date];
    if (best != null && best <= seconds) return this;
    return CampaignProgress(
      missions: missions,
      daily: <String, int>{...daily, date: seconds},
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'version': 1,
    'missions': <String, dynamic>{
      for (final e in missions.entries) e.key: e.value.toJson(),
    },
    'daily': daily,
  };

  static CampaignProgress fromJson(Map<String, dynamic> j) {
    final ms = (j['missions'] as Map<String, dynamic>?) ?? const {};
    final dl = (j['daily'] as Map<String, dynamic>?) ?? const {};
    return CampaignProgress(
      missions: <String, MissionRecord>{
        for (final e in ms.entries)
          e.key: MissionRecord.fromJson(e.value as Map<String, dynamic>),
      },
      daily: <String, int>{for (final e in dl.entries) e.key: e.value as int},
    );
  }
}

/// Fichier de progression (`campaign.json` dans le dossier de sauvegarde),
/// écrit atomiquement. Un fichier illisible redonne une progression vide
/// plutôt qu'une erreur : l'ancien fichier est conservé en `.bad`.
class ProgressStore {
  ProgressStore(this.dir);

  final Directory dir;

  File get _file => File('${dir.path}/campaign.json');

  CampaignProgress load() {
    final f = _file;
    if (!f.existsSync()) return const CampaignProgress();
    try {
      final j = jsonDecode(f.readAsStringSync());
      if (j is Map<String, dynamic>) return CampaignProgress.fromJson(j);
    } on Object {
      // Fichier corrompu : on le met de côté ci-dessous.
    }
    try {
      f.renameSync('${f.path}.bad');
    } on FileSystemException {
      // Rien de plus à faire.
    }
    return const CampaignProgress();
  }

  Future<void> save(CampaignProgress p) async {
    await dir.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(p.toJson()), flush: true);
    await tmp.rename(_file.path);
  }
}
