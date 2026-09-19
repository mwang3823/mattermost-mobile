// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

import {Platform} from 'react-native';

export const DEV_TRACE_TAG = 'TDCDBG';

type DevTraceFlags = {
    nav: boolean;
    api: boolean;
    apiRequest: boolean;
    headers: boolean;
    body: boolean;
    bodyLimit: number;
    ws: boolean;
};

const flags: DevTraceFlags = {
    nav: true,
    api: true,
    apiRequest: false,
    headers: true,
    body: true,
    bodyLimit: 1200,
    ws: true,
};

export const devTraceEnabled: boolean = __DEV__ && !Platform.isTesting;

const SENSITIVE_PARAMS = new Set(['token', 'access_token', 'password', 'secret', 'code', 'key']);
const SENSITIVE_HEADERS = new Set(['authorization', 'cookie', 'set-cookie', 'token', 'x-csrf-token', 'x-mattermost-preauth-secret']);
const SENSITIVE_FIELDS = new Set(['password', 'current_password', 'new_password', 'token', 'access_token', 'refresh_token', 'secret', 'device_id', 'id_token']);

const write = (line: string) => {
    // eslint-disable-next-line no-console
    console.log(`${DEV_TRACE_TAG} ${line}`);
};

const pad = (value: string | number, width: number) => {
    const str = String(value);
    return str.length >= width ? str : str + ' '.repeat(width - str.length);
};

const padStart = (value: string | number, width: number) => {
    const str = String(value);
    return str.length >= width ? str : ' '.repeat(width - str.length) + str;
};

const formatSize = (bytes?: number) => {
    if (!bytes) {
        return '';
    }
    if (bytes < 1024) {
        return `${bytes}B`;
    }
    if (bytes < 1024 * 1024) {
        return `${(bytes / 1024).toFixed(1)}KB`;
    }
    return `${(bytes / (1024 * 1024)).toFixed(1)}MB`;
};

// Bỏ scheme + host và che giá trị của các tham số nhạy cảm (log có thể được người dùng xuất ra)
const cleanUrl = (url: string) => {
    const relative = url.replace(/^https?:\/\/[^/]+/, '');
    const [path, query] = relative.split('?');
    if (!query) {
        return path;
    }
    const safeQuery = query.split('&').map((param) => {
        const [name, value] = param.split('=');
        return value && SENSITIVE_PARAMS.has(name.toLowerCase()) ? `${name}=***` : param;
    }).join('&');
    return `${path}?${safeQuery}`;
};

const redactHeaders = (headers?: Record<string, string>) => {
    if (!headers) {
        return '-';
    }
    const safe = Object.entries(headers).map(([name, value]) => {
        return `${name}: ${SENSITIVE_HEADERS.has(name.toLowerCase()) ? '***' : value}`;
    });
    return safe.length ? safe.join(', ') : '-';
};

const redactValues = (value: unknown): unknown => {
    if (Array.isArray(value)) {
        return value.map(redactValues);
    }
    if (value && typeof value === 'object') {
        const out: Record<string, unknown> = {};
        for (const [name, nested] of Object.entries(value as Record<string, unknown>)) {
            out[name] = SENSITIVE_FIELDS.has(name.toLowerCase()) ? '***' : redactValues(nested);
        }
        return out;
    }
    return value;
};

const formatBody = (body: unknown) => {
    if (body === undefined || body === null || body === '') {
        return '-';
    }
    let text: string;
    try {
        text = typeof body === 'string' ? body : JSON.stringify(redactValues(body));
    } catch (error) {
        return '<không stringify được>';
    }
    if (text.length <= flags.bodyLimit) {
        return text;
    }
    return `${text.slice(0, flags.bodyLimit)}… (+${text.length - flags.bodyLimit} ký tự)`;
};

type ApiPayload = {
    requestHeaders?: Record<string, string>;
    requestBody?: unknown;
    responseHeaders?: Record<string, string>;
    responseBody?: unknown;
};

export function traceApiPayload({requestHeaders, requestBody, responseHeaders, responseBody}: ApiPayload) {
    if (!devTraceEnabled || !flags.api) {
        return;
    }
    if (flags.headers) {
        write(`     req.headers ${redactHeaders(requestHeaders)}`);
    }
    if (flags.body) {
        write(`     req.body    ${formatBody(requestBody)}`);
    }
    if (flags.headers && responseHeaders) {
        write(`     res.headers ${redactHeaders(responseHeaders)}`);
    }
    if (flags.body && responseBody !== undefined) {
        write(`     res.body    ${formatBody(responseBody)}`);
    }
}

export function setDevTrace(next: Partial<DevTraceFlags>) {
    Object.assign(flags, next);
    write(`TRACE flags ${JSON.stringify(flags)}`);
}

export function traceNavigation(to?: string, from?: string, stack?: string[]) {
    if (!devTraceEnabled || !flags.nav) {
        return;
    }
    const trail = stack?.length ? `  | ${stack.join(' > ')}` : '';
    write(`NAV  ${pad(to ?? '-', 28)} <- ${pad(from ?? '-', 24)}${trail}`);
}

export function traceApiRequest(method = 'get', url: string) {
    if (devTraceEnabled && flags.apiRequest) {
        write(`API  ${pad(method.toUpperCase(), 6)} ...       ${cleanUrl(url)}`);
    }
    return Date.now();
}

export function traceApiResponse(method = 'get', url: string, status: number, startedAt: number, bytes?: number, groupLabel?: string) {
    if (!devTraceEnabled || !flags.api) {
        return;
    }
    const size = formatSize(bytes);
    const label = groupLabel ? `  [${groupLabel}]` : '';
    write(`API  ${pad(method.toUpperCase(), 6)} ${status} ${padStart(`${Date.now() - startedAt}ms`, 7)} ${pad(size, 8)} ${cleanUrl(url)}${label}`);
}

export function traceApiError(method = 'get', url: string, startedAt: number, status?: number) {
    if (!devTraceEnabled || !flags.api) {
        return;
    }
    write(`API  ${pad(method.toUpperCase(), 6)} ${status ?? 'ERR'} ${padStart(`${Date.now() - startedAt}ms`, 7)} ${pad('', 8)} ${cleanUrl(url)}  <- request failed`);
}

export function traceWebSocket(event: string, detail?: string) {
    if (!devTraceEnabled || !flags.ws) {
        return;
    }
    write(`WS   ${pad(event, 32)}${detail ?? ''}`);
}

if (devTraceEnabled) {
    // Bật/tắt ngay trong console của React Native DevTools: tdcTrace({api: false, apiRequest: true})
    (global as any).tdcTrace = setDevTrace; // eslint-disable-line @typescript-eslint/no-explicit-any
}
