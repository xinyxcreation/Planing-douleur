# Suivis douleur — v1.7

PWA Flutter pour suivre les douleurs et activités.

## Web / PWA

Le dépôt est configuré pour que **GitHub Actions construise et publie automatiquement la PWA** sur GitHub Pages.

Après un `git push`, aucune commande Flutter supplémentaire n’est nécessaire : GitHub lance automatiquement `flutter pub get` puis `flutter build web --release`.

Application : https://xinyxcreation.github.io/Planing-douleur-pwa/

## Développement local

```bash
flutter pub get
flutter run -d chrome
```

## Build manuel

```bash
flutter build web --release --base-href /Planing-douleur-pwa/
```

## Android

```bash
flutter build apk --release
```
