"""Chequeo de balance de parentesis/corchetes/llaves en GDScript,
ignorando comentarios y literales de string (el chequeo ingenuo daba
falsos positivos con comentarios tipo '# 1) hacer tal cosa')."""
import sys
from pathlib import Path

def strip(src):
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '#':
            while i < n and src[i] != '\n':
                i += 1
        elif c in '"\'':
            q = c; i += 1
            while i < n and src[i] != q:
                i += 2 if src[i] == '\\' else 1
            i += 1
        else:
            out.append(c); i += 1
    return ''.join(out)

bad = 0
for f in sorted(Path('scripts').glob('*.gd')):
    s = strip(f.read_text())
    for o, c in [('(', ')'), ('[', ']'), ('{', '}')]:
        if s.count(o) != s.count(c):
            print(f"DESBALANCE {f}: {o}{c} -> {s.count(o)} vs {s.count(c)}")
            bad += 1
    depth = 0
    for ch in s:
        if ch in '([{': depth += 1
        elif ch in ')]}':
            depth -= 1
            if depth < 0:
                print(f"DESBALANCE {f}: cierre de mas"); bad += 1; break
print("OK — todos balanceados" if not bad else f"{bad} problema(s)")
sys.exit(1 if bad else 0)
