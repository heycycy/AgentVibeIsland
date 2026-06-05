import * as net from 'net';
import * as path from 'path';
import * as os from 'os';
import * as vscode from 'vscode';
import { log } from './logger';

export interface PermissionRequest {
    requestId: string;
    agent: string;
    agentLabel: string;
    action: string;
    actionLabel: string;
    scope: string;
    taskDescription: string;
    taskProgress: number;
    workspacePath: string;
}

export interface PermissionDecision {
    requestId: string;
    decision: string;
}

/**
 * IPC client that communicates with the Agent Vibe Island macOS app
 * over a Unix domain socket using HTTP/1.1.
 */
export class IpcClient {
    private socketPath: string;
    private agentName = 'claude';
    private _connected = false;
    private reconnectTimer: NodeJS.Timeout | undefined;

    get connected(): boolean {
        return this._connected;
    }

    constructor() {
        this.socketPath = this.resolveSocketPath();
    }

    private resolveSocketPath(): string {
        const config = vscode.workspace.getConfiguration('agentVibeIsland');
        const raw = config.get<string>('socketPath', '~/.agentvibeisland/ipc.sock');
        if (raw.startsWith('~')) {
            return path.join(os.homedir(), raw.slice(1));
        }
        return raw;
    }

    /**
     * Check if the socket file exists (Agent Vibe Island is running).
     */
    private async socketExists(): Promise<boolean> {
        const fs = await import('fs');
        return new Promise(resolve => {
            fs.access(this.socketPath, fs.constants.F_OK, err => resolve(!err));
        });
    }

    /**
     * Send an HTTP request over the Unix socket and return the response body.
     */
    private sendHttp(method: string, urlPath: string, body: object): Promise<string> {
        return new Promise((resolve, reject) => {
            const json = JSON.stringify(body);
            const request = [
                `${method} ${urlPath} HTTP/1.1`,
                'Host: localhost',
                'Content-Type: application/json',
                `Content-Length: ${Buffer.byteLength(json)}`,
                'Connection: close',
                '',
                json,
            ].join('\r\n');

            const socket = net.createConnection({ path: this.socketPath }, () => {
                socket.write(request);
            });

            let data = '';
            socket.on('data', chunk => {
                data += chunk.toString();
            });

            socket.on('end', () => {
                // Parse HTTP response — extract body after \r\n\r\n
                const sepIndex = data.indexOf('\r\n\r\n');
                if (sepIndex >= 0) {
                    resolve(data.slice(sepIndex + 4));
                } else {
                    resolve(data);
                }
            });

            socket.on('error', err => {
                reject(err);
            });

            // No timeout for /request — it blocks until user acts
            if (!urlPath.includes('/request')) {
                socket.setTimeout(10000, () => {
                    socket.destroy(new Error('Socket timeout'));
                });
            }
        });
    }

    /**
     * Register this extension as an agent with the hub.
     */
    async register(agentLabel: string, pid: number): Promise<void> {
        if (!(await this.socketExists())) {
            log('Socket not found — Agent Vibe Island not running');
            this._connected = false;
            this.scheduleReconnect();
            return;
        }

        try {
            const resp = await this.sendHttp('POST', '/register', {
                agent: this.agentName,
                agentLabel,
                pid,
            });
            log(`Registered: ${resp}`);
            this._connected = true;
            this.stopReconnect();
        } catch (err) {
            log(`Registration failed: ${err}`);
            this._connected = false;
            this.scheduleReconnect();
        }
    }

    /**
     * Send a status update (task description + progress).
     */
    async sendStatus(taskDescription: string, taskProgress: number): Promise<void> {
        if (!this._connected) { return; }
        try {
            await this.sendHttp('POST', '/status', {
                agent: this.agentName,
                taskDescription,
                taskProgress,
            });
        } catch (err) {
            log(`Status update failed: ${err}`);
        }
    }

    /**
     * Send a permission request and block until the user decides.
     * Returns the decision string ('allow' or 'deny').
     */
    async sendRequest(request: PermissionRequest): Promise<PermissionDecision | null> {
        if (!(await this.socketExists())) {
            return null;
        }

        try {
            const resp = await this.sendHttp('POST', '/request', {
                event: 'permission_request',
                agent: request.agent,
                requestId: request.requestId,
                action: request.action,
                actionLabel: request.actionLabel,
                scope: request.scope,
                taskDescription: request.taskDescription,
                taskProgress: request.taskProgress,
                workspacePath: request.workspacePath,
            });
            const decision = JSON.parse(resp) as PermissionDecision;
            log(`Decision for ${request.requestId}: ${decision.decision}`);
            return decision;
        } catch (err) {
            log(`Request failed: ${err}`);
            return null;
        }
    }

    /**
     * Unregister this agent from the hub.
     */
    async unregister(): Promise<void> {
        if (!this._connected) { return; }
        try {
            await this.sendHttp('POST', '/unregister', {
                agent: this.agentName,
                pid: process.pid,
            });
            log('Unregistered');
        } catch (err) {
            log(`Unregister failed: ${err}`);
        }
        this._connected = false;
        this.stopReconnect();
    }

    private scheduleReconnect(): void {
        if (this.reconnectTimer) { return; }
        this.reconnectTimer = setInterval(async () => {
            if (await this.socketExists()) {
                log('Socket found — attempting reconnect');
                await this.register('Claude (VS Code)', process.pid);
            }
        }, 5000);
    }

    private stopReconnect(): void {
        if (this.reconnectTimer) {
            clearInterval(this.reconnectTimer);
            this.reconnectTimer = undefined;
        }
    }

    dispose(): void {
        this.stopReconnect();
    }
}
