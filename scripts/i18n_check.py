#!/usr/bin/env python3
"""Kiem tra tinh toan ven cua vi.json so voi en.json.

Chay:  python3 scripts/i18n_check.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import i18n_icu as icu  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
en = json.load(open(f'{ROOT}/assets/base/i18n/en.json'))
vi = json.load(open(f'{ROOT}/assets/base/i18n/vi.json'))

problems = []

for k in sorted(set(vi) - set(en)):
    problems.append(f'{k}: co trong vi.json nhung khong co trong en.json')
for k in sorted(set(en) - set(vi)):
    problems.append(f'{k}: thieu trong vi.json (se fallback sang tieng Anh)')
if list(vi) != sorted(vi):
    problems.append('vi.json chua duoc sort theo key')

for k, v in vi.items():
    if k not in en:
        continue
    e = en[k]
    if not isinstance(v, str) or not v.strip():
        problems.append(f'{k}: ban dich rong')
        continue
    try:
        if icu.args(e) != icu.args(v):
            problems.append(f'{k}: lech ten tham so ICU\n    en={e!r}\n    vi={v!r}')
        if icu.structure(e) != icu.structure(v):
            problems.append(f'{k}: lech cau truc plural/select\n    en={e!r}\n    vi={v!r}')
    except ValueError as err:
        problems.append(f'{k}: {err}')
    if e.count('{') != v.count('{') or e.count('}') != v.count('}'):
        problems.append(f'{k}: lech so ngoac\n    en={e!r}\n    vi={v!r}')
    if e.count('#') != v.count('#'):
        problems.append(f'{k}: lech ky tu # trong plural\n    en={e!r}\n    vi={v!r}')
    if e.count('\n') != v.count('\n'):
        problems.append(f'{k}: lech so dong\n    en={e!r}\n    vi={v!r}')
    if e.startswith(' ') != v.startswith(' ') or e.endswith(' ') != v.endswith(' '):
        problems.append(f'{k}: lech khoang trang dau/cuoi\n    en={e!r}\n    vi={v!r}')

print(f'en.json: {len(en)} key | vi.json: {len(vi)} key')
if problems:
    print(f'\n{len(problems)} VAN DE:')
    for p in problems:
        print('  -', p)
    sys.exit(1)
print('OK — vi.json day du va khop placeholder voi en.json')
