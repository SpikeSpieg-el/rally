"""Запекание звуковых ассетов для ралли-игры.

Всё считается с нуля по физической модели (см. engine_audio_model.py), так что
никаких сторонних записей в репозитории не появляется — только сгенерированные
 WAV-файлы, которые можно свободно публиковать.

Что получается на выходе:

  audio/engine/engine_<об/мин>_<режим>.wav        — лупы двигателя Mitsubishi 4G63T
        («light» — сброс газа/холостые, «full» — полный газ), сетка по оборотам;
  audio/engine/subaru/engine_<об/мин>_<режим>.wav — те же режимы для оппозитного
        Subaru EJ25: другой порядок вспышек, длинный «плоский» выпуск, свой тембр;
  audio/engine/golf/engine_<об/мин>_<режим>.wav   — атмосферный VW VR6 3.2
        (Golf R32): шесть цилиндров, rpm/20 вместо rpm/30, без турбины;
  audio/vehicle/gravel_road.wav               — шорох гравия под колёсами (луп);
  audio/vehicle/wind.wav                      — шум ветра (луп);
  audio/vehicle/bov_*.wav                     — сброс давления турбины;
  audio/vehicle/pop_*.wav                     — хлопки на сбросе газа;
  audio/vehicle/shift.wav                     — переключение передачи;
  audio/vehicle/start.wav                     — запуск двигателя;
  audio/vehicle/golf/*.wav                    — запуск и переключение VR6
        (сброса турбины и хлопков у атмосферника нет).

Запуск:
    python3 tools/render_engine_audio.py                 # всё
    python3 tools/render_engine_audio.py --rpm-grid 900 1250 1600
    python3 tools/render_engine_audio.py --only vehicle
    python3 tools/render_engine_audio.py --only subaru     # только банк Subaru
    python3 tools/render_engine_audio.py --only golf       # только банк VR6
"""
from __future__ import annotations

import argparse
import hashlib
import math
import os
import struct
import sys
import wave

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import engine_audio_model as m  # noqa: E402
import godot_import  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ENGINE_DIR = os.path.join(ROOT, "audio", "engine")
# Второй двигатель игры живёт в подпапке: сетка оборотов у него своя
# (отсечка 6800 вместо 7600), а имена файлов — те же, что у Mitsubishi.
SUBARU_DIR = os.path.join(ENGINE_DIR, "subaru")
VEHICLE_DIR = os.path.join(ROOT, "audio", "vehicle")
# Одиночные звуки боксера тоже свои: у Subaru ниже сброс турбины, глуше
# хлопок в выхлопе и тяжелее ход кулисы, потому что выхлоп длиннее и
# «плоский», а коробка — с тяжёлым механизмом переключения.
SUBARU_VEHICLE_DIR = os.path.join(VEHICLE_DIR, "subaru")

SR = 32000
# Сетка оборотов — логарифмическая: шаг в октавах одинаков, поэтому тон
# меняется равномерно и питч-коррекция не упирается в предел на малых
# оборотах. Должна совпадать с RPM_GRID в scripts/engine_sound.gd.
RPM_GRID = [900, 970, 1050, 1130, 1220, 1320, 1430, 1540, 1670, 1800, 1940,
            2100, 2270, 2450, 2640, 2850, 3080, 3330, 3600, 3880, 4190, 4530,
            4890, 5280, 5710, 6160, 6660, 7190, 7600]
# Сетка оборотов Subaru EJ25: отсечка 6800, поэтому верхняя точка ниже, а
# ступени те же ~8 %. Должна совпадать с engine_rpm_grid в
# data/vehicles/subaru.tres — именно оттуда рантайм берёт сетку.
SUBARU_RPM_GRID = [800, 865, 935, 1010, 1095, 1185, 1285, 1390, 1505, 1630, 1765,
                   1910, 2070, 2240, 2425, 2625, 2845, 3080, 3335, 3610, 3910,
                   4235, 4585, 4965, 5375, 5820, 6300, 6800]
# Третий мотор игры — атмосферный VW VR6 3.2 (Golf R32 Mk4). Банк живёт в
# своей подпапке: холостые 750 и отсечка 6500, шаг сетки тот же ~8 %.
GOLF_DIR = os.path.join(ENGINE_DIR, "golf")
# События VR6 тоже свои: запуск и переключение. Сброса турбины и хлопков у
# атмосферника нет, поэтому bov_* и pop_* в эту папку не запекаются.
GOLF_VEHICLE_DIR = os.path.join(VEHICLE_DIR, "golf")
# Сетка должна совпадать с engine_rpm_grid в data/vehicles/golf.tres — именно
# оттуда рантайм берёт обороты лупов.
GOLF_RPM_GRID = [750, 812, 880, 953, 1033, 1119, 1212, 1313, 1422, 1541, 1669,
                 1808, 1958, 2121, 2298, 2489, 2697, 2921, 3164, 3428, 3713,
                 4023, 4357, 4720, 5113, 5539, 6000, 6500]
LOOP_SECONDS = 1.0


# ---------------------------------------------------------------------------
# Запись WAV
# ---------------------------------------------------------------------------


def write_wav(path: str, data: np.ndarray, sr: int = SR, loop: bool = True) -> None:
    """Записывает моно-WAV. Для лупов добавляет блок smpl с точками зацикливания.

    Блок smpl нужен, чтобы Godot (и любой другой плеер) понял, где кончается
    луп: при импорте он выставляет loop_begin/loop_end по этим данным.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    peak = float(np.max(np.abs(data))) if data.size else 0.0
    if peak > 0.999:
        data = data / peak * 0.999
    pcm = np.clip(data * 32767.0, -32768, 32767).astype("<i2")
    frames = pcm.size
    raw = pcm.tobytes()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(raw)
    if loop:
        _append_smpl(path, frames, sr)


def _append_smpl(path: str, frames: int, sr: int) -> None:
    """Дописывает в конец WAV блок smpl с бесконечным циклом по всему файлу."""
    with open(path, "rb") as f:
        content = f.read()
    if b"smpl" in content[:64]:
        return
    sample_period = int(round(1_000_000_000.0 / float(sr)))
    chunk = struct.pack(
        "<4sIIIIIIIIII",
        b"smpl",
        60,                     # размер блока: 9 полей + один цикл
        0,                      # manufacturer
        0,                      # product
        sample_period,
        60,                     # midi unity note
        0,                      # midi pitch fraction
        0,                      # smpte format
        0,                      # smpte offset
        1,                      # число циклов
        0,                      # сэмплы в цикле с дробной частью
    )
    # Один цикл: cue id, тип (0 = вперёд), начало, конец, дробная часть,
    # число повторов (0 = бесконечно).
    chunk += struct.pack("<IIIIII", 0, 0, 0, frames, 0, 0)
    body = content + chunk
    # Поправить размер RIFF: он должен учитывать добавленный блок.
    body = body[:4] + struct.pack("<I", len(body) - 8) + body[8:]
    with open(path, "wb") as f:
        f.write(body)


def write_import_file(path: str) -> str:
    """Создаёт .import рядом с WAV — как это делает сам Godot.

    Формат и точки зацикливания описаны в tools/godot_import.py.
    """
    return godot_import.write_import_file(path, ROOT,
                                           loop=godot_import.is_loop_asset(path))


def loopify(data: np.ndarray, loop_len: int, sr: int = SR) -> np.ndarray:
    """Готовит сигнал к бесшовному воспроизведению (тот же приём, что в модели)."""
    return m._make_seamless(data, min(loop_len, data.size), sr)


# ---------------------------------------------------------------------------
# Лупы двигателя
# ---------------------------------------------------------------------------


def render_bank(rpm: int, load: float, seed: int,
                engine: str = "mitsubishi") -> np.ndarray:
    """Один луп двигателя. `engine` выбирает физическую модель мотора."""
    params = m.RenderParams(sr=SR, duration=LOOP_SECONDS, seed=seed)
    if engine == "subaru":
        # Оппозит: своя геометрия выпуска и стабильный «бокс» на холостых.
        params.spec = m.subaru_ej25()
        # Боксеры гремят на холостых заметнее рядных четвёрок.
        params.idle_lope = 0.016
        # Мягче глушитель: длинная трасса сама убирает верх, срез ставим ниже.
        params.muffler_hz = 4600.0
        params.muffler_hz_load = 2300.0
        # Меньше «цыканья» клапанов — у боксера оно глуше и тише.
        params.valvetrain_level = 0.130
        params.valvetrain_gain = 0.80
        params.turbo_gain = 0.85
        # Подчёркиваем низ: у оппозита «утробный» кузовной резонанс.
        params.exhaust_gain = 1.10
        params.intake_gain = 0.85
    elif engine == "golf":
        # Атмосферный VR6 3.2: шесть цилиндров, порядок 1-2-3-4-5-6, без турбины.
        params.spec = m.vw_vr6()
        # Шесть цилиндров держат холостые ровнее четвёрки — «лоп» почти нет.
        params.idle_lope = 0.006
        # Выпуск короче субаровского, верх срезаем позже: VR6 звонче на верхах.
        params.muffler_hz = 4900.0
        params.muffler_hz_load = 2450.0
        # 24 клапана и цепной привод ГРМ: механизм слышнее, чем у боксера.
        params.valvetrain_level = 0.190
        params.valvetrain_gain = 0.95
        # Турбины нет — слой свиста молчит (max_boost_bar = 0 дублирует это).
        params.turbo_gain = 0.0
        # Индукция у атмосферника — второй голос мотора после выхлопа.
        params.exhaust_gain = 1.0
        params.intake_gain = 1.05
    else:
        params.spec = m.EngineSpec()
    if load < 0.5:
        # Холостые/сброс газа: звук мягче, труба «глуше», слышны хлопки.
        params.decay_load = params.decay_idle
        params.decay_idle = 0.030
        params.overrun = 1.0
        params.idle_lope = max(params.idle_lope, 0.011)
        params.valvetrain_level = min(params.valvetrain_level, 0.150)
        if engine == "golf":
            # Ровные холостые шести цилиндров: перебор «лопа» не нужен, а хлопки
            # у атмосферника тихие и редкие.
            params.idle_lope = min(params.idle_lope, 0.008)
            params.overrun = 0.5
    else:
        params.overrun = 0.0
        params.idle_lope = min(params.idle_lope, 0.003)
    loop, _ = m.render_engine(rpm, load, params)
    return m.normalize(loop)


def _write_engine_loop(directory: str, rpm: int, name: str,
                       engine: str) -> tuple:
    data = render_bank(rpm, 1.0 if name == "full" else 0.12,
                       seed=rpm * 7 + (0 if name == "light" else 3), engine=engine)
    path = os.path.join(directory, "engine_%04d_%s.wav" % (rpm, name))
    write_wav(path, data)
    write_import_file(path)
    print("  %-38s %6.2f с" % (os.path.relpath(path, ROOT), data.size / SR))
    return path, data


def build_engine_bank(rpm_grid: list, engine: str = "mitsubishi",
                      directory: str = ENGINE_DIR) -> list:
    written = []
    for rpm in rpm_grid:
        for name in ("light", "full"):
            written.append(_write_engine_loop(directory, rpm, name, engine))
    return written


# ---------------------------------------------------------------------------
# Шум дороги и ветра
# ---------------------------------------------------------------------------


def gravel_road(seed: int = 11, seconds: float = 2.0) -> np.ndarray:
    """Шорох гравия: широкий шум с редкими «ударами» отдельных камней."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    body = m.biquad(noise, m.bandpass_sos(700.0, 0.7, SR))
    body = m.biquad(body, m.highpass_sos(120.0, SR))
    rumble = m.biquad(rng.standard_normal(n), m.lowpass_sos(180.0, SR))

    # Камешки: короткие щелчки со случайным интервалом.
    stones = np.zeros(n)
    pos = 0
    while pos < n - 64:
        pos += int(rng.uniform(0.004, 0.09) * SR)
        length = int(rng.uniform(0.002, 0.010) * SR)
        length = min(length, n - pos)
        if length <= 1:
            break
        env = np.exp(-np.arange(length) / max(1.0, length * 0.3))
        burst = rng.standard_normal(length) * env
        burst = m.biquad(burst, m.bandpass_sos(rng.uniform(900.0, 3500.0), 2.0, SR))
        stones[pos:pos + length] += burst * rng.uniform(0.2, 1.0)

    mix = body * 0.55 + rumble * 0.5 + stones * 0.5
    return m.normalize(loopify(mix, n))


def wind(seconds: float = 2.0, seed: int = 23) -> np.ndarray:
    """Шум ветра: медленно плывущий низкочастотный шум."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    low = m.biquad(noise, m.lowpass_sos(500.0, SR, order=2))
    mid = m.biquad(noise, m.bandpass_sos(900.0, 0.6, SR))
    # Медленная модуляция «порывов».
    t = np.arange(n) / SR
    gust = 0.65 + 0.35 * np.sin(2.0 * math.pi * 0.23 * t + 1.1)
    gust *= 0.75 + 0.25 * np.sin(2.0 * math.pi * 0.07 * t)
    mix = (low * 0.9 + mid * 0.25) * gust
    return m.normalize(loopify(mix, n))


# ---------------------------------------------------------------------------
# Одиночные звуки
# ---------------------------------------------------------------------------


def blow_off(seed: int = 31, seconds: float = 0.55,
             center_hz: tuple = (2600.0, 3400.0), decay: float = 0.16,
             click_hz: float = 900.0, fall: float = 0.985) -> np.ndarray:
    """Сброс давления турбины: широкополосный «пшшш» с падающей частотой.

    Параметры задают характер конкретного мотора: у боксера фильтр ниже и
    падает быстрее, поэтому сброс звучит коротко и глухо, а не звонко.
    """
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    # Фильтр «ползёт» вниз — так слышно, как сбрасывается давление.
    out = np.zeros(n)
    step = 64
    center = rng.uniform(center_hz[0], center_hz[1])
    for i in range(0, n, step):
        end = min(n, i + step)
        block = noise[i:end]
        center *= fall
        out[i:end] = m.biquad(block, m.bandpass_sos(max(center, 350.0), 1.1, SR))
    env = np.exp(-t / decay) * (1.0 - np.exp(-t / 0.004))
    out *= env
    # Лёгкий «хлопок» клапана в начале.
    click = np.exp(-t / 0.006) * np.sin(2.0 * math.pi * click_hz * t)
    out += click * 0.25
    return m.normalize(out)


def pop(seed: int = 41, seconds: float = 0.22,
        band_hz: tuple = (600.0, 1800.0), thump_hz: tuple = (150.0, 320.0),
        tail: float = 0.16) -> np.ndarray:
    """Хлопок на сбросе газа: резкий короткий «пук».

    Длинный «плоский» выпуск боксера режет верх и удлиняет хвост, поэтому
    хлопок ниже и толще, чем у рядной четвёрки.
    """
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    length = int(rng.uniform(0.02, 0.09) * SR)
    env = np.zeros(n)
    env[:length] = np.exp(-np.arange(length) / max(1.0, length * tail))
    out = m.biquad(noise, m.bandpass_sos(rng.uniform(band_hz[0], band_hz[1]), 1.4, SR))
    out *= env
    out += np.exp(-t / 0.004) * np.sin(
        2.0 * math.pi * rng.uniform(thump_hz[0], thump_hz[1]) * t) * 0.35
    return m.normalize(out)


def gear_shift(seed: int = 53, seconds: float = 0.30,
               band_hz: tuple = (1800.0, 3200.0), thud_hz: tuple = (110.0, 190.0),
               thud_gain: float = 0.5, body_decay: float = 0.035) -> np.ndarray:
    """Лязг переключения передачи: сухой металлический стук."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    body = m.biquad(noise, m.bandpass_sos(rng.uniform(band_hz[0], band_hz[1]), 2.2, SR))
    env = np.exp(-t / body_decay)
    low = np.exp(-t / 0.02) * np.sin(2.0 * math.pi * rng.uniform(thud_hz[0], thud_hz[1]) * t)
    out = body * env * 0.8 + low * thud_gain
    return m.normalize(out)


def engine_start(seed: int = 67, seconds: float = 1.6,
                 engine: str = "mitsubishi") -> np.ndarray:
    """Запуск двигателя: прокрутка стартером и первый «выстрел».

    У боксера неровная прокрутка (цилиндры в два ряда) и «утробный» первый
    выстрел, поэтому стартер крутится с биением, а вспышки идут по своей
    сетке оборотов Subaru. У VR6 шесть цилиндров: стартер тянет ровнее,
    а первые вспышки идут выше по тону (rpm/20 против rpm/30).
    """
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)  # noqa: F841 (сид для воспроизводимости)
    out = np.zeros(n)
    is_boxer = engine == "subaru"
    is_vr6 = engine == "golf"
    if is_boxer:
        spec = m.SUBARU_EJ25
    elif is_vr6:
        spec = m.VW_VR6_32
    else:
        spec = m.EngineSpec()
    idle_rpm = spec.idle_rpm
    lope = 0.024 if is_boxer else (0.010 if is_vr6 else 0.014)
    rumble_hz = 32.0 if is_boxer else 0.0
    crank_gain = 240.0 if is_boxer else (250.0 if is_vr6 else 260.0)
    crank_level = 0.42 if is_boxer else (0.38 if is_vr6 else 0.35)
    fire_level = 0.9 if is_boxer else (0.85 if is_vr6 else 0.8)

    # Вой стартера: нарастающий писк с пульсацией.
    t = np.arange(n) / SR
    crank = np.zeros(n)
    for i in range(n):
        crank_rpm = 200.0 + crank_gain * min(1.0, t[i] / 0.55)
        wobble = 1.0 + (0.18 * math.sin(2.0 * math.pi * rumble_hz * t[i] / 4.0)
                        if is_boxer else 0.0)
        crank[i] = (math.sin(2.0 * math.pi * crank_rpm / 30.0 * t[i])
                    * (0.25 + 0.55 * min(1.0, t[i] / 0.6)) * wobble)
    crank *= (t < 0.75).astype(np.float64)
    out += crank * crank_level

    # Старт: вспышки на холостых.
    params = m.RenderParams(sr=SR, duration=0.8, seed=seed)
    params.spec = spec
    params.decay_load = params.decay_idle
    params.decay_idle = 0.030
    params.idle_lope = lope
    loop, _ = m.render_engine(idle_rpm, 0.25, params)
    loop = m.normalize(loop)
    start = int(0.62 * SR)
    seg = min(loop.size, n - start)
    out[start:start + seg] += loop[:seg] * fire_level
    return m.normalize(out)


# ---------------------------------------------------------------------------
# Голоса одиночных звуков по моторам
# ---------------------------------------------------------------------------

# У каждого мотора своя «механика»: у боксера глуше и длиннее, у рядной
# четвёрки звонче и резче. VR6 — посередине по тембру, но без турбины, поэтому
# у него нет ни сброса давления, ни хлопков: `bov_seeds` пустой и `pops = 0`.
# Сиды намеренно разные: одинаковый сид дал бы одинаковые файлы, и машины
# зазвучали бы как клоны.
VEHICLE_PROFILES = {
    "mitsubishi": {
        "bov_seeds": (31, 32, 33),
        "bov_center": (2600.0, 3400.0),
        "bov_decay": 0.16,
        "bov_click": 900.0,
        "bov_fall": 0.985,
        "pops": 6,
        "pop_seed": 41,
        "pop_band": (600.0, 1800.0),
        "pop_thump": (150.0, 320.0),
        "pop_tail": 0.16,
        "shift_seed": 53,
        "shift_band": (1800.0, 3200.0),
        "shift_thud": (110.0, 190.0),
        "shift_thud_gain": 0.5,
        "shift_decay": 0.035,
        "start_seed": 67,
        # Базовая папка audio/vehicle/ хранит общие лупы дороги и ветра.
        "shared_loops": True,
    },
    "subaru": {
        "bov_seeds": (231, 232, 233),
        "bov_center": (1750.0, 2350.0),
        "bov_decay": 0.21,
        "bov_click": 620.0,
        "bov_fall": 0.978,
        "pops": 6,
        "pop_seed": 241,
        "pop_band": (420.0, 1250.0),
        "pop_thump": (105.0, 240.0),
        "pop_tail": 0.24,
        "shift_seed": 253,
        "shift_band": (1150.0, 2300.0),
        "shift_thud": (85.0, 150.0),
        "shift_thud_gain": 0.72,
        "shift_decay": 0.05,
        "start_seed": 267,
        "shared_loops": False,
    },
    "golf": {
        # Атмосферник: сброса турбины нет.
        "bov_seeds": (),
        "bov_center": (1900.0, 2700.0),
        "bov_decay": 0.18,
        "bov_click": 760.0,
        "bov_fall": 0.982,
        # Хлопков на сбросе газа у атмосферного VR6 тоже нет.
        "pops": 0,
        "pop_seed": 341,
        "pop_band": (520.0, 1500.0),
        "pop_thump": (130.0, 280.0),
        "pop_tail": 0.20,
        # Короткоходная кулиса VR6: лязг суше и выше, чем у боксера.
        "shift_seed": 353,
        "shift_band": (1500.0, 2700.0),
        "shift_thud": (95.0, 170.0),
        "shift_thud_gain": 0.6,
        "shift_decay": 0.042,
        "start_seed": 367,
        "shared_loops": False,
    },
}


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def build_vehicle(engine: str = "mitsubishi",
                  directory: str = VEHICLE_DIR) -> list:
    """Одиночные звуки мотора: шины и ветер общие, события — свои у каждого.

    Третий элемент — луп ли это. Одиночные звуки (хлопки, сброс турбины,
    переключение передачи, запуск) зацикливать нельзя: Godot читает блок
    smpl при импорте, и такой звук потом повторялся бы бесконечно.

    У атмосферного VR6 (Golf) нет ни турбины, ни хлопков: bov_* и pop_* в его
    папку не запекаются, рантайм их и не ищет — `engine_sound.gd` играет
    хлопок только при `turbo = true` в активном сетапе и спокойно живёт с
    пустыми списками. Остаются переключение и запуск.
    """
    written = []
    profile = VEHICLE_PROFILES[engine]
    jobs = []
    for i, seed in enumerate(profile["bov_seeds"]):
        jobs.append(("bov_%02d.wav" % (i + 1),
                     blow_off(seed=seed,
                              center_hz=profile["bov_center"],
                              decay=profile["bov_decay"],
                              click_hz=profile["bov_click"],
                              fall=profile["bov_fall"]), False))
    for i in range(profile["pops"]):
        jobs.append(("pop_%02d.wav" % (i + 1),
                     pop(seed=profile["pop_seed"] + i,
                         band_hz=profile["pop_band"],
                         thump_hz=profile["pop_thump"],
                         tail=profile["pop_tail"]), False))
    jobs.append(("shift.wav", gear_shift(seed=profile["shift_seed"],
                                        band_hz=profile["shift_band"],
                                        thud_hz=profile["shift_thud"],
                                        thud_gain=profile["shift_thud_gain"],
                                        body_decay=profile["shift_decay"]), False))
    jobs.append(("start.wav", engine_start(seed=profile["start_seed"],
                                           engine=engine), False))
    if profile["shared_loops"]:
        # Шум дороги и ветра не принадлежат мотору: они общие для всех машин,
        # лежат в базовой audio/vehicle/ и туда же их грузит engine_sound.gd.
        jobs = [("gravel_road.wav", gravel_road(), True),
                ("wind.wav", wind(), True)] + jobs
    for name, data, loop in jobs:
        path = os.path.join(directory, name)
        write_wav(path, data, loop=loop)
        write_import_file(path)
        written.append(path)
        print("  %-34s %6.2f с" % (os.path.relpath(path, ROOT), data.size / SR))
    return written


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpm-grid", type=int, nargs="*", default=RPM_GRID)
    ap.add_argument("--only", choices=["engine", "subaru", "golf", "vehicle"],
                    default=None)
    args = ap.parse_args()

    if args.only in (None, "engine"):
        print("Лупы двигателя Mitsubishi 4G63T:")
        build_engine_bank(args.rpm_grid)
    if args.only in (None, "subaru"):
        print("Лупы двигателя Subaru EJ25 (боксер):")
        build_engine_bank(SUBARU_RPM_GRID, engine="subaru", directory=SUBARU_DIR)
    if args.only in (None, "golf"):
        print("Лупы двигателя VW VR6 3.2 (Golf R32):")
        build_engine_bank(GOLF_RPM_GRID, engine="golf", directory=GOLF_DIR)
    if args.only in (None, "vehicle"):
        print("Звуки машины Mitsubishi:")
        build_vehicle()
        print("Звуки машины Subaru:")
        build_vehicle(engine="subaru", directory=SUBARU_VEHICLE_DIR)
        print("Звуки машины Volkswagen (VR6, атмосферник):")
        build_vehicle(engine="golf", directory=GOLF_VEHICLE_DIR)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
