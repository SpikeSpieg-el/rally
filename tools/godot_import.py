"""Генерация .import-файлов для WAV в формате Godot 4.

Модуль намеренно не зависит от numpy/scipy: им можно пользоваться отдельно,
чтобы перезаписать .import у уже готовых звуков, ничего не пересчитывая.

    python3 tools/godot_import.py            # перезаписать все .import
    python3 tools/godot_import.py audio/engine/engine_0900_light.wav

Почему точки зацикливания задаются явно (edit/loop_mode=2, edit/loop_begin,
edit/loop_end), а не только блоком smpl внутри WAV:

  * Godot при импорте читает smpl, но если файл переписать сторонним
    редактором и потерять блок, луп превратится в одноразовый звук;
  * явные значения однозначны и не зависят от версии импортёра.

Все параметры соответствуют Godot 4.7 (ResourceImporterWAV):
  force/8_bit, force/mono, force/max_rate, force/max_rate_hz,
  edit/trim, edit/normalize, edit/loop_mode, edit/loop_begin, edit/loop_end,
  compress/mode.
"""
from __future__ import annotations

import hashlib
import os
import struct
import sys

# Корневая папка проекта (на уровень выше tools/).
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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


def wav_frames(path: str) -> int:
    """Число кадров (сэмплов на канал) в WAV-файле."""
    with open(path, "rb") as f:
        header = f.read(12)
        if len(header) < 12 or header[:4] != b"RIFF":
            return 0
        channels = 1
        bits = 16
        pos = 12
        while True:
            f.seek(pos)
            chunk_head = f.read(8)
            if len(chunk_head) < 8:
                return 0
            chunk_id = chunk_head[:4]
            chunk_size = struct.unpack("<I", chunk_head[4:8])[0]
            if chunk_id == b"fmt ":
                fmt = f.read(min(chunk_size, 16))
                channels = struct.unpack("<H", fmt[2:4])[0]
                bits = struct.unpack("<H", fmt[14:16])[0]
            elif chunk_id == b"data":
                bytes_per_frame = max(1, channels * max(1, bits // 8))
                return chunk_size // bytes_per_frame
            pos += 8 + chunk_size + (chunk_size % 2)


def is_loop_asset(path: str) -> bool:
    """Луп ли это.

    Одиночные звуки (хлопки, сброс турбины, переключение передачи, запуск
    двигателя) зацикливать нельзя: Godot при импорте читает блок smpl, и
    такой звук потом повторялся бы бесконечно — получается непрерывный треск.
    """
    name = os.path.basename(path)
    if name.startswith(("pop_", "bov_")):
        return False
    if name in ("shift.wav", "start.wav"):
        return False
    return True


def write_import_file(path: str, root: str = ROOT, loop: bool = True) -> str:
    """Создаёт .import рядом с WAV — как это делает сам Godot.

    Имя импортированного файла содержит md5 от полного пути res:// — та же
    схема, что у уже лежащих в репозитории текстур.
    """
    res_path = "res://" + os.path.relpath(path, root).replace(os.sep, "/")
    digest = hashlib.md5(res_path.encode("utf-8")).hexdigest()
    base = os.path.basename(path)
    imported = "res://.godot/imported/%s-%s.sample" % (base, digest)
    frames = wav_frames(path)
    # edit/loop_mode: 0 — «как в WAV», 1 — выключить, 2 — вперёд.
    loop_mode = 2 if loop else 1
    loop_end = frames if loop else 0
    body = """[remap]

importer="wav"
type="AudioStreamWAV"
uid="%s"
path="%s"

[deps]

source_file="%s"
dest_files=["%s"]

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=%d
edit/loop_begin=0
edit/loop_end=%d
compress/mode=0
""" % (_uid_for(res_path), imported, res_path, imported, loop_mode, loop_end)
    with open(path + ".import", "w", encoding="utf-8") as f:
        f.write(body)
    return path + ".import"


def _uid_for(res_path: str) -> str:
    """Совместимость со старым именем в render_engine_audio.py."""
    return uid_for(res_path)


def main(argv: list) -> int:
    if len(argv) > 1:
        targets = [os.path.abspath(p) for p in argv[1:]]
    else:
        targets = []
        for folder in ("audio/engine", "audio/vehicle"):
            base = os.path.join(ROOT, folder)
            if not os.path.isdir(base):
                continue
            for name in sorted(os.listdir(base)):
                if name.endswith(".wav"):
                    targets.append(os.path.join(base, name))
    for path in targets:
        if not path.endswith(".wav"):
            print("Пропущено (не WAV): %s" % path)
            continue
        frames = wav_frames(path)
        loop = is_loop_asset(path)
        out = write_import_file(path, loop=loop)
        print("%-52s кадров %6d %-8s -> %s" % (os.path.relpath(path, ROOT), frames,
                                               "луп" if loop else "однораз",
                                               os.path.basename(out)))
    print("Готово: %d файлов" % len(targets))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
