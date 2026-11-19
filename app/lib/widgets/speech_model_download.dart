import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Requests a model from the phone's on-device service; never records speech.
class SpeechModelDownload extends StatefulWidget {
  const SpeechModelDownload(this.localeId, {super.key});

  final String localeId;

  @override
  State<SpeechModelDownload> createState() => _SpeechModelDownloadState();
}

class _SpeechModelDownloadState extends State<SpeechModelDownload> {
  bool _busy = false;
  String? _status;

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    String message;
    try {
      final status = await const MethodChannel('wobot/device')
          .invokeMethod<String>('downloadSpeechModel', {
            'localeId': widget.localeId,
          });
      message = switch (status) {
        'downloaded' =>
          'Offline model is ready. Tap the microphone to try again.',
        'scheduled' || 'requested' =>
          'Download requested. Keep the phone online; the speech service may download it later. Try the microphone again after it finishes.',
        'unsupported' =>
          'This speech service does not support this language. Try another language or phone.',
        'busy' =>
          'A model download request is already in progress. Please wait.',
        'unavailable' =>
          'Model downloads from Wobot need Android 13 or newer. Use the phone’s speech service settings, or another phone.',
        _ =>
          'Could not download the offline model. Check your connection and the phone’s speech service settings, then try again.',
      };
    } on Exception {
      message =
          'Could not request a model download. Use the phone’s speech service settings, then try again.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextButton(
        onPressed: _busy ? null : _download,
        child: Text(
          _busy ? 'Requesting offline model…' : 'Download offline model',
        ),
      ),
      if (_status case final status?) Text(status),
    ],
  );
}
