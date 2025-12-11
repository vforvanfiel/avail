# Avail agent guidelines

These instructions apply to the entire repository unless overridden by a nested `AGENTS.md`.

## Code style
- Use idiomatic Swift naming (camelCase for variables/functions, PascalCase for types) and prefer SwiftUI patterns already present in the codebase.
- Avoid force-unwrapping (`!`) and favor optional binding or guard clauses for safety.
- Keep implementations small and composable; extract helper views or functions when a view grows complex.
- Add brief inline comments when behavior is non-obvious, but avoid redundant commentary.

## Testing and validation
- Run available automated tests when feasible. If platform limitations prevent running iOS builds or tests, note this explicitly in the testing section.
- For logic-only changes that can be validated without Xcode, prefer lightweight checks (e.g., linting or format validation) when available.

## Documentation and messaging
- Update relevant documentation or in-code doc comments when introducing new behaviors or parameters.
- Pull request messages should include a short summary of changes and a clear list of tests/checks performed (or explicitly state when none were run).
