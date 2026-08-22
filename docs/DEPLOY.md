# Déploiement

## Backend

Depuis le dossier du projet :

```bash
cp backend/.env.example backend/.env
nano backend/.env

docker compose build
docker compose up -d
docker compose ps
```

Le réseau Docker `pwa-core` doit déjà exister.

## Caddy

Le backend doit être proxyfié vers :

```text
planning-douleur-api:3080
```

Le frontend peut être servi comme fichiers statiques sous `planning-douleur.xinyx.fr`.

## Auth

Cette version utilise le JWT retourné par `/auth/login`.
Le champ attendu est `token`, `accessToken` ou `jwt`, et l'identifiant utilisateur est recherché dans `user.id`, `userId` ou `id`.

Si pwa-core utilise une autre structure JWT, adapter uniquement `backend/src/auth.js`.
