#!/bin/sh

echo "checking solution id $1"
echo "grep -nr --exclude-dir=.github $1 ./.."
if result=$(grep -nr --exclude-dir='.github' "$1" ./..); then
  printf 'Solution ID %s found\n' "$1"
  echo "$result"
  exit 0
else
  echo "Solution ID $1 not found"
  exit 1
fi
