# Ingest formats

## DOCX / PDF

- Prefer tables: fields, reason codes, state machines.
- Capture heading path for citations (`§3.2 Reason codes`).
- Scratch extract under `/tmp/<task>/spec-extract.md`.
- For layout-critical DOCX, use `docs-docx-document-edit` tooling; for requirements-only, text extract may suffice.

## OpenAPI 3.x

Focus:

- `paths.*.*.parameters` and `requestBody` required fields
- `responses` codes and schema refs
- `components.schemas` enums and `additionalProperties`

Implementation order: shared schemas → handlers → tests → mock clients.

## Proto / gRPC

- Package names and field numbers are normative.
- Do not renumber fields; additive optional fields only when spec allows.

## JSON Schema

- `required`, `enum`, `format`, `oneOf/anyOf` drive validators.
- Generate or hand-write validators consistent with existing project patterns.

## Spreadsheet matrices

- One row = one requirement id.
- Columns often: id, priority, area, statement, status.
- Leave status column updates for the end of the task.

## Sibling platform port

```text
1. Diff reference tree paths for the feature
2. List file-level mapping (old path → new path)
3. Port tests first when they encode the contract
4. Adjust names, ports, config keys for target platform
5. Doc parity check
```
