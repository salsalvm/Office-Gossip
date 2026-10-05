# Office Gossip Frontend Web

Member-facing web UI for Office Gossip. This app is separate from `admin-web` and follows the Phase 1 member tabs: Home, Trending, People, and Profile.

## Run locally

```sh
cd frontend-web
npm install
npm run dev
```

## Current scope

Authentication, company selection, feed loading, post creation, likes, and people directory data use the backend API. Trending filters and some profile controls remain presentation-only. Image posts are intentionally out of scope for Phase 1.

## Member API connection

The member UI reads feed and people from the API; it does not seed posts or directory records in the browser. Configure `VITE_API_URL=http://localhost:4000` in `frontend-web/.env` (see `.env.example`). Configure Supabase and `FRONTEND_URL` in `backend/.env`. The service role key belongs only in the backend. It expects these authenticated API routes:

- `GET /api/community/feed` → `Post[]` (`id`, `person`, `role`, `company`, `time`, `body`, `likes`, `comments`, optional `anonymous`, `liked`, `tag`)
- `GET /api/community/people` → `Person[]` (`id`, `name`, `role`, `team`)
- `POST /api/community/posts` with `{ body, anonymous }`
- `POST /api/community/posts/:id/likes`

The authentication routes are implemented in `backend/src/app.ts`; community feed routes are still pending. Apply `database/001_initial_schema.sql` to the Supabase project before using auth registration and company membership. Google OAuth and password reset require the provider and redirect URLs to be enabled in Supabase Auth. Do not put Supabase service credentials in this frontend.

Registration also expects `GET /api/public/companies` to return active companies as `[{ "id": "…", "name": "…" }]`. The registration endpoint accepts either `companyId` for a listed company or `companyName` when the applicant requests a company that is not listed. In the latter case, the backend creates the user/profile and a pending `company_requests` record for admin review. The frontend does not create or activate companies directly.

## Authentication API setup

The Express API now provides Supabase-backed email registration/sign-in, Google OAuth, password reset, session refresh, active company lookup, and company request creation during registration. Configure `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, and `FRONTEND_URL` in `backend/.env` using `backend/.env.example`. Keep the service role key on the server only. In Supabase, enable email/password and Google providers and allow the frontend URL plus `/reset-password` in the Auth redirect URL list. Google OAuth credentials and provider callback URLs must also be configured in Supabase. Start the API with `cd backend && npm run dev`; point the frontend `.env` `VITE_API_URL` at that API.

Email confirmation behavior depends on the Supabase project setting. If confirmation is enabled, the API returns a confirmation-required response; the user can sign in after confirming. Company list and request creation use the existing `companies`, `profiles`, `company_memberships`, and `company_requests` tables from the schema.

The signed-in profile and preferences are loaded from `GET /api/me`. Profile edits use `PATCH /api/me/profile`; theme and notification preferences use `PATCH /api/me/preferences`. The Sign out control revokes the Supabase session through `POST /api/auth/logout`, then clears local access/refresh tokens and in-memory member data.
