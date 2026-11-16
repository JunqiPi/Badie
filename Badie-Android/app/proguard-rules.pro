# 正式包（release）用 R8 压缩、混淆。依赖库自带的规则（kotlinx.serialization、Firebase、Compose、AndroidX）会自动合进来，
# 这里只写我们自己代码要的和库的文档要求手动加的。改了以后跑 ./gradlew :app:bundleRelease，再按 docs/RELEASE.md 在真机上过一遍。

# 崩溃报告（Play 管理中心）能对上行号：映射文件随 AAB 一起上传
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# 人机验证页往回传令牌：网页调 BadieCaptcha.postMessage（features/onboarding/CaptchaView.kt），方法名不能改
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepattributes JavascriptInterface

# kotlinx.serialization：库里自带 R8 规则（留下 @Serializable 类的 serializer()）。下面是官方 README 给的同一套，
# 写在这里是为了万一库的规则变了也不会在正式包里解析失败（调接口全靠它）
-keepattributes RuntimeVisibleAnnotations,AnnotationDefault,InnerClasses
-if @kotlinx.serialization.Serializable class **
-keepclassmembers class <1> {
    static <1>$Companion Companion;
}
-if @kotlinx.serialization.Serializable class ** {
    static **$* *;
}
-keepclassmembers class <2>$<3> {
    kotlinx.serialization.KSerializer serializer(...);
}
-if @kotlinx.serialization.Serializable class ** {
    public static ** INSTANCE;
}
-keepclassmembers class <1> {
    public static <1> INSTANCE;
    kotlinx.serialization.KSerializer serializer(...);
}

# 凭据管理器（Google 登录）：Android 文档要求手动加，用反射找 Play 服务的实现
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** {
    *;
}
