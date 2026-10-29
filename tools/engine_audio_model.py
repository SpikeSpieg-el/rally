"""Физическая модель звука двигателя Mitsubishi 4G63T для ралли-игры.

Модель построена на том же принципе, что и open-source проект
Engine Simulator (https://github.com/ange-yaghi/engine-sim, MIT): звук — это не
сэмплы, а результат распространения волны давления по выхлопной системе.
Здесь та же идея реализована в виде лёгкой 1D-модели, которую можно считать
в Python (для запекания лупов) и продублировать в GDScript (для живого звука).

Состав модели:

  * рядная четвёрка 4 такта, порядок вспышек 1-3-4-2;
  * импульсы выпуска: быстрый фронт (выпускной клапан открывается) и
    экспоненциальный спад (газ уходит в коллектор);
  * неравные длины выпускных ветвей -> цилиндры «стреляют» не совсем в такт,
    отсюда характерная неровность звука рядной четвёрки;
  * 1D-волновод выхлопной трубы: стоячие волны на нечётных гармониках
    (труба с закрытым концом), потери в петле обратной связи;
  * фильтр излучения открытого конца, глушитель/катализатор, резонанс кузова;
  * шум впуска, свист турбины (частота прохода лопастей компрессора) и шум
    подхвата (spool);
  * на сбросе газа — хлопки (overrun) и сброс давления (blow-off).

Никаких внешних звуковых ассетов: всё считается с нуля, поэтому результат
полностью легален для публикации.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from scipy import signal

# ---------------------------------------------------------------------------
# Базовые фильтры
# ---------------------------------------------------------------------------


def one_pole_lp(x: np.ndarray, cutoff_hz: float, sr: int) -> np.ndarray:
    """Однополюсный ФНЧ (дешёвый, используется в петле волновода)."""
    if cutoff_hz <= 0.0:
        return x.copy()
    a = math.exp(-2.0 * math.pi * cutoff_hz / sr)
    out = np.empty_like(x)
    state = 0.0
    b = 1.0 - a
    for i in range(x.shape[0]):
        state = b * x[i] + a * state
        out[i] = state
    return out


def biquad(x: np.ndarray, sos: np.ndarray) -> np.ndarray:
    """Фильтр второго порядка из scipy (butter/iirpeak -> SOS)."""
    return signal.sosfilt(sos, x)


def lowpass_sos(cutoff_hz: float, sr: int, order: int = 2) -> np.ndarray:
    nyq = sr * 0.5
    wn = min(max(cutoff_hz / nyq, 1e-5), 0.999)
    return signal.butter(order, wn, btype="low", output="sos")


def highpass_sos(cutoff_hz: float, sr: int, order: int = 2) -> np.ndarray:
    nyq = sr * 0.5
    wn = min(max(cutoff_hz / nyq, 1e-5), 0.999)
    return signal.butter(order, wn, btype="high", output="sos")


def bandpass_sos(center_hz: float, q: float, sr: int) -> np.ndarray:
    """Полосовой фильтр, заданный центром и добротностью."""
    nyq = sr * 0.5
    bandwidth = max(center_hz / max(q, 0.05), 1.0)
    low = max(center_hz - bandwidth * 0.5, 10.0)
    high = min(center_hz + bandwidth * 0.5, nyq * 0.98)
    if high <= low:
        high = min(low * 1.5, nyq * 0.98)
    return signal.butter(2, [low / nyq, high / nyq], btype="bandpass", output="sos")


def peaking_sos(center_hz: float, q: float, gain_db: float, sr: int) -> np.ndarray:
    """Пик-фильтр (резонанс кузова/салона)."""
    a0 = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * min(max(center_hz, 1.0), sr * 0.45) / sr
    alpha = math.sin(w0) / (2.0 * q)
    b = np.array([1 + alpha * a0, -2 * math.cos(w0), 1 - alpha * a0])
    a = np.array([1 + alpha / a0, -2 * math.cos(w0), 1 - alpha / a0])
    # SOS-форма: [b0, b1, b2, a0, a1, a2]
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0],
                      1.0, a[1] / a[0], a[2] / a[0]]])


# ---------------------------------------------------------------------------
# Волновод выхлопной системы
# ---------------------------------------------------------------------------


class ExhaustWaveguide:
    """1D-волновод: труба с закрытым (коллектор) и открытым (выхлоп) концом.

    Реализация: рекуррентная задержка y[n] = x[n] + g * lp(y[n - D]).
    Так реализуется труба, закрытая с одного конца: её собственные моды стоят
    на нечётных гармониках sr / (2D). Потери (g и ФНЧ в петле) задают, насколько
    труба «глухая».
    """

    def __init__(self, sr: int, length_m: float, speed_of_sound: float = 343.0,
                 reflection: float = 0.93, loss_hz: float = 2200.0) -> None:
        self.sr = sr
        self.length_m = length_m
        self.delay = max(2, int(round(sr * length_m / speed_of_sound)))
        self.reflection = reflection
        self.lp_coeff = math.exp(-2.0 * math.pi * loss_hz / sr)

    def process(self, x: np.ndarray) -> np.ndarray:
        d = self.delay
        g = self.reflection
        a = self.lp_coeff
        b = 1.0 - a
        buf = np.zeros(d, dtype=np.float64)
        out = np.zeros(x.shape[0], dtype=np.float64)
        state = 0.0
        idx = 0
        for n in range(x.shape[0]):
            arriving = buf[idx]
            state = b * arriving + a * state
            buf[idx] = x[n] + g * state
            out[n] = state
            idx += 1
            if idx >= d:
                idx = 0
        return out


# ---------------------------------------------------------------------------
# Параметры двигателя
# ---------------------------------------------------------------------------


@dataclass
class EngineSpec:
    """Геометрия и режимы двигателя, влияющие на тембр."""

    cylinders: int = 4
    # Порядок вспышек 1-3-4-2: смещение по коллектору для каждого цилиндра
    # (в долях периода вспышки). Неровные длины ветвей — источник характерного
    # «неровного» звука рядной четвёрки.
    runner_offsets: tuple = (0.000, 0.062, 0.118, 0.181)
    idle_rpm: float = 900.0
    redline_rpm: float = 7600.0
    # Длина выхлопной системы (ветви + коллектор + катализатор + глушитель).
    exhaust_length_m: float = 2.45
    # Потери в трубе: чем «глуше» система, тем ниже и тембр.
    pipe_reflection: float = 0.90
    pipe_loss_hz: float = 5200.0
    # Турбина: частота прохода лопастей компрессора = rpm * turbo_ratio.
    turbo_ratio: float = 0.36
    max_boost_bar: float = 1.05

    def firing_frequency(self, rpm: float) -> float:
        """Частота вспышек: 4 такта, 4 цилиндра -> 2 вспышки на оборот."""
        return rpm / 30.0


# ---------------------------------------------------------------------------
# Генерация
# ---------------------------------------------------------------------------


@dataclass
class RenderParams:
    """Параметры одного рендера."""

    sr: int = 32000
    duration: float = 1.15
    seed: int = 12345
    # Сколько секунд прогревать волновод, чтобы он вышел на установившийся режим.
    warmup: float = 0.45
    # Доля периода вспышки, которую занимает открытый выпускной клапан.
    valve_open: float = 0.30
    # Время атаки/спада импульса (с) — задаёт «жёсткость» звука.
    attack: float = 0.0006
    decay_load: float = 0.011
    decay_idle: float = 0.026
    # Уровни слоёв.
    exhaust_gain: float = 1.0
    intake_gain: float = 1.0
    turbo_gain: float = 1.0
    valvetrain_gain: float = 1.0
    # Тонмауты выхлопной системы.
    highpass_hz: float = 75.0
    muffler_hz: float = 5200.0
    muffler_hz_load: float = 2600.0
    # Уровень шума механизма (клапаны, форсунки).
    valvetrain_level: float = 0.220
    # Колебания холостых (нестабильность idle).
    idle_lope: float = 0.008
    overrun: float = 0.0
    spec: EngineSpec = field(default_factory=EngineSpec)


def _pulse_kernel(length: int, attack: float, decay: float, sr: int) -> np.ndarray:
    """Форма одного импульса выпуска: быстрый фронт + экспоненциальный спад."""
    t = np.arange(length, dtype=np.float64) / sr
    env = (1.0 - np.exp(-t / max(attack, 1e-5))) * np.exp(-t / max(decay, 1e-5))
    # Мягкое окончание, чтобы у импульса не было щелчка на хвосте.
    tail = max(1, length // 8)
    fade = np.ones(length)
    fade[-tail:] = np.linspace(1.0, 0.0, tail)
    return env * fade


def _fire_schedule(rpm: float, params: RenderParams, spec: EngineSpec,
                   rng: np.random.Generator, t_start: float, t_end: float) -> tuple:
    """Моменты вспышек и их амплитуды для всех цилиндров.

    Возвращает (события, период вспышки, блуждание периода).
    """
    period = 30.0 / max(rpm, 1.0)
    events = []
    for cyl in range(spec.cylinders):
        offset = spec.runner_offsets[cyl % len(spec.runner_offsets)] * period
        # Разброс по цилиндрам: амплитуда и небольшой джиттер момента.
        cyl_gain = 1.0 + 0.11 * (cyl % 2 * 2 - 1) + rng.uniform(-0.04, 0.04)
        k = int(math.floor((t_start - offset) / period)) - 1
        while True:
            base = offset + k * period
            if base > t_end:
                break
            jitter = rng.uniform(-0.006, 0.006) * period
            t = base + jitter
            if t_start <= t <= t_end:
                events.append((t, cyl_gain, cyl))
            k += 1
    events.sort(key=lambda e: e[0])
    return events, period


def _smooth_noise(time_axis: np.ndarray, sr: int, cutoff_hz: float,
                  rng: np.random.Generator) -> np.ndarray:
    """Отфильтрованный шум той же длины, что и time_axis."""
    n = time_axis.shape[0]
    noise = rng.standard_normal(n)
    sos = lowpass_sos(cutoff_hz, sr, order=2)
    return biquad(noise, sos)


def _excitation(events, n: int, params: RenderParams, period: float, walk: np.ndarray,
                sr: int, decay: float) -> np.ndarray:
    """Сумма импульсов выпуска по цилиндрам."""
    out = np.zeros(n, dtype=np.float64)
    pulse_len = max(8, int(round(period * params.valve_open * sr)))
    kernel = _pulse_kernel(pulse_len, params.attack, decay, sr)
    for (t_event, gain, _cyl) in events:
        idx = int(t_event * sr)
        if idx < 0 or idx >= n:
            continue
        # Нестабильность idle смещает момент вспышки.
        shift = 0.0
        if walk is not None and walk.size:
            shift = float(walk[min(idx, walk.size - 1)]) * period
        start = idx + int(round(shift * sr))
        if start < 0:
            continue
        end = min(n, start + pulse_len)
        if end <= start:
            continue
        out[start:end] += kernel[: end - start] * gain
    return out


def _exhaust(rpm: float, load: float, params: RenderParams,
             spec: EngineSpec, rng: np.random.Generator, n: int,
             t_start: float, t_end: float) -> np.ndarray:
    """Выхлоп: возбуждение -> волновод -> излучение -> глушитель."""
    sr = params.sr
    events, period = _fire_schedule(rpm, params, spec, rng, t_start, t_end)

    # Нестабильность холостых: медленное блуждание периода вспышки.
    walk = None
    if params.idle_lope > 0.0:
        time_axis = np.arange(n, dtype=np.float64) / sr
        walk = _smooth_noise(time_axis, sr, 3.5, rng) * params.idle_lope

    decay = params.decay_load + (params.decay_idle - params.decay_load) * (1.0 - load)
    pulse = _excitation(events, n, params, period, walk, sr, decay)

    # Жёсткость импульса зависит от нагрузки: под нагрузкой клапан открыт
    # дольше и газ уходит быстрее -> звук звонче.
    pulse = pulse * (0.6 + 0.4 * load)

    # Волновод: потери в трубе тоже зависят от режима.
    pipe = ExhaustWaveguide(sr, spec.exhaust_length_m,
                             reflection=spec.pipe_reflection * (0.98 - 0.06 * load),
                             loss_hz=spec.pipe_loss_hz * (0.8 + 0.4 * load))
    body = pipe.process(pulse)

    # Излучение открытого конца: высокие частоты уходят из трубы лучше.
    body = biquad(body, highpass_sos(params.highpass_hz, sr))
    # Глушитель/катализатор: гасим верхний диапазон.
    body = biquad(body, lowpass_sos(params.muffler_hz + params.muffler_hz_load * load,
                                    sr, order=2))
    # Резонанс кузова и салона.
    body = biquad(body, peaking_sos(115.0, 1.6, 3.5, sr))
    body = biquad(body, peaking_sos(330.0, 1.3, 2.5, sr))
    body = biquad(body, peaking_sos(780.0, 1.1, 2.0, sr))
    body = biquad(body, peaking_sos(1600.0, 1.0, 1.5, sr))
    return body * params.exhaust_gain


def _valvetrain(rpm: float, load: float, params: RenderParams,
                rng: np.random.Generator, n: int, events, period: float) -> np.ndarray:
    """Металлический шум механизма: клапаны, форсунки, валы.

    Именно этот слой даёт настоящему двигателю « rasp » — тот самый
    рассыпающийся призвук, который отличает мотор от генератора писка.
    Уровень растёт с оборотами: на холостых клапанный стук почти не слышен.
    """
    sr = params.sr
    out = np.zeros(n)

    # Щелчки форсунок: впрыск происходит на такте впуска, то есть за пол-оборота
    # до вспышки. Короткий импульс -> широкий спектр.
    tick_len = max(4, int(0.0025 * sr))
    t_tick = np.arange(tick_len) / sr
    tick = np.exp(-t_tick / 0.0006)
    tick = tick * np.sin(2.0 * math.pi * 2600.0 * t_tick)
    half = period * 0.5
    for (t_event, gain, _cyl) in events:
        pos = int((t_event - half) * sr)
        if pos < 0 or pos + tick_len >= n:
            continue
        out[pos:pos + tick_len] += tick * gain * 0.05

    # Шум механизма: чем выше обороты, тем больше ударов клапанов.
    noise = rng.standard_normal(n)
    rasp = biquad(noise, bandpass_sos(2200.0 + rpm * 0.25, 0.8, sr))
    rasp = biquad(rasp, highpass_sos(900.0, sr))
    level = (params.valvetrain_level
             + 0.055 * (rpm / max(params.spec.redline_rpm, 1.0))) * (0.55 + 0.45 * load)
    return (out + rasp * level) * params.valvetrain_gain


def _intake(rpm: float, load: float, params: RenderParams,
            rng: np.random.Generator, n: int) -> np.ndarray:
    """Шум впуска: воздух, засасываемый через дроссельную заслонку."""
    sr = params.sr
    noise = rng.standard_normal(n)
    # Чем выше обороты, тем выше тон впуска.
    center = 500.0 + rpm * 0.17
    shaped = biquad(noise, bandpass_sos(center, 0.9, sr))
    shaped = biquad(shaped, highpass_sos(240.0, sr))
    gain = load * (0.012 + 0.045 * (rpm / max(params.spec.redline_rpm, 1.0)))
    return shaped * gain * params.intake_gain


def _induction(rpm: float, load: float, params: RenderParams,
               rng: np.random.Generator, n: int) -> np.ndarray:
    """Индукционный шум: воздух, летящий через впуск и турбину.

    Это «голос» двигателя в средней полосе (300-900 Гц). Без него звук
    получается слишком «пустым» снизу и слишком песочным сверху.
    """
    sr = params.sr
    noise = rng.standard_normal(n)
    center = 280.0 + rpm * 0.075
    roar = biquad(noise, bandpass_sos(center, 1.3, sr))
    roar = biquad(roar, peaking_sos(center * 2.0, 1.6, 3.0, sr))
    gain = load * (0.030 + 0.075 * (rpm / max(params.spec.redline_rpm, 1.0)))
    return roar * gain * params.intake_gain


def _boost_bar(rpm: float, load: float, spec: EngineSpec) -> float:
    """Давление наддува: на малых оборотах турбина не раскручена."""
    spool = np.clip((rpm - 1800.0) / (spec.redline_rpm - 1800.0), 0.0, 1.0)
    spool = spool * spool * (3.0 - 2.0 * spool)
    return spec.max_boost_bar * load * spool


def _turbo(rpm: float, load: float, params: RenderParams,
           spec: EngineSpec, rng: np.random.Generator, n: int) -> np.ndarray:
    """Свист турбины и шум подхвата.

    Частота свиста = частота прохода лопастей компрессора, то есть растёт
    вместе с оборотами. На 4000 об/мин это ~1.4 кГц — как раз тот тон,
    который слышно на раллийной машине с турбиной.
    """
    sr = params.sr
    t = np.arange(n, dtype=np.float64) / sr
    boost = _boost_bar(rpm, load, spec)
    if boost <= 1e-4:
        return np.zeros(n)

    base_f = rpm * spec.turbo_ratio
    tone = np.zeros(n)
    # Лопасти дают не одну частоту, а гармонический ряд.
    for k, amp in ((1, 1.0), (2, 0.42), (3, 0.18), (4, 0.07)):
        f = base_f * k
        if f > sr * 0.45:
            break
        # Лёгкий расстрой: реальные лопасти бьют не идеально ровно.
        detune = 1.0 + rng.uniform(-0.004, 0.004)
        tone += amp * np.sin(2.0 * math.pi * f * detune * t)
    tone /= 1.7

    # Свист проходит через узкий резонатор — так он звучит «металлическим».
    whine = biquad(tone, bandpass_sos(min(base_f, sr * 0.45), 4.0, sr))
    whine = biquad(whine, peaking_sos(min(base_f * 2.0, sr * 0.45), 3.0, 3.0, sr))

    # Шум подхвата компрессора.
    noise = rng.standard_normal(n)
    hiss = biquad(noise, bandpass_sos(min(2600.0 + rpm * 0.25, sr * 0.45), 1.1, sr))

    level = 0.05 + 0.95 * (boost / max(spec.max_boost_bar, 1e-3))
    return (whine * 0.16 + hiss * 0.09) * level * params.turbo_gain


def _overrun(rpm: float, load: float, params: RenderParams,
             rng: np.random.Generator, n: int) -> np.ndarray:
    """Хлопки на сбросе газа (незаburnt топливо в цилиндре)."""
    sr = params.sr
    out = np.zeros(n)
    if params.overrun <= 0.0:
        return out
    count = int(params.overrun * 14)
    for _ in range(count):
        if rng.random() > 0.85:
            continue
        pos = int(rng.uniform(0.0, max(1.0, n - sr * 0.05)))
        length = int(rng.uniform(0.004, 0.020) * sr)
        env = np.exp(-np.arange(length) / max(1.0, length * 0.25))
        burst = rng.standard_normal(length) * env
        burst = biquad(burst, bandpass_sos(rng.uniform(700.0, 2200.0), 1.6, sr))
        amp = rng.uniform(0.25, 1.0) * (0.4 + 0.6 * (rpm / 7600.0))
        out[pos:pos + length] += burst * amp * 0.30
    return out


def render_engine(rpm: float, load: float, params: RenderParams,
                  seed: int | None = None, layers: bool = False) -> tuple:
    """Рендерит один луп двигателя.

    Возвращает (сигнал, длина_периода_в_сэмплах). Сигнал уже приведён к
    бесшовному виду: конец стыкуется с началом.
    """
    sr = params.sr
    spec = params.spec
    rng = np.random.default_rng(params.seed if seed is None else seed)

    # Длина лупа — целое число периодов вспышек, иначе стык будет слышен.
    period = 30.0 / max(rpm, 1.0)
    n_cycles = max(1, int(round(params.duration / period)))
    loop_len = int(round(n_cycles * period * sr))

    warm = int(params.warmup * sr)
    margin = int(0.25 * sr)
    n = warm + loop_len + margin
    t_start = warm / sr
    t_end = (warm + loop_len + margin) / sr

    exhaust = _exhaust(rpm, load, params, spec, rng, n, t_start, t_end)
    intake = _intake(rpm, load, params, rng, n)
    induction = _induction(rpm, load, params, rng, n)
    turbo = _turbo(rpm, load, params, spec, rng, n)
    pops = _overrun(rpm, load, params, rng, n)
    events, _period = _fire_schedule(rpm, params, spec, rng, t_start, t_end)
    valve = _valvetrain(rpm, load, params, rng, n, events, _period)

    mix = exhaust + intake + induction + turbo + pops + valve
    # Отрезаем прогрев — берём установившийся режим волновода.
    loop = _make_seamless(mix[warm:], loop_len, sr)
    if layers:
        return loop, loop_len, {
            "exhaust": exhaust[warm:warm + loop_len],
            "intake": intake[warm:warm + loop_len],
            "induction": induction[warm:warm + loop_len],
            "turbo": turbo[warm:warm + loop_len],
            "pops": pops[warm:warm + loop_len],
            "valvetrain": valve[warm:warm + loop_len],
        }
    return loop, loop_len


def _make_seamless(signal_buf: np.ndarray, loop_len: int, sr: int) -> np.ndarray:
    """Склейка конца лупа с началом равно-power кроссфейдом.

    Хвост лупа подмешивается к началу, поэтому в точке стыка сигнал
    продолжается естественно (как если бы запись просто продолжалась).
    """
    xf = min(int(0.030 * sr), loop_len // 3)
    if xf < 8:
        return signal_buf[:loop_len].copy()
    out = signal_buf[:loop_len].copy()
    head = signal_buf[0:xf]
    tail = signal_buf[loop_len:loop_len + xf]
    if tail.shape[0] < xf:
        return out
    w = np.linspace(0.0, math.pi * 0.5, xf)
    # Начало лупа должно продолжать запись ПОСЛЕ её конца: подмешиваем
    # «хвост» (то, что было бы дальше) и плавно уходим в «голову».
    # Тогда out[0] ~= x[loop_len] и стык out[loop_len-1] -> out[0] ровный.
    fade_out = np.cos(w)
    fade_in = np.sin(w)
    out[0:xf] = head * fade_in + tail * fade_out
    return out


def normalize(signal_buf: np.ndarray, peak: float = 0.89) -> np.ndarray:
    """Нормализация с мягким ограничителем (чтобы не было клиппинга)."""
    if signal_buf.size == 0:
        return signal_buf
    m = float(np.max(np.abs(signal_buf)))
    if m < 1e-9:
        return signal_buf
    out = signal_buf / m * peak
    # Мягкий клиппер: tanh-подобная компрессия вершины.
    return np.tanh(out * 1.12) / math.tanh(1.12)
