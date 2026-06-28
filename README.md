## Introduction

Cross-Site Scripting (XSS) is what happens when user-supplied content is rendered as code. An attacker writes a "note" whose body is `<img src=x onerror="...evil...">`; when another user opens the page, the victim's browser runs that JavaScript on the attacker's behalf. From there the attacker can read the victim's session, log their keystrokes, exfiltrate cookies, or call your API as the victim.

This task adds rich-text (HTML) support to the notes app — and uses that feature to walk through XSS end-to-end: the vulnerability, a working keylogger payload, an attacker server that collects the stolen keystrokes, and a sanitizer that defends against it.

## Goals
This task's goals are:
- Render rich-text notes (HTML formatting) — and understand why `dangerouslySetInnerHTML` is named the way it is.
- Build a working XSS attack against your own app: a keylogger payload that posts every keystroke to a separate attacker server.
- Implement a sanitizer that neutralizes the attack while preserving safe formatting tags, and a UI toggle that demonstrates the difference live.
- Write Playwright tests that prove the attack works when the sanitizer is off and is blocked when it is on.

## Submission
- Coding: 70%, Questions: 30%.
- Your submitted git repo should be *private*, please add 'barashd@post.bgu.ac.il' and '[Yuval Tzvi Rays](https://github.com/YuvalZviRays)' to the list of collaborators.
- Deadline: 3.7.26, end of day.
- Additionally, solve the [theoretical questions](https://docs.google.com/forms/d/e/1FAIpQLSditpxCsGQ2sRMlO2MlXGP57WLRbvfzYNNdkq_0TJJ-oerszA/viewform?usp=dialog).
- Use TypeScript, and follow the linter's warnings (see eslint below). The linter can be faulty; use it to get early signs of bugs, the automatic tests will not take away points for linter warnings.

- Git repository:
  - HW4 builds on top of your HW3 solution. Continue working in the **same private repo** you used for HW3 — do not create a new one. Your `submission_hw3` tag stays where it is; HW4 adds a new tag on a later commit.
  - Aim for a minimal repository size that can be cloned and installed: most of the files in github should be code and package dependencies (add package.json, index.html).
  - Don't submit (add to git) .env (it's your secret file which includes passwords- add to gitignore), node_modules dir, package-lock.json, or note json files.
  - the submission commit will be tagged as `submission_hw4`.
  - to test your submission, run the presubmission script (in github). A submission that does not pass the presubmission script, gets a 0 score automatically.
      For example:
      ```bash
      bash presubmission.sh git@github.com:<your-org>/<your-repo>.git <full_.env_path>/.env
      ```
      - Tip: You can use a local git directory as the target git repository.
      - Tip: You can make the presubmission script run automatically during every git push.
      - Tip: `-x` argument to bash shows the currently executed line.

## AI

You are allowed to use AI assistants, but you must use them responsibly:

1. **Start alone.** Write the code yourself first. Use AI for the last stage: polishing, debugging, or checking your work. Not for regenerating components or whole files. This is how you actually learn.
2. **You must understand every bit of your code.** The sanitizer's whitelist, why `<script>` tags injected via `innerHTML` don't execute, why `<img onerror>` does, where the toggle lives in your component tree: you need to be able to explain all of it. If you cannot explain your code in the oral exam, the coding grade will be reduced accordingly.
3. **Both students in each pair will be tested** in an oral exam. The tester may ask about anything in your code, and will not ask the same questions to both partners.

## Plagiarism
- We use a plagiarism detector.
- The person who copies and the person who was copied from are both responsible.
- Set your repository private, and don't share your code.

## Prerequisites

### Recommended reading:
- MDN — Cross-site scripting (XSS): https://developer.mozilla.org/en-US/docs/Glossary/Cross-site_scripting
- OWASP — XSS Prevention Cheat Sheet: https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
- React — `dangerouslySetInnerHTML`: https://react.dev/reference/react-dom/components/common#dangerously-setting-the-inner-html
- DOMPurify (read for reference only — **do not use it in this assignment**): https://github.com/cure53/DOMPurify
- Node.js HTTP server basics: https://nodejs.org/en/learn/getting-started/introduction-to-nodejs

### Tools
- **A separate Node.js process** that plays the role of the attacker server, running outside the app's backend. No new npm dependencies are required for it — `http` from the standard library is enough.
- Your existing React frontend and Express backend from hw3 carry over. No new MongoDB collections; the existing notes collection stores rich-text content as-is.

## Feature: "Rich Notes with HTML"

A note's `content` field has always been a string. This task changes how the frontend *renders* that string — instead of plain text, the note body is rendered as HTML so users can use `<b>`, `<i>`, `<ul>`, etc. for formatting.

That change is one line of React (`<div dangerouslySetInnerHTML={{ __html: note.content }} />`), and that one line is the entire attack surface. Any user who can create a note can now ship arbitrary HTML — including HTML that contains script-equivalent behaviour — into every other user's browser.

The interesting part is not the attack itself; the attack works as soon as you do `innerHTML`. The interesting parts are: *which* HTML actually runs, what the attacker can do once it runs, and how a small sanitizer flips the whole feature from dangerous to safe without losing the formatting.

### How it works

1. A user (the attacker) creates a note whose `content` is HTML that includes a payload — for example, an `<img>` tag with an `onerror` attribute that runs JavaScript.
2. A second user (the victim) opens the page. The frontend fetches the note and renders its `content` via `dangerouslySetInnerHTML`.
3. The browser parses the HTML, fails to load the bogus `<img src=x>`, and runs `onerror` — the attacker's JavaScript now executes inside the victim's tab, with the victim's session.
4. The payload installs a `keydown` listener on `document` and ships each keystroke to a separate **attacker server** running on a different port.
5. The attacker server appends each keystroke to a file (`keylog.txt`).
6. Toggling the **sanitizer** on rewrites the note's HTML before render — `<img onerror=...>` becomes `<img>` (or is stripped entirely), the payload never executes, and the keylog stays empty.

**The shape of the attack.** The attacker creates a note whose `content` is HTML carrying a payload — typically a tag the browser parses with an event-handler attribute that fires immediately (think `<img>` with `onerror`, or `<svg>` with `onload`). When another user opens the page, the browser parses the rich content, the event fires, and the attacker's code runs in the victim's tab. With the sanitizer toggled on, the same note renders harmlessly; with the sanitizer off, the payload installs a keystroke listener and the attacker server starts collecting keys. Finding a payload that works is part of the exercise — see *Recommended reading* for pointers.

### What you implement

Four pieces. None of them require new backend routes; the existing `POST /notes` already accepts a string `content`.

**1. Rich-text rendering (frontend).** Render `note.content` as HTML so formatting tags are honored. Use React's `dangerouslySetInnerHTML` (or DOM `innerHTML` via a ref) — the name is the warning.

**2. Attacker server (separate process).** A small standalone Node script at `attacker_server.js` in the repo root. It listens for POST requests and appends each request body to a file (e.g., `keylog.txt`). Default port `4000`. Make sure cross-origin POSTs from the React origin actually reach it.

**3. Keylogger payload.** A note `content` string that, once rendered into the victim's DOM, installs a global `keydown` listener and ships each key to the attacker server above. Two things to know up front:
- `<script>` tags inserted via `innerHTML` *do not execute*. The browser ignores them. You need a DOM-event-handler attribute on a tag that the browser *does* run when it parses — `<img onerror>`, `<svg onload>`, etc.
- The payload runs in the React app's origin, not the attacker's. That is exactly why XSS is dangerous: the attacker's JavaScript runs as the victim.

**4. Sanitizer (frontend).** A function that takes raw HTML and returns HTML safe to inject. The exact whitelist of allowed tags depends on what rich-text formatting your app supports — e.g., basic formatting (`<b>`, `<i>`, `<strong>`) or a richer set (`<a>`, `<ul>`, `<h1>`, etc.). Whatever you allow, the sanitizer must drop the rest. General rules:
- Drop tags the browser uses to execute code (e.g., `<script>`, `<iframe>`).
- Drop event-handler attributes (`onclick`, `onerror`, `onload`, …) on every tag.
- If you allow `<a href>`, reject URL schemes that can execute code (`javascript:`, `data:`).

The toggle controls *whether* the sanitizer runs:
- Sanitizer **ON** (default): every note body is passed through `sanitizeHtml` before render. The keylogger payload above is neutralized; the keylog stays empty.
- Sanitizer **OFF**: raw `content` is rendered as HTML. The keylogger payload runs.

### Error handling

- Attacker server returns `200` on any well-formed POST and `500` on filesystem failure. It does not validate the body — that's the attacker's problem to get right.
- The frontend sanitizer must never throw on malformed input; it returns the empty string for non-string inputs and degrades gracefully on parse errors.

### Backend test requirements

- **Backend - Jest:** carry over the hw3 tests in `crud.test.ts`, `auth.test.ts`, `notes-filter.test.ts`, `ai.test.ts`. No new backend endpoints means no new backend tests beyond the hw3 carry-over. Run with `npm run test` from the backend directory (use `--runInBand` to keep tests from clobbering each other's data).

### Frontend test requirements

- **Playwright:** 3 new tests for the rich-text / XSS / sanitizer flow, in `frontend/playwright-tests/test.spec.ts` (alongside your hw3 carry-over). Run with `npm run test` from the frontend directory.

The required tests:

1. **Rich-text rendering is preserved.** Create a note with `content` `Hello <b>world</b>`. Assert the rendered note contains a `<b>` element whose text is `world`.
2. **XSS works when sanitizer is OFF.** Toggle the sanitizer off. Create a note containing your keylogger payload. Type a few keys somewhere on the page. Assert the attacker server's `keylog.txt` contains the keys you typed.
3. **XSS is blocked when sanitizer is ON.** Reset `keylog.txt` to empty. Toggle the sanitizer on. Create the same payload. Type a few keys. Assert `keylog.txt` is still empty.

### Notes for grading

We do not test against arbitrary XSS payloads. Grading uses common event-handler-based payloads (e.g., `<img onerror=...>`, `<svg onload>`). Your sanitizer must block at least these; perfection across the whole space of payloads is not the bar.

Anything this README does not explicitly require, you are free to design and implement however you like. We will not grade it. Examples: extra endpoints on the attacker server, additional toggles or settings, the visual layout of the homepage. Only the rules stated above are tested.

## Frontend requirements

### Routes

No new routes beyond hw3. Rich rendering and the toggle live on the existing homepage `/`.

### Components

- **Rich-note rendering** (visible in the existing post list):
    - Each note's body renders its `content` as HTML — through the sanitizer when the toggle is on, raw when it is off.
    - Container element `data-testid`: **"note_body"**.

- **Sanitizer toggle button** (`/` homepage):
    - `data-testid`: **"sanitizer_toggle"**
    - Text: `Sanitizer: ON` / `Sanitizer: OFF` depending on current state.
    - Default state: ON.
    - Persistence: React state only — refreshing the page resets to ON. (No localStorage, no backend column.)

- **Add Note form**: identical to hw3, except `content` is now treated as HTML downstream.

All hw3 components (Login, Create User, Logout, AI assistant, etc.) carry over unchanged.

## The tester will:
- Assume Ollama is already running locally on `http://localhost:11434` with the `qwen2.5:3b` model pulled and available (carried over from hw3 — the AI assistant must still work).
- Assume ports `3000` (frontend), `3001` (backend), and `4000` (attacker server) are free.
- `git clone <your_submitted_github_repo>`
- `cd <cloned_dir>`
- `git checkout submission_hw4`
- `npm install` from the `frontend` dir (package.json should exist)
- `npm run dev` from the `frontend` dir (configured to default port 3000)
- Copy a `.env` file into the `backend` dir.
- `npm install` from the `backend` dir (package.json should exist)
- `node index.js` from the `backend` dir (configured to default port 3001)
- `node attacker_server.js` from the repo root (configured to default port 4000)
- Run tests: frontend (playwright) and backend (jest).

## Appendix

### Suggestions

- The sanitizer is the only place that touches HTML strings. Keep it as a single pure function in one file; resist the temptation to spread "small fixes" across components.
- `<script>` tags injected via `innerHTML` do not execute. If your first keylogger attempt is `<script>...</script>` and nothing happens, that is why. Use an event-handler attribute on a tag the browser parses (e.g., `<img onerror>` or `<svg onload>`).
- The keylogger payload runs in the victim's origin — meaning it can read `document.cookie`, your React state's auth token, and call your own backend with the victim's credentials. The hw3 JWT is reachable from here: HW3 noted that storing the token in React state is "not secure"; this is the attack that note was about. Try swapping `body: e.key` in the payload for the in-memory token and watch it land in `keylog.txt`. Not required for grading — but exactly the lesson the assignment exists to teach.
- Don't forget CORS on the attacker server. Without `Access-Control-Allow-Origin: *` the browser will block the POST and your keylogger will look broken when it is in fact working.

### Smoke-test XSS without the frontend

Before wiring up the React side, verify the attacker server works in isolation:

```bash
# In one terminal
node attacker_server.js

# In another
curl -X POST http://localhost:4000/log -d 'a'
curl -X POST http://localhost:4000/log -d 'b'
cat keylog.txt
```

Expected: `keylog.txt` contains two lines, one per request, each with the body and a timestamp.

Then verify the sanitizer in isolation by writing a one-off Node script (or a Jest unit test) that imports `sanitizeHtml` and asserts:

```ts
sanitizeHtml('<b>hi</b>')                                  // → '<b>hi</b>'
sanitizeHtml('<img src=x onerror="evil()">')               // → '<img src="x">' (or '')
sanitizeHtml('<a href="javascript:evil()">click</a>')      // → '<a>click</a>'
sanitizeHtml('<script>evil()</script>safe')                // → 'safe'
```

If both isolated checks pass, the React integration is mostly a matter of wiring the toggle and the `dangerouslySetInnerHTML` call.

Common failures and what they mean:
- The page is blank after toggling sanitizer off and creating a payload note — the payload likely contains a tag that broke the surrounding DOM. Wrap your test payload in benign text first (`hello <img ...> world`) so a broken payload doesn't take the whole page with it.
- The keylogger runs but `keylog.txt` stays empty — almost always CORS. Open DevTools' Network tab; a CORS-blocked POST shows as red with no status.
- The keylogger runs but every keystroke shows up as `undefined` in the log — your payload is reading the wrong property of the event. Use `e.key`, not `e.value`.

## Good luck!
