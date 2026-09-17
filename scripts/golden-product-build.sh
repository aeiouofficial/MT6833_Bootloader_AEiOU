#!/usr/bin/env bash
set -euo pipefail
capture_root="$1"
candidate="$2"
source_img="$capture_root/source-product.img"
tsv="$capture_root/apps.tsv"
for tool in debugfs e2fsck tune2fs sha256sum python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing required WSL tool: $tool (install e2fsprogs/coreutils/python3)" >&2; exit 20; }
done
[[ -f "$source_img" ]] || { echo "missing source product image: $source_img" >&2; exit 21; }
[[ -f "$tsv" ]] || { echo "missing app build table: $tsv" >&2; exit 22; }
if ! e2fsck -fn "$source_img" >/tmp/aeiou-golden-source-fsck.log 2>&1; then
  cat /tmp/aeiou-golden-source-fsck.log >&2
  echo "source product filesystem failed read-only fsck" >&2
  exit 23
fi
cp --reflink=auto "$source_img" "$candidate"
work="$(mktemp -d /tmp/aeiou-golden.XXXXXX)"
trap 'rm -rf "$work"' EXIT
cmds="$work/debugfs.cmd"
: > "$cmds"
while IFS=$'\t' read -r system_dir apk_name rel_file expected_sha; do
  [[ -n "$system_dir" ]] || continue
  src="$capture_root/$rel_file"
  [[ -f "$src" ]] || { echo "missing captured APK: $src" >&2; exit 24; }
  actual_sha="$(sha256sum "$src" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || { echo "captured APK hash mismatch: $rel_file" >&2; exit 25; }
  safe_src="$work/${system_dir}.apk"
  cp "$src" "$safe_src"
  dir="/app/$system_dir"
  dst="$dir/$apk_name"
  {
    echo "mkdir $dir"
    echo "set_inode_field $dir uid 0"
    echo "set_inode_field $dir gid 0"
    echo "set_inode_field $dir mode 040755"
    echo "ea_set $dir security.selinux u:object_r:system_file:s0"
    echo "write $safe_src $dst"
    echo "set_inode_field $dst uid 0"
    echo "set_inode_field $dst gid 0"
    echo "set_inode_field $dst mode 0100644"
    echo "ea_set $dst security.selinux u:object_r:system_file:s0"
  } >> "$cmds"
done < "$tsv"
debugfs -w -f "$cmds" "$candidate" >"$work/debugfs-write.log" 2>&1 || { cat "$work/debugfs-write.log" >&2; exit 26; }
e2fsck -fy "$candidate" >"$work/fsck-fix.log" 2>&1 || rc=$?
rc="${rc:-0}"
if [[ "$rc" -gt 1 ]]; then cat "$work/fsck-fix.log" >&2; echo "candidate fsck repair failed rc=$rc" >&2; exit 27; fi
if ! e2fsck -fn "$candidate" >"$work/fsck-final.log" 2>&1; then cat "$work/fsck-final.log" >&2; echo "candidate filesystem not clean" >&2; exit 28; fi
free_blocks="$(tune2fs -l "$candidate" 2>/dev/null | awk -F: '/^Free blocks:/{gsub(/ /,"",$2);print $2}')"
block_size="$(tune2fs -l "$candidate" 2>/dev/null | awk -F: '/^Block size:/{gsub(/ /,"",$2);print $2}')"
[[ "$free_blocks" =~ ^[0-9]+$ && "$block_size" =~ ^[0-9]+$ ]] || { echo "could not determine candidate free space" >&2; exit 29; }
free_bytes=$((free_blocks * block_size))
(( free_bytes >= 67108864 )) || { echo "candidate product has less than 64 MiB free: $free_bytes" >&2; exit 30; }
while IFS=$'\t' read -r system_dir apk_name rel_file expected_sha; do
  [[ -n "$system_dir" ]] || continue
  dst="/app/$system_dir/$apk_name"
  dumped="$work/${system_dir}.verify.apk"
  debugfs -R "dump -p $dst $dumped" "$candidate" >/dev/null 2>&1 || { echo "cannot dump embedded APK: $dst" >&2; exit 31; }
  actual_sha="$(sha256sum "$dumped" | awk '{print $1}')"
  [[ "$actual_sha" == "$expected_sha" ]] || { echo "embedded APK hash mismatch: $dst" >&2; exit 32; }
  attrs="$(debugfs -R "ea_list $dst" "$candidate" 2>&1)"
  grep -Fq 'security.selinux' <<<"$attrs" || { echo "missing SELinux xattr: $dst" >&2; exit 33; }
  grep -Fq 'u:object_r:system_file:s0' <<<"$attrs" || { echo "wrong SELinux xattr: $dst" >&2; exit 34; }
done < "$tsv"
echo "GOLDEN_PRODUCT_BUILD_OK free_bytes=$free_bytes sha256=$(sha256sum "$candidate" | awk '{print $1}')"
