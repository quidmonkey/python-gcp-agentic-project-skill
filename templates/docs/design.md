# {{project-name}} Design

> **RFC — Request for Comments.** This document defines the project architecture and design. Update it as the design evolves; when you do, also update `design.mmd` and any other doc in this directory the change affects. The `scripts/docs-sync-check.sh` Stop hook enforces this.

## Overview

_What does this project do? What problem does it solve?_

## Architecture

_High-level architecture. Reference the Mermaid diagram in `design.mmd`._

## Components

_List and describe each major component._

## Data Flow

_How data moves through the system._

## Flows

_One numbered entry per end-to-end flow: a one-line summary, then a link to its spec under `specs/`. While the project is small, describe the flows inline here and leave this section empty — `specs/` doesn't exist yet._

_Once this document passes ~400 lines or covers three or more flows, create `specs/` and split each flow into `specs/<flow>.md` (copied from `templates/spec.md`) with a `specs/<flow>-diagram.mmd` (copied from `templates/diagram.mmd`) beside it. What stays here: the overview, this index, the architecture, the data flow between components, deployment, and anything cross-cutting. What moves out: per-flow step-by-step behavior, the tools and endpoints a single flow calls, its configuration, and its edge cases._

## Trade-offs and Alternatives

_Project-wide decisions only: the few that shape the whole system and must not be lost, each with the alternatives rejected and why. Decisions scoped to particular code are recorded as commit trailers instead (see "Decision history" in `README.md`) and found by path with `scripts/decisions.sh`._
