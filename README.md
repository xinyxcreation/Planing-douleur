# Suivis douleur — v1.7

Application Flutter de suivi des douleurs et activités, désormais préparée pour **Android + Web/PWA**.

## PWA / Web

La version Web peut être installée comme une application depuis Chrome/Edge sur ordinateur ou Android.

- stockage local via `SharedPreferences` ;
- fonctionnement sans compte ni serveur ;
- export/import CSV ;
- interface responsive ;
- manifest PWA et icônes inclus ;
- service worker généré automatiquement par Flutter lors du build.

### Lancer sur le Web

```bash
flutter pub get
flutter run -d chrome
```

### Construire la PWA

```bash
flutter build web --release
```

Le contenu à publier est dans :

```text
build/web/
```

## Icône et splash Android

```bash
flutter pub get
flutter pub run flutter_launcher_icons
flutter pub run flutter_native_splash:create
```

## Android

```bash
flutter pub get
flutter run
```

## CI

GitHub Actions construit maintenant également la version Web dans `build/web`.
