# Planning Douleur — PWA complète

Nouvelle implémentation indépendante de l'ancien client Flutter.

## Objectif

PWA de suivi des douleurs avec :

- authentification via `pwa-core`
- MariaDB
- synchronisation serveur/client
- fonctionnement hors ligne
- niveaux de douleur **0 à 3**
- catégories de douleurs personnalisables
- activités personnalisables
- historique
- import/export JSON
- installation PWA sur téléphone et PC

## Architecture

```text
PWA navigateur
   │ HTTPS
   ▼
planning-douleur-api
   │
   ▼
MariaDB (pwa-core-db)
```

Le backend utilise Fastify + MariaDB.
Le frontend est une PWA HTML/CSS/JavaScript sans framework obligatoire.

## Démarrage backend

```bash
cd backend
npm install
cp .env.example .env
npm start
```

## Base de données

Exécuter :

```bash
mariadb ... < backend/sql/schema.sql
```

Le schéma est prévu pour les utilisateurs déjà présents dans `pwa-core`.

## Frontend

Servir `frontend/` derrière HTTPS et configurer :

```text
API_BASE_URL=https://planning-douleur.xinyx.fr
```

Le fichier `frontend/config.js` contient cette configuration.

## Important

Les données locales sont conservées dans IndexedDB.
La synchronisation est basée sur un curseur serveur.

Les opérations locales sont placées dans une file et envoyées au serveur.
Le serveur traite chaque changement dans une transaction.

Les niveaux sont strictement :

```text
0 = aucune
1 = légère
2 = modérée
3 = forte
```
