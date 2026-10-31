import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Contrato para la reproducción de audio del efecto visual.
abstract interface class BouquetAudioService {
  Future<void> preload();
  Future<void> playChime();
  Future<void> dispose();
}

/// Implementación concreta respaldada por [AudioPlayer].
class AppBouquetAudioService implements BouquetAudioService {
  AudioPlayer? _player;
  bool _isDisposed = false;

  static const String assetPath = 'audio/bouquet_chime.wav';

  @override
  Future<void> preload() async {
    if (_isDisposed) return;
    try {
      _player ??= AudioPlayer();
      await _player?.setSource(AssetSource(assetPath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Precarga de audio omitida o no soportada: $e');
      }
    }
  }

  @override
  Future<void> playChime() async {
    if (_isDisposed) return;
    try {
      _player ??= AudioPlayer();
      await _player?.stop();
      await _player?.play(AssetSource(assetPath));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('NexusBO: Reproducción de audio omitida o no soportada: $e');
      }
    }
  }

  @override
  Future<void> dispose() async {
    _isDisposed = true;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}

