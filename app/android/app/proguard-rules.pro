# JNI entry points resolved dynamically from libuth_whisper*.so.
-keep class dev.summitstudio.uponthyhead.WhisperNative { *; }

# Android components and broadcast receivers instantiated by the system or intents.
-keep class dev.summitstudio.uponthyhead.MainActivity { *; }
-keep class dev.summitstudio.uponthyhead.BlessingFiles { *; }
-keep class dev.summitstudio.uponthyhead.RecordingService { *; }
-keep class dev.summitstudio.uponthyhead.PlaybackService { *; }
-keep class dev.summitstudio.uponthyhead.ShareChannel$Chosen { *; }
