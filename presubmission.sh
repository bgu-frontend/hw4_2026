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

# Start backend
cd backend
npm run backend > ../backend.log 2>&1 &
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
  kill $BACK_PID $FRONT_PID
  exit 1
}
cd ..

kill $BACK_PID $FRONT_PID
exit 0
