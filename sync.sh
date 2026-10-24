#!/usr/bin/env bash
# Синхронизация плагинов из рабочей папки Noctalia в этот репозиторий.
#
#   ./sync.sh            # скопировать, закоммитить и запушить
#   SRC=... ./sync.sh    # из другой папки
#
# Рабочая папка остаётся источником правды; здесь — публичная копия.

set -euo pipefail

SRC="${SRC:-$HOME/dev/noctalia-plugins}"
DST="$(cd "$(dirname "$0")" && pwd)"

for p in equalizer ruh-vpn timer; do
  [ -d "$SRC/$p" ] || { echo "нет $SRC/$p" >&2; exit 1; }
  rsync -a --delete \
    --exclude=.git --exclude=__pycache__ --exclude='*.pyc' \
    --exclude=m-idle.png --exclude=m-idle-crop.png \
    "$SRC/$p/" "$DST/$p/"
done

cd "$DST"
git add -A
if git diff --cached --quiet; then
  echo "изменений нет"
  exit 0
fi

git commit -m "sync plugins from $SRC"
git push
