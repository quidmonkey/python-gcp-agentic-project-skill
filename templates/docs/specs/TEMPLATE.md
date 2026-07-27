# Spec — {{Flow Name}}

> Copy this file to `docs/specs/<flow>.md` (kebab-case, one file per flow), fill it in, delete the sections that don't apply, and add a matching `docs/specs/<flow>-diagram.mmd`. Leave this template in place for the next flow. Keep the two links below — the up-link to `design.md` and the down-link to the diagram are how the set stays navigable.

Flow covered: **{{Flow Name}}** — one sentence on what the user asks for and what they get back.

Diagram: [{{flow}}-diagram.mmd]({{flow}}-diagram.mmd). High-level architecture: [design.md](../design.md).

## How it works

Numbered steps through the flow. Name the actual functions, endpoints, and tools, and link to the source files. State what happens on the unhappy paths — no match, ambiguous match, upstream error, missing permission.

## Components and integrations

What this flow touches. A table works well when there are more than two or three:

| Component | Role in this flow |
|---|---|
| | |

## Configuration

Settings this flow reads, where they come from, and what happens when one is unset.

| Setting | Where | Value |
|---|---|---|
| | | |

## Auth and access

Whose identity each call runs as, and what that means for what the user can see.

## Limits and out of scope

What this flow deliberately does not do, and the data it does not have. Record the shortcuts here rather than leaving them implicit — this is the section that stops the same question being re-litigated.

## Open questions

Decisions still outstanding, each with who owns it. Delete the section when it empties.

<!-- Diagram skeleton for docs/specs/<flow>-diagram.mmd:

%%{init: {'theme':'forest'}}%%
graph TD
    U([User])
    A[Component]
    U <-->|request| A

-->
