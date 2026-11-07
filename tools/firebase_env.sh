#!/usr/bin/env bash
# Writes the Firebase API keys of project nextcue-5085d into .env
# (git-ignored), keeping any other lines already there.
# Needs the Firebase CLI signed in to an account with access to the project:
#   npx -y firebase-tools@latest login
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT=nextcue-5085d
fb() { npx -y firebase-tools@latest "$@" --project "$PROJECT" 2>/dev/null; }

web=$(fb apps:sdkconfig WEB 1:63944566183:web:6edbdafead58f36d54c282 |
  grep -o '"apiKey": *"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
android=$(fb apps:sdkconfig ANDROID 1:63944566183:android:169d86c925b6518754c282 |
  grep -o '"current_key": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
ios=$(fb apps:sdkconfig IOS 1:63944566183:ios:74d623dcf57495b154c282 |
  grep -A1 '<key>API_KEY</key>' | grep -o '<string>[^<]*' | sed 's/<string>//')

[ -n "$web" ] && [ -n "$android" ] && [ -n "$ios" ] ||
  { echo "Could not read the keys; is the Firebase CLI signed in?" >&2; exit 1; }

touch .env
grep -v '^FIREBASE_\(WEB\|ANDROID\|IOS\)_API_KEY=' .env > .env.tmp || true
{
  cat .env.tmp
  echo "FIREBASE_WEB_API_KEY=$web"
  echo "FIREBASE_ANDROID_API_KEY=$android"
  echo "FIREBASE_IOS_API_KEY=$ios"
} > .env
rm -f .env.tmp
echo "Wrote Firebase keys to .env"
