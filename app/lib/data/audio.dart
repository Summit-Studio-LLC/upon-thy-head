import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where recordings are kept: Library/Application Support/audio. The recorder marks the folder
/// as excluded from backups (ios/Runner/SpeechChannel.swift), so the audio never leaves the phone,
/// not even in an iCloud or computer backup. Each file is named after its blessing: `<id>.m4a`.
Future<String> defaultAudioDir() async => p.join((await getApplicationSupportDirectory()).path, 'audio');
