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
    bodyLimit: 4000,
    ws: true,
};

export const devTraceEnabled: boolean = __DEV__ && !Platform.isTesting;

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

// Bỏ scheme + host cho gọn dòng log
const cleanUrl = (url: string) => url.replace(/^https?:\/\/[^/]+/, '');

const formatHeaders = (headers?: Record<string, string>) => {
    if (!headers) {
        return '-';
    }
    const entries = Object.entries(headers).map(([name, value]) => `${name}: ${value}`);
    return entries.length ? entries.join(', ') : '-';
};

const formatBody = (body: unknown) => {
    if (body === undefined || body === null || body === '') {
        return '-';
    }
    let text: string;
    try {
        text = typeof body === 'string' ? body : JSON.stringify(body);
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
        write(`     req.headers ${formatHeaders(requestHeaders)}`);
    }
    if (flags.body) {
        write(`     req.body    ${formatBody(requestBody)}`);
    }
    if (flags.headers && responseHeaders) {
        write(`     res.headers ${formatHeaders(responseHeaders)}`);
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

export function traceWebSocket(event: string, detail?: string, payload?: unknown) {
    if (!devTraceEnabled || !flags.ws) {
        return;
    }
    write(`WS   ${pad(event, 32)}${detail ?? ''}`);
    if (flags.body && payload !== undefined) {
        write(`     ws.data     ${formatBody(payload)}`);
    }
}

if (devTraceEnabled) {
    // Bật/tắt ngay trong console của React Native DevTools: tdcTrace({api: false, apiRequest: true})
    (global as any).tdcTrace = setDevTrace; // eslint-disable-line @typescript-eslint/no-explicit-any
}
