#!/bin/zsh
# Usage: make-loop.sh <input> <output.m4a> <start seconds> <loop length seconds> [stereo|mono]
# Cuts a segment and crossfades its end into its start (equal power, so there is no volume dip),
# applies one fixed gain to reach a steady level (no pumping), and encodes AAC.
set -euo pipefail
in="$1"; out="$2"; start="$3"; len="$4"; ch="${5:-stereo}"; fade=5
layout=stereo; [[ "$ch" == mono ]] && layout=mono
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
ffmpeg -v error -y -ss "$start" -t $((len + fade)) -i "$in" -filter_complex "
[0:a]aformat=sample_rates=44100:channel_layouts=${layout},asplit=3[w][h][t];
[w]atrim=start=${len}:end=$((len + fade)),asetpts=PTS-STARTPTS,afade=t=out:st=0:d=${fade}:curve=qsin[cont];
[h]atrim=start=0:end=${fade},asetpts=PTS-STARTPTS,afade=t=in:st=0:d=${fade}:curve=qsin[head];
[head][cont]amix=inputs=2:normalize=0:duration=first[x];
[t]atrim=start=${fade}:end=${len},asetpts=PTS-STARTPTS[tail];
[x][tail]concat=n=2:v=0:a=1[o]" -map "[o]" "$tmp/loop.wav"
mean=$(ffmpeg -hide_banner -i "$tmp/loop.wav" -af volumedetect -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p')
gain=$(printf '%.1f' $((-26.0 - mean)))
ffmpeg -v error -y -i "$tmp/loop.wav" -af "volume=${gain}dB,alimiter=limit=0.9" -c:a aac -b:a 112k "$out"
