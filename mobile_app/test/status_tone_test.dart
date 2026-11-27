import 'package:app/theme/app_theme.dart';
import 'package:app/utils/status_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usage status picks the card colour', () {
    expect(cardToneOf('unhealthy'), CardTone.unhealthy);
    expect(cardToneOf('Unhealthy'), CardTone.unhealthy);
    expect(cardToneOf('warning'), CardTone.warning);
    expect(cardToneOf('Warning'), CardTone.warning);
    expect(cardToneOf('healthy'), CardTone.normal);
    expect(cardToneOf(null), CardTone.normal);
    expect(cardToneOf(''), CardTone.normal);
  });

  test('healthy keeps the brand card, warning and unhealthy change it', () {
    expect(cardGradient(CardTone.normal), AppColors.heroGradient);
    expect(cardGradient(CardTone.warning), isNot(AppColors.heroGradient));
    expect(cardGradient(CardTone.unhealthy), isNot(AppColors.heroGradient));
    expect(cardProgressColor(CardTone.normal), AppColors.teal);
    expect(cardProgressColor(CardTone.unhealthy), Colors.white);
  });
}
