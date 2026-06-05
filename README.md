# Agent Vibe Island

A macOS notch-anchored permission hub for coding agents. Consolidates permission
requests from Claude, Cursor, and OpenAI Codex so you never have to switch windows
to approve an agent action.

## Requirements

- MacBook with notch (MacBook Pro 2021+, MacBook Air 2022+)
- macOS 13 Ventura or later
- VS Code or Cursor

## Installation

### 1. Install the macOS app

**Option A — Direct download**

Download the latest `.dmg` from [Releases](https://github.com/clarkyao_microsoft/AgentVibeIsland/releases),
open it, and drag AgentVibeIsland.app to /Applications.

On first launch, right-click → Open to bypass Gatekeeper (unsigned build).

**Option B — Homebrew** *(coming soon)*

```
brew install --cask agentvibe-island
```

### 2. Install the VS Code extension

In VS Code, open the Extensions panel and install from VSIX:

1. Download `agentvibe-island-vscode-0.1.0.vsix` from Releases
2. Extensions panel → `...` → Install from VSIX

Or from the command line:

```
code --install-extension agentvibe-island-vscode-0.1.0.vsix
```

### 3. That's it

Agent Vibe Island launches at login automatically. The next time Claude or Cursor
asks for permission, it'll appear in the notch instead of a modal.

## Development

```bash
git clone https://github.com/clarkyao_microsoft/AgentVibeIsland.git
cd AgentVibeIsland
open AgentVibeIsland.xcodeproj
```

To test the IPC connection:

```bash
./scripts/test_ipc.sh
```
