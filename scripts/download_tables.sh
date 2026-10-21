#!/usr/bin/env bash
# Download CDC's annual EHDI Hearing Screening and Follow-up Survey state tables,
# 2015 to 2022, from the CDC archive. Six tables per year:
#   02 screening, 04 screened by 1 month, 06 diagnostics, 07 diagnosed by 3 months,
#   09 early intervention, 10 early intervention by 6 months.
# Usage: bash scripts/download_tables.sh raw/tables
set -e
out="${1:-raw/tables}"; mkdir -p "$out"
base="https://archive.cdc.gov/www_cdc_gov/ncbddd/hearingloss"
for y in 2015 2016 2017 2018 2019 2020 2021 2022; do
  idx="$out/ehdi-data$y.html"
  curl -sL -A "Mozilla/5.0" -o "$idx" "$base/ehdi-data$y.html"
  for p in $(grep -o "/ncbddd/hearingloss/$y-data/\(02\|04\|06\|07\|09\|10\)-[^\"]*" "$idx" | sort -u); do
    curl -sL -A "Mozilla/5.0" -o "$out/${y}_$(basename "$p")" "https://archive.cdc.gov/www_cdc_gov$p"
    sleep 0.5
  done
  echo "$y done"
done
