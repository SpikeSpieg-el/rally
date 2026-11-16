"""Аркадный режим: связность ресурсов и сцены (без запуска Godot).

Игра не запускается в CI, поэтому битая ссылка в .tscn или забытая строчка в
конфиге всплыла бы только у игрока. Здесь проверяется вся цепочка:

    RallyGameConfig.tracks → stage_arcade.tres → scenes/rally_arcade.tscn
    → скрипт этапа → генератор / сеть / стример / чанк

и то, что аркадный этап не тянет за собой финиш, мини-карту и маршрут
обычного спецучастка.

Запуск: python3 -m unittest tests.test_arcade_scene
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
import check_project
import gdtype_check

TRACK = ROOT / 'data/tracks/stage_arcade.tres'
SCENE = ROOT / 'scenes/rally_arcade.tscn'
CONFIG = ROOT / 'data/rally_game_config.tres'
STAGE = ROOT / 'scripts/arcade/arcade_stage.gd'
ROAD = ROOT / 'scripts/arcade/arcade_road.gd'
NETWORK = ROOT / 'scripts/arcade/arcade_network.gd'
STREAMER = ROOT / 'scripts/arcade/arcade_streamer.gd'
CHUNK = ROOT / 'scripts/arcade/arcade_chunk.gd'
LEG = ROOT / 'scripts/data/rally_arcade_leg.gd'


def _text(path):
    return path.read_text(encoding='utf-8')


class ArcadeSceneTest(unittest.TestCase):
    def test_all_arcade_files_exist(self):
        for path in (TRACK, SCENE, STAGE, ROAD, NETWORK, STREAMER, CHUNK, LEG):
            self.assertTrue(path.exists(), f'нет файла {path.relative_to(ROOT)}')

    def test_resource_references_resolve(self):
        errors = check_project.check_resources()
        arcade = [e for e in errors if 'arcade' in e]
        self.assertEqual(arcade, [], 'битые ссылки в аркадных ресурсах:\n' + '\n'.join(arcade))

    def test_track_points_to_the_arcade_scene(self):
        text = _text(TRACK)
        self.assertIn('stage_scene = "res://scenes/rally_arcade.tscn"', text)
        # Аркада — не процедурный спецучасток: у неё нет кривой маршрута,
        # иначе этап попытался бы строить его как раллийную трассу.
        self.assertIn('procedural = false', text)

    def test_arcade_is_registered_in_the_game_config(self):
        text = _text(CONFIG)
        self.assertIn('path="res://data/tracks/stage_arcade.tres"', text)
        tracks = re.search(r'^tracks = Array\[Resource\]\(\[(.*)\]\)', text, re.M)
        self.assertIsNotNone(tracks, 'в конфиге нет списка трасс')
        self.assertIn('ExtResource("arcade")', tracks.group(1))

    def test_scene_contains_what_the_stage_needs(self):
        text = _text(SCENE)
        for required in (
            '[node name="RallyArcadeStage"',
            'path="res://scripts/arcade/arcade_stage.gd"',
            '[node name="RallyCar"',
            '[node name="HUD"',
            'path="res://scenes/ui/rally_hud.tscn"',
            '[node name="VisualEffects"',
            '[node name="WorldEnvironment"',
            '[node name="SunLight"',
        ):
            self.assertIn(required, text, f'в аркадной сцене нет: {required}')

    def test_stage_has_the_contract_the_car_expects(self):
        text = _text(STAGE)
        # Машина ищет эти методы у родителя; без них она молча теряет
        # покрытие, сброс и тряску камеры.
        for signature in (
            'func surface_contact(',
            'func live_surface_grip(',
            'func speed_shake_offset(',
            'func speed_shake_angles(',
            'func surface_kind_at(',
        ):
            self.assertIn(signature, text, f'аркадный этап не реализует {signature}')

    def test_stage_has_no_finish_or_route(self):
        # Только код, без комментариев: в шапке эти слова как раз объясняют,
        # почему аркада их не использует.
        text = '\n'.join(line for line in _text(STAGE).splitlines()
                          if not line.lstrip().startswith('#'))
        for forbidden in ('_check_finish', '_finish_stage', 'finish_pos', 'Path3D',
                          'mini_map'):
            self.assertNotIn(forbidden, text,
                             f'аркадный этап не должен использовать {forbidden}')

    def test_prop_library_is_not_needed(self):
        # Аркада строит обстановку сама (дома, зебры): библиотека пропсов
        # тянет сцены с LOD-ами и бандлами, которых у бесконечной дороги нет.
        self.assertNotIn('prop_library', _text(STAGE))

    def test_stage_only_reads_fields_that_exist(self):
        # Опечатка в имени поля ресурса не ловится ни gdparse, ни линтером:
        # `track.rally_seed` упал бы только в заезде. Здесь сверяются поля,
        # которые этап читает у трассы и раскладки спавнов.
        sys.path.insert(0, str(ROOT / 'tools'))
        import check_project
        errors = check_project.check_pulpits()
        arcade = [e for e in errors if 'arcade' in e]
        self.assertEqual(arcade, [], 'этап читает несуществующие поля:\n' + '\n'.join(arcade))

    def test_no_invented_game_state_fields(self):
        # Поля RallyGame, которые этап спрашивает через get(): опечатка здесь
        # даёт null и тихо ломает сид/выход.
        game = _text(ROOT / 'scripts/game_state.gd')
        stage = _text(STAGE)
        for match in re.finditer(r'game\.get\("(\w+)"\)', stage):
            field = match.group(1)
            self.assertIn('var %s' % field, game,
                          f'этап читает несуществующее поле RallyGame.%s' % field)

    def test_generator_constants_stay_in_the_documented_range(self):
        text = _text(ROAD)
        length = float(re.search(r'const LEG_LENGTH: float = ([\d.]+)', text).group(1))
        self.assertAlmostEqual(length, 260.0, msg='чанк стримера обязан делить длину участка')
        chunk = float(re.search(r'const CHUNK_LENGTH: float = ([\d.]+)', _text(STREAMER)).group(1))
        self.assertAlmostEqual(length % chunk, 0.0, places=6,
                               msg='длина чанка не делит длину участка — меш порвётся '
                                   'на смене ширины посреди домена')

    def test_colliders_are_in_the_groups_the_wheel_asks_for(self):
        # wheel.gd запрашивает покрытие ТОЛЬКО у коллайдеров в группах
        # Road/Dirt/Grass. Коллайдер без группы — это дорога, которая на
        # ощупь становится травой: сцепление и пыль пропадают молча.
        self.assertIn('add_to_group("Road"', _text(STREAMER))
        self.assertIn('add_to_group("Grass"', _text(STREAMER))
        self.assertIn('var kinds: Array[String]', _text(CHUNK))

    def test_road_and_chunk_agree_on_the_width(self):
        # Ширина полотна — один источник правды (генератор), меш её только читает.
        for path in (CHUNK, NETWORK):
            text = _text(path)
            self.assertIn('half_width_at(', text)
            self.assertNotIn('const DEFAULT_HALF_WIDTH', text,
                             f'{path.name} не должен дублировать ширину полотна')

    def test_no_function_is_defined_twice(self):
        # Две функции с одним именем в классе — это Parse Error, и Godot гасит
        # весь скрипт разом: этап падает с «Could not preload arcade_network.gd»,
        # хотя виноват самый нижний файл. Поймать это глазами в 700-строчном
        # файле после правок почти невозможно.
        for path in (CHUNK, NETWORK, ROAD, STAGE, STREAMER, LEG):
            seen = {}
            for number, line in enumerate(_text(path).splitlines(), 1):
                found = re.match(r'^(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(', line)
                if not found:
                    continue
                name = found.group(1)
                self.assertNotIn(
                    name, seen,
                    f'{path.name}: функция {name}() определена дважды '
                    f'(строки {seen.get(name)} и {number})')
                seen[name] = number

    def test_no_point_of_the_wrong_dimensionality(self):
        # gdparse проверяет только синтаксис, а Godot — ещё и типы аргументов:
        # `bounds.expand(Vector3(...))` валит разбор файла целиком, потому что
        # Rect2.expand() ждёт Vector2. Ни линтер, ни глаза этого не видят:
        # Vector3 и Vector2 различаются одним символом.
        #
        # Проверяется ВЕСЬ проект, а не только аркада: такой ошибке всё равно,
        # в каком файле жить, а падает на ней всегда загрузка сцены.
        for path in sorted((ROOT / 'scripts').rglob('*.gd')):
            for number, method, got, owner, expected in gdtype_check.check_file(
                    _text(path)):
                self.fail(f'{path.name}:{number}: {owner}.{method}() ждёт {expected}, '
                          f'а получает {got} — Godot не разберёт файл')

    def test_type_check_catches_the_real_failure(self):
        # Защита от «тест зелёный, потому что ничего не проверяет»: подсовываем
        # ровно ту строку, из-за которой игра не запускалась, и требуем, чтобы
        # проверка её нашла.
        broken = (
            'var bounds: Rect2 = Rect2()\n'
            'func _build_to() -> void:\n'
            '\tbounds = bounds.expand(Vector3(1.0, 0.0, 2.0))\n'
        )
        found = gdtype_check.check_file(broken)
        self.assertEqual(len(found), 1, 'проверка типов не видит ошибку разбора')
        self.assertEqual(found[0][1], 'expand')
        self.assertEqual(found[0][2], 'Vector3')

    def test_type_check_does_not_blame_correct_code(self):
        # Ложные падения хуже пропусков: на них перестают смотреть. AABB
        # трёхмерный, три-в-три — это правильно, и ругаться нельзя.
        correct = (
            'func _build() -> void:\n'
            '\tvar box: AABB = AABB(Vector3.ZERO, Vector3.ONE)\n'
            '\tbox = box.merge(Vector3.ONE)\n'
            '\tvar a: Vector3 = Vector3.ZERO\n'
            '\tvar b: Vector3 = Vector3.ONE\n'
            '\tvar d: float = a.distance_to(b)\n'
        )
        self.assertEqual(gdtype_check.check_file(correct), [])


if __name__ == '__main__':
    unittest.main()
