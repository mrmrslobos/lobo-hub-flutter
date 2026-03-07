# App Icon Assets

Drop your source images in this folder, then run:

```bash
npm run assets:generate
```

This auto-generates every required icon and splash screen size
for both iOS and Android.

## Required files

| File | Size | Purpose |
|------|------|---------|
| `icon.png` | 1024×1024 px | Main app icon (both platforms) |
| `icon-foreground.png` | 1024×1024 px | Android adaptive icon — foreground layer |
| `icon-background.png` | 1024×1024 px | Android adaptive icon — background color/image |
| `splash.png` | 2732×2732 px | Splash / launch screen |

## Quick start (single icon only)

If you only have one PNG (like your current icon), you can use it for all
four by duplicating it:

```bash
cp icon.png icon-foreground.png
cp icon.png icon-background.png
cp icon.png splash.png
npm run assets:generate
```

The generated files go into android/app/src/main/res/ (and ios/ when added).
