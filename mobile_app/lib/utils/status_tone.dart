import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Colour of the screen-time cards (guardian dashboard and child home):
/// normal (brand purple), amber for Warning and red for Unhealthy.
/// Pure so it can be unit tested.
enum CardTone { normal, warning, unhealthy }

/// Reads the usage status ("healthy", "warning", "unhealthy", or the
/// labels "Healthy", "Warning", "Unhealthy").
CardTone cardToneOf(String? status) {
  switch ((status ?? '').trim().toLowerCase()) {
    case 'unhealthy':
      return CardTone.unhealthy;
    case 'warning':
      return CardTone.warning;
    default:
      return CardTone.normal;
  }
}

const LinearGradient _warningGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFB86A00), Color(0xFFD9822B), Color(0xFFE6A23C)],
);

const LinearGradient _unhealthyGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFA51D3A), Color(0xFFC62F4B), Color(0xFFDB4E5E)],
);

LinearGradient cardGradient(CardTone tone) => switch (tone) {
  CardTone.normal => AppColors.heroGradient,
  CardTone.warning => _warningGradient,
  CardTone.unhealthy => _unhealthyGradient,
};

/// Fill of the goal bar or ring on the card. White on the amber and red
/// cards so it stays visible.
Color cardProgressColor(CardTone tone) =>
    tone == CardTone.normal ? AppColors.teal : Colors.white;
