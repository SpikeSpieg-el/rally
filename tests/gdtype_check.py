"""Проверка типов аргументов у встроенных методов GDScript (без Godot).

Зачем. `gdparse` и `gdlint` проверяют только синтаксис. Godot при загрузке
скрипта проверяет ещё и типы, и ошибка вроде

    bounds = bounds.expand(Vector3(...))     # Rect2.expand() ждёт Vector2

валит разбор ВСЕГО файла. Сообщение при этом указывает на файл, который
пытался его загрузить, так что искать приходится вверх по цепочке.

Путаница Vector2/Vector3 особенно неприятна: типы различаются одним символом,
а `:=` подхватывает тип молча. Поэтому здесь для аргумента выводится тип по
объявлению переменной/поля/сигнатуры, и если это Vector3, а метод принимает
Vector2 — тест падает.

Ограничение: это не компилятор. Разбираются только простые выражения —
имена, поля через точку, индексация, вызовы, литералы. Если тип вывести не
удалось, аргумент пропускается (ложных падений быть не должно).
"""
import re

# Методы, у которых Rect2 и AABB называются одинаково, но ждут РАЗНЫЕ типы:
# Rect2 — плоскую точку Vector2, AABB — объёмную Vector3. Ровно здесь
# `bounds.expand(Vector3(...))` проходит линтер и валит разбор в Godot.
SHARED_METHODS = {
    'expand', 'merge', 'grow', 'has_point', 'encloses', 'intersection',
    'grow_side', 'grow_individual', 'distance_to',
}

# Какой тип аргумента ждёт метод у каждого получателя. Для Vector2/Vector3
# это тоже полезно: `v.distance_to(Vector3)` — такая же ошибка.
EXPECTED = {
    'Rect2': 'Vector2',
    'Vector2': 'Vector2',
    'AABB': 'Vector3',
    'Vector3': 'Vector3',
}

# Методы, у которых аргумент — не точка того же типа (угол, ось и т.п.),
# поэтому сверять его с EXPECTED нельзя.
SKIP_METHODS = {'grow_side', 'grow_individual', 'abs'}

# Из чего складывается тип: имя -> тип, где имя может быть полем, локальной
# переменной или параметром. Ключи повторяются для разных функций, поэтому
# таблица строится на функцию, а не на файл.
_DECL = re.compile(r'^\s*var\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w\[\]]*)')
_INFER = re.compile(r'^\s*var\s+([A-Za-z_]\w*)\s*:=\s*(.+)$')
_FUNC = re.compile(r'^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\((.*?)\)\s*(?:->\s*([\w\[\]]+))?')
_CLASS_FIELD = re.compile(r'^var\s+([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w\[\]]*)')


def _strip_comment(line):
    """Убрать комментарий, не тронув '#' внутри строкового литерала."""
    out, quote = [], None
    for char in line:
        if quote:
            out.append(char)
            if char == quote:
                quote = None
        elif char in '"\'':
            quote = char
            out.append(char)
        elif char == '#':
            break
        else:
            out.append(char)
    return ''.join(out)


def _balanced_arguments(text, open_paren):
    """Аргументы вызова, начиная с позиции сразу после '('. None — не закрылось."""
    depth, args, current, quote = 1, [], '', None
    for char in text[open_paren:]:
        if quote:
            current += char
            if char == quote:
                quote = None
            continue
        if char in '"\'':
            quote = char
            current += char
        elif char in '([{':
            depth += 1
            current += char
        elif char in ')]}':
            depth -= 1
            if depth == 0:
                args.append(current)
                return args
            current += char
        elif char == ',' and depth == 1:
            args.append(current)
            current = ''
        else:
            current += char
    return None


def _split_top_level(text):
    """Разбить по запятым, не глядя внутрь скобок (для параметров функции)."""
    parts, depth, current, quote = [], 0, '', None
    for char in text:
        if quote:
            current += char
            if char == quote:
                quote = None
            continue
        if char in '"\'':
            quote = char
            current += char
        elif char in '([{':
            depth += 1
            current += char
        elif char in ')]}':
            depth -= 1
            current += char
        elif char == ',' and depth == 0:
            parts.append(current)
            current = ''
        else:
            current += char
    if current.strip():
        parts.append(current)
    return parts


class Scope:
    """Типы, известные в точке разбора: поля класса и локальные имена."""

    def __init__(self):
        self.types = {}

    def typeof(self, expression):
        """Тип выражения как строка ('Vector3', 'PackedVector3Array', …) или None."""
        expression = expression.strip()
        if not expression:
            return None
        # Константы вида Vector3.ZERO / Vector3.ONE / Vector3.UP
        constant = re.match(r'^(Vector3|Vector2)\.(ZERO|ONE|INF|UP|DOWN|LEFT|RIGHT|'
                            r'FORWARD|BACK)$', expression)
        if constant:
            return constant.group(1)
        # Литералы
        literal = re.match(r'^Vector3\s*\(', expression)
        if literal:
            return 'Vector3'
        if re.match(r'^Vector2\s*\(', expression):
            return 'Vector2'
        if re.match(r'^(Rect2|AABB)\s*\(', expression):
            return re.match(r'^(Rect2|AABB)', expression).group(1)
        # Вызовы без аргументов, тип которых известен по имени метода.
        no_args = re.match(r'^[\w.\[\]]+\.(get_aabb|get_rect|get_used_rect|'
                           r'get_item_rect)\(\)$', expression)
        if no_args:
            return {'get_aabb': 'AABB'}.get(no_args.group(1), 'Rect2')
        if expression.startswith(('"', "'")):
            return 'String'
        if re.match(r'^-?\d+$', expression):
            return 'int'
        if re.match(r'^-?\d*\.\d+$', expression) or re.match(r'^-?\d+$', expression):
            return 'float'
        if re.match(r'^-?\d*\.?\d+\s*[-+*/%]\s*-?\d*\.?\d+$', expression):
            return 'float'
        if re.match(r'^-?\d*\.\d+$', expression):
            return 'float'
        # Вызов метода: X.foo(...) — тип метода по имени не выводим, но
        # несколько встроенных конструкторов знаем.
        call = re.match(r'^(Vector3|Vector2|PackedVector3Array|PackedFloat32Array|'
                        r'PackedVector2Array|Rect2|AABB|Color|Basis|Transform3D|'
                        r'Quaternion|StringName)\s*\(', expression)
        if call:
            return call.group(1)
        # Индексация: имя[i]
        index = re.match(r'^([A-Za-z_]\w*)\s*\[', expression)
        if index and index.group(1) in self.types:
            container = self.types[index.group(1)]
            element = {
                'PackedVector3Array': 'Vector3',
                'PackedVector2Array': 'Vector2',
                'PackedFloat32Array': 'float',
                'PackedInt32Array': 'int',
                'PackedStringArray': 'String',
            }.get(container)
            if element:
                return element
        # Простое имя или имя поля: a / self.a / obj.a
        name = re.match(r'^(?:self\.)?([A-Za-z_]\w*)$', expression)
        if name:
            return self.types.get(name.group(1))
        return None


def _receiver_before(line, dot_position):
    """Выражение получателя перед точкой: `b` в `b.expand(...)`, `a.b` в `a.b.merge(...)`."""
    end = dot_position
    while end > 0 and line[end - 1] == ' ':
        end -= 1
    start = end
    # Отступаем назад по имени, индексам и цепочкам точек.
    while start > 0:
        char = line[start - 1]
        if char.isalnum() or char == '_' or char in '.]':
            start -= 1
        elif char == '[':
            # Вернуться к открывающей скобке индекса.
            depth, index = 0, start - 1
            while index >= 0:
                if line[index] == ']':
                    depth += 1
                elif line[index] == '[':
                    depth -= 1
                    if depth == 0:
                        break
                index -= 1
            if index < 0:
                break
            start = index
        else:
            break
    return line[start:end].strip()


def check_file(text):
    """Все подозрительные вызовы в файле: (строка, метод, тип аргумента)."""
    problems = []
    class_scope = Scope()
    # Поля класса: и явные (`var p: Vector3`), и выведенные (`var p := Vector3()`).
    for line in text.split('\n'):
        code = _strip_comment(line)
        declaration = _CLASS_FIELD.match(code)
        if declaration:
            class_scope.types[declaration.group(1)] = declaration.group(2)
            continue
        inferred = _INFER.match(code)
        if inferred:
            kind = class_scope.typeof(inferred.group(2))
            if kind:
                class_scope.types[inferred.group(1)] = kind

    scope = Scope()
    scope.types = dict(class_scope.types)
    for number, raw in enumerate(text.split('\n'), 1):
        line = _strip_comment(raw)
        header = _FUNC.match(line)
        if header:
            # Новая функция — свои локальные имена, поля класса остаются.
            scope = Scope()
            scope.types = dict(class_scope.types)
            for parameter in _split_top_level(header.group(2)):
                declared = re.match(r'^\s*([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w\[\]]*)',
                                    parameter)
                if declared:
                    scope.types[declared.group(1)] = declared.group(2)
        if line.lstrip().startswith(('##', '#')):
            continue
        declaration = _DECL.match(line)
        if declaration:
            scope.types[declaration.group(1)] = declaration.group(2)
        inferred = _INFER.match(line)
        if inferred:
            kind = scope.typeof(inferred.group(2))
            if kind:
                scope.types[inferred.group(1)] = kind

        for method in SHARED_METHODS:
            for call in re.finditer(r'\.' + method + r'\(', line):
                if method in SKIP_METHODS:
                    continue
                arguments = _balanced_arguments(line, call.end())
                if not arguments:
                    continue
                # Ключ — тип получателя: Rect2 ждёт Vector2, AABB — Vector3.
                # Сверяем с ожиданием, а не «Vector3 — плохо»: у AABB
                # трёхмерный аргумент правилен, и ругаться на него было бы
                # ложным падением.
                receiver = _receiver_before(line, call.start())
                owner = scope.typeof(receiver)
                expected = EXPECTED.get(owner)
                if not expected:
                    continue
                kind = scope.typeof(arguments[0])
                if not kind:
                    continue
                # Перегрузки тех же имён — законные формы, ошибкой не считаем:
                #   Rect2.grow(float) / grow_side / grow_individual
                #   Rect2.merge(AABB), AABB.merge(AABB), AABB.merge(Rect2)
                if kind in ('float', 'int'):
                    continue
                if method == 'merge' and kind in ('Rect2', 'AABB'):
                    continue
                if kind != expected:
                    problems.append((number, method, kind, owner, expected))

        # Присваивание результата: `bounds = bounds.expand(...)` сохраняет
        # Rect2, а вот `var x = obj.get_aabb()` мог бы сменить тип. Обновляем
        # только то, что выводится уверенно.
        assignment = re.match(r'^\s*(?:self\.)?([A-Za-z_]\w*)\s*=\s*(.+)$', line)
        if assignment and assignment.group(1) in scope.types:
            kind = scope.typeof(assignment.group(2))
            if kind:
                scope.types[assignment.group(1)] = kind
    return problems
