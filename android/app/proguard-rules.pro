# shared_preferences_android 2.5.x chama a API Kotlin via JNI (package:jni 1.1.0),
# que procura estas classes pelo nome. As regras do próprio jni não as mantêm,
# e no release o R8 as renomeia: NoSuchMethodError / ClassNotFoundException.
# Lista tirada das referências em package:jni/lib.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep class kotlin.coroutines.Continuation { *; }
-keep class kotlin.coroutines.intrinsics.CoroutineSingletons { *; }
-keep class kotlin.coroutines.intrinsics.IntrinsicsKt { *; }

# Classes do plugin acessadas por nome pelos bindings JNI.
-keep class io.flutter.plugins.sharedpreferences.** { *; }
