"""Реестр машин: в гараже ровно те машины, которые описаны ресурсами.

Godot не нужен — тест читает data/vehicles/*.tres и data/rally_game_config.tres
как текст и проверяет то, из-за чего в гараже появлялись лишние машины:

  * одна и та же сцена, записанная в двух видах (``res://scenes/rally_car3.tscn``
    и ``uid://hw61h2203ly2``), не находилась как занятая, и ``sync_registry()``
    создавал рядом дубль с именем файла — «RALLY CAR3»;
  * ресурс машины, который лежит в data/vehicles/, но не перечислен в конфиге,
    тоже превращался в такую автоматическую запись.

Заодно проверяется, что каждая машина самодостаточна: свои пресеты в конфиге,
свой банк звуков мотора и своя сетка оборотов.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = "data/rally_game_config.tres"
VEHICLE_SCRIPT = "scripts/data/rally_vehicle.gd"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def resource_block(text: str) -> str:
    """Секция [resource] — там лежат значения полей."""
    return text.split("[resource]", 1)[1] if "[resource]" in text else text


def fields(text: str) -> dict[str, str]:
    """Поля ресурса: {имя: значение как записано в файле}.

    Godot не пишет свойства, равные значениям по умолчанию из скрипта, поэтому
    отсутствие поля — не ошибка: его подменяет script_default().
    """
    return dict(re.findall(r"^(\w+) = (.*)$", resource_block(text), re.M))


def script_default(field: str) -> str:
    """Значение поля по умолчанию из скрипта ресурса машины."""
    match = re.search(r'@export var %s: String = "([^"]*)"' % re.escape(field),
                      read(VEHICLE_SCRIPT))
    return match.group(1) if match else ""


def unquote(value: str) -> str:
    return value.strip().strip('"')


def local_dir(value: str) -> str:
    """res://audio/engine/ -> audio/engine/; пустое значение остаётся пустым."""
    path = unquote(value)
    return path[len("res://"):] if path.startswith("res://") else path


def string_array(value: str) -> list[str]:
    return re.findall(r'"([^"]*)"', value)


def int_array(value: str) -> list[int]:
    return [int(x) for x in re.findall(r"-?\d+", value)]


def scene_uids() -> dict[str, str]:
    """uid сцены -> путь сцены относительно корня репозитория."""
    result = {}
    for scene in (ROOT / "scenes").glob("*.tscn"):
        head = scene.read_text(encoding="utf-8")[:400]
        match = re.search(r'uid="(uid://[^"]+)"', head)
        if match:
            result[match.group(1)] = scene.relative_to(ROOT).as_posix()
    return result


def resolve_scene(value: str, uids: dict[str, str]) -> str:
    """Значение race_scene -> путь сцены в репозитории.

    Инспектор Godot 4.7 пишет uid:// вместо res://, поэтому сравнивать нужно
    раскрытые пути — ровно так это делает car_models.gd через ResourceUID.
    """
    if value.startswith("uid://"):
        assert value in uids, f"uid сцены не найден в проекте: {value}"
        return uids[value]
    assert value.startswith("res://"), f"race_scene должен быть res:// или uid://: {value}"
    return value[len("res://"):]


def car_scenes() -> list[str]:
    """Игровые сцены машин: их и показывает гараж."""
    scenes = sorted(scene.relative_to(ROOT).as_posix()
                    for scene in (ROOT / "scenes").glob("rally_car*.tscn"))
    assert scenes, "в scenes/ нет сцен машин rally_car*.tscn"
    return scenes


# Жадно до последней «]» строки: в groups=["…"] встречаются скобки, и робкий
# шаблон «до первой ]» обрезал бы заголовок посередине списка групп.
_NODE_HEADER_RE = re.compile(r'^\[node .*\]$', re.MULTILINE)
_ATTR_RE = re.compile(r'(\w+)="([^"]*)"')


def _scene_nodes(scene_text: str) -> list[dict[str, str]]:
    """Узлы сцены: {имя, тип, parent} из заголовков [node …].

    Порядок атрибутов произвольный; безкавычные поля (unique_id, groups) не
    нужны, поэтому берём только пары ключ="значение".
    """
    nodes: list[dict[str, str]] = []
    for match in _NODE_HEADER_RE.finditer(scene_text):
        nodes.append(dict(_ATTR_RE.findall(match.group(0))))
    return nodes


def _rim_meshes(scene_text: str, mount: str, holder: str) -> list[str]:
    """Катящиеся обода внутри держателя колеса у заданного крепления подвески.

    Крепления подвески висят прямо на корне, поэтому родитель держателя всегда
    равен ``<крепление>/<держатель>`` без префикса. Рядом с ободом в том же
    держателе стоит плоскость тормозного диска (Plane_*); обод отличаем по
    подстроке «wheel» в имени — тот же признак, что и в CarModels.wheel_mesh_names.
    """
    parent_path = mount + "/" + holder
    rims: list[str] = []
    for node in _scene_nodes(scene_text):
        if node.get("type") != "MeshInstance3D":
            continue
        if node.get("parent", "") != parent_path:
            continue
        name = node.get("name", "")
        if "wheel" in name.lower():
            rims.append(name)
    return rims


def vehicles() -> dict[str, dict]:
    """Все ресурсы машин из data/vehicles/: {id: поля}."""
    uids = scene_uids()
    result = {}
    for path in sorted((ROOT / "data" / "vehicles").glob("*.tres")):
        relative = path.relative_to(ROOT).as_posix()
        props = fields(path.read_text(encoding="utf-8"))
        vehicle_id = unquote(props.get("id", "")) or script_default("id")
        race_scene = unquote(props.get("race_scene", ""))
        result[vehicle_id] = {
            "file": relative,
            "id": vehicle_id,
            "display_name": unquote(props.get("display_name", "")) or script_default("display_name"),
            "race_scene": race_scene,
            "scene": resolve_scene(race_scene, uids) if race_scene else "",
            "setup_ids": string_array(props.get("setup_ids", "")),
            "engine_dir": local_dir(props.get("engine_dir", "")),
            "engine_events_dir": local_dir(props.get("engine_events_dir", "")),
            "rpm_grid": int_array(props.get("engine_rpm_grid", "")),
        }
    return result


def config() -> dict:
    """Конфиг игры: внешние ресурсы, список машин и список пресетов."""
    text = read(CONFIG_PATH)
    ext = {}
    for match in re.finditer(
            r'\[ext_resource type="\w+"[^\n]*?path="(res://[^"]+)" id="([^"]+)"\]', text):
        ext[match.group(2)] = match.group(1)[len("res://"):]

    def ext_array(field: str) -> list[str]:
        match = re.search(r"^%s = Array\[Resource\]\(\[(.*?)\]\)" % field, text, re.M | re.S)
        if not match:
            return []
        return [ext[ext_id] for ext_id in re.findall(r'ExtResource\("([^"]+)"\)', match.group(1))]

    return {
        "ext": ext,
        "vehicles": ext_array("vehicles"),
        "all_setups": ext_array("all_setups"),
        "subtitle": unquote(fields(text).get("subtitle", "")),
    }


def setup_ids_in_config() -> dict[str, str]:
    """id пресета -> файл пресета для всех пресетов из конфига."""
    result = {}
    for relative in config()["all_setups"]:
        props = fields(read(relative))
        setup_id = unquote(props.get("id", ""))
        assert setup_id, f"у пресета {relative} нет id"
        result[setup_id] = relative
    return result


SETUP_SCRIPT = "scripts/data/rally_car_setup.gd"
## Одиночные звуки, которые играет только мотор с турбиной: blow-off и хлопки.
TURBO_ONE_SHOTS = ["bov_01.wav", "bov_02.wav", "bov_03.wav"] + [
    "pop_%02d.wav" % i for i in range(1, 7)
]


def setup_defaults() -> dict[str, str]:
    """Значения по умолчанию из скрипта пресета: Godot не пишет их в .tres."""
    text = read(SETUP_SCRIPT)
    result = {}
    for name, kind, value in re.findall(
            r"@export(?:_\w+\([^)]*\))? var (\w+): (\w+) = ([^\n]+)", text):
        result[name] = value.strip()
    return result


def vehicle_setups(vehicle: dict) -> list[tuple[str, dict[str, str]]]:
    """Пресеты одной машины: [(id, поля .tres с подставленными значениями по умолчанию)]."""
    defaults = setup_defaults()
    files = setup_ids_in_config()
    result = []
    for setup_id in vehicle["setup_ids"]:
        props = dict(fields(read(files[setup_id])))
        for key, value in defaults.items():
            props.setdefault(key, value)
        result.append((setup_id, props))
    return result


def default_grid() -> list[int]:
    """Сетка оборотов по умолчанию — она же у Mitsubishi (scripts/engine_sound.gd)."""
    sound = read("scripts/engine_sound.gd")
    match = re.search(r"const RPM_GRID := \[(.*?)\]", sound, re.S)
    assert match, "в engine_sound.gd нет const RPM_GRID"
    return [int(x) for x in re.findall(r"\d+", match.group(1))]


class VehicleRosterTest(unittest.TestCase):
    def test_every_car_scene_is_claimed_by_exactly_one_vehicle(self):
        """Лишние машины в гараже берутся оттуда, где сцена ничья или ничья дважды."""
        roster = vehicles()
        for scene in car_scenes():
            owners = [vehicle["id"] for vehicle in roster.values() if vehicle["scene"] == scene]
            self.assertEqual(len(owners), 1,
                             f"{scene}: сцену должны занимать ровно одна машина, найдено {owners}")

    def test_config_lists_every_vehicle_exactly_once(self):
        """Машина из data/vehicles/ обязана быть в конфиге — иначе реестр создаст дубль."""
        roster = vehicles()
        listed = config()["vehicles"]
        self.assertEqual(len(listed), len(set(listed)), f"в конфиге машины повторяются: {listed}")
        self.assertEqual(sorted(listed), sorted(vehicle["file"] for vehicle in roster.values()),
                         "список машин конфига не совпадает с data/vehicles/")

    def test_no_auto_generated_entries_in_the_roster(self):
        """Записи вида «RALLY CAR2» (их создаёт sync_registry) в гараже не нужны."""
        for vehicle in vehicles().values():
            self.assertNotRegex(vehicle["id"], r"^rally_car",
                                f"{vehicle['file']}: id выглядит как имя файла сцены")
            self.assertNotRegex(vehicle["display_name"], r"^RALLY CAR",
                                f"{vehicle['file']}: имя выглядит как автоматическое")
            self.assertTrue(vehicle["display_name"].strip(),
                            f"{vehicle['file']}: у машины пустое имя")

    def test_ids_names_and_scenes_are_unique(self):
        roster = list(vehicles().values())
        for key in ("id", "display_name", "race_scene"):
            values = [vehicle[key] for vehicle in roster]
            self.assertEqual(len(values), len(set(values)),
                             f"{key} у машин должен быть своим: {values}")

    def test_subtitle_matches_the_roster(self):
        """Подпись главного меню обещает столько машин, сколько их в реестре."""
        subtitle = config()["subtitle"]
        match = re.search(r"(\d+)\s+МАШИН", subtitle)
        self.assertIsNotNone(match, f"в подписи нет числа машин: {subtitle}")
        if match:
            self.assertEqual(int(match.group(1)), len(vehicles()),
                             f"подпись «{subtitle}» не совпадает с реестром машин")

    def test_every_vehicle_preset_is_listed_in_the_config(self):
        """Пресеты машины живут в общем all_setups: без них гараж пуст."""
        available = setup_ids_in_config()
        for vehicle in vehicles().values():
            self.assertTrue(vehicle["setup_ids"],
                            f"{vehicle['file']}: у машины нет ни одного пресета")
            for setup_id in vehicle["setup_ids"]:
                self.assertIn(setup_id, available,
                              f"{vehicle['file']}: пресет {setup_id} не перечислен в конфиге")
        # Обратная сторона: пресет принадлежит одной машине, иначе списки смешаются.
        owners: dict[str, list[str]] = {}
        for vehicle in vehicles().values():
            for setup_id in vehicle["setup_ids"]:
                owners.setdefault(setup_id, []).append(vehicle["id"])
        shared = {setup_id: who for setup_id, who in owners.items() if len(who) > 1}
        self.assertEqual(shared, {}, f"пресеты принадлежат нескольким машинам: {shared}")
        self.assertEqual(sorted(owners), sorted(available),
                         "в конфиге есть пресеты, которых нет ни у одной машины")

    def test_every_vehicle_has_its_own_engine_bank(self):
        """Свой мотор звучит своим банком: лупы на каждую точку сетки оборотов."""
        for vehicle in vehicles().values():
            loops = vehicle["engine_dir"] or "audio/engine/"
            events = vehicle["engine_events_dir"] or "audio/vehicle/"
            # Папка обязана заканчиваться на «/»: рантайм склеивает её с именем файла.
            if vehicle["engine_dir"]:
                self.assertTrue(vehicle["engine_dir"].endswith("/"),
                                f"{vehicle['file']}: engine_dir должен заканчиваться на /")
            if vehicle["engine_events_dir"]:
                self.assertTrue(vehicle["engine_events_dir"].endswith("/"),
                                f"{vehicle['file']}: engine_events_dir должен заканчиваться на /")
            grid = vehicle["rpm_grid"]
            with self.subTest(vehicle=vehicle["id"]):
                self.assertTrue((ROOT / loops).is_dir(), f"{vehicle['file']}: нет папки лупов {loops}")
                self.assertTrue((ROOT / events).is_dir(),
                                f"{vehicle['file']}: нет папки одиночных звуков {events}")
                if grid:
                    self.assertEqual(grid, sorted(set(grid)),
                                     f"{vehicle['file']}: сетка оборотов должна возрастать")
                # Пустая сетка означает «банк по умолчанию» (Mitsubishi).
                effective = grid or default_grid()
                for rpm in effective:
                    for bank in ("light", "full"):
                        name = "engine_%04d_%s.wav" % (rpm, bank)
                        self.assertTrue((ROOT / loops / name).is_file(),
                                        f"{vehicle['file']}: нет лупа {loops}{name}")
                        self.assertTrue((ROOT / loops / (name + ".import")).is_file(),
                                        f"{vehicle['file']}: нет .import для {loops}{name}")
                for one_shot in ("start.wav", "shift.wav"):
                    self.assertTrue((ROOT / events / one_shot).is_file(),
                                    f"{vehicle['file']}: нет звука {events}{one_shot}")

    def test_turbo_flag_matches_the_engine_character(self):
        """Турбина в пресете обязана совпадать с мотором и кривой момента.

        У атмосферного Golf сначала стояли ``torque_shape = 1`` (турбо-полка) и
        подпись «VR6 3.2 · ATMO»: кривая обещала рывок наддува там, где его нет.
        """
        for vehicle in vehicles().values():
            for setup_id, props in vehicle_setups(vehicle):
                engine_name = unquote(props.get("engine_name", "")).upper()
                turbo = props.get("turbo", "true").strip() == "true"
                torque_shape = int(props.get("torque_shape", "1"))
                with self.subTest(vehicle=vehicle["id"], setup=setup_id):
                    self.assertTrue(engine_name, f"{setup_id}: у пресета нет engine_name")
                    # Турбину видно либо по слову «TURBO», либо по индексу мотора:
                    # у Mitsubishi наддувный мотор пишется с «T» на конце (4G63T).
                    engine_code = engine_name.split("·")[0].strip()
                    if turbo:
                        self.assertTrue("TURBO" in engine_name or engine_code.endswith("T"),
                                        f"{setup_id}: турбо-пресет не называется турбо")
                    else:
                        self.assertNotIn("TURBO", engine_name,
                                         f"{setup_id}: атмосферный пресет назван турбо")
                        self.assertIn("АТМО", engine_name,
                                      f"{setup_id}: у атмосферника нет отметки «АТМО»")
                        # 1 — «Турбо-полка»: у атмосферника такой кривой быть не должно.
                        self.assertNotEqual(torque_shape, 1,
                                            f"{setup_id}: атмосфернику не подходит турбо-полка")

    def test_one_shot_sounds_follow_the_turbo_presets(self):
        """Хлопки и blow-off лежат только у машины с турбо-пресетом.

        Движок играет их при ``turbo`` и наддуве выше 0.3 бара, поэтому у
        атмосферного Golf таких файлов нет вовсе — и появиться они должны вместе
        с первым турбо-пресетом.
        """
        for vehicle in vehicles().values():
            events = vehicle["engine_events_dir"] or "audio/vehicle/"
            turbo = any(props.get("turbo", "true").strip() == "true"
                        for _, props in vehicle_setups(vehicle))
            with self.subTest(vehicle=vehicle["id"]):
                for name in TURBO_ONE_SHOTS:
                    exists = (ROOT / events / name).is_file()
                    self.assertEqual(exists, turbo,
                                     f"{vehicle['file']}: {events}{name} "
                                     f"{'лишний' if not turbo else 'не найден'}")

    def test_registry_compares_scenes_by_resolved_path(self):
        """Реестр обязан раскрывать uid://, иначе дубль машины возвращается."""
        models = read("scripts/car_models.gd")
        self.assertIn("static func scene_path(value: String) -> String:", models)
        self.assertIn("ResourceUID.text_to_id(value)", models)
        self.assertIn("scene_path(candidate.race_scene) == path", models)
        self.assertIn("_vehicle_on_disk(path)", models,
                      "реестр должен подхватывать ресурс машины из data/vehicles/")
        garage = read("scripts/garage_menu.gd")
        self.assertIn("config.vehicle_ids()", garage,
                      "список машин гаража берётся из конфига, а не из имён сцен")

    def test_vitrine_wheels_come_from_the_car_scene(self):
        """Колёса на витрине ищутся по креплениям подвески, а не по имени модели.

        Subaru и Golf сегодня ездят на мешах Lancer (``Mitsubishi_Wheel_*``),
        поэтому захардкоженный список имён работал. Четвёртая машина со своими
        колёсами осталась бы на витрине неподвижной.
        """
        models = read("scripts/car_models.gd")
        self.assertIn('const WHEEL_META := "car_wheel_meshes"', models)
        self.assertIn("static func wheel_mesh_names(car: Node3D) -> Array[String]:", models)
        self.assertIn("for mount_name in WHEEL_MOUNTS:", models,
                      "имена колёс берутся из креплений Wheel_FL/FR/RL/RR")
        self.assertIn("preview.set_meta(WHEEL_META, wheel_mesh_names(car))", models)
        garage = read("scripts/garage_menu.gd")
        self.assertIn("model.get_meta(CarModels.WHEEL_META, [])", garage,
                      "гараж крутит колёса той машины, которую показывает")
        self.assertIn("_track_wheels(model, wheel_names if not wheel_names.is_empty()"
                      " else SCENE_WHEEL_NAMES)", garage,
                      "список имён сцены витрины остался запасным вариантом")
        # Крепления подвески во всех сценах машин на месте, а в держателе
        # WheelVisual каждого угла ровно один обод. Рядом с креплением может
        # висеть плоскость тормозного диска, но колесо на витрине — одно:
        # иначе garage насчитает восемь колёс вместо четырёх.
        for scene in car_scenes():
            text = read(scene)
            rims_total = 0
            for mount in ("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"):
                self.assertIn(f'[node name="{mount}"', text,
                              f"{scene}: нет крепления подвески {mount}")
                rims = _rim_meshes(text, mount, "WheelVisual")
                self.assertEqual(len(rims), 1,
                                 f"{scene}: в WheelVisual у {mount} один обод, найдено {rims}")
                rims_total += len(rims)
            self.assertEqual(rims_total, 4,
                             f"{scene}: на машину четыре колеса витрины, найдено {rims_total}")


if __name__ == "__main__":
    unittest.main()
