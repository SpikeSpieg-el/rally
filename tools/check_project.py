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
     посыпались все сцены пропсов ("Expected 4 arguments for constructor");
  4) профили эффектов — у RallyFxProfile / RallySurfaceFxProfile не бывает
     двух полей с одним именем (дубль — ошибка компиляции, а не «переопределение»),
     каждый uniform car_dirt.gdshader выставляется кодом и наоборот;
  5) строгий GDScript — `static func` не вызывает нестатические функции (движок
     падает с «Cannot call non-static function»), а `:=` не выводит тип из
     тернарника с null или из `.get()` без приведения («Cannot infer the type»);
  6) повторное объявление локальной переменной в одной области видимости — это
     parse-ошибка, из-за которой скрипт нельзя даже preload'ить (так один раз
     «упал» surface_effects.gd, и каскадом посыпались машина и этап).

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


FX_CONSUMERS = [
    "scripts/surface_effects.gd",
    "scripts/rally_car.gd",
    "scripts/ui/wheel_fx_settings.gd",
]
FX_PROFILES = [
    "scripts/data/rally_fx_profile.gd",
    "scripts/data/rally_surface_fx_profile.gd",
]
DIRT_SHADER = "shaders/car_dirt.gdshader"
SURFACE_EFFECTS = "scripts/surface_effects.gd"


def check_fx_profiles():
    """Дубли полей в профилях эффектов и рассинхрон uniform'ов шейдера грязи."""
    errors = []
    for rel in FX_PROFILES:
        path = os.path.join(ROOT, rel)
        with open(path, encoding="utf-8") as handle:
            names = re.findall(r"^@export[^\n]*?\bvar\s+(\w+)", handle.read(), re.M)
        seen = set()
        for name in names:
            if name in seen:
                errors.append("%s: поле %s объявлено дважды" % (rel, name))
            seen.add(name)
    # Код читает поля профиля по строкам (_p("имя"), _pv("имя"), cfg.имя):
    # опечатка не всплывёт до заезда, поэтому сверяем имена здесь.
    known = set()
    for rel in FX_PROFILES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as handle:
            known.update(re.findall(r"^@export[^\n]*?\bvar\s+(\w+)", handle.read(), re.M))
    for rel in FX_CONSUMERS:
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            continue
        with open(path, encoding="utf-8") as handle:
            code = handle.read()
        used = set(re.findall(r'_p[bcv]?\("(\w+)"', code))
        used.update(re.findall(r'\bcfg\.(\w+)', code))
        for name in sorted(used - known):
            errors.append("%s: поле %r нет в профиле эффектов" % (rel, name))
    shader_path = os.path.join(ROOT, DIRT_SHADER)
    code_path = os.path.join(ROOT, SURFACE_EFFECTS)
    if os.path.exists(shader_path) and os.path.exists(code_path):
        with open(shader_path, encoding="utf-8") as handle:
            shader = handle.read()
        with open(code_path, encoding="utf-8") as handle:
            code = handle.read()
        uniforms = set(re.findall(r"^uniform\s+\w+\s+(\w+)", shader, re.M))
        set_params = set(re.findall(r'set_shader_parameter\("(\w+)"', code))
        # uniform без значения по умолчанию обязан быть выставлен из кода,
        # иначе на кузове будет мусор вместо слоя грязи.
        for name in sorted(uniforms - set_params):
            line = re.search(r"^uniform\s+\w+\s+%s\b[^;]*;" % re.escape(name), shader, re.M)
            if line and "=" not in line.group(0):
                errors.append("%s: uniform %s не выставляется из %s"
                              % (DIRT_SHADER, name, SURFACE_EFFECTS))
        for name in sorted(set_params - uniforms):
            errors.append("%s: код выставляет %r, но такого uniform нет в %s"
                          % (SURFACE_EFFECTS, name, DIRT_SHADER))
    return errors


def _opens_scope(code: str) -> bool:
    """Строка открывает блок: if/else/for/match/arm-метка/лямбда — всё это `:`."""
    stripped = code.strip()
    return stripped.endswith(":")


def _duplicate_locals(rel, lines):
    """Повтор `var имя` в одной области видимости.

    В соседних ветках if/for одно и то же имя объявлять можно — движок это
    разрешает. Ошибка только внутри одного блока (так один раз «упал»
    surface_effects.gd: дубль `var spin`, и каскадом посыпались машина и этап).
    """
    problems = []
    head_re = re.compile(r"^(\t*)(?:static )?func (\w+)\(")
    index = 0
    while index < len(lines):
        head = head_re.match(lines[index])
        if not head:
            index += 1
            continue
        func_indent = len(head.group(1))
        fname = head.group(2)
        # Тело кончается на первой непустой строке без отступа тела:
        # следующая функция, класс, поле или директива.
        body_end = index + 1
        while body_end < len(lines):
            probe = lines[body_end]
            stripped = probe.strip()
            if stripped and not stripped.startswith("#"):
                indent = len(probe) - len(probe.lstrip("\t"))
                if indent <= func_indent:
                    break
            body_end += 1
        stack = [(0, {})]  # (отступ блока, {имя: строка объявления})
        for lineno in range(index + 1, body_end):
            code = lines[lineno].split("#", 1)[0].rstrip()
            if not code.strip() or code.lstrip().startswith("@"):
                continue
            indent = len(code) - len(code.lstrip("\t"))
            while len(stack) > 1 and indent <= stack[-1][0]:
                stack.pop()
            if _opens_scope(code):
                stack.append((indent, {}))
            scope = stack[-1][1]
            for hit in re.finditer(r"\bvar (\w+)", code):
                name = hit.group(1)
                earlier = None
                for _, block in reversed(stack):
                    if name in block:
                        earlier = block[name]
                        break
                if earlier is not None:
                    problems.append(
                        "%s:%d: в %s() переменная '%s' уже объявлена в строке %d"
                        % (rel, lineno + 1, fname, name, earlier)
                    )
                else:
                    scope[name] = lineno + 1
        index = body_end
    return problems


def check_gdscript_strict():
    """Две ошибки, которые gdparse пропускает, а движок — нет."""
    errors = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", ".godot", "__pycache__")]
        for name in files:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            with open(path, encoding="utf-8") as handle:
                lines = handle.read().splitlines()
            errors.extend(_static_calls_nonstatic(rel, lines))
            errors.extend(_infer_from_variant(rel, lines))
            errors.extend(_duplicate_locals(rel, lines))
    return errors


def _static_calls_nonstatic(rel, lines):
    """static func не имеет self: вызов обычного метода — ошибка компиляции."""
    text = "\n".join(lines)
    instance_methods = set(re.findall(r"^func (\w+)\(", text, re.M))
    if not instance_methods:
        return []
    errors = []
    index = 0
    while index < len(lines):
        head = re.match(r"static func (\w+)\(", lines[index])
        if not head:
            index += 1
            continue
        fname = head.group(1)
        body_end = index + 1
        while body_end < len(lines) and not re.match(
            r"^(static )?func ", lines[body_end]
        ):
            body_end += 1
        for lineno in range(index + 1, body_end):
            code = lines[lineno].split("#", 1)[0]
            for call in re.findall(r"(?<![\w.\"])([A-Za-z_]\w*)\(", code):
                if call in instance_methods:
                    errors.append(
                        "%s:%d: static %s() зовёт нестатический %s()"
                        % (rel, lineno + 1, fname, call)
                    )
        index = body_end
    return errors


def _infer_from_variant(rel, lines):
    """`var x := ... if c else null` и `var x := obj.get(k)` не выводят тип."""
    errors = []
    for lineno, line in enumerate(lines, 1):
        code = line.split("#", 1)[0]
        match = re.match(r"\s*var \w+ := (.+)$", code)
        if not match:
            continue
        rhs = match.group(1).strip()
        if re.search(r"\belse\s+null\b", rhs):
            errors.append(
                "%s:%d: := из тернарника с null — укажите тип явно" % (rel, lineno)
            )
        elif re.search(r"\.get\([^()]*\)\s*$", rhs) and " as " not in rhs:
            errors.append(
                "%s:%d: := из .get() без приведения — тип не выводится" % (rel, lineno)
            )
    return errors


def main():
    errors = (
        check_pulpits()
        + check_resources()
        + check_constructors()
        + check_fx_profiles()
        + check_gdscript_strict()
    )
    if errors:
        for item in errors:
            print(item)
        print("ИТОГО проблем: %d" % len(errors))
        return 1
    print("Всё чисто: поля и ссылки сходятся.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
