"""Проверка проекта без запуска движка.

Движка в окружении разработчика может не быть, а опечатки в именах полей и
битые ссылки в .tscn/.tres всплывают только в заезде. Этот скрипт закрывает
обе дыры:

  1) «пульты» — каждое обращение вида `cfg.имя` внутри rally_stage.gd
     сверяется с полями и методами соответствующего класса-ресурса
     (RallyStageSettings, RallySpawnLayout, RallySceneryConfig, …);
  2) ресурсы — во всех .tscn/.tres проверяется, что каждый ExtResource/
     SubResource объявлен, а каждый `path="res://…"` существует на диске;
  3) конструкторы — у `Color()`, `Vector3()`, `Transform3D()` и прочих
     проверяется число аргументов. Текстовый формат строгий: `Color(r, g, b)`
     не читается, нужен четвёртый аргумент — альфа. Именно так однажды
     посыпались все сцены пропсов ("Expected 4 arguments for constructor").

Запуск:  python3 tools/check_project.py
Код выхода: 0 — чисто, 1 — есть проблемы.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Через какие геттеры в rally_stage.gd приходят «пульты».
PULPITS = {
    "s_settings()": "scripts/data/rally_stage_settings.gd",
    "s_spawn()": "scripts/data/rally_spawn_layout.gd",
    "s_fx()": "scripts/data/rally_fx_profile.gd",
    "s_scenery()": "scripts/data/rally_scenery_config.gd",
    "s_props()": "scripts/data/rally_prop_library.gd",
}

# Переменные, чей тип известен из имени (поля классов, а не «пультов»).
KNOWN_OWNERS = {
    "track": "scripts/data/rally_track_config.gd",
    "network": "scripts/road_network.gd",
    "prop": "scripts/data/rally_prop.gd",
    "companion": "scripts/data/rally_prop.gd",
    "library": "scripts/data/rally_prop_library.gd",
    "weather": "scripts/data/rally_weather_config.gd",
}

# Публичные поля структур данных и встроенные методы Resource: их в классах нет.
ALLOWED = {
    "resource_path",
    "resource_name",
    "changed",
    "duplicate",
    "cell",
    "cols",
    "rows",
    "origin",
    "samples",
    "sample_dists",
    "sample_dirs",
    "total_length",
    "bounds",
    "field_dist",
    "field_along",
    "field_site",
    "regional",
    "regional_cell",
    "regional_cols",
    "regional_rows",
    "regional_origin",
}

EXPORT_RE = re.compile(
    r"^@export(?:_range\([^)]*\)|_group\([^)]*\)|_tool_button\([^)]*\)"
    r"|_enum\([^)]*\)|_storage|_var|_dir|_file|_multiline|_flags)?\s+var\s+(\w+)",
    re.M,
)


def members_of(rel_path):
    """Имена полей, констант, методов и вложенных классов ресурса."""
    with open(os.path.join(ROOT, rel_path), encoding="utf-8") as handle:
        text = handle.read()
    names = set(EXPORT_RE.findall(text))
    names |= set(re.findall(r"^\t?var\s+(\w+)\s*[:=]", text, re.M))
    names |= set(re.findall(r"^\t?(?:static\s+)?func\s+(\w+)", text, re.M))
    names |= set(re.findall(r"^const\s+(\w+)", text, re.M))
    names |= set(re.findall(r"^class\s+(\w+)", text, re.M))
    return names


def check_pulpits():
    """Сверить обращения к полям «пультов» с реальными полями классов."""
    with open(os.path.join(ROOT, "scripts/rally_stage.gd"), encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    tables = {key: members_of(path) for key, path in PULPITS.items()}
    for key, path in KNOWN_OWNERS.items():
        tables[key] = members_of(path) | ALLOWED
    errors = []
    owners = {}
    inside_inner_class = False
    for lineno, line in enumerate(lines, 1):
        stripped = line.strip()
        if re.match(r"^class\s+\w+\s*:\s*$", stripped):
            inside_inner_class = True
        elif stripped.startswith(("func ", "const ", "var ", "@")):
            inside_inner_class = False
        if inside_inner_class:
            continue
        matched = re.search(r"var\s+(\w+)\s*:?=\s*(s_\w+\(\))", stripped)
        if matched:
            owners[matched.group(1)] = matched.group(2)
        for owner, field in re.findall(r"\b(\w+)\.(\w+)\b", stripped):
            table_key = owners.get(owner, owner if owner in KNOWN_OWNERS else None)
            if table_key is None or field in ALLOWED:
                continue
            if field not in tables[table_key]:
                errors.append("scripts/rally_stage.gd:%d: %s.%s — нет такого поля (%s)"
                              % (lineno, owner, field, table_key))
    return errors


EXT_HEADER = re.compile(r'^\[ext_resource\s+.*?\bid="([^"]+)"')
SUB_HEADER = re.compile(r'^\[sub_resource\s+.*?\bid="([^"]+)"')
EXT_USE = re.compile(r'ExtResource\(\s*"([^"]+)"\s*\)')
SUB_USE = re.compile(r'SubResource\(\s*"([^"]+)"\s*\)')
PATH_USE = re.compile(r'\bpath="(res://[^"]+)"')


def check_resources():
    """Сверить ссылки внутри .tscn/.tres с объявлениями и файлами на диске."""
    errors = []
    total = 0
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "__pycache__")]
        for name in files:
            if not name.endswith((".tscn", ".tres")):
                continue
            path = os.path.join(base, name)
            total += 1
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            declared = set(EXT_HEADER.findall(text, re.M)) if False else set()
            declared = set()
            for line in text.split("\n"):
                hit = EXT_HEADER.match(line)
                if hit:
                    declared.add(hit.group(1))
                hit = SUB_HEADER.match(line)
                if hit:
                    declared.add(hit.group(1))
            for used in set(EXT_USE.findall(text) + SUB_USE.findall(text)):
                if used not in declared:
                    errors.append("%s: нет ресурса с id=%r"
                                  % (os.path.relpath(path, ROOT), used))
            for res in set(PATH_USE.findall(text)):
                disk = os.path.join(ROOT, res[len("res://"):])
                if not os.path.exists(disk):
                    errors.append("%s: нет файла %s" % (os.path.relpath(path, ROOT), res))
    print("Проверено ресурсов: %d" % total)
    return errors


# Сколько аргументов ждёт конструктор в текстовом формате Godot. Множества —
# на случай перегруженных конструкторов (Basis из 9 чисел или из оси и угла).
ARITY = {
    "Vector2": {2}, "Vector2i": {2}, "Vector3": {3}, "Vector3i": {3},
    "Vector4": {4}, "Vector4i": {4},
    "Color": {4},               # Color(r, g, b) движок НЕ примет
    "Quaternion": {4}, "Rect2": {4}, "Rect2i": {4}, "Plane": {4},
    "Transform2D": {6}, "Transform3D": {12, 6, 2}, "Basis": {9, 4},
    "AABB": {6, 2}, "Projection": {16},
}


def count_top_args(text, open_idx):
    """Число аргументов верхнего уровня: запятые внутри вложенных скобок не в счёт."""
    depth, args, seen = 0, 0, False
    i = open_idx
    while i < len(text):
        char = text[i]
        if char in "([{":
            depth += 1
        elif char in ")]}":
            depth -= 1
            if depth == 0:
                return args + (1 if seen else 0)
        elif char == '"':
            i += 1
            while i < len(text) and text[i] != '"':
                i += 1
        elif char == "," and depth == 1:
            args += 1
            seen = False
        elif not char.isspace() and depth == 1:
            seen = True
        i += 1
    return None


def check_constructors():
    """Число аргументов у конструкторов вариантов в .tscn/.tres."""
    errors = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "__pycache__")]
        for name in files:
            if not name.endswith((".tscn", ".tres")):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            with open(path, encoding="utf-8") as handle:
                for lineno, line in enumerate(handle, 1):
                    for hit in re.finditer(r"\b(\w+)\s*\(", line):
                        ctor = hit.group(1)
                        if ctor not in ARITY:
                            continue
                        found = count_top_args(line, hit.end() - 1)
                        if found is not None and found not in ARITY[ctor]:
                            expected = "/".join(str(a) for a in sorted(ARITY[ctor]))
                            errors.append(
                                "%s:%d: %s(%d арг.) — текстовый формат ждёт %s\n    %s"
                                % (rel, lineno, ctor, found, expected, line.strip()))
    return errors


def main():
    errors = check_pulpits() + check_resources() + check_constructors()
    if errors:
        for item in errors:
            print(item)
        print("ИТОГО проблем: %d" % len(errors))
        return 1
    print("Всё чисто: поля и ссылки сходятся.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
