# Planning-douleur backend 1.1

API dédiée à Planning-douleur.

## Base de données

- BDD: `pwa_planning_douleur`
- utilisateur: `planning_douleur_user`
- droits applicatifs: SELECT, INSERT, UPDATE, DELETE uniquement
- structure: administrateur + migrations

## Installation/reinstallation

Copier `.env.example` vers `.env` et renseigner les secrets.

```bash
npm install
npm run setup
```

`setup` :
1. crée la BDD si nécessaire ;
2. crée/répare `admin@localhost` et `admin@%` ;
3. applique ALL PRIVILEGES + GRANT OPTION aux comptes admin ;
4. crée/répare `planning_douleur_user@localhost` et `@%` ;
5. limite ce compte à SELECT/INSERT/UPDATE/DELETE sur `pwa_planning_douleur.*` ;
6. exécute les migrations manquantes.

Aucun secret ne doit être commité.

## Vérifications

```bash
npm audit
npm run typecheck
```
