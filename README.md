# Recipes

A recipe library, meal planner, and grocery-list app.

Live: <https://alexdalgleishmorel.github.io/recipes/>

Browse a personal cookbook with a Datadog-style query language, sketch a week
of meals on a day×meal calendar, get an automatically aggregated grocery list
from whichever meals you select, and (eventually) hand the planning over to an
AI assistant.

The frontend is a Flutter app that targets web first, with mobile and desktop
support coming for free. The backend is not yet implemented — all data is
mocked behind a repository abstraction so it can be slotted in later without
touching UI code.

## Repository layout

```
recipe/
├── frontend/              # Flutter app (web + mobile + desktop)
├── backend/               # placeholder — not yet implemented
└── recipes-wireframe/     # design handoff bundle (HTML/CSS/JS prototype)
```

## Frontend

A Flutter app organised by layer (`models/`, `screens/`, `services/`,
`widgets/`, `utils/`, `theme/`). No external state-management package — a
top-level `AppShell` `StatefulWidget` owns the loaded recipes + plans, and
mutations bubble up via callbacks.

### Tech stack

- **Flutter 3.41+** (Material 3, web target enabled)
- **shared_preferences** for the mock data layer (swappable for HTTP later)
- **google_fonts** for Inter Tight, Newsreader, and JetBrains Mono
- **file_picker** for the upload dropzone
- **flutter_markdown** for AI chat replies

### Data layer

Each entity has an abstract `XRepository` interface in
[`frontend/lib/services/repositories.dart`](frontend/lib/services/repositories.dart).
Today's only implementation wraps `shared_preferences`; tomorrow's will hit
HTTP. Swapping is a one-line change in [`main.dart`](frontend/lib/main.dart) —
nothing else needs to move.

On first launch, the local repositories seed storage from the bundled JSON in
[`frontend/assets/seed/`](frontend/assets/seed/) (24 recipes + 2 sample plans
extracted verbatim from the wireframe), so the demo experience matches the
design.

### Screens

| Screen | Path |
|---|---|
| Browse | [browse_screen.dart](frontend/lib/screens/browse_screen.dart) |
| Recipe detail (read + edit) | [recipe_detail_screen.dart](frontend/lib/screens/recipe_detail_screen.dart) |
| Upload | [upload_screen.dart](frontend/lib/screens/upload_screen.dart) |
| Meal plans list | [plans_screen.dart](frontend/lib/screens/plans_screen.dart) |
| Plan detail (calendar + chat + grocery) | [plan_detail_screen.dart](frontend/lib/screens/plan_detail_screen.dart) |

### Notable utilities

- [`utils/search_query.dart`](frontend/lib/utils/search_query.dart) — full
  Datadog-syntax parser (free text, `field:value`, quoted values,
  `(a OR b)`, AND/OR, negation, numeric comparisons, custom tags).
- [`utils/grocery_aggregator.dart`](frontend/lib/utils/grocery_aggregator.dart)
  — sums ingredients across selected recipes, dedupes by name+unit, and
  groups into Produce / Protein / Dairy / Pantry / Other.

## Local setup

### 1. Install Flutter

If you don't already have Flutter installed, follow
<https://docs.flutter.dev/get-started/install> for your platform.

Verify the install:

```sh
flutter --version    # should report Flutter 3.41+ and Dart 3.11+
flutter doctor       # check for any platform-specific gaps
```

### 2. Install dependencies

```sh
cd frontend
flutter pub get
```

### 3. Run the app

```sh
# In a Chrome browser (recommended for development):
flutter run -d chrome

# Or pick another device:
flutter devices
flutter run -d <device-id>
```

The app boots with the 24 seeded recipes and 2 seeded meal plans already
populated in local storage.

### 4. Run the tests

```sh
cd frontend
flutter test
```

Covers the search-query parser and the grocery aggregator.

### 5. Build for production

```sh
cd frontend
flutter build web
# output: frontend/build/web/
```

### Wiping seed data

Mock data lives in `shared_preferences`. To reset:

- **Web (Chrome)**: open DevTools → Application → Local Storage → clear the
  origin's entries, then reload.
- **Mobile / desktop**: uninstall and reinstall the app, or delete the
  app's `shared_preferences` plist/SharedPrefs file.

## Backend

Not yet implemented. The eventual contract will mirror the
`RecipesRepository` / `MealPlansRepository` / `SettingsRepository` interfaces
defined in the frontend's `services/` directory. When ready, drop in HTTP
implementations (e.g. `HttpRecipesRepository`) and switch the wiring in
`main.dart`.

## Wireframe

The design originated from a Claude Design (claude.ai/design) handoff. The
full source HTML lives at
[`recipes-wireframe/project/Recipes.html`](recipes-wireframe/project/Recipes.html)
— useful as the source of truth for any visual or behavioural questions.
