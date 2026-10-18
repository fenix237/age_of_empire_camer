import 'package:age_of_empire_camer/sim/core/tick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('10 ticks par seconde = 100 ms par tick', () {
    expect(Tick.perSecond, 10);
    expect(Tick.millis, 100);
    expect(Tick.fromSeconds(12), 120);
  });
}
