# Office Gossip

A mobile-first workplace community app. Members join an approved company community to read and share workplace updates. **Phase 1 supports text and emoji posts only.** Image posts are planned for a later phase.

## Project overview

The project is kept in one repository so the Flutter app, React admin dashboard, Node.js API, and database schema can evolve together.

| Part | Technology | Purpose |
| --- | --- | --- |
| Member app | Flutter, BLoC, Clean Architecture (`com.tabletalk.officegossip`) | Sign-in, company onboarding, feed, profiles, and notifications |
| Admin dashboard | React + Vite + TypeScript | Company requests/imports, membership administration, and post moderation |
| API | Node.js + Express + TypeScript | Authentication checks, authorization, business rules, and app APIs |
| Data | PostgreSQL / Supabase | App records and optional Supabase Auth infrastructure |
| Push | Firebase Cloud Messaging (FCM) | Push delivery to registered mobile devices |

## Phase 1 member experience

The mobile app has four bottom-navigation destinations:

1. **Home** — Company feed, text-and-emoji post composer, likes, comments, and report action.
2. **Trending** — Popular company posts with simple time filters.
3. **People** — Search company members and view their profiles.
4. **Profile** — View and edit profile, select or request a company, choose theme, manage notification preferences, and sign out.

Sign-in options are Google, Apple, email, or mobile. New members complete a basic profile and select a company. If the company is missing, they can request it for admin review. Membership may use an invite or admin approval; a matching email domain alone is not proof of employment.

Posts support text and emojis, optional anonymous display, author edit/delete, likes, comments, and reporting. Anonymous posts hide the author from regular members; authorized moderation retains an internal author reference. Themes are light, dark, and system default.

## Flutter architecture: BLoC + Clean Architecture

The mobile app will use **feature-first Clean Architecture**, with BLoC handling presentation state. Each feature keeps its UI, business rules, and data access separated:

```text
mobile/lib/
├── app/                         # App bootstrap, router, theme, dependency setup
├── core/                        # Shared failures, API client, common widgets/utilities
└── features/
    ├── auth/
    │   ├── data/                # Auth data sources, models, repository implementation
    │   ├── domain/              # Auth entities, repository contract, use cases
    │   └── presentation/         # Screens, widgets, AuthBloc/events/states
    ├── company/                 # Search/select/request company; same three layers
    ├── feed/                    # Feed, post creation, likes, comments; same layers
    ├── people/                  # Directory and member profiles; same layers
    └── profile/                 # Profile CRUD, theme and notification preferences
```

### Dependency direction

```text
Presentation (widgets + BLoC)
             ↓
Domain (entities + use cases + repository contracts)
             ↑
Data (API sources + DTOs + repository implementations)
```

- **Presentation:** Widgets render state and send user intent as BLoC events. BLoCs emit explicit loading, success, empty, and failure states. Widgets do not call the API directly.
- **Domain:** Entities, repository interfaces, and use cases hold app rules. This layer should not depend on Flutter, HTTP, or database libraries.
- **Data:** Repository implementations translate API responses into domain entities. Remote data sources call the Node API; DTOs stay in this layer.
- **Core/app:** Shared infrastructure, dependency injection, navigation, and themes live outside individual features.

Keep BLoCs focused on a feature and avoid one global BLoC for the whole app. Use Cubit for simple state where event-based BLoC adds no value. Add `flutter_bloc` (and the chosen immutable/state utilities) when the starter UI is refactored into these layers.

**Current status:** `mobile/lib/main.dart` is a small UI preview and does not yet implement this architecture, real authentication, API calls, or BLoC. The structure above is the target for implementation, not a claim that those layers already exist.

## Admin and backend responsibilities

The admin dashboard is for authorized admins. It will support company requests, a company directory, CSV import with preview and duplicate detection, membership review, and a reported-post moderation queue.

The backend is the trusted application boundary. It must verify identity tokens, check role and active company membership, validate input, and enforce access rules for every operation. Clients should not use privileged database credentials. Keep the Supabase service-role key and other secrets on the backend only.

## Repository layout

```text
office-gossip/
├── admin-web/                   # React admin dashboard
├── backend/                     # Node.js / Express API
├── mobile/                      # Flutter member app
├── database/                    # PostgreSQL schema and import template
├── docs/                        # Product overview and build workflow
│   └── .env.example             # Backend configuration template
└── README.md
```

## Start the current starters

Prerequisites: Node.js, npm, Flutter SDK, and a PostgreSQL database or Supabase project.

```sh
# API (currently only implements GET /health)
cd backend
cp .env.example .env
npm install
npm run dev

# Admin UI starter
cd ../admin-web
npm install
npm run dev

# Flutter UI preview
cd ../mobile
flutter pub get
flutter run
```

The current starter screens and API are not a complete, connected product. Provider sign-in, BLoC layers, API features, database migrations/policies, CSV import, moderation actions, and FCM delivery still need implementation. Follow [`docs/BUILD_WORKFLOW.md`](docs/BUILD_WORKFLOW.md) for the recommended order.

## Database and company CSV

`database/001_initial_schema.sql` is a schema draft for PostgreSQL/Supabase. Review it and add appropriate row-level security policies before exposing tables to client credentials. `database/companies_import_template.csv` shows the admin import columns:

```csv
company_name,website_domain,approved_email_domains
Acme Technologies,acme.example,acme.example;acme.co.example
```

Website domains and approved work-email domains are separate fields. Domain verification should be an explicitly enabled company policy; use invite/admin approval by default.

## Local configuration and secrets

Copy `backend/.env.example` to `backend/.env.local` for local configuration. `.env` files are ignored by Git. Never commit passwords, OAuth client secrets, Firebase service-account files, signing keys, or the Supabase service-role key. Use environment-specific secret storage for deployment.

## Out of scope for Phase 1

Image posts and image upload/storage/moderation are deferred. Keep Phase 1 centered on company onboarding, text-and-emoji posting, profiles, basic interactions, moderation, themes, and user-controlled push notifications.
