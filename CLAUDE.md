# CLAUDE.md

Guidance for Claude Code (and other coding agents) working in this repo.

## What this is

A recipe library + meal planner + grocery-list app. Frontend is Flutter (web
first, but mobile/desktop supported). Backend doesn't exist yet — all data is
mocked behind a repository abstraction.

```
recipe/
├── frontend/              ← Flutter app (this is where 99% of work happens)
├── backend/               ← empty placeholder; ignore until specced
└── recipes-wireframe/     ← original HTML design handoff (source of truth)
```

## Architecture conventions

These conventions mirror the user's other Flutter project at
`/Users/alexdalgleishmorel/Desktop/budget-trace/frontend` — keep them
consistent so the user gets the same shape across projects.

- **No state-management package.** A top-level `AppShell` `StatefulWidget`
  ([widgets/app_shell.dart](frontend/lib/widgets/app_shell.dart)) owns the
  loaded recipes + plans. Mutations from screens bubble up via callbacks
  (`onChanged`) which trigger a refetch. Don't reach for Provider, Riverpod,
  Bloc, or GetX.
- **Layered folders** under `lib/`: `models/`, `screens/`, `services/`,
  `widgets/`, `utils/`, `theme/`. No feature-folder nesting.
- **Plain Dart models** with `copyWith` + `toJson` / `fromJson`. No `freezed`,
  no `json_serializable`, no codegen.
- **Material 3** with a custom `RecipeTheme` `ThemeExtension`
  ([theme/app_theme.dart](frontend/lib/theme/app_theme.dart)) carrying every
  design token from the wireframe (light + dark). Access via `context.rt` —
  the extension getter on `BuildContext`.
- **Navigator 1.0.** Per-tab nested `Navigator`s in the `AppShell` so each
  tab keeps its own back stack. No `go_router` / `auto_route`.
- **Web target** is enabled and is the primary dev target. Don't break the
  build by adding mobile-only widgets without responsive fallbacks.

## Repository pattern (the swap point)

Every persistent entity has an abstract repository in
[`services/repositories.dart`](frontend/lib/services/repositories.dart):

```dart
abstract class RecipesRepository {
  Future<List<Recipe>> list();
  Future<Recipe?> get(String id);
  Future<Recipe> save(Recipe recipe);   // upsert
  Future<void> delete(String id);
}
```

Today's implementations (`LocalRecipesRepository`, etc.) wrap
`shared_preferences` and seed from
[`assets/seed/`](frontend/assets/seed/) on first launch. When the backend is
specced, write `HttpRecipesRepository` (etc.) implementing the same
interface and swap the wiring in [`main.dart`](frontend/lib/main.dart) — no
other file should need to change.

**When adding a new persistent entity**: define an `XRepository` abstract
class first, then a `LocalXRepository` implementation, and inject through
`AppShell` like the existing ones.

## Theming

Every visual token lives in [`theme/app_theme.dart`](frontend/lib/theme/app_theme.dart):

- `RecipeColors` — raw light + dark constants, ported from the wireframe's
  CSS variables (`paper`, `paper2`, `ink`, `ink2`, `ink3`, `hair`, `hair2`,
  `accent`, `accentSoft`, `accentInk`, `danger`, `ok`, ...).
- `RecipeRadius` — `card=10`, `field=6`, `chip=999`.
- `RecipeTypography.sans/serif/mono` — Inter Tight, Newsreader, JetBrains
  Mono via `google_fonts`.

**Always pull colors from `context.rt`.** Never hardcode hex values in
widgets — if a token doesn't exist for what you need, add it to
`RecipeTheme` (light + dark + `copyWith` + `lerp`) and reference it from
there.

## Wireframe is source of truth

When in doubt about visuals or behaviour, read
[`recipes-wireframe/project/Recipes.html`](recipes-wireframe/project/Recipes.html).
It's a complete HTML/CSS/JS prototype. Specifically:

- CSS variables (lines ~11–51) are the authoritative design tokens.
- Class names like `.g-cell`, `.cal-cell`, `.tchip-kv`, `.btn-primary` map
  directly to widgets in `lib/widgets/`. When matching styling, search the
  wireframe for the relevant class and port colors/sizes/borders verbatim.
- The hardcoded `RECIPES` and `PLANS` arrays (lines ~1579+ and ~1952+) are
  the source of [`assets/seed/recipes.json`](frontend/assets/seed/recipes.json)
  and [`assets/seed/plans.json`](frontend/assets/seed/plans.json).

## Tests

Unit tests live in [`frontend/test/`](frontend/test/) and cover the two
non-trivial pure-Dart utilities:

- [`search_query_test.dart`](frontend/test/search_query_test.dart) — Datadog
  query parser (free text, `field:value`, AND/OR, negation, numeric ops,
  custom tags).
- [`grocery_aggregator_test.dart`](frontend/test/grocery_aggregator_test.dart)
  — `parseAmt`, `normUnit`, `categorize`, ingredient summing.

When you change either of those utilities, update the tests. Don't write
widget tests unless explicitly asked.

## Common commands

```sh
cd frontend
flutter pub get          # install / sync dependencies
flutter analyze          # static analysis (must be clean before declaring done)
flutter test             # run unit tests
flutter run -d chrome    # local web dev
flutter build web        # production web build → build/web/
```

After every meaningful code change, run `flutter analyze` and confirm "No
issues found!" before declaring the task done.

## Things to NOT do

- Don't add `Provider`, `Riverpod`, `Bloc`, `GetX`, or any other
  state-management package.
- Don't add `freezed`, `json_serializable`, or any other codegen tool.
- Don't add `go_router` or `auto_route`.
- Don't touch `backend/` until the user starts a backend conversation.
- Don't hardcode hex colors in widgets — extend `RecipeTheme` instead.
- Don't render the wireframe HTML in a browser to "see" what something
  looks like — the wireframe README is explicit that you should read the
  source directly.
- Don't use emoji in code or commits.

## How to add a new screen

1. Add the screen file under `lib/screens/`.
2. Wire it into the appropriate tab inside `AppShell._tabRoot()` (or push it
   onto a tab's `Navigator` from another screen).
3. Wrap the body in a `ContentScroll` + `PageHead` from
   [`widgets/page_head.dart`](frontend/lib/widgets/page_head.dart) so it
   matches the spacing/typography of existing screens.
4. Pull colors via `context.rt` and typography via `RecipeTypography`.
5. Run `flutter analyze`.
