# NekoVPN: no ML Kit any more (zxing-cpp ships its own consumer rules).

-keepclassmembers class * extends java.lang.Enum {
    <fields>;
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
