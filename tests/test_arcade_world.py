"""Аркадный мир: проверка рельефа, обстановки, атмосферы, шейдеров и HUD.

Запуск: python3 -m unittest tests.test_arcade_world
"""
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
sys.path.insert(0, str(ROOT / 'tests'))
import gdtype_check

TERRAIN = ROOT / 'scripts/arcade/arcade_terrain.gd'
SCENERY = ROOT / 'scripts/arcade/arcade_scenery.gd'
TRAFFIC = ROOT / 'scripts/arcade/arcade_traffic.gd'
PEDESTRIANS = ROOT / 'scripts/arcade/arcade_pedestrians.gd'
RULES = ROOT / 'scripts/arcade/arcade_rules.gd'
SETTINGS_SCRIPT = ROOT / 'scripts/data/rally_arcade_settings.gd'
SETTINGS_RES = ROOT / 'data/stage/default_arcade_settings.tres'
SCENE = ROOT / 'scenes/rally_arcade.tscn'
STAGE = ROOT / 'scripts/arcade/arcade_stage.gd'
CHUNK = ROOT / 'scripts/arcade/arcade_chunk.gd'
STREAMER = ROOT / 'scripts/arcade/arcade_streamer.gd'
TRACK = ROOT / 'data/tracks/stage_arcade.tres'


def _text(path):
    return path.read_text(encoding='utf-8')


class ArcadeWorldTest(unittest.TestCase):
    def test_terrain_and_scenery_scripts_exist(self):
        self.assertTrue(TERRAIN.exists(), 'нет scripts/arcade/arcade_terrain.gd')
        self.assertTrue(SCENERY.exists(), 'нет scripts/arcade/arcade_scenery.gd')
        self.assertTrue(TRAFFIC.exists(), 'нет scripts/arcade/arcade_traffic.gd')
        self.assertTrue(PEDESTRIANS.exists(), 'нет scripts/arcade/arcade_pedestrians.gd')
        self.assertTrue(RULES.exists(), 'нет scripts/arcade/arcade_rules.gd')
        self.assertTrue(SETTINGS_SCRIPT.exists(), 'нет scripts/data/rally_arcade_settings.gd')
        self.assertTrue(SETTINGS_RES.exists(), 'нет data/stage/default_arcade_settings.tres')

    def test_scene_and_inspector_settings_are_authored(self):
        scene_text = _text(SCENE)
        for required in (
            'default_arcade_settings.tres',
            '[node name="ArcadeTraffic"',
            '[node name="ArcadePedestrians"',
            '[node name="ArcadeStatusPanel"',
            'arcade_settings =',
        ):
            self.assertIn(required, scene_text, f'в scenes/rally_arcade.tscn нет редактируемого элемента {required}')
        cfg_text = _text(SETTINGS_SCRIPT)
        self.assertIn('@tool', cfg_text)
        self.assertIn('class_name RallyArcadeSettings', cfg_text)
        for group in ('Трафик', 'Пешеходы и переходы', 'Очки и прочность (HP)'):
            self.assertIn(group, cfg_text)

    def test_pedestrians_rules_and_leaderboard_contracts(self):
        ped_text = _text(PEDESTRIANS)
        self.assertIn('spectator_person.tscn', ped_text)
        self.assertIn('pedestrian_hit', ped_text)
        self.assertIn('crosswalk_courtesy', ped_text)
        self.assertTrue((ROOT / 'scenes/props/spectator_person.tscn').exists())

        rules_text = _text(RULES)
        for required in ('MAX_HP', 'on_traffic_event', 'on_pedestrian_event', 'record_run', 'load_leaderboard'):
            self.assertIn(required, rules_text, f'arcade_rules.gd не содержит {required}')

        stage_text = _text(STAGE)
        for required in (
            'PedestriansType',
            'RulesType',
            '_end_arcade_run',
            'ArcadeStatusPanel',
            'surface_height_at',
            'ResultsPanel/Box/AgainButton',
        ):
            self.assertIn(required, stage_text, f'arcade_stage.gd не интегрирует {required}')

    def test_traffic_system_contracts(self):
        traffic_text = _text(TRAFFIC)
        for required in (
            'AnimatableBody3D',
            'collision_layer = 2',
            'sync_to_physics = true',
            '_compute_yield_offset',
            '_nearest_ahead_gap',
            '_player_hazard_speed',
            'SpotLight3D',
        ):
            self.assertIn(required, traffic_text, f'arcade_traffic.gd не содержит {required}')
        stage_text = _text(STAGE)
        self.assertIn('TrafficType', stage_text)
        self.assertIn('_traffic.process_mode = Node.PROCESS_MODE_PAUSABLE', stage_text)
        self.assertIn('_traffic.step(', stage_text)
        road_text = _text(ROOT / 'scripts/arcade/arcade_road.gd')
        hw = float(re.search(r'const DEFAULT_HALF_WIDTH: float = ([\d.]+)', road_text).group(1))
        self.assertGreaterEqual(hw, 4.5, 'двухполосная дорога должна вмещать две машины шириной 2.3 м')

    def test_scenery_asset_paths_exist(self):
        text = _text(SCENERY)
        paths = re.findall(r'"(res://[^"]+)"', text)
        self.assertGreater(len(paths), 20, 'слишком мало ассетов в arcade_scenery.gd')
        for res_path in paths:
            disk = ROOT / res_path.removeprefix('res://')
            self.assertTrue(disk.exists(), f'отсутствует ресурс в arcade_scenery.gd: {res_path}')

    def test_terrain_covers_horizon_beyond_fog_and_uses_grass_group(self):
        text = _text(TERRAIN)
        load_r = float(re.search(r'const LOAD_RADIUS: float = ([\d.]+)', text).group(1))
        track_text = _text(TRACK)
        fog_far = float(re.search(r'fog_far = ([\d.]+)', track_text).group(1))
        self.assertGreater(load_r, fog_far, 'радиус тайлов рельефа должен выходить за fog_far')
        self.assertIn('add_to_group("Grass")', text)
        self.assertIn('ROAD_CELL_SIZE: float = 96.0', text)

    def test_stage_configures_atmosphere_weather_and_shaders(self):
        text = _text(STAGE)
        for required in (
            '_configure_world',
            '_setup_precipitation',
            'NightSkyShader',
            'ProceduralSkyMaterial',
            'resolve_night_choice',
            'ps1_textures',
            'wetness',
            'snow_cover',
            'rock_color',
            'flat_shading',
            'section_surfaces',
        ):
            self.assertIn(required, text, f'arcade_stage.gd не настраивает {required}')

    def test_stage_updates_full_hud_and_pause(self):
        text = _text(STAGE)
        for required in (
            'StageTitle',
            'update_timer_display',
            'SplitLabel',
            'SetupLabel',
            'EngineLabel',
            'RPMBar',
            'ThrottleBar',
            'ControlsButton',
            'CameraOptions',
        ):
            self.assertIn(required, text, f'arcade_stage.gd не обновляет/не связывает {required}')

    def test_verge_skirt_does_not_overlap_hairpins(self):
        text = _text(CHUNK)
        verge_w = float(re.search(r'const VERGE_WIDTH: float = ([\d.]+)', text).group(1))
        self.assertLessEqual(verge_w, 10.0, 'VERGE_WIDTH слишком велик и налезет на встречный виток шпильки')
        self.assertIn('bridge_deck_factor', text)

    def test_new_scripts_pass_gdtype_check(self):
        for path in (TERRAIN, SCENERY, TRAFFIC, PEDESTRIANS, RULES, SETTINGS_SCRIPT, STAGE, CHUNK, STREAMER):
            issues = gdtype_check.check_file(_text(path))
            self.assertEqual(issues, [], f'ошибки типов в {path.name}: {issues}')


if __name__ == '__main__':
    unittest.main()
