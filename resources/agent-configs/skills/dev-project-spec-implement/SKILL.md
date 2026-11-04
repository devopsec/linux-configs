---
name: "dev-project-spec-implement"
description: "Implement features or logic from specifications and requirements of many kinds: DOCX/PDF ICDs, Markdown/Rst specs, OpenAPI/Swagger, AsyncAPI, proto/gRPC, JSON Schema, requirements tables, ADRs, ticket acceptance criteria, and spreadsheet matrices. Use when asked to implement from a spec, satisfy requirements, build to an ICD/API document, or close gaps against a written contract."
---

# Implement from specification

Turn external requirements into code + tests + doc updates, with an explicit gap analysis first.

## Spec source routing

| Format | How to ingest | Notes |
|--------|---------------|-------|
| **DOCX / PDF** | Extract tables & normative sections (use `docs-docx-document-edit` for DOCX fidelity) | ICDs, reason-code tables |
| **Markdown / AsciiDoc / RST** | Open sections by heading | ADRs, RFCs-in-repo |
| **OpenAPI / Swagger (YAML/JSON)** | Paths, schemas, status codes | Server + client stubs |
| **AsyncAPI / proto / gRPC** | Messages + RPCs | Keep codegen boundaries clean |
| **JSON Schema / Avro** | Validation rules | Shared validators |
| **CSV / XLSX matrices** | Requirement id × behavior | Use spreadsheet skill if heavy |
| **Ticket / tracker text** | Acceptance checkboxes | May chain `dev-project-todo-implement` |
| **Tests as spec** | Golden files, contract tests | Prefer extending those tests |
| **Sibling platform** | "as implemented in X" | Diff X, port to Y with renames |

Load [references/ingest-formats.md](references/ingest-formats.md) for extractor tips and [references/requirements-checklist.md](references/requirements-checklist.md) for the machine checklist template.

## Workflow

1. **Identify authoritative spec**
   - Path/URL/version the user named. If multiple, ask which wins on conflict.
   - Record version/date/filename in the working notes.

2. **Ingest → checklist**
   - Extract **normative** requirements (MUST/SHALL/required fields/error codes).
   - Ignore pure marketing prose unless it constrains behavior.
   - Build a checklist: `REQ-id | statement | touchpoint | status`.
   - Mark non-goals explicitly.

3. **Gap analysis**
   - Map each REQ to current code (exists / partial / missing / contradicts).
   - Prefer sibling-platform reference implementations when available.
   - Present a short plan (ordered REQ groups) before large multi-file work if scope is ambiguous.

4. **Implement**
   - One REQ group at a time when risky; keep changes minimal.
   - Encode error codes, enums, and field names **exactly** as specified (including case).
   - Validation: reject unknown / missing fields per spec level (strict vs open).

5. **Prove**
   - Tests per critical REQ (tables of inputs → expected codes).
   - Contract tests against OpenAPI when present.
   - Manual checks only when automation is absent — list them.

6. **Documentation**
   - Update API docs, reason-code tables, README snippets.
   - If a requirements matrix exists, mark implemented rows.
   - Tracker items: close or annotate via `dev-project-todo-implement` patterns.

7. **Handoff**
   - REQ coverage table (done / deferred / blocked).
   - Spec ambiguities encountered + assumption chosen.
   - Commit message draft only (no commit).

## Conflict rules

- Spec vs code comment → **spec** wins unless user says code is source of truth.
- Spec vs sibling platform → call out deltas; do not silently "improve" the contract.
- Spec vs security/safety → stop and ask (do not implement known-dangerous MUST without confirmation).

## Anti-patterns

- Coding from memory of a similar API without re-reading field lists
- Implementing only happy path when the spec defines error taxonomy
- Leaving checklist status untracked in the reply
- Editing the normative spec to match buggy code without user approval

## Related skills

- DOCX editing/extraction fidelity → `docs-docx-document-edit`
- Single tracker id execution → `dev-project-todo-implement`
- Kamailio/SIP platform constraints → `dev-kamailio-platform-manage`

## References

- [references/ingest-formats.md](references/ingest-formats.md)
- [references/requirements-checklist.md](references/requirements-checklist.md)
