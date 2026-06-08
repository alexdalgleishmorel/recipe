# Recipe import schema (canonical)

This is the **single source of truth** for the recipe-draft shape produced by
`POST /recipes/import`. The same schema is reused three ways and they must stay
in lockstep:

1. **JSON-upload validator** — a `.json` upload is strictly validated against
   this schema (`jsonschema`, `additionalProperties:false`) plus a completeness
   gate, with **no AI call** (tier `json`, $0).
2. **AI structured output** — the Anthropic call constrains the model to this
   schema via `output_config.format` (`type: json_schema`).
3. **UI** — the frontend (#77) renders/edits a draft of exactly this shape.

`id` and `image` are intentionally **not** part of the draft: the server assigns
the `id` on save (`POST /recipes`) and the image is the uploaded photo, not a
field the model invents.

## Fields

| Field          | Type                | Required | Notes |
|----------------|---------------------|----------|-------|
| `title`        | string              | yes      | Dish name. Completeness gate requires it to be non-empty. |
| `cuisine`      | string              | yes      | Cuisine/region; empty string when unclear. |
| `description`  | string              | yes      | One or two sentences; empty string if none. |
| `prepTime`     | integer             | yes      | Whole minutes; `0` when not stated. |
| `cookTime`     | integer             | yes      | Whole minutes; `0` when not stated. |
| `servings`     | integer             | yes      | Servings/yield; `0` when not stated. |
| `tags`         | string[]            | yes      | Short lowercase keywords; `[]` if none. |
| `dietary`      | string[]            | yes      | Dietary labels the ingredients support; `[]` if none. |
| `author`       | string              | yes      | Source/author; empty string if absent. |
| `ingredients`  | object[]            | yes      | Each `{amount, unit, name}` (all required strings, `additionalProperties:false`). Completeness gate requires >=1 entry with a non-empty `name`. |
| `instructions` | string[]            | yes      | One step per element, in order. Completeness gate requires >=1 non-empty step. |

Each ingredient object:

| Field    | Type   | Required | Notes |
|----------|--------|----------|-------|
| `amount` | string | yes      | Quantity as a string (`"2"`, `"1/2"`); empty string when not stated. |
| `unit`   | string | yes      | Measurement word (`"cup"`, `"tbsp"`); empty string when none. |
| `name`   | string | yes      | Ingredient name with no quantity. |

### Completeness gate (reliability floor)

A draft is **only** accepted (from either the JSON tier or the AI tier) when:

- `title` is a non-empty string, **and**
- there is at least one ingredient with a non-empty `name`, **and**
- there is at least one non-empty instruction.

Incomplete drafts are never emitted: the AI tier retries once on the fallback
model, and a JSON upload that parses/validates but is incomplete is rejected
with an `off-schema` error.

## Valid example

```json
{
  "title": "Garlic Butter Pasta",
  "cuisine": "Italian",
  "description": "A fast weeknight pasta in a garlicky butter sauce.",
  "prepTime": 5,
  "cookTime": 15,
  "servings": 2,
  "tags": ["pasta", "weeknight"],
  "dietary": ["vegetarian"],
  "author": "",
  "ingredients": [
    {"amount": "8", "unit": "oz", "name": "spaghetti"},
    {"amount": "3", "unit": "tbsp", "name": "butter"},
    {"amount": "3", "unit": "clove", "name": "garlic, minced"},
    {"amount": "", "unit": "", "name": "salt"}
  ],
  "instructions": [
    "Boil the spaghetti in salted water until al dente.",
    "Melt the butter and gently cook the garlic until fragrant.",
    "Toss the drained pasta in the garlic butter and season with salt."
  ]
}
```

## Raw JSON Schema

```json
{
  "type": "object",
  "properties": {
    "title": {"type": "string"},
    "cuisine": {"type": "string"},
    "description": {"type": "string"},
    "prepTime": {"type": "integer"},
    "cookTime": {"type": "integer"},
    "servings": {"type": "integer"},
    "tags": {"type": "array", "items": {"type": "string"}},
    "dietary": {"type": "array", "items": {"type": "string"}},
    "author": {"type": "string"},
    "ingredients": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "amount": {"type": "string"},
          "unit": {"type": "string"},
          "name": {"type": "string"}
        },
        "required": ["amount", "unit", "name"],
        "additionalProperties": false
      }
    },
    "instructions": {"type": "array", "items": {"type": "string"}}
  },
  "required": [
    "title", "cuisine", "description", "prepTime", "cookTime", "servings",
    "tags", "dietary", "author", "ingredients", "instructions"
  ],
  "additionalProperties": false
}
```

## API shapes

`POST /recipes/import` (auth required):

- **Single (back-compat):** `{contentBase64, contentType, filename}` or
  `{key, contentType?}` → `200` with a single Recipe draft (the schema above).
- **Multi:** `{files:[{contentBase64, contentType, filename}, ...], mode?}` →
  `200 {"results":[{"filename","ok",("tier","draft")|("error")}], "mode":"sync"}`.
  `tier` is one of `json` | `haiku` | `sonnet`.
- **Batch:** add `mode:"batch"` → `200 {"mode":"batch","batchId":str}`; poll
  `GET /recipes/import/batch/{id}` for status/results.

## Cost levers / tuning

All env-overridable (defaults in parens):

- `PRIMARY_MODEL` (`claude-haiku-4-5`), `FALLBACK_MODEL` (`claude-sonnet-4-6`) —
  never Opus.
- `PDF_MODE` (`image`) — `image` renders pages (no document text-token
  surcharge); `document` sends the raw PDF.
- `MAX_FILES` (`10`) — extras get a per-file error, not a 400.
- Per-MTok rates: `HAIKU_INPUT_PER_MTOK` (1), `HAIKU_OUTPUT_PER_MTOK` (5),
  `SONNET_INPUT_PER_MTOK` (3), `SONNET_OUTPUT_PER_MTOK` (15); batch billing is
  half.

Built-in levers: a substantial cached system block (prompt caching engages once
the static prefix exceeds Haiku 4.5's 4096-token minimum), image downsize to
longest-edge ≤1568 px (fewer image tokens), PDF rendered to images, and the
JSON tier that skips the model entirely.
