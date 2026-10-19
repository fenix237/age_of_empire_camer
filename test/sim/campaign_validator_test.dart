import 'dart:io';

import 'package:age_of_empire_camer/sim/campaign/mission_def.dart';
import 'package:age_of_empire_camer/sim/campaign/mission_validator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_defs.dart';

CampaignDef loadCampaign() => CampaignDef.fromString(
  File('assets/campaign/campaign.json').readAsStringSync(),
);

void main() {
  test('la campagne est valide (références, positions, ressources)', () {
    final problems = validateCampaign(testDefs, loadCampaign());
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
