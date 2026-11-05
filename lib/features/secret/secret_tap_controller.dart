/// Resultado evaluado al registrar un tap en la secuencia secreta.
enum SecretTapOutcome {
  /// Sin feedback visual (segundo tap o taps intermedios).
  idle,

  /// Tap 1: Aviso tipo toast informando que hay algo especial escondido.
  firstTapHint,

  /// Tap 3: Desbloqueo completado.
  unlocked,

  /// Ya se encuentra desbloqueado: no vuelve a ejecutar la animación.
  alreadyUnlocked,
}

/// Controlador de secuencia de pulsaciones para la activación secreta.
///
/// Gestiona la cadencia y ventana de tiempo (2.5 segundos) requerida para
/// completar los 3 taps sucesivos sobre el indicador de versión.
class SecretTapController {
  SecretTapController({
    this.timeout = const Duration(milliseconds: 2500),
    this.targetTaps = 3,
    this.isUnlocked = false,
    DateTime Function()? nowProvider,
  }) : _nowProvider = nowProvider ?? DateTime.now;

  final Duration timeout;
  final int targetTaps;
  bool isUnlocked;
  final DateTime Function() _nowProvider;

  int _tapCount = 0;
  DateTime? _lastTapTime;

  /// Cantidad actual de taps acumulados en la ventana activa.
  int get tapCount => _tapCount;

  /// Registra una pulsación y devuelve el resultado evaluado.
  SecretTapOutcome registerTap() {
    if (isUnlocked) {
      return SecretTapOutcome.alreadyUnlocked;
    }

    final now = _nowProvider();

    if (_lastTapTime != null && now.difference(_lastTapTime!) > timeout) {
      _tapCount = 0;
    }

    _lastTapTime = now;
    _tapCount++;

    if (_tapCount == 1) {
      return SecretTapOutcome.firstTapHint;
    } else if (_tapCount == 2) {
      return SecretTapOutcome.idle;
    } else if (_tapCount >= targetTaps) {
      _tapCount = 0;
      _lastTapTime = null;
      isUnlocked = true;
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
