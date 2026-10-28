-keep class ai.onnxruntime.** { *; }
# ML Kit: R8 (AGP 9) breaks InputImage in release ("getClass() on a null
# object reference" in mlkit_vision_common), keep ML Kit as is.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
