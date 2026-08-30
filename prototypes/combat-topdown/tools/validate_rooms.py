#!/usr/bin/env python3
"""Valida la geometria de RoomData.gd sin necesidad de abrir Godot.

En este proyecto no hay editor de Godot disponible (todo se edita como
texto, ver STATUS.md), asi que un error de geometria en RoomData.gd —un
spawn dentro de un muro, dos rects que no se tocan, una puerta que no cae
sobre el borde— solo se descubriria jugando. Este script hace ese chequeo
por adelantado.

Uso:
    python3 tools/validate_rooms.py

Sale con codigo 1 y lista los problemas si encuentra alguno.

Que valida:
  1. Cada sala tiene una union CONECTADA (dos rects que solo se tocan en
     la arista no cuentan: el generador de muros de Main.gd trabaja sobre
     una grilla, y ahi queda pared entre medio).
  2. entry / spawns / props.pos caen dentro de la union, con margen para
     el radio de colision del jugador/enemigos (14px).
  3. Cada doors[side].pos cae SOBRE el borde de la union (no adentro ni
     flotando afuera).
  4. Cada doors[side].to apunta a una sala que existe.
  5. Todas las salas son alcanzables desde room_1 siguiendo las puertas.
"""

import re
import sys
from pathlib import Path

ROOM_DATA = Path(__file__).resolve().parent.parent / "scripts" / "RoomData.gd"

# Radio de colision de jugador/enemigos (CircleShape2D_player en
# Player.tscn y equivalentes) — un punto mas cerca que esto de un muro
# deja al cuerpo incrustado.
BODY_RADIUS = 14.0
# Mismo tamano de celda que usa Main._build_walls_for_room().
CELL = 20.0


def parse_rooms(text):
    """Extrae {room_id: {...}} de RoomData.gd con regex.

    No es un parser de GDScript de verdad: depende del formato consistente
    del archivo (un bloque `"room_x": { ... }` por sala). Alcanza porque
    RoomData.gd es tabla de datos plana y la escribimos nosotros.
    """
    rooms = {}
    # Cada sala arranca con `"room_id": {` a 2 tabs de indentacion.
    for m in re.finditer(r'^\t\t"(\w+)": \{$', text, re.M):
        rid = m.group(1)
        start = m.end()
        # El bloque termina en el primer `\t\t},` posterior.
        end_m = re.search(r"^\t\t\},$", text[start:], re.M)
        body = text[start : start + end_m.start()]
        rooms[rid] = parse_room_body(body)
    return rooms


def parse_room_body(body):
    room = {}
    rects_m = re.search(r'"rects": \[(.*?)\n\t\t\t\]', body, re.S)
    room["rects"] = _rects(rects_m.group(1)) if rects_m else []

    block_m = re.search(r'"blockers": \[(.*?)\n\t\t\t\]', body, re.S)
    room["blockers"] = _rects(block_m.group(1)) if block_m else []

    entry_m = re.search(r'"entry":\s*Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)', body)
    room["entry"] = (
        (float(entry_m.group(1)), float(entry_m.group(2))) if entry_m else None
    )

    spawns_m = re.search(r'"spawns": \[(.*?)\]', body, re.S)
    room["spawns"] = _vectors(spawns_m.group(1)) if spawns_m else []

    props_m = re.search(r'"props": \[(.*?)\n\t\t\t\]', body, re.S)
    room["props"] = []
    if props_m:
        for line in props_m.group(1).splitlines():
            vis = re.search(r'"visible":\s*(true|false)', line)
            pos = re.search(r'"pos":\s*Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)', line)
            if vis and pos:
                room["props"].append(
                    {
                        "visible": vis.group(1) == "true",
                        "pos": (float(pos.group(1)), float(pos.group(2))),
                    }
                )

    room["doors"] = {}
    for dm in re.finditer(
        r'"(east|west|north|south)":\s*\{"to":\s*"(\w+)",\s*"pos":\s*Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)\}',
        body,
    ):
        room["doors"][dm.group(1)] = {
            "to": dm.group(2),
            "pos": (float(dm.group(3)), float(dm.group(4))),
        }
    return room


def _rects(chunk):
    return [
        tuple(float(v) for v in r)
        for r in re.findall(
            r"Rect2\(\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)",
            chunk,
        )
    ]


def _vectors(chunk):
    return [
        (float(a), float(b))
        for a, b in re.findall(r"Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)", chunk)
    ]


def cells_of(rects):
    """Convierte la union de rects en un set de celdas de la grilla."""
    cells = set()
    for x, y, w, h in rects:
        cx0, cy0 = int(x // CELL), int(y // CELL)
        cx1, cy1 = int((x + w) // CELL), int((y + h) // CELL)
        for cy in range(cy0, cy1):
            for cx in range(cx0, cx1):
                cells.add((cx, cy))
    return cells


def connected(cells):
    """True si todas las celdas forman una sola region (4-conectada)."""
    if not cells:
        return False
    start = next(iter(cells))
    seen = {start}
    stack = [start]
    while stack:
        cx, cy = stack.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (cx + dx, cy + dy)
            if n in cells and n not in seen:
                seen.add(n)
                stack.append(n)
    return len(seen) == len(cells)


def inside(pt, rects, margin=0.0):
    x, y = pt
    for rx, ry, rw, rh in rects:
        if (
            rx + margin <= x <= rx + rw - margin
            and ry + margin <= y <= ry + rh - margin
        ):
            return True
    return False


def on_border(pt, cells):
    """True si el punto cae sobre el borde de la union (la celda de adentro
    mas cercana tiene un vecino fuera de la union)."""
    x, y = pt
    for dx in (-CELL, 0.0, CELL):
        for dy in (-CELL, 0.0, CELL):
            c = (int((x + dx) // CELL), int((y + dy) // CELL))
            if c not in cells:
                continue
            for ndx, ndy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if (c[0] + ndx, c[1] + ndy) not in cells:
                    return True
    return False


def in_blocker(pt, blockers, margin=0.0):
    """True si el punto cae dentro (o pegado) a un muro interior."""
    x, y = pt
    for bx, by, bw, bh in blockers:
        if (
            bx - margin <= x <= bx + bw + margin
            and by - margin <= y <= by + bh + margin
        ):
            return True
    return False


def main():
    text = ROOM_DATA.read_text(encoding="utf-8")
    rooms = parse_rooms(text)
    if not rooms:
        print("ERROR: no se parseo ninguna sala — cambio el formato de RoomData.gd?")
        return 1

    problems = []

    for rid, room in sorted(rooms.items()):
        rects = room["rects"]
        if not rects:
            problems.append(f"{rid}: sin rects")
            continue
        cells = cells_of(rects)

        if not connected(cells):
            problems.append(
                f"{rid}: los rects NO forman una region conectada "
                f"(hay una isla inalcanzable; recorda que deben solaparse, "
                f"no solo tocarse en la arista)"
            )

        if room["entry"] is None:
            problems.append(f"{rid}: falta entry")
        elif not inside(room["entry"], rects, BODY_RADIUS):
            problems.append(
                f"{rid}: entry {room['entry']} cae fuera de la union "
                f"(o a menos de {BODY_RADIUS}px de un muro)"
            )
        elif in_blocker(room["entry"], room["blockers"], BODY_RADIUS):
            problems.append(
                f"{rid}: entry {room['entry']} cae dentro de un muro interior"
            )

        for i, sp in enumerate(room["spawns"]):
            if not inside(sp, rects, BODY_RADIUS):
                problems.append(
                    f"{rid}: spawns[{i}] {sp} cae fuera de la union "
                    f"(o pegado a un muro)"
                )
            elif in_blocker(sp, room["blockers"], BODY_RADIUS):
                problems.append(
                    f"{rid}: spawns[{i}] {sp} cae dentro de un muro interior"
                )

        n_props = len(room["props"])
        if n_props != 5:
            problems.append(f"{rid}: tiene {n_props} props, deben ser 5")
        for i, p in enumerate(room["props"]):
            if not p["visible"]:
                continue
            if not inside(p["pos"], rects, BODY_RADIUS):
                problems.append(
                    f"{rid}: props[{i}] visible en {p['pos']} cae fuera de la union"
                )
            elif in_blocker(p["pos"], room["blockers"], BODY_RADIUS):
                problems.append(
                    f"{rid}: props[{i}] visible en {p['pos']} pisa un muro interior"
                )

        for side, d in room["doors"].items():
            if d["to"] not in rooms:
                problems.append(
                    f"{rid}: puerta {side} apunta a '{d['to']}', que no existe"
                )
            if not on_border(d["pos"], cells):
                problems.append(
                    f"{rid}: puerta {side} en {d['pos']} no cae sobre el borde "
                    f"de la union"
                )

    # Los spawns fijos de Policia/Criminal viven en Main.gd (no en
    # RoomData) pero se plantan en room_1, asi que se validan igual.
    main_gd = ROOM_DATA.parent / "Main.gd"
    if main_gd.exists() and "room_1" in rooms:
        mt = main_gd.read_text(encoding="utf-8")
        r1 = rooms["room_1"]["rects"]
        pol = re.search(
            r"police\.global_position = Vector2\(\s*(-?[\d.]+),\s*(-?[\d.]+)\s*\)", mt
        )
        if pol and not inside(
            (float(pol.group(1)), float(pol.group(2))), r1, BODY_RADIUS
        ):
            problems.append(
                f"Main._spawn_police: ({pol.group(1)}, {pol.group(2)}) "
                f"cae fuera de room_1"
            )
        # _spawn_criminals y _spawn_civilians usan ambos `var positions :=
        # [...]`, asi que se buscan por nombre de funcion para poder
        # nombrar cual falla.
        for fname in ("_spawn_criminals", "_spawn_civilians"):
            fm = re.search(
                rf"func {fname}\(\).*?var positions := \[(.*?)\]", mt, re.S
            )
            if not fm:
                continue
            for i, c in enumerate(_vectors(fm.group(1))):
                if not inside(c, r1, BODY_RADIUS):
                    problems.append(
                        f"Main.{fname}: positions[{i}] {c} cae fuera de room_1"
                    )
                elif in_blocker(c, rooms["room_1"]["blockers"], BODY_RADIUS):
                    problems.append(
                        f"Main.{fname}: positions[{i}] {c} pisa un muro interior"
                    )

    # Alcanzabilidad desde room_1.
    if "room_1" in rooms:
        seen = {"room_1"}
        stack = ["room_1"]
        while stack:
            cur = stack.pop()
            for d in rooms[cur]["doors"].values():
                if d["to"] in rooms and d["to"] not in seen:
                    seen.add(d["to"])
                    stack.append(d["to"])
        for rid in rooms:
            if rid not in seen:
                problems.append(f"{rid}: inalcanzable desde room_1")

    if problems:
        print(f"{len(problems)} problema(s):\n")
        for p in problems:
            print("  -", p)
        return 1

    print(f"OK — {len(rooms)} salas validadas:")
    for rid, room in sorted(rooms.items()):
        cells = cells_of(room["rects"])
        xs = [c[0] for c in cells]
        ys = [c[1] for c in cells]
        w = (max(xs) - min(xs) + 1) * CELL
        h = (max(ys) - min(ys) + 1) * CELL
        print(
            f"  {rid:10s} {len(room['rects'])} rect(s), "
            f"bbox {w:.0f}x{h:.0f}, {len(room['doors'])} puerta(s)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
