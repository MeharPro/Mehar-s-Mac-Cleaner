#!/usr/bin/env bash

###############################################################################
# full-mac-cleaner.sh — The Ultimate Dynamic macOS Storage Cleaner
# Author: Mehar Khanna
# License: MIT
###############################################################################

set -euo pipefail

#── CONFIGURATION ─────────────────────────────────────────────────────────────

MIN_SIZE_BYTES=$((500 * 1024 * 1024))   # 500 MB threshold

EXCLUDES=(
  "/System"
  "/Applications"
  "/private/var/vm"
  "/Volumes"
  "/Users/$USER/Documents"
  "/Users/$USER/Downloads"
  "/Users/$USER/Desktop"
  "/dev"
)

CACHE_PATHS=(
  "~/Library/Caches"
  "/Library/Caches"
  "/System/Library/Caches"
  "/private/var/folders"
  "~/Library/Logs"
  "/private/var/log"
  "/Users/$USER/Library/Developer/Xcode/DerivedData"
  "/Users/$USER/Library/Developer/CoreSimulator"
  "/Users/$USER/.cache"
)

QUARANTINE_DIR=~/Desktop/mac_cleaner_quarantine_$(date +%Y%m%d_%H%M%S)

#── SETUP ──────────────────────────────────────────────────────────────────────

RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

LOGFILE_TMP=/tmp/cleaner_log_$(date +%Y%m%d_%H%M%S).txt
: > "$LOGFILE_TMP"

EXCLUDE_ARGS=()
for p in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=( -path "$p" -prune -o )
done

trap 'echo -e "\n${YELLOW}Interrupted by user; exiting cleanly.${RESET}" >>"$LOGFILE_TMP"; exit 1' INT

echo "${CYAN}🔐  Requesting sudo permissions...${RESET}"
sudo -v

#── UTILITY FUNCTIONS ──────────────────────────────────────────────────────────

log()   { echo -e "$*" | tee -a "$LOGFILE_TMP"; }
abort() { echo -e "${RED}✖ $*${RESET}"; exit 2; }

size_human() { awk -v bytes="$1" 'BEGIN {
  split("B KB MB GB TB PB", units);
  for (i=1; bytes>=1024 && i<6; i++) bytes/=1024;
  printf "%.1f%s\n", bytes, units[i]
}'; }

scan_large_folders() {
  sudo du -x -B1 -d1 / "${EXCLUDE_ARGS[@]}" \
    2>/dev/null | sort -nrk1 | awk -v min="$MIN_SIZE_BYTES" '$1>=min' | head -n20
}

cleanup_caches() {
  log "${CYAN}🧹 Clearing known caches...${RESET}"
  for path in "${CACHE_PATHS[@]}"; do
    eval target=${path/#\~/$HOME}
    if [ -d "$target" ]; then
      sudo find "$target" -mindepth 1 -maxdepth 1 -exec sudo rm -rf {} \; 2>/dev/null || true
      log "  • Cleared $target"
    fi
  done
}

delete_or_quarantine() {
  local item=$1
  if [ "$DRY_RUN" = true ]; then
    log "  [DRY] Would delete $item"
  elif [ "$QUARANTINE" = true ]; then
    mkdir -p "$QUARANTINE_DIR"
    sudo mv "$item" "$QUARANTINE_DIR"/ 2>/dev/null || true
    log "  • Quarantined $item"
  else
    sudo rm -rf "$item" 2>/dev/null || true
    log "  • Deleted $item"
  fi
}

#── MAIN ───────────────────────────────────────────────────────────────────────

echo "${GREEN}⚙️  Starting full-machine storage cleanup.${RESET}"
log "Logfile: $LOGFILE_TMP"
log "Excluding: ${EXCLUDES[*]}"
log "Threshold: $(size_human $MIN_SIZE_BYTES)"

echo
read -p "🚦  Dry-run only? (no deletions) [y/N]: " ans
DRY_RUN=false; [[ $ans =~ ^[Yy] ]] && DRY_RUN=true

echo
read -p "📦  Move items to quarantine folder instead of permanent delete? [y/N]: " ans
QUARANTINE=false; [[ $ans =~ ^[Yy] ]] && QUARANTINE=true

echo
read -p "❗  Do you want to auto-clear caches first? [Y/n]: " ans
[[ ! $ans =~ ^[Nn] ]] && cleanup_caches

echo
log "${CYAN}📊 Scanning for large folders...${RESET}"

LARGE=()
while IFS= read -r line; do
  LARGE+=("$line")
done < <(scan_large_folders | awk '{print $1" "$2}')

echo "${CYAN}Found ${#LARGE[@]} folders above threshold.${RESET}" | tee -a "$LOGFILE_TMP"

for entry in "${LARGE[@]}"; do
  size=$(echo "$entry" | awk '{print $1}')
  dir=$(echo "$entry" | awk '{print $2}')
  echo
  echo -e "${YELLOW}📂 $dir${RESET} — $(size_human $size)"
  echo "Contents preview:"
  sudo du -x -h -d1 "$dir" 2>/dev/null | sort -hr | head -10

  read -p "⚠️  Delete ALL contents inside this folder? [y/N]: " choice
  if [[ $choice =~ ^[Yy] ]]; then
    delete_or_quarantine "$dir"
  else
    log "Skipped $dir"
  fi
done

echo
echo "${GREEN}🎉 Cleanup session complete!${RESET}"
if [ "$DRY_RUN" = true ]; then
  echo "— Dry-run mode; no actual deletions performed."
elif [ "$QUARANTINE" = true ]; then
  echo "— Items moved to quarantine: $QUARANTINE_DIR"
fi

cp "$LOGFILE_TMP" ~/Desktop/ 2>/dev/null || true
echo "— Detailed log at: ~/Desktop/$(basename "$LOGFILE_TMP")"

exit 0
