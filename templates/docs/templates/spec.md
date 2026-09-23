<!--
Copy to docs/specs/<flow>.md (kebab-case) when design.md splits into per-flow
specs. Fill it in, drop the sections that don't apply, and delete this comment.
Keep both links: the up-link to design.md and the down-link to the diagram are
how the set stays navigable. Draw the diagram from docs/templates/diagram.mmd.
-->

# Spec — <Flow Name>

Flow covered: **<Flow Name>** — one sentence on what the user asks for and what they get back.

Diagram: [<flow>-diagram.mmd](<flow>-diagram.mmd). High-level architecture: [design.md](../design.md).

## How it works

Numbered steps through the flow. Name the actual functions, endpoints, and tools, and link to the source files. State what happens on the unhappy paths — no match, ambiguous match, upstream error, missing permission.

## Components and integrations

What this flow touches. A table works well past two or three.

## Configuration

Settings this flow reads, where they come from, and what happens when one is unset.

## Auth and access

Whose identity each call runs as, and what that means for what the user can see.

## Limits and out of scope

What this flow deliberately does not do, and the data it does not have. Record the shortcuts here rather than leaving them implicit.

## Open questions

Decisions still outstanding, each with who owns it. Delete the section when it empties.
