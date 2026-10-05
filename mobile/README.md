# Office Gossip mobile

Android application ID and iOS bundle identifier: `com.tabletalk.officegossip`.

Flutter member app organized by feature and Clean Architecture layers:

```text
lib/
├── app/                         # App widget and GoRouter
├── core/
│   ├── auth/                    # Shared session feature (data/domain/presentation)
│   ├── config/ env/             # AppEnvironment + per-environment AppConfig
│   ├── di/                      # get_it service locator modules
│   ├── error/                   # AppException (data) and Failure (domain)
│   ├── network/                 # Dio ApiClient, endpoints, interceptors, base classes
│   └── storage/ logger/ usecase/ utils/
└── features/
    ├── feed/{data,domain,presentation}
    ├── people/{domain,presentation}
    ├── notifications/{data,domain}
    └── profile/presentation
```

REST flow: `Bloc → UseCase → IRepository (Either<Failure, T>) → RepositoryImpl
(BaseRepository.handleRequest) → RemoteDataSource (BaseRemoteDataSource.safeApiCall)
→ Dio`. Dio interceptors attach the bearer token, refresh it once on 401, and log
requests/responses (with secrets redacted) when the environment enables logging.
Each feature registers its dependencies in its own `dependency_injection.dart`,
called from `core/di/injection_container.dart`.

Select the environment with `APP_ENV` (`dev` by default, logging on; `prod` has
logging off). In `dev` the API defaults to `http://10.0.2.2:4000` on Android
emulators and `http://localhost:4000` elsewhere; `API_BASE_URL` overrides the
host in any environment:

```sh
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:4000
flutter run --dart-define=APP_ENV=staging --dart-define=API_BASE_URL=https://staging.example.com
flutter build apk --dart-define=APP_ENV=prod --dart-define=API_BASE_URL=https://api.example.com
```

The backend must have Supabase configured. Apply the repository schema before
using registration and company community endpoints.

## Firebase push setup

Firebase is used for mobile push notifications; account authentication remains
on the REST/Supabase API. The app initializes Firebase Messaging when native
configuration is present and registers the device token with the API when the
member enables notifications from Profile.

The default Firebase project is `office-gossip` (`.firebaserc`). FlutterFire has
registered Android and iOS apps with the current package and bundle ID
`com.tabletalk.officegossip`. To refresh the generated configuration, run:

```sh
dart pub global activate flutterfire_cli
firebase login
firebase use office-gossip
flutterfire configure --project=office-gossip --platforms=android,ios --android-package-name=com.tabletalk.officegossip --ios-bundle-id=com.tabletalk.officegossip
```

FlutterFire generates `lib/firebase_options.dart` and the native Google
configuration files. Do not commit service-account credentials. The mobile app
uses native Firebase initialization from those generated platform files.
For iOS delivery, enable Push Notifications for the Runner target and upload an
APNs authentication key in the Firebase project settings.
