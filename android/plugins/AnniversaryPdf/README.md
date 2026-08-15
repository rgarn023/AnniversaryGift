# AnniversaryPdf Android Plugin

Integrated into the Godot Gradle build template:

- Java: `android/build/src/main/java/com/charoitegames/anniversarygift/AnniversaryPdfPlugin.java`
- Manifest meta-data in `android/build/src/main/AndroidManifest.xml`:
  `org.godotengine.plugin.v2.AnniversaryPdf`

Uses Godot's built-in FileProvider (`${applicationId}.fileprovider` with `@xml/godot_provider_paths`).
Do not register a second FileProvider.

From GDScript:

```gdscript
var plugin = Engine.get_singleton("AnniversaryPdf")
plugin.openPdf(absolute_path)
plugin.sharePdf(absolute_path)
```

If you reinstall the Android build template, re-copy the Java class into `android/build` and restore the manifest meta-data entry. Also restore `android/.build_version` with `4.7.1.stable`.
