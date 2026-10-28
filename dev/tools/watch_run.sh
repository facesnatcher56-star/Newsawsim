#!/usr/bin/env bash
# Watchdog for a visible Godot demo run: waits until the log shows DONE_PATTERN, or until
# no line matching PROGRESS_PATTERN has appeared for STALL seconds, then kills the run.
# Usage: watch_run.sh LOG PID DONE_PATTERN PROGRESS_PATTERN [STALL=60] [MAX=900]
log="$1"; pid="$2"; done_pat="$3"; prog_pat="$4"; stall="${5:-60}"; max="${6:-900}"
last_count=-1; last_t=$(date +%s); start=$last_t
while true; do
  sleep 3
  now=$(date +%s)
  if grep -aqE "$done_pat" "$log" 2>/dev/null; then echo "DONE after $((now - start)) s"; break; fi
  if grep -aq "SCRIPT ERROR" "$log" 2>/dev/null; then echo "SCRIPT ERROR after $((now - start)) s"; break; fi
  count=$(grep -acE "$prog_pat" "$log" 2>/dev/null)
  if [ "$count" != "$last_count" ]; then last_count=$count; last_t=$now; fi
  if [ $((now - last_t)) -ge "$stall" ]; then echo "STALLED: no progress for $stall s (at $((now - start)) s)"; break; fi
  if [ $((now - start)) -ge "$max" ]; then echo "TIME LIMIT $max s"; break; fi
done
powershell.exe -NoProfile -Command "Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue"
if powershell.exe -NoProfile -Command "Get-Process -Id $pid -ErrorAction SilentlyContinue" | grep -q "$pid"; then echo "WARNING: run $pid still alive"; fi
echo "run $pid stopped"
