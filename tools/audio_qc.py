"""Контроль качества звука двигателя: метрики и спектрограммы.

Инструмент нужен, чтобы проверить две вещи:

  1) звук не «пищит» — то есть в спектре есть гармонический ряд от частоты
     вспышек, а не один узкий пик;
  2) луп бесшовный — стык не даёт щелчка и спектр на стыке не рвётся.

Запуск:
    python3 tools/audio_qc.py                 # метрики по всем лупам + спектрограммы
    python3 tools/audio_qc.py --preview 3000  # разбор одного лупа
"""
from __future__ import annotations

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

try:
    from scipy import signal as _sig
except Exception:  # pragma: no cover
    _sig = None

DEFAULT_AUDIO_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "engine")


# ---------------------------------------------------------------------------
# Анализ
# ---------------------------------------------------------------------------


def read_wav(path: str) -> tuple:
    import wave
    with wave.open(path, "rb") as w:
        sr = w.getframerate()
        channels = w.getnchannels()
        width = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if width == 2:
        data = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif width == 1:
        data = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    elif width == 4:
        data = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    else:
        raise ValueError("неподдерживаемая ширина сэмпла: %d" % width)
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, sr


def rms(x: np.ndarray) -> float:
    if x.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(x * x)))


def dominant_fundamental(x: np.ndarray, sr: int, lo: float = 8.0,
                         hi: float = 400.0, expect: float = 0.0) -> float:
    """Оценка основного тона по автокорреляции (устойчива к шуму).

    Если известен ожидаемый тон (частота вспышек из имени файла), ищем
    рядом с ним: вслепую автокорреляция иногда цепляется за суб-гармонику
    и показывает «неправильные» обороты.
    """
    if x.size < 1024:
        return 0.0
    if expect > 0.0:
        lo = max(lo, expect * 0.85)
        hi = min(hi, expect * 1.15)
    x = x - x.mean()
    n = x.size
    nfft = 1 << int(math.ceil(math.log2(n * 2)))
    spec = np.fft.rfft(x, nfft)
    ac = np.fft.irfft(np.abs(spec) ** 2, nfft)[:n]
    if ac[0] <= 0:
        return 0.0
    ac = ac / ac[0]
    lo_lag = max(2, int(sr / hi))
    hi_lag = min(n - 1, int(sr / lo))
    if hi_lag <= lo_lag:
        return 0.0
    seg = ac[lo_lag:hi_lag]
    if seg.size == 0:
        return 0.0
    best = int(np.argmax(seg))
    peak = seg[best]
    if peak <= 0.2:
        return 0.0
    # Автокорреляция иногда «падает» на октаву ниже: проверяем, нет ли
    # сопоставимого пика на вдвое меньшем лаге, и если есть — берём его.
    lag = best
    while lag > 2:
        half = lag // 2
        if half >= lo_lag and ac[half] >= ac[lag] * 0.85:
            lag = half
        else:
            break
    # Уточнение лага параболической интерполяцией по трём точкам.
    idx = lag + lo_lag
    if 0 < idx < n - 1:
        y0, y1, y2 = ac[idx - 1], ac[idx], ac[idx + 1]
        denom = (y0 - 2.0 * y1 + y2)
        if abs(denom) > 1e-12:
            delta = 0.5 * (y0 - y2) / denom
            if abs(delta) < 1.0:
                idx = idx + delta
    return sr / float(idx)


def harmonic_profile(x: np.ndarray, sr: int, f0: float, n_harm: int = 12) -> np.ndarray:
    """Амплитуды гармоник f0 (в дБ относительно самой громкой)."""
    if _sig is None or f0 <= 0:
        return np.zeros(n_harm)
    freqs, psd = _sig.welch(x, sr, nperseg=min(4096, x.size))
    psd = psd / (psd.max() + 1e-20)
    out = np.zeros(n_harm)
    for i in range(1, n_harm + 1):
        f = f0 * i
        if f >= sr * 0.5:
            break
        band = (freqs >= f * 0.94) & (freqs <= f * 1.06)
        if band.any():
            out[i - 1] = 10.0 * np.log10(max(psd[band].max(), 1e-12))
    return out


def spectral_centroid(x: np.ndarray, sr: int) -> float:
    if _sig is None or x.size == 0:
        return 0.0
    freqs, psd = _sig.welch(x, sr, nperseg=min(4096, x.size))
    total = psd.sum()
    if total <= 0:
        return 0.0
    return float((freqs * psd).sum() / total)


def harmonic_contrast(x: np.ndarray, sr: int, f0: float) -> float:
    """Насколько гармоники f0 выделяются над фоном между ними.

    У настоящего двигателя гармоническая лестница хорошо видна: 10-20 дБ.
    У чистого тона («писка») гармоник нет вовсе, а у шума лестницы нет.
    """
    if _sig is None or f0 <= 0:
        return 0.0
    freqs, psd = _sig.welch(x, sr, nperseg=min(16384, x.size))
    psd = psd / (psd.max() + 1e-20)
    on = []
    off = []
    for i in range(1, 25):
        f = f0 * i
        if f >= sr * 0.5:
            break
        band = (freqs >= f * 0.97) & (freqs <= f * 1.03)
        if band.any():
            on.append(10.0 * np.log10(max(psd[band].max(), 1e-12)))
        mid = f + f0 * 0.5
        band2 = (freqs >= mid * 0.985) & (freqs <= mid * 1.015)
        if band2.any():
            off.append(10.0 * np.log10(max(psd[band2].max(), 1e-12)))
    if not on or not off:
        return 0.0
    return float(np.mean(on) - np.mean(off))


def tonal_ratio(x: np.ndarray, sr: int, f0: float) -> float:
    """Доля энергии в гармониках f0 — «писк» это 1.0, а настоящий ДВС << 1."""
    if _sig is None or f0 <= 0:
        return 0.0
    freqs, psd = _sig.welch(x, sr, nperseg=min(4096, x.size))
    total = psd.sum() + 1e-20
    mask = np.zeros_like(freqs, dtype=bool)
    for i in range(1, 25):
        f = f0 * i
        if f >= sr * 0.5:
            break
        mask |= (freqs >= f * 0.96) & (freqs <= f * 1.04)
    return float(psd[mask].sum() / total)


def seam_discontinuity(x: np.ndarray) -> float:
    """Разрыв на стыке лупа: |x[0] - x[-1]| в единицах RMS."""
    if x.size < 2:
        return 0.0
    r = rms(x)
    if r <= 0:
        return 0.0
    return float(abs(x[0] - x[-1]) / r)


def seam_vs_natural(x: np.ndarray) -> float:
    """Насколько стык «тише» обычного скачка сигнала внутри лупа.

    Значение около 1 означает, что стык неотличим от обычного хода сигнала:
    щелчка не будет. Больше 1 — стык выделяется и его слышно.
    """
    if x.size < 4:
        return 0.0
    diffs = np.abs(np.diff(x))
    natural = float(diffs.max())
    if natural <= 1e-9:
        return 0.0
    return float(abs(x[0] - x[-1]) / natural)


def seam_spectral_jump(x: np.ndarray, sr: int) -> float:
    """Насколько спектр меняется при переходе через стык."""
    if _sig is None or x.size < 4096:
        return 0.0
    win = min(1024, x.size // 4)
    a = x[-win:]
    b = x[:win]
    fa, pa = _sig.welch(a, sr, nperseg=min(512, win))
    fb, pb = _sig.welch(b, sr, nperseg=min(512, win))
    n = min(pa.size, pb.size)
    pa = pa[:n] / (pa.max() + 1e-20)
    pb = pb[:n] / (pb.max() + 1e-20)
    return float(np.abs(pa - pb).sum() / n)


def analyze(path: str) -> dict:
    x, sr = read_wav(path)
    name = os.path.basename(path)
    rpm = None
    load = None
    parts = name.replace(".wav", "").split("_")
    for p in parts:
        if p.isdigit() and len(p) == 4:
            rpm = int(p)
        if p in ("light", "full"):
            load = p
    expected = (rpm / 30.0) if rpm else 0.0
    f0 = dominant_fundamental(x, sr, expect=expected)
    return {
        "name": name,
        "sr": sr,
        "duration": x.size / sr,
        "rms": rms(x),
        "peak": float(np.max(np.abs(x))),
        "f0": f0,
        "f0_expected": expected,
        "f0_error": (f0 - expected) / expected * 100.0 if expected else 0.0,
        "centroid": spectral_centroid(x, sr),
        "tonal": tonal_ratio(x, sr, expected or f0),
        "contrast": harmonic_contrast(x, sr, expected or f0),
        "seam": seam_discontinuity(x),
        "seam_ratio": seam_vs_natural(x),
        "seam_spec": seam_spectral_jump(x, sr),
        "harmonics": harmonic_profile(x, sr, expected or f0),
    }


def _draw_spectrogram(ax, x, sr, title, f0=None):
    f, t, sxx = _sig.spectrogram(x, sr, nperseg=2048, noverlap=1536,
                                  scaling="spectrum", mode="magnitude")
    sxx_db = 20.0 * np.log10(sxx + 1e-9)
    top = min(4000.0, sr * 0.5)
    keep = f <= top
    vmin, vmax = np.percentile(sxx_db, 12), np.percentile(sxx_db, 99.5)
    ax.pcolormesh(t, f[keep] / 1000.0, sxx_db[keep], shading="auto", cmap="magma",
                  vmin=vmin, vmax=vmax)
    if f0:
        # Оранжевые линии — гармоники частоты вспышек: по ним видно, что звук
        # держит тон двигателя, а не шум.
        for k in range(1, 40):
            fh = f0 * k
            if fh > top:
                break
            ax.axhline(fh / 1000.0, color="cyan", alpha=0.30, linewidth=0.5)
    ax.set_ylim(0.0, top / 1000.0)
    ax.set_title(title, fontsize=10)
    ax.set_ylabel("частота, кГц")
    ax.grid(alpha=0.25, color="w", linewidth=0.4)


def spectrogram_png(path: str, out_path: str, title: str = "", f0: float = 0.0) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    x, sr = read_wav(path)
    fig, ax = plt.subplots(figsize=(11, 4.2), dpi=110)
    _draw_spectrogram(ax, x, sr, title or os.path.basename(path), f0)
    ax.set_xlabel("время, с")
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def spectrogram_compare(paths: list, out_path: str, title: str = "") -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, axes = plt.subplots(len(paths), 1, figsize=(11, 3.4 * len(paths)), dpi=110)
    if len(paths) == 1:
        axes = [axes]
    for ax, p in zip(axes, paths):
        x, sr = read_wav(p)
        f0 = 0.0
        for part in os.path.basename(p).replace(".wav", "").split("_"):
            if part.isdigit() and len(part) == 4:
                f0 = int(part) / 30.0
        _draw_spectrogram(ax, x, sr, os.path.basename(p), f0)
    axes[-1].set_xlabel("время, с")
    fig.suptitle(title or "", fontsize=11)
    fig.tight_layout()
    fig.savefig(out_path)
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=DEFAULT_AUDIO_DIR)
    ap.add_argument("--preview", type=int, default=None,
                    help="разобрать один луп по оборотам (например 3000)")
    ap.add_argument("--png", default=None, help="куда сохранить спектрограмму")
    ap.add_argument("--out-dir", default=None, help="папка для PNG")
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        print("НЕТ ПАПКИ: %s" % args.dir)
        return 1

    files = sorted(f for f in os.listdir(args.dir) if f.endswith(".wav"))
    if not files:
        print("В папке нет WAV: %s" % args.dir)
        return 1

    if args.preview is not None:
        match = [f for f in files if "_%04d_" % args.preview in f]
        if not match:
            print("Нет лупа на %d об/мин" % args.preview)
            return 1
        for m in match:
            path = os.path.join(args.dir, m)
            res = analyze(path)
            print("== %s" % res["name"])
            print("  длительность      : %.3f с  (%d Гц)" % (res["duration"], res["sr"]))
            print("  RMS / пик         : %.4f / %.4f" % (res["rms"], res["peak"]))
            print("  основной тон      : %.2f Гц (ожидалось %.2f, ошибка %.1f%%)"
                  % (res["f0"], res["f0_expected"], res["f0_error"]))
            print("  спектральный центр: %.0f Гц" % res["centroid"])
            print("  контраст гармоник : %.1f дБ (у настоящего ДВС 10-20)" % res["contrast"])
            print("  доля гармоник     : %.3f (1.0 = чистый тон/писк)" % res["tonal"])
            print("  разрыв на стыке   : %.4f (RMS)" % res["seam"])
            print("  стык vs естеств.  : %.2f (<=1 — щелчка не будет)" % res["seam_ratio"])
            print("  скачок спектра    : %.3f" % res["seam_spec"])
            print("  гармоники (дБ)    : %s"
                  % " ".join("%.0f" % h for h in res["harmonics"]))
            if args.png:
                spectrogram_png(path, args.png, res["name"], res["f0_expected"])
                print("  спектрограмма     : %s" % args.png)
        return 0

    print("%-28s %7s %7s %7s %7s %8s %7s" %
          ("файл", "f0 Гц", "центр", "контр", "гарм.", "стык", "стик/естеств"))
    worst = []
    for f in files:
        res = analyze(os.path.join(args.dir, f))
        print("%-28s %7.2f %7.0f %7.1f %7.3f %8.4f %7.2f" %
              (res["name"], res["f0"], res["centroid"], res["contrast"],
               res["tonal"], res["seam"], res["seam_ratio"]))
        worst.append(res)

    f0_err = max(abs(r["f0_error"]) for r in worst)
    tonal = max(r["tonal"] for r in worst)
    seam = max(r["seam"] for r in worst)
    seam_ratio = max(r["seam_ratio"] for r in worst)
    contrast = min(r["contrast"] for r in worst)
    print("\nИтоги: худшая ошибка тона %.1f%%, макс. доля гармоник %.3f, "
          "мин. контраст гармоник %.1f дБ, макс. разрыв стыка %.4f, "
          "стык/естественный скачок %.2f"
          % (f0_err, tonal, contrast, seam, seam_ratio))

    if args.out_dir:
        os.makedirs(args.out_dir, exist_ok=True)
        for name in ("engine_0900_light.wav", "engine_3000_full.wav",
                     "engine_7600_full.wav"):
            p = os.path.join(args.dir, name)
            if os.path.exists(p):
                spectrogram_png(p, os.path.join(args.out_dir,
                                               name.replace(".wav", ".png")))
        print("Спектрограммы: %s" % args.out_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
