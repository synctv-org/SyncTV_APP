import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:audio_session/audio_session.dart';

class AudioUtil {
  static Future<void> stopPlaying() async {
    debugPrint('AudioUtil: stopPlaying called');
  }

  static Future<void> setVoiceCallMode(bool enabled) async {
    debugPrint('AudioUtil: setVoiceCallMode $enabled');
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;

    try {
      final session = await AudioSession.instance;
      if (enabled) {
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.voiceChat,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.speech,
            usage: AndroidAudioUsage.voiceCommunication,
            flags: AndroidAudioFlags.audibilityEnforced,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
        ));
      } else {
        await session.configure(const AudioSessionConfiguration.music());
      }
    } catch (e) {
      debugPrint('Error configuring AudioSession: $e');
    }
  }
}
