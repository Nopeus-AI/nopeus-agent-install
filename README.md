# Install Nopeus Agent

Standalone agent service, independent of Nopeus Business.

On an existing Linux x86-64 Docker server (including a Coolify host):

```sh
curl -fsSL https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh | bash
```

The installer discovers the newest published Nopeus Agent release, verifies its
checksummed runtime and image identities, installs a background service and the `nopeus-agent`
command, and opens the terminal setup wizard. No
GitHub login, source checkout, host Node.js, or build is needed. Enter model keys
and channel settings in the wizard; settings and conversations persist in a Docker
volume. No public ports or domains are required. Docker Compose v2 is a prerequisite;
the installer does not install or reconfigure Docker or other Coolify applications.

Later: `nopeus-agent setup`, `nopeus-agent status`, `nopeus-agent logs`.
Install unattended: `curl -fsSL https://raw.githubusercontent.com/Nopeus-AI/nopeus-agent-install/main/install.sh | bash -s -- --no-setup`.
Run setup later from an interactive terminal.

The current standalone alpha includes approval-gated workspace and terminal tools,
public web research, schedules, memory, versioned skills, browser demonstrations
and replay, presentations, image/PDF understanding, audio transcription, and
researcher/planner/reviewer specialists. Each specialist has a separate persistent
workspace and Debian VM. Cross-workspace artifact imports require approval of the
exact source, destination, and file contents. Automated skill promotion, coordinated
team channels, spend limits, personal-device companions, and native mobile clients
remain planned. AI usage and server costs are separate.

## Releases

Versioned runtime assets are published with the standalone installer repository. This
installer discovers the newest published version from this repository's public releases API and
verifies the archive hashes and all six Docker image identities before starting it. This distribution repository does not contain development credentials,
customer data, or the private development history. Runtime code and dependencies
are included in the executable image; their notices remain in that image.

Inspect the installer before running if desired. The version changes automatically
when a newer runtime release is published; the selected release metadata pins both
archive SHA256 values and every Docker image identity. Installation requires permission to use
Docker and an interactive controlling terminal unless `--no-setup` is passed.

Persistent volumes include `agent-data`, `agent-workspace`, `agent-control`,
`agent-browser-profile`, and `audio-control`. Back them up with the service stopped.
Re-running the installer preserves them. Deleting them deletes credentials, pairing,
conversation history, files, and browser state. No Business migration is performed.

The shorter `https://nopeus.xyz/agent/install` alias redirects to the current
installer on this repository's main branch. The public GitHub URL above also
works directly and needs no GitHub login.

## Owner-triggered self-update (v0.1.7)

On hosts with an active systemd service, the installer enables a small host-side
watcher. An authorized private Telegram or WhatsApp sender can ask for an update
or send `/upgrade`. The watcher runs the installer, which selects the highest published semantic version (including prereleases),
verifies its checksum-pinned images, and restarts the stack while preserving data. The model receives no shell or Docker
access. Without systemd, update from the server terminal with `nopeus-agent update`.
This update action does not let the model change its own source code.

## Telegram command menu (v0.1.8)

The runtime registers `/start`, `/new`, `/status`, `/handoff`, `/link`, `/cancel`,
`/upgrade`, and `/version` with Telegram on startup. They appear in the chat's slash
command menu. The installer checks the newest published version on each upgrade and preserves
existing conversation and workspace volumes.

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

## Telegram pairing (v0.1.2)

No numeric Telegram user-ID lookup is needed. Choose Pair my account in setup,
open the private link in Telegram, tap Start, and confirm your account in the
terminal. Save to grant access. Expired links, groups and bot accounts cannot enroll.
Manual numeric IDs remain an advanced option. Rerun the installer to upgrade;
your stored data and ChatGPT sign-in are preserved.

## Pairing link fallback (v0.1.3)

Setup now preserves the full Telegram link behind a short clickable label. If the
link only opens the bot chat, paste the exact /start command displayed in setup
into that chat. A plain /start without its pairing argument does not enroll an
account. Keep the setup terminal open and return there to confirm/save. Pairing
expires after five minutes; retry with a fresh link after timeout. The bot sends
an acknowledgement when an account is detected. Access still requires terminal
confirmation. The update preserves existing settings and account credentials.

## Create a bot for me (v0.1.4)

Telegram setup now defaults to Create a bot for me. Enter a name, follow the private
link to @NopeusSetupBot, approve Telegram's bot-creation prompt and Confirm this bot,
then return to setup to connect/save. Token and owner ID transfer automatically.
After saving, open the new bot and tap Start. BotFather/token copying is only needed
for the advanced existing-bot path. The standalone agent uses the existing setup
API and does not require the Business suite. The user owns the child bot;
@NopeusSetupBot remains its manager. Ordinary agent messages go directly between
the user's server and Telegram. No model keys, conversations or files are sent to
the setup service. Real creation requires the user's Telegram approval.
