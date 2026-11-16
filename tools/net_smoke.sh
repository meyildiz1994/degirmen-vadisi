#!/usr/bin/env bash
# Çevrimiçi duman testi: aynı makinede bir ev sahibi ve bir katılan açar, ikisinin de
# ekran görüntüsünü alır ve NETPROBE satırlarını yazdırır.
#   GODOT=/yol/godot tools/net_smoke.sh [çıktı_klasörü]
set -euo pipefail
G=${GODOT:-godot}
OUT=${1:-/tmp/net}
mkdir -p "$OUT"
B="--quality=1 --bridge=oak,pine,copper --no_finale=1 --step=11 --locale=tr"
xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . -- --screenshot="$OUT/host.png" $B --give=1 \
	--player=-9.5,9.5,-80 --net_host=1 --net_wave=1 --net_wait=18 --frames=20 > "$OUT/host.log" 2>&1 &
HOST=$!
sleep 8
timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$G" --path . -- --screenshot="$OUT/guest.png" --quality=1 \
	--locale=tr --net_join=127.0.0.1 --net_wait=10 --net_attack=3 --frames=12 > "$OUT/guest.log" 2>&1 || true
wait $HOST || true
grep -h NETPROBE "$OUT"/host.log "$OUT"/guest.log
