---
name: infra-terraform-policy-manage
description: "Write, test, or convert Terraform Policy files (.policy.hcl, .policytest.hcl, Sentinel to tfpolicy). Use when writing policy.hcl, policytest, converting Sentinel, or authoring tfpolicy."
license: MPL-2.0
---

# infra-terraform-policy-manage

**UTILITY SKILL** — INVOKES: [tfpolicy-author](references/tfpolicy-author.md) | [tfpolicy-test](references/tfpolicy-test.md)

## USE FOR:

- Writing a new `.policy.hcl` policy from a description or requirement
- Converting a `.sentinel` policy to Terraform Policy
- Writing or debugging a `.policytest.hcl` test file
- Migrating a Sentinel policy library to Terraform Policy

## DO NOT USE FOR:

- Writing `.tftest.hcl` files for Terraform modules — use `infra-terraform-test-manage`
- General Terraform HCL authoring — use `infra-terraform-style-review`

## Routing

| Task | Sub-skill |
|------|-----------|
| Write or convert a `.policy.hcl` policy | [tfpolicy-author](references/tfpolicy-author.md) |
| Write or debug a `.policytest.hcl` test | [tfpolicy-test](references/tfpolicy-test.md) |

## Examples

- "Block EC2 instances without encryption" → [tfpolicy-author](references/tfpolicy-author.md)
- "Convert this Sentinel policy to tfpolicy" → [tfpolicy-author](references/tfpolicy-author.md)
- "Write a policytest for my EBS policy" → [tfpolicy-test](references/tfpolicy-test.md)

## Side-by-side conversion examples

`examples/conversion/<policy-name>/` contains matching `.sentinel` and `.policy.hcl` files (plus a `README.md`) for real-world AWS policies — use `open` on a matching pair when converting a similar Sentinel rule.

## Troubleshooting

- **Wrong skill triggered?** Load the sub-skill directly from the routing table above.

Junie note: Use `open` to load `references/tfpolicy-author.md` or `references/tfpolicy-test.md` only when routed there — don't preload both. Use `grep_search` over `examples/conversion/` to find a similar existing Sentinel→policy conversion before writing one from scratch. Before running `terraform test -filter=*.policytest.hcl` or applying a policy in an enforced HCP Terraform workspace via `bash`, confirm with the user since policy enforcement can block real runs.
