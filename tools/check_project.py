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
  3б) uniform-массивы шейдеров — у `uniform vec3 wheels[4] = …` в Godot 4 нет
     значений по умолчанию: такой шейдер не компилируется целиком, поэтому
     car_dirt.gdshader однажды молча перестал красить кузов (в консоли —
     «Shader compilation failed»). Массивы обязан выставлять код;
  4) профили эффектов — у RallyFxProfile / RallySurfaceFxProfile не бывает
     двух полей с одним именем (дубль — ошибка компиляции, а не «переопределение»),
     каждый uniform car_dirt.gdshader выставляется кодом и наоборот;
  5) строгий GDScript — `static func` не вызывает нестатические функции (движок
     падает с «Cannot call non-static function»), а `:=` не выводит тип из
     тернарника с null или из `.get()` без приведения («Cannot infer the type»);
  5б) имена параметров и локальных переменных не затеняют члены базовых
     классов (SHADOWED_VARIABLE / SHADOWED_VARIABLE_BASE_CLASS): `name`,
     `position`, `size`, `basis`, `material`, `top`/`bottom` и прочие. Раньше
     такой шум забивал консоль так, что настоящие ошибки в ней не читались;
  5в) значения enum'ов не берутся прямо из Array — элемент Array это Variant,
     и движок предупреждает INT_AS_ENUM_WITHOUT_CAST;
  5 г) клуб пыли на пике жизни не крупнее машины: при 5.6 м он рождается под
     аркой и виден «сквозь кузов» (жалоба про пыль, проходящую сквозь кузов);
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
]
FX_PROFILES = [
    "scripts/data/rally_fx_profile.gd",
    "scripts/data/rally_surface_fx_profile.gd",
]
DIRT_SHADER = "shaders/car_dirt.gdshader"
SURFACE_EFFECTS = "scripts/surface_effects.gd"
SHADERS_DIR = "shaders"


def check_shader_arrays():
    """Uniform-массивы без значений по умолчанию.

    Godot 4 отвергает `uniform vec3 wheels[4] = vec3[4](...)` с ошибкой
    «Setting default values to uniform arrays is not supported». Шейдер при
    этом не компилируется целиком: вместо слоя грязи на кузове остаётся голая
    краска, а в консоли — «Shader compilation failed». Такое не всплывает до
    запуска заезда, поэтому проверяем здесь.
    """
    errors = []
    root = os.path.join(ROOT, SHADERS_DIR)
    for name in sorted(os.listdir(root)):
        if not name.endswith(".gdshader"):
            continue
        rel = "%s/%s" % (SHADERS_DIR, name)
        with open(os.path.join(root, name), encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        for index, line in enumerate(lines):
            stripped = line.strip()
            if not stripped.startswith("uniform ") or "[" not in stripped or "=" not in stripped:
                continue
            errors.append(
                "%s:%d: у uniform-массива есть значение по умолчанию — Godot не "
                "скомпилирует шейдер: %s"
                % (rel, index + 1, stripped.rstrip(";"))
            )
    return errors


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


# Свойства StandardMaterial3D, которых в Godot 4 не существует.
# `specular` (из Godot 3.x) стал `metallic_specular`; обращение к старому имени
# движок перехватывает как 3.x-совместимость и сыплет
# «Godot 3.x SpatialMaterial remapped parameter not found: specular».
BAD_MATERIAL_PROPS = {
    "specular": "metallic_specular",
    "flags_transparent": "transparency",
    "params_cull_mode": "cull_mode",
    "params_billboard_mode": "billboard_mode",
    "params_depth_draw_mode": "depth_draw_mode",
    "flags_no_depth_test": "no_depth_test",
}

MATERIAL_HOLDERS = ("material", "mat", "paint", "base", "visual", "instance")


def check_material_props():
    """Свойства материала по именам Godot 4, а не по старому 3.x-API."""
    errors = []
    pattern = re.compile(r"\b(\w+)\.(%s)\s*=(?!=)"
                         % "|".join(sorted(BAD_MATERIAL_PROPS)), re.M)
    for base, _dirs, names in os.walk(ROOT):
        if os.sep + ".git" in base or os.sep + "tools" in base:
            continue
        for name in names:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as handle:
                code = handle.read()
            for match in pattern.finditer(code):
                holder = match.group(1)
                if holder not in MATERIAL_HOLDERS:
                    continue
                line = code[: match.start()].count("\n") + 1
                errors.append(
                    "%s:%d: %s.%s — в Godot 4 это %s"
                    % (os.path.relpath(path, ROOT), line, holder,
                       match.group(2), BAD_MATERIAL_PROPS[match.group(2)])
                )
    return errors


# Члены базовых классов, на которые GDScript ругается предупреждением
# SHADOWED_VARIABLE_BASE_CLASS, если назвать ими параметр или локальную
# переменную. Предупреждение не мешает игре, но забивает консоль так, что
# настоящие ошибки в ней не видны — поэтому имена держим свободными.
BASE_MEMBERS = {
    "Node": {"name", "owner"},
    "Node2D": {"position", "rotation", "scale", "name"},
    "Node3D": {
        "position", "rotation", "rotation_degrees", "scale", "quaternion",
        "basis", "transform", "global_transform", "global_basis",
        "global_position", "global_rotation", "global_rotation_degrees",
        "visible", "top_level", "name",
    },
    "Control": {
        "position", "size", "rotation", "scale", "pivot_offset", "focus_mode",
        "visible", "modulate", "self_modulate", "theme", "material", "name",
    },
    "CanvasItem": {"material", "modulate", "self_modulate", "visible", "z_index"},
    "Resource": {"resource_name", "resource_path", "resource_local_to_scene"},
    "RigidBody3D": {"mass", "linear_velocity", "angular_velocity", "gravity_scale"},
    "Camera3D": {"fov", "current", "near", "far"},
    "RayCast3D": {"target_position"},
    "MeshInstance3D": {"mesh", "material_override", "material_overlay", "skeleton"},
}

FUNC_RE = re.compile(r"^(?:\s*static\s+)?func\s+(\w+)\s*\(", re.M)
EXTENDS_RE = re.compile(r"^extends\s+([\w\"/.]+)", re.M)


def _signature(code, start):
    """Строка сигнатуры с продолжениями — до закрывающей скобки."""
    depth = 0
    index = start
    while index < len(code):
        char = code[index]
        if char == "(":
            depth += 1
        elif char == ")":
            depth -= 1
            if depth == 0:
                return code[start:index + 1]
        index += 1
    return code[start:]


def _argument_names(signature):
    inner = signature[1:-1] if signature.startswith("(") else signature
    names = []
    depth = 0
    current = ""
    for char in inner + ",":
        if char in "([":
            depth += 1
        elif char in ")]":
            depth -= 1
        if char == "," and depth == 0:
            match = re.match(r"\s*(?:var\s+)?(\w+)", current)
            if match:
                names.append(match.group(1))
            current = ""
        else:
            current += char
    return names


def check_shadowed_names():
    """Параметры и локальные переменные не занимают имена членов базовых классов."""
    errors = []
    for base, _dirs, names in os.walk(ROOT):
        if os.sep + ".git" in base or os.sep + "tools" in base:
            continue
        for name in names:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as handle:
                code = handle.read()
            extends = EXTENDS_RE.search(code)
            if not extends:
                continue
            native = extends.group(1).split("/")[-1].strip('"')
            reserved = BASE_MEMBERS.get(native)
            if not reserved:
                continue
            rel = os.path.relpath(path, ROOT)
            members = set(re.findall(
                r"^(?:@export[^\n]*\s)?(?:static\s+)?var\s+(\w+)", code, re.M))
            for match in FUNC_RE.finditer(code):
                signature = _signature(code, match.end() - 1)
                for argument in _argument_names(signature):
                    if argument in reserved:
                        line = code[: match.start()].count("\n") + 1
                        errors.append(
                            "%s:%d: параметр %r затеняет %s.%s (SHADOWED_VARIABLE_BASE_CLASS)"
                            % (rel, line, argument, native, argument))
                # локальные переменные внутри тела функции
                body_start = code.find("\n", code.find(":", match.end()))
                if body_start < 0:
                    continue
                body_end = code.find("\nfunc ", body_start)
                if body_end < 0:
                    body_end = len(code)
                body = code[body_start:body_end]
                # Только строки с отступом: `var` в нулевой колонке — поле класса,
                # и повторять его имя локальной переменной законно.
                for local in re.finditer(r"^[ \t]+var\s+(\w+)", body, re.M):
                    local_name = local.group(1)
                    if local_name in reserved:
                        line = code[: body_start + local.start()].count("\n") + 1
                        errors.append(
                            "%s:%d: переменная %r затеняет %s.%s (SHADOWED_VARIABLE_BASE_CLASS)"
                            % (rel, line, local_name, native, local_name))
                    elif local_name in members:
                        line = code[: body_start + local.start()].count("\n") + 1
                        errors.append(
                            "%s:%d: переменная %r затеняет поле класса (SHADOWED_VARIABLE)"
                            % (rel, line, local_name))
    return errors


def check_enum_assignments():
    """Значение enum'а нельзя брать из нетипизированного массива или int-поля.

    Godot 4 предупреждает «Integer used when an enum value is expected»
    (INT_AS_ENUM_WITHOUT_CAST): элемент `Array` — это Variant, и присваивание
    такого элемента в поле-enum теряет тип. Помогает явная локальная
    переменная с типом enum.
    """
    errors = []
    # имена полей-enum проекта: <ресурс>.<поле> встречается как .field = ...;
    enum_fields = set()
    for base, _dirs, names in os.walk(ROOT):
        if os.sep + ".git" in base or os.sep + "tools" in base:
            continue
        for name in names:
            if not name.endswith(".gd"):
                continue
            with open(os.path.join(base, name), encoding="utf-8") as handle:
                code = handle.read()
            for match in re.finditer(r"^enum\s+\w+\s*\{([^}]*)\}", code, re.M | re.S):
                members = re.findall(r"(\w+)\s*(?:=|,|$)", match.group(1))
                if members:
                    enum_fields.add(match.group(1))
    pattern = re.compile(
        r"^\s*[\w.\[\]()]+\.(\w+)\s*=\s*\[[^\]]*\]\s*\[", re.M)
    for base, _dirs, names in os.walk(ROOT):
        if os.sep + ".git" in base or os.sep + "tools" in base:
            continue
        for name in names:
            if not name.endswith(".gd"):
                continue
            path = os.path.join(base, name)
            with open(path, encoding="utf-8") as handle:
                code = handle.read()
            for match in pattern.finditer(code):
                line = code[: match.start()].count("\n") + 1
                errors.append(
                    "%s:%d: значение enum'а берётся прямо из Array — нужна "
                    "локальная переменная с типом enum (INT_AS_ENUM_WITHOUT_CAST)"
                    % (os.path.relpath(path, ROOT), line)
                )
    return errors


# Кузов машины в координатах модели: половина ширины и высота. Клуб пыли,
# который на пике жизни выходит за эти пределы, рождается под аркой и читается
# как «пыль сквозь кузов» (камера видит центр билборда ближе к себе, чем
# боковину). Значения — из scenes/rally_car.tscn (меши Mitsubishi_Body*).
BODY_HALF_WIDTH = 1.22
BODY_HEIGHT = 1.70
# Насколько клуб может быть крупнее кузова, прежде чем это станет артефактом.
PUFF_BUDGET = 1.9


def _tres_value(path, key, default):
    pattern = re.compile(r"^%s\s*=\s*([^\n#]+)" % re.escape(key), re.M)
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        match = pattern.search(handle.read())
    if not match:
        return default
    raw = match.group(1).strip()
    try:
        return float(raw)
    except ValueError:
        return default


def _gd_value(path, key, default):
    pattern = re.compile(
        r"^@export[^\n]*\bvar\s+%s\s*:\s*float\s*=\s*([-\d.]+)" % re.escape(key), re.M)
    with open(os.path.join(ROOT, path), encoding="utf-8") as handle:
        match = pattern.search(handle.read())
    if not match:
        return default
    try:
        return float(match.group(1))
    except ValueError:
        return default


def check_puff_size():
    """Клуб пыли не должен быть крупнее машины.

    Размер на пике жизни: сторона квада (foam_size × 2) × scale_max ×
    foam_growth × particle_scale конкретного покрытия. При 0.26/1.85/3.4/1.7
    это было 5.6 м — длиннее всей машины, и пыль «проходила сквозь кузов».
    """
    defaults = "scripts/data/rally_fx_profile.gd"
    foam_size = _tres_value("data/stage/default_fx_profile.tres", "foam_size",
                            _gd_value(defaults, "foam_size", 0.165))
    growth = _tres_value("data/stage/default_fx_profile.tres", "foam_growth",
                         _gd_value(defaults, "foam_growth", 2.4))
    scale_max = _tres_value("data/stage/default_fx_profile.tres", "foam_scale_max",
                            _gd_value(defaults, "foam_scale_max", 1.35))
    errors = []
    budget = BODY_HEIGHT * PUFF_BUDGET
    with open(os.path.join(ROOT, "data/stage/default_fx_profile.tres"), encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    scales = []
    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("particle_scale"):
            try:
                scales.append((index + 1, float(stripped.split("=")[1])))
            except (IndexError, ValueError):
                continue
    if not scales:
        scales = [(0, 1.0)]
    for line_number, particle_scale in scales:
        peak = foam_size * 2.0 * scale_max * growth * particle_scale
        if peak > budget:
            errors.append(
                "data/stage/default_fx_profile.tres:%d: клуб пыли %.2f м на пике "
                "(бюджет %.2f м) — крупнее машины, будет виден сквозь кузов"
                % (line_number, peak, budget)
            )
    return errors


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
        + check_shader_arrays()
        + check_material_props()
        + check_shadowed_names()
        + check_enum_assignments()
        + check_puff_size()
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
