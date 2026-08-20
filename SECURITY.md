# Security Policy

## Supported Versions

Only the latest release of Clipbara receives security updates.

| Version | Supported |
| ------- | --------- |
| Latest release | Yes |
| Older releases | No |

## Reporting a Vulnerability

Please do not report security vulnerabilities through public GitHub issues.

Instead, use one of the following private channels:

- **GitHub private vulnerability reporting (preferred):** [Report a vulnerability](https://github.com/mobrava/Clipbara/security/advisories/new)
- **Email:** minseusang@gmail.com

When reporting, please include:

- A description of the vulnerability and its impact
- Steps to reproduce or a proof of concept
- The Clipbara version and macOS version you tested

## What to Expect

- I will acknowledge your report within 7 days.
- I will investigate and keep you informed of progress.
- Once a fix is released, the vulnerability may be disclosed publicly with credit to the reporter (unless you prefer to remain anonymous).

## Scope

Clipbara is a local-only clipboard manager. Areas of particular interest:

- Clipboard data being written anywhere other than local SwiftData storage
- Excluded apps (e.g. password managers) being recorded despite exclusion settings
- Sparkle update channel integrity (appcast tampering, signature bypass)
- Privilege escalation through the app's helper processes
