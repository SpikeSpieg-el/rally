"""Запекание звуковых ассетов для ралли-игры.

Всё считается с нуля по физической модели (см. engine_audio_model.py), так что
никаких сторонних записей в репозитории не появляется — только сгенерированные
 WAV-файлы, которые можно свободно публиковать.

Что получается на выходе:

  audio/engine/engine_<об/мин>_<режим>.wav  — лупы двигателя Mitsubishi 4G63T
        («light» — сброс газа/холостые, «full» — полный газ), сетка по оборотам;
  audio/vehicle/gravel_road.wav               — шорох гравия под колёсами (луп);
  audio/vehicle/wind.wav                      — шум ветра (луп);
  audio/vehicle/bov_*.wav                     — сброс давления турбины;
  audio/vehicle/pop_*.wav                     — хлопки на сбросе газа;
  audio/vehicle/shift.wav                     — переключение передачи;
  audio/vehicle/start.wav                     — запуск двигателя.

Запуск:
    python3 tools/render_engine_audio.py                 # всё
    python3 tools/render_engine_audio.py --rpm-grid 900 1250 1600
    python3 tools/render_engine_audio.py --only vehicle
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
VEHICLE_DIR = os.path.join(ROOT, "audio", "vehicle")

SR = 32000
# Сетка оборотов — логарифмическая: шаг в октавах одинаков, поэтому тон
# меняется равномерно и питч-коррекция не упирается в предел на малых
# оборотах. Должна совпадать с RPM_GRID в scripts/engine_sound.gd.
RPM_GRID = [900, 970, 1050, 1130, 1220, 1320, 1430, 1540, 1670, 1800, 1940,
            2100, 2270, 2450, 2640, 2850, 3080, 3330, 3600, 3880, 4190, 4530,
            4890, 5280, 5710, 6160, 6660, 7190, 7600]
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


def render_bank(rpm: int, load: float, seed: int) -> np.ndarray:
    params = m.RenderParams(sr=SR, duration=LOOP_SECONDS, seed=seed)
    spec = m.EngineSpec()
    params.spec = spec
    if load < 0.5:
        # Холостые/сброс газа: звук мягче, труба «глуше», слышны хлопки.
        params.decay_load = params.decay_idle
        params.decay_idle = 0.030
        params.overrun = 1.0
        params.idle_lope = 0.011
        params.valvetrain_level = 0.150
    else:
        params.overrun = 0.0
        params.idle_lope = 0.003
    loop, _ = m.render_engine(rpm, load, params)
    return m.normalize(loop)


def build_engine_bank(rpm_grid: list) -> list:
    written = []
    for rpm in rpm_grid:
        for load, name in ((0.12, "light"), (1.0, "full")):
            # Сид зависит от оборотов: каждый луп свой, но воспроизводимый.
            data = render_bank(rpm, load, seed=rpm * 7 + (0 if name == "light" else 3))
            path = os.path.join(ENGINE_DIR, "engine_%04d_%s.wav" % (rpm, name))
            write_wav(path, data)
            write_import_file(path)
            written.append((path, data))
            print("  %-34s %6.2f с" % (os.path.relpath(path, ROOT), data.size / SR))
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


def blow_off(seed: int = 31, seconds: float = 0.55) -> np.ndarray:
    """Сброс давления турбины: широкополосный «пшшш» с падающей частотой."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    # Фильтр «ползёт» вниз — так слышно, как сбрасывается давление.
    out = np.zeros(n)
    step = 64
    center = rng.uniform(2600.0, 3400.0)
    for i in range(0, n, step):
        end = min(n, i + step)
        block = noise[i:end]
        center *= 0.985
        out[i:end] = m.biquad(block, m.bandpass_sos(max(center, 350.0), 1.1, SR))
    env = np.exp(-t / 0.16) * (1.0 - np.exp(-t / 0.004))
    out *= env
    # Лёгкий «хлопок» клапана в начале.
    click = np.exp(-t / 0.006) * np.sin(2.0 * math.pi * 900.0 * t)
    out += click * 0.25
    return m.normalize(out)


def pop(seed: int = 41, seconds: float = 0.22) -> np.ndarray:
    """Хлопок на сбросе газа: резкий короткий «пук»."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    length = int(rng.uniform(0.02, 0.09) * SR)
    env = np.zeros(n)
    env[:length] = np.exp(-np.arange(length) / max(1.0, length * 0.16))
    out = m.biquad(noise, m.bandpass_sos(rng.uniform(600.0, 1800.0), 1.4, SR))
    out *= env
    out += np.exp(-t / 0.004) * np.sin(2.0 * math.pi * rng.uniform(150.0, 320.0) * t) * 0.35
    return m.normalize(out)


def gear_shift(seed: int = 53, seconds: float = 0.30) -> np.ndarray:
    """Лязг переключения передачи: сухой металлический стук."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    t = np.arange(n) / SR
    body = m.biquad(noise, m.bandpass_sos(rng.uniform(1800.0, 3200.0), 2.2, SR))
    env = np.exp(-t / 0.035)
    low = np.exp(-t / 0.02) * np.sin(2.0 * math.pi * rng.uniform(110.0, 190.0) * t)
    out = body * env * 0.8 + low * 0.5
    return m.normalize(out)


def engine_start(seed: int = 67, seconds: float = 1.6) -> np.ndarray:
    """Запуск двигателя: прокрутка стартером и первый «выстрел»."""
    n = int(seconds * SR)
    rng = np.random.default_rng(seed)
    out = np.zeros(n)

    # Вой стартера: нарастающий писк с пульсацией.
    t = np.arange(n) / SR
    crank = np.zeros(n)
    for i in range(n):
        rpm = 220.0 + 260.0 * min(1.0, t[i] / 0.55)
        crank[i] = math.sin(2.0 * math.pi * rpm / 30.0 * t[i]) * (0.25 + 0.55 * min(1.0, t[i] / 0.6))
    crank *= (t < 0.75).astype(np.float64)
    out += crank * 0.35

    # Старт: вспышки на холостых.
    params = m.RenderParams(sr=SR, duration=0.8, seed=seed)
    params.spec = m.EngineSpec()
    params.decay_load = params.decay_idle
    params.decay_idle = 0.030
    params.idle_lope = 0.014
    loop, _ = m.render_engine(900, 0.25, params)
    loop = m.normalize(loop)
    start = int(0.62 * SR)
    seg = min(loop.size, n - start)
    out[start:start + seg] += loop[:seg] * 0.8
    return m.normalize(out)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def build_vehicle() -> list:
    written = []
    # Третий элемент — луп ли это. Одиночные звуки (хлопки, сброс турбины,
    # переключение передачи, запуск) зацикливать нельзя: Godot читает блок
    # smpl при импорте, и такой звук потом повторялся бы бесконечно.
    jobs = [
        ("gravel_road.wav", gravel_road(), True),
        ("wind.wav", wind(), True),
        ("bov_01.wav", blow_off(seed=31), False),
        ("bov_02.wav", blow_off(seed=32), False),
        ("bov_03.wav", blow_off(seed=33), False),
        ("shift.wav", gear_shift(), False),
        ("start.wav", engine_start(), False),
    ]
    for i in range(6):
        jobs.append(("pop_%02d.wav" % (i + 1), pop(seed=41 + i), False))
    for name, data, loop in jobs:
        path = os.path.join(VEHICLE_DIR, name)
        write_wav(path, data, loop=loop)
        write_import_file(path)
        written.append(path)
        print("  %-34s %6.2f с" % (os.path.relpath(path, ROOT), data.size / SR))
    return written


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rpm-grid", type=int, nargs="*", default=RPM_GRID)
    ap.add_argument("--only", choices=["engine", "vehicle"], default=None)
    args = ap.parse_args()

    if args.only in (None, "engine"):
        print("Лупы двигателя:")
        build_engine_bank(args.rpm_grid)
    if args.only in (None, "vehicle"):
        print("Звуки машины:")
        build_vehicle()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
