# JNI entry points are looked up by name.
-keep class uz.carrotube.carro_native.CarroDspJni { *; }
-keepclasseswithmembernames class * { native <methods>; }
-keep class uz.carrotube.carro_native.CarroPlaybackService { *; }
