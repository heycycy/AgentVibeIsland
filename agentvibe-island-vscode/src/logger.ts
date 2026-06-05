import * as vscode from 'vscode';

let channel: vscode.OutputChannel | undefined;

export function getLogger(): vscode.OutputChannel {
    if (!channel) {
        channel = vscode.window.createOutputChannel('Agent Vibe Island');
    }
    return channel;
}

export function log(message: string): void {
    getLogger().appendLine(`[${new Date().toISOString()}] ${message}`);
}

export function disposeLogger(): void {
    channel?.dispose();
    channel = undefined;
}
