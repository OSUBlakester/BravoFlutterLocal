// Windows-only audio device enumeration and selection using just_audio_windows
// This file should only be imported on Windows
import 'package:just_audio_windows/just_audio_windows.dart';

Future<List<WindowsAudioDevice>> getWindowsAudioDevices() async {
  return await JustAudioWindowsPlatform.instance.getOutputDevices();
}

Future<void> setWindowsAudioDevice(String deviceId, JustAudioWindowsPlayer player) async {
  await player.setAudioDevice(deviceId);
}
