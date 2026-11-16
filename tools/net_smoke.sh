#!/usr/bin/env bash
# Çevrimiçi duman testi: aynı makinede bir ev sahibi ve bir katılan açar, ikisinin de
# ekran görüntüsünü alır ve NETPROBE satırlarını yazdırır.
#   GODOT=/yol/godot tools/net_smoke.sh [çıktı_klasörü]
set -euo pipefail
G=${GODOT:-godot}
OUT=${1:-/tmp/net}
mkdir -p "$OUT"
# RELAY=ws://127.0.0.1:8765 verilirse oda koduyla (aracı üzerinden) bağlanır.
R=""
[ -n "${RELAY:-}" ] && R="--relay=$RELAY"
B="--quality=1 --bridge=oak,pine,copper --no_finale=1 --step=11 --locale=tr"
xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . -- --screenshot="$OUT/host.png" $B --give=1 \
	--player=-9.5,9.5,-80 $R --net_host=1 --net_wave=1 --net_wait=18 --frames=20 > "$OUT/host.log" 2>&1 &
HOST=$!
TARGET=127.0.0.1
if [ -n "$R" ]; then
	until grep -q "room [A-Z]" "$OUT/host.log" 2>/dev/null; do sleep 1; done
	TARGET=$(grep -o "room [A-Z]*" "$OUT/host.log" | cut -d' ' -f2)
else
	sleep 8
fi
timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . -- --screenshot="$OUT/guest.png" --quality=1 \
	--locale=tr $R --net_join=$TARGET --net_wait=10 --net_attack=3 --frames=12 > "$OUT/guest.log" 2>&1 || true
wait $HOST || true
grep -h NETPROBE "$OUT"/host.log "$OUT"/guest.log
