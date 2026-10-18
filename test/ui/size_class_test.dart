import 'package:age_of_empire_camer/ui/responsive/size_class.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('classes de taille aux frontières', () {
    expect(SizeClass.fromWidth(360), SizeClass.compact);
    expect(SizeClass.fromWidth(699.9), SizeClass.compact);
    expect(SizeClass.fromWidth(700), SizeClass.medium);
    expect(SizeClass.fromWidth(1100), SizeClass.medium);
    expect(SizeClass.fromWidth(1100.1), SizeClass.large);
    expect(SizeClass.fromWidth(3440), SizeClass.large);
  });

  test("échelle d'interface bornée, NaN sûr", () {
    expect(clampUiScale(0.1), kMinUiScale);
    expect(clampUiScale(9), kMaxUiScale);
    expect(clampUiScale(double.nan), 1);
    expect(clampUiScale(1.2), 1.2);
  });

  test('cibles tactiles >= 48 dp hors PC', () {
    expect(SizeClass.compact.minTouchTarget, greaterThanOrEqualTo(48));
    expect(SizeClass.medium.minTouchTarget, greaterThanOrEqualTo(48));
  });
}
