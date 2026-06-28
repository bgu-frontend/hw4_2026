#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "Usage: $0 <git_repo_url> <path_to_.env_file>"
  exit 1
fi

REPO_URL="$1"
ENV_FILE="$2"
TMP_DIR="tmp_submission_check"

rm -rf "$TMP_DIR"
mkdir "$TMP_DIR"
cd "$TMP_DIR" || exit 1

git clone "$REPO_URL" repo
if [ $? -ne 0 ]; then
  echo "Git clone failed."
  exit 1
fi

cd repo || exit 1
git checkout submission_hw4 2>/dev/null || echo "Branch 'submission_hw4' not found. Using default branch."

# Copy .env to backend
cp "$ENV_FILE" backend/.env || { echo "Failed to copy .env file"; exit 1; }

# Install dependencies
cd backend || { echo "Missing backend directory"; exit 1; }
npm install || { echo "Backend npm install failed"; exit 1; }
cd ..

cd frontend || { echo "Missing frontend directory"; exit 1; }
npm install || { echo "Frontend npm install failed"; exit 1; }
npx playwright install || { echo "Playwright install failed"; exit 1; }
cd ..

# Kill processes on common ports
PORTS=(3000 3001)
for PORT in "${PORTS[@]}"; do
  PID=$(lsof -ti tcp:$PORT)
  if [ -n "$PID" ]; then
    echo "Killing process $PID on port $PORT"
    kill -9 "$PID"
  fi
done

# If the user defined a backend/package.json script named "attacker", start it.
# Otherwise assume the attacker server was started manually (the precheck below
# enforces port 4000 is listening before tests run).
if node -e "process.exit(require('./backend/package.json').scripts?.attacker ? 0 : 1)" 2>/dev/null; then
  ( cd backend && npm run attacker ) > ../attacker.log 2>&1 &
  ATTACKER_PID=$!
  sleep 2
fi

# Precheck: attacker server must be listening on port 4000 before the Playwright
# XSS tests run, otherwise they fail with a confusing ECONNREFUSED instead of a
# clear setup hint.
if ! lsof -ti tcp:4000 >/dev/null 2>&1; then
  echo "Attacker server not detected on port 4000."
  echo "Either define a 'scripts.attacker' in backend/package.json, or start it"
  echo "manually before re-running this script (e.g., node attacker_server.js)."
  kill $ATTACKER_PID 2>/dev/null
  exit 1
fi

# Start backend — prefer the user's `npm run dev` if defined, otherwise fall
# back to `node index.js` (matches the README's "The tester will" description).
cd backend
if node -e "process.exit(require('./package.json').scripts?.dev ? 0 : 1)" 2>/dev/null; then
  npm run dev > ../backend.log 2>&1 &
else
  node index.js > ../backend.log 2>&1 &
fi
BACK_PID=$!
cd ..
sleep 2

# Start frontend
cd frontend
npm run dev > ../frontend.log 2>&1 &
FRONT_PID=$!
cd ..
sleep 2

# Playwright tests
cd frontend
npx playwright test || {
  echo "Test failed."
  kill $BACK_PID $FRONT_PID $ATTACKER_PID 2>/dev/null
  exit 1
}
cd ..

kill $BACK_PID $FRONT_PID $ATTACKER_PID 2>/dev/null
exit 0
