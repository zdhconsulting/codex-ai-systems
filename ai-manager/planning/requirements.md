# Requirements

## Draft

AI Manager is a conductor worker for Zev's projects. It makes sure important projects are running, explains why they are not running, reports that back clearly, and makes bounded changes when the fix is safe and explicitly configured.

## Core Requirements

- Track configured projects and their expected running state.
- Check whether each project path exists and whether its git repo is healthy enough to work from.
- Check project-specific signals such as required files, expected branch, expected remote, local process names, health URLs, and optional check commands.
- Map owner-button aliases to the correct project so blockers are reported next to the affected project.
- Maintain a durable live project registry and interaction map.
- Explain failures in plain language: missing path, missing repo, branch mismatch, remote mismatch, dirty worktree, missing required file, stopped process, failing URL, failing command, or owner-only blocker.
- Report a compact status across all projects: running, needs attention, or not running.
- Support explicit fix commands, but only run them when the operator passes a fix flag.
- Preserve Zev's approval gates for production, repo history, permissions, secrets, billing, auth, and destructive actions.

## First Slice

Build a local CLI report that reads a project inventory and prints:

- Summary counts.
- One section per project.
- What is running.
- What is not running.
- Why it is not running.
- Suggested or configured next actions.

## Not Yet

- Autonomous production deploys.
- Secret management.
- Billing/auth/security changes.
- Destructive git operations.
- Unconfigured repair commands.
