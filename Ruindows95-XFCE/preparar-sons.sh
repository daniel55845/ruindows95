#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$(realpath "$0")")"
command -v ffmpeg >/dev/null || { echo 'Instale ffmpeg no ambiente de preparação.'; exit 1; }
mkdir -p sons
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ $# == 2 ]]; then
  first=$1; second=$2
else
  echo 'Uso: bash preparar-sons.sh inicializacao.mp3 usb.mp3'; exit 2
fi
ffmpeg -nostdin -v error -y -i "$first" -map 0:a:0 -t 25 -ac 2 -ar 48000 -c:a pcm_s16le "$work/startup.wav"
ffmpeg -nostdin -v error -y -i "$second" -map 0:a:0 -t 10 -ac 2 -ar 48000 -c:a pcm_s16le "$work/usb.wav"
python3 verificar-sons.py "$work"
install -m644 "$work/startup.wav" sons/startup.wav
install -m644 "$work/usb.wav" sons/usb.wav
printf 'Sons preparados. Agora execute sudo bash build.sh.\n'
