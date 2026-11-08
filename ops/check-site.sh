#!/usr/bin/env bash
# Lists what is still missing on the website before you submit:
#   - yellow FILL markers (real values you still have to type in)
#   - evidence screenshots the pages expect but that are not in docs/evidence/ yet
#   bash ops/check-site.sh
cd "$(dirname "$0")/../docs" || exit 1

echo "== FILL markers left, per page"
total=0
for f in *.html; do
  n=$(grep -o 'FILL' "$f" | wc -l)
  total=$((total + n))
  [[ $n -gt 0 ]] && printf '  %-24s %3d\n' "$f" "$n"
done
echo "  total: $total"

echo
echo "== Evidence images still missing"
missing=0
for img in $(grep -oh 'src="evidence/[^"]*"' ./*.html | sed 's/src="//;s/"$//' | sort -u); do
  if [[ ! -f "$img" ]]; then echo "  $img"; missing=$((missing + 1)); fi
done
echo "  missing: $missing"

echo
echo "== Video"
grep -q 'embed/VIDEO_ID' index.html && echo "  index.html still has VIDEO_ID - paste your YouTube video id" || echo "  video id set"

[[ $total -eq 0 && $missing -eq 0 ]] && echo "READY." || echo "NOT READY YET."
