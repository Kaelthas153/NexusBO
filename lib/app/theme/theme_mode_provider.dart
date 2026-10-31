import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier para gestionar el modo de tema (Sistema, Claro, Oscuro).
/// Permite probar visualmente tanto el modo claro como el oscuro desde Ajustes
/// o la cabecera de la aplicación.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) {
    state = mode;
  }

  void toggleLightDark(Brightness currentBrightness) {
    state = currentBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

