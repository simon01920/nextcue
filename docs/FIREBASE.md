# Connecting Firebase

The app is already wired for Firebase. While `lib/firebase_options.dart` is
the placeholder, it runs on on-device accounts. Once you generate the real
file, it switches automatically to:

* **Firebase Auth** (email + password, password reset) for accounts;
* **Cloud Firestore** for cloud sync of each account's watched episodes,
  statuses, ratings, favourites, artwork choices and theme
  (`lib/services/cloud_sync.dart`, one document per user at `users/{uid}`).

No other code edits are needed. Everything fits the free **Spark** plan.

## 1. Create the project (console, ~5 min)

1. <https://console.firebase.google.com>, then **Add project**, named e.g.
   `nextcue`. Google Analytics is optional.
2. **Build → Authentication → Get started → Sign-in method**: enable
   **Email/Password**.
3. **Build → Firestore Database → Create database**: production mode,
   region close to your users (e.g. `eur3` for Europe). The location can't
   be changed later.
4. **Authentication → Settings → Authorized domains**: add the domain the
   web app will be served from (e.g. `nextcue.simondev.app`). `localhost`
   and `*.web.app` are there by default.

## 2. Generate the app config (terminal)

```bash
npm install -g firebase-tools        # Firebase CLI
dart pub global activate flutterfire_cli
firebase login
flutterfire configure --project=<your-project-id> \
  --platforms=android,ios,web \
  --android-package-name=app.simondev.nextcue \
  --ios-bundle-id=app.simondev.nextcue
```

This overwrites `lib/firebase_options.dart`, and that's all the app needs.
It also writes `android/app/google-services.json` and
`ios/Runner/GoogleService-Info.plist` and adds the Google Services Gradle
plugin.

These config files are **not secrets**. Firebase client keys are public by
design, and access is controlled by the security rules below. They are
listed in `.gitignore` only to be conservative. Either:

* commit them (simplest: any clone builds), by deleting the
  `google-services.json` / `GoogleService-Info.plist` lines from
  `.gitignore`; or
* keep them out of git and re-run `flutterfire configure` on each machine.

## 3. Deploy the security rules

```bash
cp .firebaserc.example .firebaserc   # then put your project id in it
firebase deploy --only firestore
```

`firestore.rules` lets a signed-in user read and write **only their own**
`users/{uid}` document, with only the fields the app writes. Every other
path is denied.

## 4. Run

```bash
flutter run -d chrome --dart-define-from-file=.env
```

Register an account, mark some episodes, then sign in on a second browser
or device: the state follows the account.

### Local emulators (optional, no real project touched)

```bash
firebase emulators:start
flutter run -d chrome --dart-define=USE_FIREBASE_EMULATOR=true
# Android emulator: add --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2
```

## 5. Host the web app (optional, free)

```bash
flutter build web --release --dart-define-from-file=.env
firebase deploy --only hosting
```

`firebase.json` serves `build/web` with SPA rewrites, no-cache on the
bootstrap files (so a deploy is picked up immediately) and long caching on
assets and CanvasKit. A custom domain is added under **Hosting → Add custom
domain**.

## How sync behaves

* Local storage is still the first source: the app paints from it with no
  network wait. The cloud copy is pulled right after sign-in and merged in.
  Edits made on this device since then are kept.
* First sign-in on an account with no cloud document uploads the device's
  data.
* Edits are gathered for 3 s and sent as **one** merged write. Rapid swiping
  costs one write, not dozens, which keeps well inside the free 20K
  writes/day. Pending edits are flushed when the app is backgrounded and
  before sign-out.
* Offline: Firestore's persistent cache serves reads and queues writes until
  the connection returns (enabled on web too, in `main.dart`).
* One document holds roughly 15,000 watched episodes (1 MiB limit). Past
  that, move `watched`/`watchedAt` into a subcollection.

## Free-tier budget (Spark)

| Resource        | Free / day or month | NextCue use per active user          |
| --------------- | ------------------- | ------------------------------------ |
| Firestore reads | 50K / day           | ~1 per app start                     |
| Firestore writes| 20K / day           | ~1 per 3 s burst of edits            |
| Storage         | 1 GiB               | ~10-100 KB per user                  |
| Auth            | 50K MAU             | 1 per user                           |
| Hosting         | 10 GB / month       | ~3-5 MB per first visit, then cached |

## Later

* **App Check** (Firestore → App Check): blocks scripted abuse of the public
  config. Turn it on once the app is public.
* **Sign in with Google / Apple**: enable the provider in Authentication.
  The app needs a button and `firebase_auth`'s provider flow.
* The local demo account (`TRY THE DEMO`) becomes a real Firebase account
  on first use. Disable it before a public launch if you don't want a
  shared account.
