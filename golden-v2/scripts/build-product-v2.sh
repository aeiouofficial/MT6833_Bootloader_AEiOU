#!/usr/bin/env bash
set -euo pipefail
capture_root="$1"
candidate="$2"
provisioner_apk="$3"
apps_json="$4"
permissions_xml="$5"
tsv="$6"
source_img="$capture_root/source-product.img"
for tool in debugfs e2fsck tune2fs sha256sum; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 20; }
done
for f in "$source_img" "$provisioner_apk" "$apps_json" "$permissions_xml" "$tsv"; do
  [[ -f "$f" ]] || { echo "missing input: $f" >&2; exit 21; }
done
if ! e2fsck -fn "$source_img" >/tmp/aeiou-v2-source-fsck.log 2>&1; then
  cat /tmp/aeiou-v2-source-fsck.log >&2
  exit 22
fi
cp --reflink=auto "$source_img" "$candidate"
work="$(mktemp -d /tmp/aeiou-golden-v2.XXXXXX)"
trap 'rm -rf "$work"' EXIT
cmds="$work/debugfs.cmd"
: > "$cmds"
add_dir() {
  local dir="$1"
  {
    echo "mkdir $dir"
    echo "set_inode_field $dir uid 0"
    echo "set_inode_field $dir gid 0"
    echo "set_inode_field $dir mode 040755"
    echo "ea_set $dir security.selinux u:object_r:system_file:s0"
  } >> "$cmds"
}
add_file() {
  local src="$1" dst="$2" safe="$3"
  cp "$src" "$work/$safe"
  {
    echo "write $work/$safe $dst"
    echo "set_inode_field $dst uid 0"
    echo "set_inode_field $dst gid 0"
    echo "set_inode_field $dst mode 0100644"
    echo "ea_set $dst security.selinux u:object_r:system_file:s0"
  } >> "$cmds"
}
add_dir /etc/aeiou-golden
add_dir /etc/aeiou-golden/apks
add_dir /priv-app/AEiOUGoldenProvisioner
add_file "$apps_json" /etc/aeiou-golden/apps.json apps.json
add_file "$permissions_xml" /etc/permissions/privapp-permissions-aeiou-golden.xml perms.xml
add_file "$provisioner_apk" /priv-app/AEiOUGoldenProvisioner/AEiOUGoldenProvisioner.apk provisioner.apk
while IFS=$'\t' read -r mode system_dir apk_name rel_file expected_sha; do
  [[ -n "$mode" ]] || continue
  expected_sha="${expected_sha%$'\r'}"
  src="$capture_root/$rel_file"
  [[ -f "$src" ]] || { echo "missing APK: $src" >&2; exit 23; }
  actual="$(sha256sum "$src" | awk '{print $1}')"
  [[ "$actual" == "$expected_sha" ]] || { echo "APK hash mismatch: $rel_file" >&2; exit 24; }
  safe="$(basename "$apk_name").$RANDOM.apk"
  if [[ "$mode" == "system" ]]; then
    [[ -n "$system_dir" ]] || { echo "systemDir missing for $apk_name" >&2; exit 25; }
    add_dir "/app/$system_dir"
    add_file "$src" "/app/$system_dir/$apk_name" "$safe"
  elif [[ "$mode" == "provision" ]]; then
    add_file "$src" "/etc/aeiou-golden/apks/$apk_name" "$safe"
  else
    echo "unknown app mode: $mode" >&2; exit 26
  fi
done < "$tsv"
debugfs -w -f "$cmds" "$candidate" >"$work/write.log" 2>&1 || { cat "$work/write.log" >&2; exit 27; }
rc=0
e2fsck -fy "$candidate" >"$work/fsck-fix.log" 2>&1 || rc=$?
if [[ "$rc" -gt 1 ]]; then cat "$work/fsck-fix.log" >&2; exit 28; fi
if ! e2fsck -fn "$candidate" >"$work/fsck-final.log" 2>&1; then cat "$work/fsck-final.log" >&2; exit 29; fi
free_blocks="$(tune2fs -l "$candidate" 2>/dev/null | awk -F: '/^Free blocks:/{gsub(/ /,"",$2);print $2}')"
block_size="$(tune2fs -l "$candidate" 2>/dev/null | awk -F: '/^Block size:/{gsub(/ /,"",$2);print $2}')"
[[ "$free_blocks" =~ ^[0-9]+$ && "$block_size" =~ ^[0-9]+$ ]] || exit 30
free_bytes=$((free_blocks * block_size))
(( free_bytes >= 67108864 )) || { echo "less than 64 MiB free: $free_bytes" >&2; exit 31; }
if debugfs -R 'stat /app/AEiOU_AppManager' "$candidate" 2>&1 | grep -q 'Inode:'; then
  echo 'forbidden system App Manager path exists' >&2; exit 32
fi
while IFS=$'\t' read -r mode system_dir apk_name rel_file expected_sha; do
  [[ -n "$mode" ]] || continue
  expected_sha="${expected_sha%$'\r'}"
  if [[ "$mode" == "system" ]]; then dst="/app/$system_dir/$apk_name"; else dst="/etc/aeiou-golden/apks/$apk_name"; fi
  dumped="$work/verify-$RANDOM.apk"
  debugfs -R "dump -p $dst $dumped" "$candidate" >/dev/null 2>&1 || exit 33
  [[ "$(sha256sum "$dumped" | awk '{print $1}')" == "$expected_sha" ]] || exit 34
  attrs="$(debugfs -R "ea_list $dst" "$candidate" 2>&1)"
  grep -Fq 'u:object_r:system_file:s0' <<<"$attrs" || exit 35
done < "$tsv"
for dst in /etc/aeiou-golden/apps.json /etc/permissions/privapp-permissions-aeiou-golden.xml /priv-app/AEiOUGoldenProvisioner/AEiOUGoldenProvisioner.apk; do
  debugfs -R "stat $dst" "$candidate" 2>&1 | grep -q 'Inode:' || { echo "missing embedded file: $dst" >&2; exit 36; }
done
echo "GOLDEN_V2_PRODUCT_OK free_bytes=$free_bytes sha256=$(sha256sum "$candidate" | awk '{print $1}')"
