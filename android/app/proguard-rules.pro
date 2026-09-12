packageOptimization=true
minifyEnabled=true
shrinkResources=true

# Flutter 核心保留规则
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.metamorphosis.bilibiliglass.** { *; }

# Chewie / video_player
-keep class com.teoprime.chewie.** { *; }
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# 第三方库警告忽略
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.conscrypt.**

# 保留注解和泛型信息
-keepattributes Signature, InnerClasses, EnclosingMethod
-keepattributes *Annotation*, SourceFile, LineNumberTable