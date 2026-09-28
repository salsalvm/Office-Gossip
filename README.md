# OfficeGossip

Mobile-first company communities for workplace updates. Phase 1 supports text-and-emoji posts only.

## Project layout

- `mobile/` — Flutter member app (Home, Trending, People, Profile).
- `admin-web/` — React admin dashboard starter.
- `backend/` — Node.js, Express, and TypeScript API starter.
- `database/` — PostgreSQL schema draft and migration notes.
- `docs/` — product scope, build workflow, and local setup notes.

## Prerequisites

Install Node.js (LTS), Flutter SDK, and PostgreSQL or create a Supabase project. Use a recent stable version of each.

## Start the starters

```sh
cd backend && cp .env.example .env && npm install && npm run dev
cd admin-web && npm install && npm run dev
cd mobile && flutter pub get && flutter run
```

The backend currently exposes only `/health`; the app entry points are UI/project skeletons. Authentication, database access, real CRUD, provider sign-in, and push delivery still need implementation. See `docs/BUILD_WORKFLOW.md`.

Never commit secrets. Keep service-role keys only on the backend.
