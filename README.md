# Install Nopeus Agent

Standalone agent service, independent of Nopeus Business.

On an existing Linux x86-64 Docker server (including a Coolify host):

```sh
curl -fsSL https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh | bash
```

The installer downloads a checksum-pinned, prebuilt runtime, installs a background
service and the `nopeus-agent` command, and opens the terminal setup wizard. No
GitHub login, source checkout, host Node.js, or build is needed. Enter model keys
and channel settings in the wizard; settings and conversations persist in a Docker
volume. No public ports or domains are required. Docker Compose v2 is a prerequisite;
the installer does not install or reconfigure Docker or other Coolify applications.

Later: `nopeus-agent setup`, `nopeus-agent status`, `nopeus-agent logs`.
Install unattended: `curl -fsSL https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh | bash -s -- --no-setup`.
Run setup later from an interactive terminal.

This first pilot is text-and-messaging only. Computer tools, presentation artifacts,
learning and VM control are not yet implemented. AI usage and server costs are separate.
WhatsApp pairing uses the QR in service logs; protect those logs.

## Releases

Release assets contain the Linux amd64 Docker runtime archive, reviewed installer
and checksums. This distribution repository does not contain development credentials,
customer data, or the private development history. Runtime code and dependencies
are included in the executable image; their notices remain in that image.

Inspect the installer before running if desired. The script pins the runtime archive
SHA256 and reviewed Docker image identity. Installation requires permission to use
Docker and an interactive controlling terminal unless `--no-setup` is passed.

Persistent volume: `nopeus-agent_agent-data`. Back up the entire volume with the
service stopped. Re-running the installer preserves it. Deleting that volume deletes
credentials, pairing and conversation history. No Business migration is performed.

The shorter `https://nopeus.xyz/agent/install` alias is awaiting website deployment.
The public GitHub URL above is verified and needs no GitHub login.

## OpenAI subscription login (v0.1.1)

Exit the old setup wizard, rerun the public install command, then select OpenAI →
Sign in with ChatGPT subscription. Open the displayed device link on your phone
or computer and enter its one-time code. No API key is needed for that mode.
Account/workspace model availability and usage limits apply. Device-code access
may need to be enabled in ChatGPT security settings. API keys remain an explicit
alternative; other providers still use API keys in this release.

Existing installation data is preserved during the upgrade. The engine stores
and refreshes its ChatGPT session in the persistent agent home. Live sign-in is
completed by the account owner; automated validation uses synthetic credentials.
