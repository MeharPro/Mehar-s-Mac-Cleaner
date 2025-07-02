#!/usr/bin/env bash

###############################################################################
# full-mac-cleaner.sh — The Ultimate Dynamic macOS Storage Cleaner
# Author: Mehar Khanna
# License: MIT
###############################################################################

set -euo pipefail

#── CONFIGURATION ─────────────────────────────────────────────────────────────

# Size threshold for “large folder” (in bytes). e.g. 500M = 500*1024*1024
MIN_SIZE_BYTES=$((500 * 1024 * 1024))

# Paths to exclude from ANY scanning or deletion
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

# Extra cache targets for Homebrew, Xcode, Docker, etc.
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

# Quarantine folder prefix (for backup instead of rm)
QUARANTINE_DIR=~/Desktop/mac_cleaner_quarantine_$(date +%Y%m%d_%H%M%S)

#── SETUP ──────────────────────────────────────────────────────────────────────

# Color helpers
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

LOGFILE=~/Desktop/cleaner_log_$(date +%Y%m%d_%H%M%S).txt
touch "$LOGFILE"

# Build find exclude args
EXCLUDE_ARGS=()
for p in "${EXCLUDES[@]}"; do
  EXCLUDE_ARGS+=( -path "$p" -prune -o )
done

# Trap Ctrl+C
trap 'echo -e "\n${YELLOW}Interrupted by user; exiting cleanly.${RESET}" >>"$LOGFILE"; exit 1' INT

# Require sudo upfront
echo "${CYAN}🔐  Requesting sudo permissions...${RESET}"
sudo -v

#── UTILITY FUNCTIONS ──────────────────────────────────────────────────────────

log()   { echo -e "$*" | tee -a "$LOGFILE"; }
abort() { echo -e "${RED}✖ $*${RESET}"; exit 2; }

size_human() { numfmt --to=iec --suffix=B --format="%.1f" "$1"; }

# List top N largest folders under /
scan_large_folders() {
  sudo du -x -B1 -d1 / "${EXCLUDE_ARGS[@]}" \
    2>/dev/null | sort -nrk1 | awk -v min="$MIN_SIZE_BYTES" '$1>=min' | head -n20
}

# Cleanup caches (with optional backup)
cleanup_caches() {
  log "${CYAN}🧹 Clearing known caches...${RESET}"
  for path in "${CACHE_PATHS[@]}"; do
    eval target=${path/#\~/$HOME}
    if [ -d "$target" ]; then
      sudo find "$target" -mindepth 1 -maxdepth 1 -exec sudo rm -rf {} \; \
        && log "  • Cleared $target" \
        || log "${YELLOW}  • Skipped $target${RESET}"
    fi
  done
}

# Quarantine instead of rm if backup was requested
delete_or_quarantine() {
  local item=$1
  if [ "$DRY_RUN" = true ]; then
    log "  [DRY] Would delete $item"
  elif [ "$QUARANTINE" = true ]; then
    mkdir -p "$QUARANTINE_DIR"
    sudo mv "$item" "$QUARANTINE_DIR"/ \
      && log "  • Quarantined $item" \
      || log "${YELLOW}  • Failed to quarantine $item${RESET}"
  else
    sudo rm -rf "$item" \
      && log "  • Deleted $item" \
      || log "${YELLOW}  • Failed to delete $item${RESET}"
  fi
}

#── MAIN ───────────────────────────────────────────────────────────────────────

echo "${GREEN}⚙️  Starting full-machine storage cleanup.${RESET}"
log "Logfile: $LOGFILE"
log "Excluding: ${EXCLUDES[*]}"
log "Threshold: $(size_human $MIN_SIZE_BYTES)"

# Ask for dry run / quarantine / real delete
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
mapfile -t LARGE < <(scan_large_folders | awk '{print $1" "$2}')
echo "${CYAN}Found ${#LARGE[@]} folders above threshold.${RESET}" | tee -a "$LOGFILE"

# Ask to delete each
for entry in "${LARGE[@]}"; do
  size=$(echo "$entry" | awk '{print $1}')
  dir=$(echo "$entry" | awk '{print $2}')
  echo
  echo -e "${YELLOW}📂 $dir${RESET} — ${size_human $size}"
  echo "Contents preview:"
  sudo du -x -h -d1 "$dir" 2>/dev/null | sort -hr | head -10

  read -p "⚠️  Delete ALL contents inside this folder? [y/N]: " choice
  if [[ $choice =~ ^[Yy] ]]; then
    delete_or_quarantine "$dir"
  else
    log "Skipped $dir"
  fi
done

# Summary
echo
echo "${GREEN}🎉 Cleanup session complete!${RESET}"
if [ "$DRY_RUN" = true ]; then
  echo "— Dry-run mode; no actual deletions performed."
elif [ "$QUARANTINE" = true ]; then
  echo "— Items moved to quarantine: $QUARANTINE_DIR"
fi
echo "— Detailed log at: $LOGFILE"

exit 0
