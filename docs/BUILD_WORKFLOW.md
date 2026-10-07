# Build workflow

1. Confirm product rules: roles, company membership approval, anonymity, report handling, and retention.
2. Create Supabase/PostgreSQL project and apply `database/scheme.sql` after review. Enable auth providers and callback URLs.
3. Implement backend configuration, auth token verification, authorization, company and membership APIs, then profile and feed CRUD. Keep business rules and privileged DB access in the API.
4. Build admin web: company requests, CSV preview/import, memberships, and moderation queue.
5. Build Flutter member flow: sign-in, onboarding/company selection, Home, Trending, People, and Profile. Connect through the API.
6. Add FCM token registration, notification preferences, and event delivery. Request OS permission in context.
7. Complete light/dark/system themes and loading, empty, error, and offline states.
8. Before release, configure provider credentials, production secrets, backups, abuse controls, privacy policy, and app-store requirements.

## Company CSV
Use a header row `company_name,website_domain,approved_email_domains`. Domains are optional and may be semicolon-separated. Preview and validate rows, flag duplicates, then require an admin confirmation. Do not auto-enroll a person solely from a matching domain.
