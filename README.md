# Suivis douleur

Application Flutter de suivi des douleurs et activités.

## PWA / Web

La version Web est construite et publiée automatiquement sur GitHub Pages à chaque push sur `main`.

URL : https://xinyxcreation.github.io/Planing-douleur-pwa/

Aucune commande Flutter n'est nécessaire pour le déploiement : GitHub Actions lance automatiquement `flutter pub get` puis `flutter build web --release`.

## Android

Le workflow `release.yml` est conservé pour les builds Android.
