"""Оптимизация музыки для Godot 4: MP3 -> Ogg Vorbis.

Зачем:
  * 100 треков по 320 кбит/с занимают ~616 МБ. Godot держит музыку в
    импортированном виде в `.godot/imported`, поэтому размер ассетов
    напрямую влияет и на репозиторий, и на вес экспорта;
  * Ogg Vorbis - рекомендованный формат для музыки в Godot: при ~160
    кбит/с (q5) звучит не хуже 320 кбит/с MP3, но занимает примерно вдвое
    меньше. Godot умеет импортировать OGG с точками лупа;
  * попутно выравнивается громкость (EBU R128, -14 LUFS) - треки из
    разных источников больше не «прыгают» по уровню;
  * из файлов вырезаются обложки и ID3-теги: в игре они не нужны и могут
    добавлять сотни килобайт на трек.

Что делает скрипт:
  1. находит все `audio/music/*.mp3`;
  2. измеряет громкость (loudnorm, два прохода);
  3. кодирует в OGG Vorbis рядом с исходником (имя сохраняется);
  4. пишет `.import` для Godot (importer="oggvorbisstr", loop=false).

Запуск:
    python3 tools/optimize_music.py                  # все треки
    python3 tools/optimize_music.py --jobs 8         # параллельно
    python3 tools/optimize_music.py --quality 6      # ~192 кбит/с
    python3 tools/optimize_music.py --no-normalize   # только перекодирование
    python3 tools/optimize_music.py --dry-run        # показать план
    python3 tools/optimize_music.py audio/music/файл.mp3

Исходные MP3 не удаляются: после проверки их можно убрать из проекта
(например, `--archive-originals source/music_src`).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_DIR = os.path.join(ROOT, "audio", "music")

IMPORT_TEMPLATE = """[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"
uid="{uid}"
path="{imported}"

[deps]

source_file="{source}"
dest_files=["{imported}"]

[params]

loop={loop}
loop_offset=0
bpm=0
beat_count=0
bar_beats=4
"""


def uid_for(res_path: str) -> str:
    """Стабильный uid в формате Godot (основание 36, 63 бита)."""
    digest = hashlib.md5(res_path.encode("utf-8")).digest()
    value = int.from_bytes(digest[:8], "big") & ((1 << 63) - 1)
    if value == 0:
        value = 1
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = ""
    while value > 0:
        out = alphabet[value % 36] + out
        value //= 36
    return "uid://" + out


def write_import_file(ogg_path: str, root: str = ROOT, loop: bool = False) -> str:
    """Создаёт .import рядом с OGG - так же, как это делает редактор Godot."""
    res_path = "res://" + os.path.relpath(ogg_path, root).replace(os.sep, "/")
    digest = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    imported = "res://.godot/imported/%s-%s.oggvorbisstr" % (
        os.path.basename(ogg_path),
        digest,
    )
    body = IMPORT_TEMPLATE.format(
        uid=uid_for(res_path),
        imported=imported,
        source=res_path,
        loop="true" if loop else "false",
    )
    with open(ogg_path + ".import", "w", encoding="utf-8", newline="\n") as f:
        f.write(body)
    return ogg_path + ".import"


def human_size(num: float) -> str:
    for unit in ("Б", "КБ", "МБ", "ГБ"):
        if abs(num) < 1024.0 or unit == "ГБ":
            return "%.1f %s" % (num, unit)
        num /= 1024.0
    return "%.1f ГБ" % num


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        encoding="utf-8",
        errors="replace",
    )


def measure_loudness(src: str, target_i: float, target_tp: float, lra: float) -> dict | None:
    """Первый проход loudnorm: измеряет интегральную громкость трека."""
    af = "loudnorm=I=%s:TP=%s:LRA=%s:print_format=json" % (target_i, target_tp, lra)
    proc = run(
        [
            "ffmpeg", "-hide_banner", "-nostats", "-i", src,
            "-map", "0:a:0", "-af", af, "-f", "null", "-",
        ]
    )
    if proc.returncode != 0:
        return None
    text = proc.stderr
    start = text.rfind("{")
    end = text.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError:
        return None


def encode(
    src: str,
    dst: str,
    quality: int,
    normalize: bool,
    target_i: float,
    target_tp: float,
    lra: float,
    threads: int,
) -> tuple[bool, str]:
    """Кодирует один трек. Возвращает (успех, сообщение)."""
    tmp = dst + ".tmp.ogg"
    cmd = [
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-i", src,
        "-map", "0:a:0", "-vn", "-sn", "-dn", "-map_metadata", "-1",
    ]
    if normalize:
        stats = measure_loudness(src, target_i, target_tp, lra)
        if stats is None:
            return False, "не удалось измерить громкость"
        af = (
            "loudnorm=I=%s:TP=%s:LRA=%s"
            ":measured_I=%s:measured_TP=%s:measured_LRA=%s:measured_thresh=%s"
            ":offset=%s:linear=true"
            % (
                target_i, target_tp, lra,
                stats["input_i"], stats["input_tp"], stats["input_lra"],
                stats["input_thresh"], stats["target_offset"],
            )
        )
        cmd += ["-af", af]
    cmd += [
        "-ar", "44100", "-ac", "2",
        "-c:a", "libvorbis", "-q:a", str(quality),
        "-compression_level", "10",
        "-threads", str(max(1, threads)),
        "-f", "ogg", tmp,
    ]
    proc = run(cmd)
    if proc.returncode != 0:
        if os.path.exists(tmp):
            os.remove(tmp)
        tail = (proc.stderr or "").strip().splitlines()
        return False, tail[-1] if tail else "ffmpeg завершился с ошибкой"
    os.replace(tmp, dst)
    return True, "ok"


def collect_targets(paths: list[str], directory: str) -> list[str]:
    if paths:
        targets = []
        for p in paths:
            full = os.path.abspath(p)
            if os.path.isdir(full):
                targets += sorted(
                    os.path.join(full, n)
                    for n in os.listdir(full)
                    if n.lower().endswith(".mp3")
                )
            else:
                targets.append(full)
        return targets
    return sorted(
        os.path.join(directory, n)
        for n in os.listdir(directory)
        if n.lower().endswith(".mp3")
    )


def archive_originals(targets: list[str], archive_dir: str) -> None:
    os.makedirs(archive_dir, exist_ok=True)
    for src in targets:
        base = os.path.basename(src)
        dst = os.path.join(archive_dir, base)
        shutil.move(src, dst)
        import_path = src + ".import"
        if os.path.exists(import_path):
            shutil.move(import_path, dst + ".import")
    print("Исходники перенесены в %s" % os.path.relpath(archive_dir, ROOT))


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="MP3 -> OGG Vorbis для Godot 4")
    parser.add_argument("paths", nargs="*", help="файлы или папки (по умолчанию audio/music)")
    parser.add_argument("--dir", default=DEFAULT_DIR, help="папка с музыкой")
    parser.add_argument("--quality", type=int, default=5, help="качество Vorbis 0..10 (5 ~ 160 кбит/с)")
    parser.add_argument("--normalize", dest="normalize", action="store_true", default=True,
                        help="выравнивать громкость (включено по умолчанию)")
    parser.add_argument("--no-normalize", dest="normalize", action="store_false",
                        help="не трогать громкость")
    parser.add_argument("--lufs", type=float, default=-14.0, help="целевая громкость, LUFS")
    parser.add_argument("--true-peak", type=float, default=-1.5, help="лимит пиков, dBTP")
    parser.add_argument("--lra", type=float, default=11.0, help="целевой диапазон громкости, LU")
    parser.add_argument("--jobs", type=int, default=4, help="сколько треков кодировать параллельно")
    parser.add_argument("--force", action="store_true", help="перекодировать даже готовые OGG")
    parser.add_argument("--loop", action="store_true", help="включить loop в .import")
    parser.add_argument("--no-import", action="store_true", help="не создавать .import")
    parser.add_argument("--import-only", action="store_true",
                        help="не кодировать, только перезаписать .import у готовых OGG")
    parser.add_argument("--archive-originals", metavar="DIR",
                        help="после успешного кодирования перенести MP3 в DIR")
    parser.add_argument("--dry-run", action="store_true", help="только показать план")
    args = parser.parse_args(argv[1:])

    if shutil.which("ffmpeg") is None:
        print("ffmpeg не найден в PATH", file=sys.stderr)
        return 1
    if not 0 <= args.quality <= 10:
        print("--quality должен быть в диапазоне 0..10", file=sys.stderr)
        return 1

    targets = collect_targets(args.paths, args.dir)
    if not targets:
        print("MP3 не найдены")
        return 0

    if args.import_only:
        written = 0
        for src in targets:
            dst = os.path.splitext(src)[0] + ".ogg"
            if not os.path.exists(dst):
                print("Нет OGG: %s" % os.path.basename(dst))
                continue
            write_import_file(dst, loop=args.loop)
            written += 1
        print("Обновлено .import: %d" % written)
        return 0 if written else 1

    plan = []
    for src in targets:
        dst = os.path.splitext(src)[0] + ".ogg"
        if os.path.exists(dst) and not args.force and os.path.getmtime(dst) >= os.path.getmtime(src):
            continue
        plan.append((src, dst))

    total_in = sum(os.path.getsize(s) for s, _ in plan)
    print("Треков: %d, к кодированию: %d (%s)" % (len(targets), len(plan), human_size(total_in)))
    print("Качество Vorbis: q%d, нормализация: %s" % (
        args.quality, ("%.0f LUFS" % args.lufs) if args.normalize else "выкл."))
    if args.dry_run or not plan:
        return 0

    started = time.time()
    done = 0
    failed = []
    total_out = 0

    def worker(item: tuple[str, str]) -> tuple[str, str, str | None, int]:
        src, dst = item
        ok, msg = encode(
            src, dst, args.quality, args.normalize,
            args.lufs, args.true_peak, args.lra, 1,
        )
        size = os.path.getsize(dst) if ok else 0
        return src, dst, None if ok else msg, size

    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        futures = {pool.submit(worker, item): item for item in plan}
        for future in concurrent.futures.as_completed(futures):
            src, dst, error, size = future.result()
            name = os.path.basename(src)
            done += 1
            if error:
                failed.append((name, error))
                print("[%3d/%3d] ОШИБКА  %s: %s" % (done, len(plan), name, error))
                continue
            total_out += size
            if not args.no_import:
                write_import_file(dst, loop=args.loop)
            src_size = os.path.getsize(src)
            print("[%3d/%3d] %6.1f МБ -> %5.1f МБ  %s" % (
                done, len(plan), src_size / 1048576, size / 1048576, name))

    elapsed = time.time() - started
    print("-" * 60)
    print("Готово за %.1f с: %d/%d, %s -> %s (%.0f%%)" % (
        elapsed, len(plan) - len(failed), len(plan),
        human_size(total_in), human_size(total_out),
        100.0 * total_out / total_in if total_in else 0.0,
    ))
    if failed:
        print("Не удалось: %d" % len(failed))
        for name, error in failed:
            print("  %s: %s" % (name, error))
        return 1

    if args.archive_originals:
        archive_originals([src for src, _ in plan], os.path.abspath(args.archive_originals))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
