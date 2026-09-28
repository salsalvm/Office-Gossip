# OfficeGossip — Phase 1 overview

## Product
A mobile-first app for members of approved company communities to share and discuss workplace updates. Phase 1 posts contain text and emojis only.

## Member app
Four bottom tabs: **Home**, **Trending**, **People**, and **Profile**. Home includes the feed and a compose action. Profile includes profile CRUD, company selection/change, light/dark/system theme, notification preferences, and sign-out/account actions.

Sign-in choices: Google, Apple, email, or mobile. Onboarding collects a display name and asks the user to select a company or request one. Company membership can require an invite or admin approval.

## Phase 1 scope
- Company feed; text-and-emoji posts; optional anonymity; edit/delete own post.
- Likes, comments, reports, and basic moderation states.
- Company directory and member profile viewing.
- Admin company management, bulk CSV import, membership requests, and reported-post review.
- Push notifications via Firebase Cloud Messaging after user permission and preference selection.
- Light, dark, and system theme.

## Later phase
Image posts and their upload, storage, preview, and moderation flow are out of Phase 1.

## Trust and privacy decisions
- Never expose the author identity in an anonymous post response to ordinary members. Retain an internal author ID for authorized moderation.
- Do not assume an email-domain match proves employment. Use an invite or admin approval by default; allow domain-based verification only when configured by the company.
- Collect only necessary account/profile fields. Keep privileged database keys server-side.
