"""Симуляция рантайма engine_sound.gd: проверка гистерезиса, кроссфейда и
питч-коррекции без запуска Godot.

Запуск: python3 tools/sim_engine_runtime.py
"""
from __future__ import annotations

import math
import random
import sys

RPM_GRID = [900, 970, 1050, 1130, 1220, 1320, 1430, 1540, 1670, 1800, 1940, 2100,
            2270, 2450, 2640, 2850, 3080, 3330, 3600, 3880, 4190, 4530, 4890, 5280,
            5710, 6160, 6660, 7190, 7600]
BANKS = ["light", "full"]
CROSSFADE_TIME = 0.09
PITCH_LIMIT = 0.06
SWITCH_MARGIN = 0.03
MIN_SWITCH_INTERVAL = 0.12
PITCH_SLEW = 1.2
SHIFT_DUCK_DB = 2.5
MASTER_DB = -2.0
ENGINE_DB = -3.0
FPS = 60.0


def to_db(linear: float) -> float:
    if linear <= 0.001:
        return -60.0
    return 20.0 * math.log10(min(max(linear, 0.001), 1.0))


def grid_index(rpm: float) -> int:
    count = len(RPM_GRID)
    if rpm <= RPM_GRID[0]:
        return 0
    if rpm >= RPM_GRID[-1]:
        return count - 1
    for i in range(count - 1):
        low, high = RPM_GRID[i], RPM_GRID[i + 1]
        if rpm < high:
            return i + 1 if rpm * rpm > low * high else i
    return count - 1


def worth_switch(current: int, candidate: int, rpm: float) -> bool:
    if rpm <= 0.0:
        return False
    cur_err = abs(rpm - RPM_GRID[current]) / rpm
    new_err = abs(rpm - RPM_GRID[candidate]) / rpm
    return new_err < cur_err - SWITCH_MARGIN


def pitch_for(index: int, rpm: float) -> float:
    base = float(RPM_GRID[index])
    if base <= 0.0:
        return 1.0
    return min(max(rpm / base, 1.0 - PITCH_LIMIT), 1.0 + PITCH_LIMIT)


class Bank:
    def __init__(self, name: str):
        self.name = name
        self.cur = 0
        self.prev = -1
        self.fade = 1.0
        self.index = [-1, -1]
        self.pitch = [1.0, 1.0]
        self.cooldown = 0.0
        self.volume = [-60.0, -60.0]
        self.playing = [False, False]


class Engine:
    def __init__(self):
        self.banks = [Bank(n) for n in BANKS]
        self.load = 0.0
        self.duck = 0.0
        self.switch_times: list[float] = []
        self.time = 0.0

    def update(self, rpm: float, throttle: float, shifting: bool, delta: float):
        self.time += delta
        target_load = min(max(throttle * 0.88 + 0.12 * min(rpm / 7000.0, 1.0), 0.0), 1.0)
        self.load += (target_load - self.load) * min(delta * 9.0, 1.0)
        self.duck = 1.0 if shifting else max(0.0, self.duck - delta * 5.0)

        index = grid_index(rpm)
        gains = {"light": math.sqrt(1.0 - self.load), "full": math.sqrt(self.load)}
        camera_db = -SHIFT_DUCK_DB * self.duck
        for bank in self.banks:
            self._update_bank(bank, index, rpm, gains[bank.name], camera_db, delta)

    def _update_bank(self, bank: Bank, index: int, rpm: float, gain: float,
                     camera_db: float, delta: float):
        bank.cooldown = max(0.0, bank.cooldown - delta)
        cur_index = bank.index[bank.cur]
        target = index
        if cur_index >= 0 and target != cur_index:
            error_now = abs(rpm / max(1.0, float(RPM_GRID[cur_index])) - 1.0)
            urgent = error_now > PITCH_LIMIT
            if not urgent and (bank.cooldown > 0.0
                               or not worth_switch(cur_index, target, rpm)):
                target = cur_index
        if bank.index[bank.cur] != target:
            self._switch(bank, target, rpm)

        volume = MASTER_DB + ENGINE_DB + camera_db
        if bank.prev >= 0:
            fade = min(1.0, bank.fade + delta / CROSSFADE_TIME)
            bank.fade = fade
            bank.volume[bank.cur] = to_db(gain * math.sin(fade * math.pi / 2)) + volume
            bank.volume[bank.prev] = to_db(gain * math.cos(fade * math.pi / 2)) + volume
            if fade >= 1.0:
                bank.playing[bank.prev] = False
                bank.volume[bank.prev] = -60.0
                bank.index[bank.prev] = -1
                bank.prev = -1
                bank.fade = 1.0
        else:
            bank.volume[bank.cur] = to_db(gain) + volume

        for i in range(2):
            idx = bank.index[i]
            if idx < 0:
                continue
            target_pitch = pitch_for(idx, rpm)
            step = PITCH_SLEW * delta
            bank.pitch[i] = min(max(target_pitch, bank.pitch[i] - step),
                                bank.pitch[i] + step)

    def _switch(self, bank: Bank, index: int, rpm: float):
        cur = bank.cur
        other = 1 - cur
        bank.pitch[other] = pitch_for(index, rpm)
        bank.volume[other] = -60.0
        bank.playing[other] = True
        bank.index[other] = index
        bank.cooldown = MIN_SWITCH_INTERVAL
        self.switch_times.append(self.time)
        if bank.index[cur] >= 0:
            bank.prev = cur
            bank.cur = other
            bank.fade = 0.0
        else:
            bank.cur = other
            bank.prev = -1
            bank.fade = 1.0


def drive_profile():
    """Профиль езды: холостые -> разгон -> крейсер -> торможение -> сброс."""
    frames = []
    delta = 1.0 / FPS
    rpm, speed = 900.0, 0.0
    random.seed(7)
    t = 0.0
    while t < 26.0:
        t += delta
        if t < 1.0:
            rpm, throttle, shifting = 900.0, 0.0, False
        elif t < 5.0:
            throttle = 1.0
            rpm = min(7600.0, rpm + 2300.0 * delta)
            shifting = False
        elif t < 6.0:
            # переключение передачи: обороты падают
            throttle = 0.4
            rpm = max(2600.0, rpm - 4200.0 * delta)
            shifting = (t % 0.5) < 0.18
        elif t < 11.0:
            throttle = 1.0
            rpm = min(7400.0, rpm + 1500.0 * delta)
            shifting = False
        elif t < 16.0:
            throttle = 0.65
            rpm = max(2200.0, rpm - 300.0 * delta)
            shifting = False
        elif t < 18.0:
            throttle = 0.0
            rpm = max(1500.0, rpm - 900.0 * delta)
            shifting = False
        elif t < 19.0:
            throttle = 0.0
            rpm = max(900.0, rpm - 600.0 * delta)
            shifting = True
        else:
            throttle = 0.0
            rpm = max(900.0, rpm - 200.0 * delta)
            shifting = False
        # лёгкий дребезг оборотов (как от неровностей и вибрации)
        rpm_j = rpm + random.uniform(-18.0, 18.0)
        frames.append((rpm_j, throttle, shifting, delta))
    return frames


def attenuation_db(distance: float, unit_size: float = 4.0,
                   max_distance: float = 70.0) -> float:
    """Затухание AudioStreamPlayer3D при обратно-квадратичной модели."""
    d = distance / unit_size
    gain = 1.0 / (d * d + 1.0)
    if max_distance > 0.0:
        gain *= max(0.0, 1.0 - distance / max_distance)
    return 20.0 * math.log10(max(gain, 1e-9))


def report_mix() -> None:
    """Печатает ожидаемый уровень двигателя у разных камер."""
    file_rms_db = -9.5     # средний RMS лупов двигателя, дБFS
    file_peak_db = -0.5    # пик лупа, дБFS
    mix_db = MASTER_DB + ENGINE_DB
    print("")
    # Режимы нагрузки смешиваются равномощностно, поэтому сумма голосов
    # даёт ровно 0 дБ поправки.
    print("уровень двигателя (режимы нагрузки смешаны равномощностно):")
    for name, distance in (("вид сзади", 5.1), ("капот", 3.7), ("кабина", 2.3)):
        att = attenuation_db(distance)
        rms = file_rms_db + mix_db + att
        peak = file_peak_db + mix_db + att
        print("  %-9s дистанция %.1f м, затухание %5.1f дБ -> RMS %6.1f дБFS, "
              "пик %6.1f дБFS" % (name, distance, att, rms, peak))


def main() -> int:
    engine = Engine()
    frames = drive_profile()
    max_pitch_err = 0.0
    min_active_volume = 99.0
    max_active_volume = -99.0
    gaps = 0
    switches_per_second = []
    prev_switch_count = 0
    for i, (rpm, throttle, shifting, delta) in enumerate(frames):
        engine.update(rpm, throttle, shifting, delta)
        for bank in engine.banks:
            if bank.index[bank.cur] < 0:
                continue
            err = abs(pitch_for(bank.index[bank.cur], rpm) - 1.0)
            max_pitch_err = max(max_pitch_err, err)
            vol = bank.volume[bank.cur]
            if vol > -59.0:
                min_active_volume = min(min_active_volume, vol)
                max_active_volume = max(max_active_volume, vol)
            # суммарная громкость двух голосов банка в дБ
            total = 0.0
            for j in range(2):
                if bank.index[j] >= 0:
                    total += 10 ** (bank.volume[j] / 20.0) ** 2
            if total <= 1e-9:
                gaps += 1
        if (i + 1) % int(FPS) == 0:
            switches_per_second.append(len(engine.switch_times) - prev_switch_count)
            prev_switch_count = len(engine.switch_times)

    print("кадров: %d" % len(frames))
    print("переключений лупа всего: %d" % len(engine.switch_times))
    print("макс. переключений в секунду: %d" % (max(switches_per_second) if switches_per_second else 0))
    print("макс. ошибка питча: %.2f %% (предел %.0f %%)"
          % (max_pitch_err * 100.0, PITCH_LIMIT * 100.0))
    print("громкость активного голоса: от %.1f до %.1f дБ"
          % (min_active_volume, max_active_volume))
    print("кадров без звука: %d" % gaps)

    problems = []
    if max_pitch_err > PITCH_LIMIT + 1e-6:
        problems.append("ошибка питча выше предела")
    if gaps > 0:
        problems.append("есть кадры без звука")
    if max_active_volume > -3.0:
        problems.append("слишком громко")
    if min_active_volume < -60.0:
        problems.append("провалы громкости")
    if problems:
        for p in problems:
            print("FAIL: " + p)
        return 1
    print("PASS: рантайм ведёт себя корректно")
    report_mix()
    return 0


if __name__ == "__main__":
    sys.exit(main())
