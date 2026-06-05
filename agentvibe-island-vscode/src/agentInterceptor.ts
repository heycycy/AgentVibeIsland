import * as vscode from 'vscode';
import { IpcClient, PermissionRequest } from './ipcClient';
import { log } from './logger';

/**
 * Action mapping from agent event types to hub action strings.
 */
const ACTION_MAP: Record<string, { action: string; actionLabel: string }> = {
    'file_write':       { action: 'write_file',       actionLabel: 'Write to file' },
    'write_file':       { action: 'write_file',       actionLabel: 'Write to file' },
    'file_read':        { action: 'read_file',        actionLabel: 'Read file' },
    'read_file':        { action: 'read_file',        actionLabel: 'Read file' },
    'file_create':      { action: 'create_file',      actionLabel: 'Create file' },
    'create_file':      { action: 'create_file',      actionLabel: 'Create file' },
    'shell_command':    { action: 'run_shell',         actionLabel: 'Run shell command' },
    'run_shell':        { action: 'run_shell',         actionLabel: 'Run shell command' },
    'network_request':  { action: 'network_request',   actionLabel: 'Network request' },
};

let requestCounter = 0;

/**
 * Intercept a permission request from a coding agent.
 * If the IPC client is connected, routes through Agent Vibe Island.
 * Otherwise falls back to a native VS Code modal.
 */
export async function interceptPermission(
    ipcClient: IpcClient,
    eventType: string,
    scope: string,
    taskDescription: string,
    taskProgress: number,
): Promise<'allow' | 'deny'> {
    const config = vscode.workspace.getConfiguration('agentVibeIsland');
    const enabled = config.get<boolean>('enabled', true);
    const fallback = config.get<boolean>('fallbackToNative', true);

    const mapping = ACTION_MAP[eventType] ?? {
        action: eventType,
        actionLabel: eventType,
    };

    // If disabled or not connected, use fallback modal
    if (!enabled || !ipcClient.connected) {
        if (fallback) {
            return showNativeModal(mapping.actionLabel, scope);
        }
        return 'allow'; // auto-allow if no fallback
    }

    const workspacePath = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? '';
    const requestId = `req_${Date.now()}_${++requestCounter}`;

    const request: PermissionRequest = {
        requestId,
        agent: 'claude',
        agentLabel: 'Claude (VS Code)',
        action: mapping.action,
        actionLabel: mapping.actionLabel,
        scope,
        taskDescription,
        taskProgress,
        workspacePath,
    };

    log(`Sending permission request: ${mapping.actionLabel} — ${scope}`);

    const decision = await ipcClient.sendRequest(request);

    if (decision) {
        return decision.decision === 'allow' ? 'allow' : 'deny';
    }

    // IPC failed — fall back to native modal if configured
    if (fallback) {
        return showNativeModal(mapping.actionLabel, scope);
    }

    return 'deny';
}

/**
 * Show a native VS Code information message as fallback.
 */
async function showNativeModal(
    actionLabel: string,
    scope: string,
): Promise<'allow' | 'deny'> {
    const result = await vscode.window.showInformationMessage(
        `Agent wants to: ${actionLabel}\nScope: ${scope}`,
        { modal: true },
        'Allow',
        'Deny',
    );
    return result === 'Allow' ? 'allow' : 'deny';
}
