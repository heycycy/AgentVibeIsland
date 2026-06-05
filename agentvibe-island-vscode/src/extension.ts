import * as vscode from 'vscode';
import { exec } from 'child_process';
import { IpcClient } from './ipcClient';
import { interceptPermission } from './agentInterceptor';
import { log, getLogger, disposeLogger } from './logger';

let ipcClient: IpcClient | undefined;

export async function activate(context: vscode.ExtensionContext): Promise<void> {
    const logger = getLogger();
    log('Agent Vibe Island extension activating');

    const config = vscode.workspace.getConfiguration('agentVibeIsland');
    if (!config.get<boolean>('enabled', true)) {
        log('Extension disabled via settings');
        return;
    }

    // Initialize IPC client
    ipcClient = new IpcClient();
    await ipcClient.register('Claude (VS Code)', process.pid);

    // Register the "Open Preferences Folder" command
    const openPrefsCmd = vscode.commands.registerCommand(
        'agentVibeIsland.openPreferences',
        () => {
            exec('open ~/.agentvibeisland', (err) => {
                if (err) {
                    log(`Failed to open preferences folder: ${err.message}`);
                }
            });
        },
    );
    context.subscriptions.push(openPrefsCmd);

    // Export the interceptPermission function for other extensions to use.
    // An agent extension can call:
    //   const vibeIsland = vscode.extensions.getExtension('clarkyao-microsoft.agentvibe-island-vscode');
    //   const api = await vibeIsland.activate();
    //   const decision = await api.interceptPermission('write_file', 'src/foo.ts', 'task', 0.5);
    const api = {
        interceptPermission: (
            eventType: string,
            scope: string,
            taskDescription: string,
            taskProgress: number,
        ) => interceptPermission(ipcClient!, eventType, scope, taskDescription, taskProgress),

        sendStatus: (taskDescription: string, taskProgress: number) =>
            ipcClient?.sendStatus(taskDescription, taskProgress),
    };

    // Dispose IPC client on deactivation
    context.subscriptions.push({
        dispose: () => {
            ipcClient?.dispose();
        },
    });

    log('Agent Vibe Island extension activated');
    return api as any;
}

export async function deactivate(): Promise<void> {
    log('Agent Vibe Island extension deactivating');
    if (ipcClient) {
        await ipcClient.unregister();
        ipcClient.dispose();
        ipcClient = undefined;
    }
    disposeLogger();
}
