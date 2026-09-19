"""Parser ICU toi thieu: tra ve danh sach TEN THAM SO thuc su (bo qua than cua cac nhanh)."""
import re

SUBMSG_TYPES = {'plural', 'select', 'selectordinal'}
NAME = re.compile(r'\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?=[,}])')


def _match(s, i):
    """i tro vao '{' -> tra ve index cua '}' tuong ung."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                return j
    raise ValueError(f'ngoac khong can bang: {s!r}')


def args(s):
    out = []

    def message(i, end):
        while i < end:
            if s[i] == '{':
                j = _match(s, i)
                argument(i + 1, j)
                i = j + 1
            else:
                i += 1

    def argument(i, end):
        body = s[i:end]
        m = NAME.match(body)
        if not m:
            return
        out.append(m.group(1))
        c1 = body.find(',')
        if c1 < 0:
            return
        rest = body[c1 + 1:]
        typ = rest.split(',')[0].strip()
        if typ not in SUBMSG_TYPES:
            return
        c2 = rest.find(',')
        if c2 < 0:
            return
        branches(i + c1 + 1 + c2 + 1, end)

    def branches(i, end):
        while i < end:
            if s[i] == '{':
                j = _match(s, i)
                message(i + 1, j)      # than nhanh la mot message long nhau
                i = j + 1
            else:
                i += 1

    message(0, len(s))
    return sorted(out)


def structure(s):
    """Bo xuong cu phap: ten tham so + type + cac selector, de so sanh en vs vi."""
    toks = []
    for m in re.finditer(r'\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([A-Za-z]+)', s):
        toks.append(f'{m.group(1)}:{m.group(2)}')
    for m in re.finditer(r'(?:^|[\s{])(=\d+|zero|one|two|few|many|other|true|false)\s*\{', s):
        toks.append(f'sel:{m.group(1)}')
    return sorted(toks)
