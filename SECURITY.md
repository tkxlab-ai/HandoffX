# Security Policy

## Supported Versions

| Version | Status |
|---------|--------|
| 2.x     | ✅ Active — security fixes ship in the next patch release |
| 1.x     | ❌ End-of-life — please upgrade to 2.x |

## Reporting a Vulnerability

Please **do not** open a public GitHub Issue for security problems.

**Preferred channel** — private vulnerability report:
- Use GitHub's [private security advisory](https://github.com/tkxlab-ai/HandoffX/security/advisories/new) feature, **or**
- Email: `dev@tkxlab.ai`

**Response timeline**:

| Action | Within |
|--------|--------|
| Acknowledge receipt | 72 hours |
| Initial assessment | 7 days |
| Fix or mitigation in a release | 30 days (severity-dependent) |

**Please include**:
- Affected version(s) (e.g., `v2.1.5`)
- Reproduction steps or proof-of-concept
- Suggested fix (if you have one)
- Whether you'd like credit in the release notes

## Scope

This policy covers:
- `install.sh` and bundled scripts under `scripts/` and `skills/handoff/scripts/`
- The `/handoff*` slash commands' behavior contracts
- Release artifacts (`.skill`, source tarballs, SBOM)

Out of scope:
- Third-party CLIs that consume this plugin (Claude Code, OpenCode, Codex) — report to their respective maintainers
- User-authored `HANDOFF.md` content (a privacy concern, not a vulnerability)

## Coordinated Disclosure

We follow a **90-day disclosure window** by default. If a fix is not yet released after 90 days, the reporter is free to publish details. We may request an extension for complex issues; you are not obligated to grant it.

## Hall of Fame

Reporters who follow this policy and contribute to a fix will be credited in the relevant `Release Notes` and listed below (with their permission).

_No reports yet._
