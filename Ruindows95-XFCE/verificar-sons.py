#!/usr/bin/env python3
import sys
import wave
from pathlib import Path


def validate(folder):
    for name, limit in [('startup.wav', 25), ('usb.wav', 10)]:
        path = Path(folder) / name
        try:
            with wave.open(str(path), 'rb') as w:
                if not (w.getcomptype() == 'NONE' and w.getsampwidth() == 2 and
                        w.getnchannels() == 2 and w.getframerate() == 48000 and
                        0 < w.getnframes() <= limit * 48000 and
                        len(w.readframes(w.getnframes())) == w.getnframes() * 4):
                    raise ValueError('WAV PCM 16-bit estéreo 48 kHz inválido ou longo demais')
        except (OSError, EOFError, wave.Error, ValueError) as exc:
            raise SystemExit(f'{path}: {exc}. Execute bash preparar-sons.sh primeiro.')


if __name__ == '__main__':
    validate(sys.argv[1] if len(sys.argv) > 1 else 'sons')
