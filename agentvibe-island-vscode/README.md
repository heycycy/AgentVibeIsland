# Agent Vibe Island — VS Code Extension

Routes coding agent permission requests (from Claude, Cursor, etc.) to the
[Agent Vibe Island](https://github.com/clarkyao_microsoft/AgentVibeIsland)
notch hub instead of showing native permission modals.

## Requirements

- macOS with the Agent Vibe Island app running
- VS Code 1.85+

## Settings

| Setting | Default | Description |
|---|---|---|
| `agentVibeIsland.socketPath` | `~/.agentvibeisland/ipc.sock` | Path to the IPC socket |
| `agentVibeIsland.enabled` | `true` | Enable/disable the extension |
| `agentVibeIsland.fallbackToNative` | `true` | Fall back to native modals if the app isn't running |

## Commands

- **Agent Vibe Island: Open Preferences Folder** — opens `~/.agentvibeisland/` in Finder
