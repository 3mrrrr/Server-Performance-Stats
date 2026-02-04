#!/usr/bin/env bash
set -euo pipefail

# server-stats.sh
# Basic server performance stats (CPU, memory, disk, top processes)

hr() { printf '%*s\n' "${COLUMNS:-60}" '' | tr ' ' '-'; }

echo "Server Stats - $(hostname) - $(date)"
hr

# -------- CPU (total) --------
# Try parsing "top" summary. Works across many distros.
cpu_idle="$(
  top -bn1 2>/dev/null | awk '
    /Cpu\(s\):/ || /%Cpu\(s\):/ {
      for (i=1; i<=NF; i++) if ($i ~ /id,?/){print $(i-1); exit}
    }'
)"
# Fallback (busy = 100 - idle). If parsing fails, show N/A.
if [[ -n "${cpu_idle:-}" ]]; then
  cpu_used="$(awk -v idle="$cpu_idle" 'BEGIN{printf "%.1f", (100.0 - idle)}')"
  echo "Total CPU usage: ${cpu_used}%"
else
  echo "Total CPU usage: N/A (could not parse top output)"
fi

hr

# -------- Memory --------
# free -m output is consistent: Mem: total used free ...
read -r mem_total mem_used mem_free mem_shared mem_buff_cache mem_available < <(
  free -m | awk '/^Mem:/ {print $2,$3,$4,$5,$6,$7}'
)

# "Used" commonly considered total - available (more meaningful than free column)
mem_used_effective=$(( mem_total - mem_available ))
mem_free_effective=$mem_available

mem_used_pct="$(awk -v u="$mem_used_effective" -v t="$mem_total" 'BEGIN{printf "%.1f", (u/t)*100}')"
mem_free_pct="$(awk -v f="$mem_free_effective" -v t="$mem_total" 'BEGIN{printf "%.1f", (f/t)*100}')"

echo "Total memory usage:"
echo "  Used: ${mem_used_effective} MiB (${mem_used_pct}%)"
echo "  Free: ${mem_free_effective} MiB (${mem_free_pct}%)"

hr

# -------- Disk --------
# Use df -P for POSIX output; summarize totals across all local filesystems.
# Exclude pseudo filesystems commonly not relevant.
disk_line="$(df -P -B1 \
  -x tmpfs -x devtmpfs -x squashfs -x overlay -x aufs 2>/dev/null \
  | awk 'NR>1 {t+=$2; u+=$3; a+=$4} END {print t,u,a}')"

read -r disk_total_b disk_used_b disk_free_b <<< "$disk_line"

if [[ -n "${disk_total_b:-}" && "$disk_total_b" -gt 0 ]]; then
  disk_used_pct="$(awk -v u="$disk_used_b" -v t="$disk_total_b" 'BEGIN{printf "%.1f", (u/t)*100}')"
  disk_free_pct="$(awk -v f="$disk_free_b" -v t="$disk_total_b" 'BEGIN{printf "%.1f", (f/t)*100}')"

  # Human readable (GiB)
  to_gib() { awk -v b="$1" 'BEGIN{printf "%.2f", b/1024/1024/1024}'; }

  echo "Total disk usage (local filesystems):"
  echo "  Used: $(to_gib "$disk_used_b") GiB (${disk_used_pct}%)"
  echo "  Free: $(to_gib "$disk_free_b") GiB (${disk_free_pct}%)"
else
  echo "Total disk usage: N/A"
fi

hr

# -------- Top processes --------
echo "Top 5 processes by CPU usage:"
# Print: PID  %CPU  %MEM  COMMAND
ps -eo pid,pcpu,pmem,comm --sort=-pcpu | head -n 6 | awk 'NR==1{printf "  %-8s %-6s %-6s %s\n",$1,$2,$3,$4; next} {printf "  %-8s %-6s %-6s %s\n",$1,$2,$3,$4}'

hr

echo "Top 5 processes by memory usage:"
ps -eo pid,pcpu,pmem,comm --sort=-pmem | head -n 6 | awk 'NR==1{printf "  %-8s %-6s %-6s %s\n",$1,$2,$3,$4; next} {printf "  %-8s %-6s %-6s %s\n",$1,$2,$3,$4}'

hr