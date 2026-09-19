#!/usr/bin/env node
// Copyright (c) 2015-present Mattermost, Inc. All Rights Reserved.
// See LICENSE.txt for license information.

// Bộ xem log gỡ lỗi của TDC Chat: đọc logcat/log stream ở stdin, gom các dòng
// "TDCDBG ..." thành từng mục NAV / API / WS rồi cho gập-mở từng mục.
//
//   adb logcat -v brief '*:S' ReactNativeJS:V | node scripts/trace_viewer.mjs
//
// Phím: ↑/↓ chọn · Enter mở-gập · e mở tất cả · c gập tất cả · f lọc loại
//       / tìm · g/G đầu-cuối · p tạm dừng bám đuôi · x xoá · q thoát

import fs from 'node:fs';
import readline from 'node:readline';
import tty from 'node:tty';

const MAX_ENTRIES = 2000;
const FILTERS = ['tất cả', 'API', 'WS', 'NAV'];

const C = {
    reset: '[0m',
    dim: '[2m',
    bold: '[1m',
    inverse: '[7m',
    cyan: '[36m',
    green: '[32m',
    red: '[31m',
    yellow: '[33m',
    grey: '[90m',
};

const entries = [];
let selected = 0;
let follow = true;
let filterIndex = 0;
let search = '';
let searchMode = false;
let scrollTop = 0;
let renderTimer = null;

const out = process.stdout;

const kindOf = (line) => {
    if (line.startsWith('NAV')) {
        return 'NAV';
    }
    if (line.startsWith('API')) {
        return 'API';
    }
    if (line.startsWith('WS')) {
        return 'WS';
    }
    return 'LOG';
};

const addEntry = (line) => {
    entries.push({kind: kindOf(line), summary: line, details: [], expanded: false});
    if (entries.length > MAX_ENTRIES) {
        entries.splice(0, entries.length - MAX_ENTRIES);
        selected = Math.max(0, selected - 1);
    }
};

const ingest = (raw) => {
    const at = raw.indexOf('TDCDBG ');
    if (at === -1) {
        return;
    }
    const line = raw.slice(at + 'TDCDBG '.length).replace(/\s+$/, '');
    if (!line) {
        return;
    }
    if (line.startsWith(' ')) {
        entries[entries.length - 1]?.details.push(line.trim());
        return;
    }
    addEntry(line);
};

const visible = () => {
    const kind = FILTERS[filterIndex];
    const needle = search.toLowerCase();
    return entries.filter((entry) => {
        if (kind !== 'tất cả' && entry.kind !== kind) {
            return false;
        }
        if (!needle) {
            return true;
        }
        return entry.summary.toLowerCase().includes(needle) ||
            entry.details.some((detail) => detail.toLowerCase().includes(needle));
    });
};

const colorFor = (entry) => {
    switch (entry.kind) {
        case 'NAV': return C.cyan;
        case 'WS': return C.yellow;
        case 'API': return (/ (?:ERR|[45]\d\d) /).test(entry.summary) ? C.red : C.green;
        default: return C.grey;
    }
};

// "res.body    {...}" -> nhãn + JSON xuống dòng cho dễ đọc
const MAX_DETAIL_ROWS = 200;

const detailRows = (detail, width) => {
    const match = (/^(\S+)\s+([\s\S]*)$/).exec(detail);
    const label = match ? match[1] : '';
    const value = match ? match[2] : detail;
    let text = value;
    try {
        text = JSON.stringify(JSON.parse(value), null, 2);
    } catch {
        // không phải JSON (hoặc đã bị cắt bớt) thì in nguyên văn
    }

    const indent = '    ';
    const hanging = indent + ' '.repeat(label ? label.length + 1 : 0);
    const body = Math.max(20, width - hanging.length);
    const rows = [];
    for (const piece of text.split('\n')) {
        let line = `${label && rows.length === 0 ? `${indent}${label} ` : hanging}${piece}`;
        rows.push(line.slice(0, width));
        line = line.slice(width);
        while (line.length) {
            rows.push(hanging + line.slice(0, body));
            line = line.slice(body);
        }
        if (rows.length >= MAX_DETAIL_ROWS) {
            rows.push(`${hanging}… (còn nữa)`);
            break;
        }
    }
    return rows;
};

const render = () => {
    renderTimer = null;
    const width = out.columns || 100;
    const height = out.rows || 30;
    const listHeight = Math.max(3, height - 2);
    const list = visible();

    if (follow) {
        selected = Math.max(0, list.length - 1);
    }
    selected = Math.min(selected, Math.max(0, list.length - 1));

    // mỗi mục chiếm 1 dòng, cộng thêm phần chi tiết nếu đang mở
    const rows = [];
    let selectedRow = 0;
    list.forEach((entry, index) => {
        if (index === selected) {
            selectedRow = rows.length;
        }
        const marker = entry.details.length ? (entry.expanded ? '▾' : '▸') : ' ';
        const text = `${marker} ${entry.summary}`.slice(0, width);
        rows.push({text, color: colorFor(entry), selected: index === selected});
        if (entry.expanded) {
            for (const detail of entry.details) {
                for (const row of detailRows(detail, width - 2)) {
                    rows.push({text: row.slice(0, width), color: C.dim, selected: false});
                }
            }
        }
    });

    if (selectedRow < scrollTop) {
        scrollTop = selectedRow;
    }
    if (selectedRow >= scrollTop + listHeight) {
        scrollTop = selectedRow - listHeight + 1;
    }
    scrollTop = Math.max(0, Math.min(scrollTop, Math.max(0, rows.length - listHeight)));

    const frame = [];
    frame.push(`${C.bold}${C.cyan}  TDC trace${C.reset}  ${C.dim}${list.length}/${entries.length} mục` +
        `  ·  lọc: ${FILTERS[filterIndex]}${search ? `  ·  tìm: "${search}"` : ''}` +
        `  ·  ${follow ? 'bám đuôi' : 'đã dừng'}${C.reset}`);

    for (let i = 0; i < listHeight; i++) {
        const row = rows[scrollTop + i];
        if (!row) {
            frame.push('');
            continue;
        }
        frame.push(row.selected ? `${C.inverse}${row.text}${C.reset}` : `${row.color}${row.text}${C.reset}`);
    }

    frame.push(searchMode ?
        `${C.yellow}  tìm: ${search}${C.reset}` :
        `${C.dim}  ↑↓ chọn · Enter mở/gập · e mở hết · c gập hết · f lọc · / tìm · g/G · p dừng · x xoá · q thoát${C.reset}`);

    out.write(`[H[2J${frame.join('\n')}`);
};

const schedule = () => {
    if (!renderTimer) {
        renderTimer = setTimeout(render, 40);
    }
};

const move = (delta) => {
    const list = visible();
    follow = false;
    selected = Math.max(0, Math.min(list.length - 1, selected + delta));
    if (selected === list.length - 1) {
        follow = true;
    }
    schedule();
};

const toggle = () => {
    const entry = visible()[selected];
    if (entry) {
        entry.expanded = !entry.expanded;
        follow = false;
    }
    schedule();
};

const quit = () => {
    out.write('[?1049l[?25h');
    process.exit(0);
};

// Bàn phím đọc từ /dev/tty vì stdin đang là ống dẫn log.
// Không có terminal (ví dụ khi ghi ra file) thì in thẳng từng dòng, không dựng giao diện.
let keyboard;
try {
    if (!out.isTTY) {
        throw new Error('stdout không phải terminal');
    }
    const ttyFd = fs.openSync('/dev/tty', 'r');
    keyboard = new tty.ReadStream(ttyFd);
    readline.emitKeypressEvents(keyboard);
    keyboard.setRawMode(true);
    keyboard.resume();
} catch {
    const input = readline.createInterface({input: process.stdin, terminal: false});
    input.on('line', (raw) => {
        const at = raw.indexOf('TDCDBG ');
        if (at === -1) {
            return;
        }
        const line = raw.slice(at + 'TDCDBG '.length).replace(/\s+$/, '');
        const color = line.startsWith(' ') ? C.dim : colorFor({kind: kindOf(line), summary: line});
        out.write(`${color}${line}${C.reset}\n`);
    });
    input.on('close', () => process.exit(0));
}

if (keyboard) {

keyboard.on('keypress', (str, key) => {
    if (searchMode) {
        if (key.name === 'return' || key.name === 'escape') {
            searchMode = false;
        } else if (key.name === 'backspace') {
            search = search.slice(0, -1);
        } else if (str && !key.ctrl) {
            search += str;
        }
        schedule();
        return;
    }

    switch (key.name) {
        case 'q': quit(); break;
        case 'c': if (key.ctrl) {
            quit();
        } else {
            entries.forEach((e) => {
                e.expanded = false;
            });
        } break;
        case 'up': case 'k': move(-1); break;
        case 'down': case 'j': move(1); break;
        case 'pageup': move(-10); break;
        case 'pagedown': move(10); break;
        case 'return': case 'space': toggle(); break;
        case 'e': entries.forEach((e) => {
            e.expanded = true;
        }); break;
        case 'f': filterIndex = (filterIndex + 1) % FILTERS.length; break;
        case 'g':
            if (key.shift) {
                selected = visible().length - 1;
                follow = true;
            } else {
                selected = 0;
                follow = false;
            }
            break;
        case 'p': follow = !follow; break;
        case 'x': entries.length = 0; selected = 0; follow = true; break;
        case 'slash': searchMode = true; search = ''; break;
        default:
            if (str === '/') {
                searchMode = true;
                search = '';
            }
    }
    schedule();
});

out.write('[?1049h[?25l');
out.on('resize', schedule);
process.on('SIGINT', quit);
process.on('SIGTERM', quit);

const input = readline.createInterface({input: process.stdin, terminal: false});
input.on('line', (line) => {
    ingest(line);
    schedule();
});
input.on('close', schedule);

render();
}
