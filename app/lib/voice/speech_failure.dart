/// An actionable speech error shared by the lab and Avatar mode.
class SpeechFailure implements Exception {
  const SpeechFailure(this.message);

  final String message;

  static const permission = SpeechFailure(
    'Microphone access is denied. Allow it in Settings, then try again.',
  );
  static const unavailable = SpeechFailure(
    'On-device speech recognition is unavailable. Use an Android 12 or newer '
    'phone with an on-device speech service. You can still use text chat.',
  );
  static const language = SpeechFailure(
    'The offline speech model for this language is not downloaded. '
    'Download it, then try the microphone again.',
  );
  static const unsupportedLanguage = SpeechFailure(
    'This phone’s on-device speech service does not support this language. '
    'Try another language or phone. Text chat is still available.',
  );

  static SpeechFailure fromCode(String code) => switch (code) {
    'error_permission' || 'error_permission_denied' => permission,
    'error_language_not_supported' => unsupportedLanguage,
    'error_language_unavailable' => language,
    'error_busy' => const SpeechFailure(
      'Speech recognition is busy. Close other microphone apps and try again.',
    ),
    'error_audio_error' => const SpeechFailure(
      'The microphone is unavailable. Check the phone’s microphone access and try again.',
    ),
    _ => const SpeechFailure('Speech recognition stopped. Please try again.'),
  };

  @override
  String toString() => message;
}
