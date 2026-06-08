# Recipe import JSON schema

You can import a recipe by uploading a `.json` file on the **Upload** screen.
JSON files are imported directly (no AI pass) as long as they match the shape
below. Files that don't match are rejected with an error so you can fix them
and try again.

You can also upload images (`.jpg`, `.jpeg`, `.png`, `.webp`, `.gif`) and
`.pdf` files; those are parsed with AI. Select multiple files at once — each
file becomes its own recipe draft you review and save.

## Expected shape

All fields are required. Do **not** include `id` or `image` — those are
assigned by the app.

| Field          | Type                                  | Notes                          |
| -------------- | ------------------------------------- | ------------------------------ |
| `title`        | string                                | Recipe name.                   |
| `cuisine`      | string                                | e.g. `Italian`.                |
| `description`  | string                                | Short blurb.                   |
| `prepTime`     | int                                   | Minutes.                       |
| `cookTime`     | int                                   | Minutes.                       |
| `servings`     | int                                   | Number of servings.            |
| `tags`         | string[]                              | Free-form tags.                |
| `dietary`      | string[]                              | e.g. `vegetarian`, `gluten-free`. |
| `author`       | string                                | Recipe author.                 |
| `ingredients`  | array of `{amount, unit, name}`       | Each entry is an object.       |
| `instructions` | string[]                              | One string per step.           |

## Example

```json
{
  "title": "Weeknight Tomato Pasta",
  "cuisine": "Italian",
  "description": "A fast pantry pasta.",
  "prepTime": 10,
  "cookTime": 20,
  "servings": 4,
  "tags": ["weeknight", "vegetarian"],
  "dietary": ["vegetarian"],
  "author": "Me",
  "ingredients": [
    {"amount": "400", "unit": "g", "name": "spaghetti"},
    {"amount": "1", "unit": "can", "name": "crushed tomatoes"}
  ],
  "instructions": ["Boil the pasta until al dente.", "Simmer the tomatoes, toss with the pasta, and serve."]
}
```
