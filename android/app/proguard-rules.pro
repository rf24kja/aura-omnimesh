# R8/ProGuard keep rules for release builds.
#
# The ONNX Runtime native library resolves its Java classes via JNI
# FindClass at runtime (e.g. ai.onnxruntime.TensorInfo inside
# OrtSession.run). Nothing in Dart/Java references those names, so R8
# strips them and the native call aborts with
#   ClassNotFoundException: ai.onnxruntime.TensorInfo
#   JNI DETECTED ERROR IN APPLICATION: java_class == null
# Keep the whole package (and its enums/fields the JNI layer reads).
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }

# Isar's native engine likewise calls back into Java via JNI.
-keep class dev.isar.** { *; }

# Flutter defaults already keep the embedding; this is belt-and-braces
# for plugins that register via reflection.
-keep class io.flutter.plugins.** { *; }
