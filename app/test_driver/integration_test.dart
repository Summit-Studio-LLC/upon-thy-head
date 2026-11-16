import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Writes each screenshot the test takes to `design/sim/<name>.png` (or under
/// the folder in SIM_DIR, relative to app/, to keep earlier shots). With
/// SIM_SHOTS set, a script has already saved the simulator's own screenshot
/// there (see tool/store_lifecycle.sh), and the app's frame is not written.
Future<void> main() => integrationDriver(
      onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
        final file = File('${Platform.environment['SIM_DIR'] ?? '../design/sim'}/$name.png');
        await file.parent.create(recursive: true);
        if (Platform.environment['SIM_SHOTS'] == '1') return true;
        await file.writeAsBytes(bytes);
        return true;
      },
    );
