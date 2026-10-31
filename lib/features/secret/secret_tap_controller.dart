/// Resultado evaluado al registrar un tap en la secuencia secreta.
enum SecretTapOutcome {
  /// Taps 1 a 4 o después de expirado el tiempo: sin feedback visual.
  idle,

  /// Tap 5: Faltan 2 pasos para desbloquear.
  twoStepsRemaining,

  /// Tap 6: Falta 1 paso para desbloquear.
  oneStepRemaining,

  /// Tap 7: Desbloqueo completado.
  unlocked,
}

/// Controlador de secuencia de pulsaciones para la activación secreta.
///
/// Gestiona la cadencia y ventana de tiempo (2.5 segundos) requerida para
/// completar los 7 taps sucesivos sobre el indicador de versión.
class SecretTapController {
  SecretTapController({
    this.timeout = const Duration(milliseconds: 2500),
    this.targetTaps = 7,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final Duration timeout;
  final int targetTaps;
  final DateTime Function() _nowProvider;

  int _tapCount = 0;
  DateTime? _lastTapTime;

  /// Cantidad actual de taps acumulados en la ventana activa.
  int get tapCount => _tapCount;

  /// Registra una pulsación y devuelve el resultado evaluado.
  SecretTapOutcome registerTap() {
    final now = _nowProvider();

    if (_lastTapTime != null && now.difference(_lastTapTime!) > timeout) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    if (_tapCount < 5) {
      return SecretTapOutcome.idle;
    } else if (_tapCount == 5) {
      return SecretTapOutcome.twoStepsRemaining;
    } else if (_tapCount == 6) {
      return SecretTapOutcome.oneStepRemaining;
    } else if (_tapCount >= targetTaps) {
      _tapCount = 0;
      _lastTapTime = null;
      return SecretTapOutcome.unlocked;
    }

    return SecretTapOutcome.idle;
  }

  /// Reinicia manualmente el contador de taps.
  void reset() {
    _tapCount = 0;
    _lastTapTime = null;
  }
}
