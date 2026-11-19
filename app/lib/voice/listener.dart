import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_failure.dart';

/// The phone's speech recognizer, so a test can stand in for it.
abstract class SpeechEngine {
  /// Asks for the microphone and speech recognition the first time; false when either
  /// is refused or the phone has no recognizer.
  Future<bool> initialize({
    required void Function(String error) onError,
    required void Function(String status) onStatus,
  });

  Future<void> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onResult,
  });

  /// Stops listening; the recognizer then sends its final result.
  Future<void> stop();

  /// Stops listening with no final result.
  Future<void> cancel();
}

/// Apple's Speech framework on iOS, SpeechRecognizer on Android, recognizing on the
/// phone: the audio never leaves it (DEC-092).
class DeviceSpeechEngine implements SpeechEngine {
  DeviceSpeechEngine({SpeechToText? recognizer})
    : _speech = recognizer ?? SpeechToText();

  final SpeechToText _speech;
  static const _device = MethodChannel('wobot/device');

  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _requireOnDevice() async {
    if (_android &&
        await _device.invokeMethod<bool>('isOnDeviceRecognitionAvailable') !=
            true) {
      throw SpeechFailure.unavailable;
    }
  }

  @override
  Future<bool> initialize({
    required void Function(String error) onError,
    required void Function(String status) onStatus,
  }) async {
    await _requireOnDevice();
    // SpeechToText is a singleton and initializes natively only once. Refresh its
    // Dart callbacks for each question, including after opening another page.
    _speech.errorListener = (SpeechRecognitionError e) => onError(e.errorMsg);
    _speech.statusListener = onStatus;
    if (_android &&
        _speech.isAvailable &&
        await _device.invokeMethod<bool>('hasMicrophonePermission') != true) {
      throw SpeechFailure.permission;
    }
    final ready = await _speech.initialize(
      onError: _speech.errorListener,
      onStatus: onStatus,
      options: [SpeechToText.androidNoBluetooth],
    );
    if (!ready && _android) throw SpeechFailure.permission;
    return ready;
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String words, bool isFinal) onResult,
  }) async {
    // Recheck immediately before listen: the plugin otherwise falls back to a
    // recognizer whose EXTRA_PREFER_OFFLINE is only a hint on Android.
    await _requireOnDevice();
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) =>
          onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        onDevice: true,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

/// Why listening ended.
enum EndReason {
  /// No new words for a moment after some were heard: the speaker stopped.
  pause,

  /// The speaker tapped to send.
  manual,

  /// The longest question, 60 seconds (VOI-011).
  limit,

  /// No words at all since listening started.
  silence,

  /// The recognizer stopped by itself, or failed.
  engine,
}

/// What was heard, and when: the times are what Voice lab shows.
class Heard {
  const Heard({
    required this.text,
    required this.reason,
    required this.total,
    this.firstWords,
    this.lastWordsToEnd,
    required this.finalWait,
    required this.finalArrived,
  });

  /// Empty when nothing was recognized: then nothing is sent (spec 22).
  final String text;
  final EndReason reason;

  /// From the start to the end of listening.
  final Duration total;

  /// From the start to the first words recognized.
  final Duration? firstWords;

  /// From the last words recognized to the end of listening.
  final Duration? lastWordsToEnd;

  /// From the end of listening to the text being settled.
  final Duration finalWait;

  /// Whether the recognizer's final result came within the wait, or the last partial
  /// result stands in for it.
  final bool finalArrived;

  bool get empty => text.trim().isEmpty;
}

/// Listens for one spoken question, in words as they come, until the speaker stops,
/// taps, or a limit is reached (spec 22, DEC-092).
///
/// All four ends go through one finalize, guarded by a generation: whichever comes
/// first ends this question, and anything later, or from an earlier question, is
/// dropped.
class QuestionListener extends ChangeNotifier {
  QuestionListener(
    this._engine, {
    // Past a pause within a sentence: a word comes 0.3 to 0.5 s after it is said, so a
    // 1 s pause measured longer than 1.2 s (DEC-092).
    this.pause = const Duration(milliseconds: 1800),
    this.silence = const Duration(seconds: 10),
    this.limit = const Duration(seconds: 60),
    this.finalWait = const Duration(seconds: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SpeechEngine _engine;

  /// No new words for this long after some were heard ends the question.
  final Duration pause;

  /// No words at all for this long ends it with nothing heard.
  final Duration silence;
  final Duration limit;

  /// How long the final result is waited for after listening stops.
  final Duration finalWait;
  final DateTime Function() _now;

  /// Why the recognizer could not start or failed, as it says.
  String? error;

  /// The words so far.
  String words = '';
  bool listening = false;
  bool starting = false;

  int _generation = 0;
  bool _ending = false;
  Completer<Heard?>? _heard;
  Completer<String>? _final;
  DateTime? _startedAt;
  DateTime? _firstWordsAt;
  DateTime? _lastWordsAt;
  Timer? _pauseTimer;
  Timer? _silenceTimer;
  Timer? _limitTimer;
  bool _disposed = false;

  /// Listens for one question. Completes with what was heard, or null when listening
  /// was cancelled or could not start.
  Future<Heard?> listen({String localeId = 'zh-TW'}) async {
    if (starting) return null;
    if (listening) await cancel();
    final generation = ++_generation;
    _ending = false;
    words = '';
    error = null;
    _firstWordsAt = null;
    _lastWordsAt = null;
    _final = null;
    final heard = _heard = Completer<Heard?>();
    starting = true;
    _notify();
    bool ready;
    try {
      ready = await _engine.initialize(
        onError: (message) => _onError(generation, message),
        onStatus: (status) => _onStatus(generation, status),
      );
    } on Exception catch (e) {
      if (generation != _generation) return null;
      error = e is SpeechFailure
          ? e.message
          : 'Speech recognition could not start. Please try again.';
      _notify();
      return null;
    } finally {
      if (generation == _generation) {
        starting = false;
        _notify();
      }
    }
    if (generation != _generation) return null;
    if (!ready) {
      error = 'Speech recognition is unavailable on this phone.';
      _notify();
      return null;
    }
    _startedAt = _now();
    listening = true;
    _notify();
    _silenceTimer = Timer(silence, () => _end(generation, EndReason.silence));
    _limitTimer = Timer(limit, () => _end(generation, EndReason.limit));
    try {
      await _engine.listen(
        localeId: localeId,
        onResult: (text, isFinal) => _onResult(generation, text, isFinal),
      );
    } on Exception catch (e) {
      if (generation != _generation) return null;
      error = e is SpeechFailure
          ? e.message
          : 'Speech recognition could not start. Please try again.';
      await _end(generation, EndReason.engine);
    }
    return heard.future;
  }

  /// The speaker tapped to send what was said.
  Future<void> finish() => _end(_generation, EndReason.manual);

  /// Throws the question away: nothing is sent (leaving, going to the background).
  Future<void> cancel() async {
    final heard = _heard;
    _generation++;
    starting = false;
    _stopTimers();
    if (listening) {
      listening = false;
      try {
        await _engine.cancel();
      } on Exception {
        // Already stopped.
      }
    }
    if (heard != null && !heard.isCompleted) heard.complete(null);
    _notify();
  }

  void _onResult(int generation, String text, bool isFinal) {
    if (generation != _generation) return;
    if (_ending) {
      // Listening has stopped: this is the recognizer settling the text.
      if (isFinal && _final?.isCompleted == false) _final?.complete(text);
      return;
    }
    if (text != words) {
      final now = _now();
      words = text;
      if (text.trim().isNotEmpty) {
        _firstWordsAt ??= now;
        _lastWordsAt = now;
        _silenceTimer?.cancel();
        _pauseTimer?.cancel();
        _pauseTimer = Timer(pause, () => _end(generation, EndReason.pause));
      }
      _notify();
    }
    if (isFinal) {
      // The recognizer ended by itself, with this text.
      _final = Completer<String>()..complete(text);
      _end(generation, EndReason.engine);
    }
  }

  void _onError(int generation, String message) {
    if (generation != _generation || _ending) return;
    // No words matched: the same as hearing nothing.
    if (message != 'error_no_match' && message != 'error_speech_timeout') {
      error = SpeechFailure.fromCode(message).message;
    }
    _end(generation, EndReason.engine);
  }

  void _onStatus(int generation, String status) {
    if (generation != _generation || _ending) return;
    if (status == SpeechToText.doneStatus) _end(generation, EndReason.engine);
  }

  /// The one way a question ends: the first caller wins, later ones do nothing.
  Future<void> _end(int generation, EndReason reason) async {
    if (generation != _generation || _ending || !listening) return;
    _ending = true;
    _stopTimers();
    final endedAt = _now();
    final settled = _final ??= Completer<String>();
    if (!settled.isCompleted) {
      try {
        await _engine.stop();
      } on Exception {
        // The partial result stands.
      }
    }
    final text = await settled.future
        .then<String?>((t) => t)
        .timeout(finalWait, onTimeout: () => null);
    if (generation != _generation) return;
    final settledAt = _now();
    listening = false;
    final started = _startedAt!;
    final heard = Heard(
      text: text ?? words,
      reason: reason,
      total: endedAt.difference(started),
      firstWords: _firstWordsAt?.difference(started),
      lastWordsToEnd: _lastWordsAt == null
          ? null
          : endedAt.difference(_lastWordsAt!),
      finalWait: settledAt.difference(endedAt),
      finalArrived: text != null,
    );
    words = heard.text;
    _heard?.complete(heard);
    _notify();
  }

  void _stopTimers() {
    _pauseTimer?.cancel();
    _silenceTimer?.cancel();
    _limitTimer?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(cancel());
    super.dispose();
  }
}
