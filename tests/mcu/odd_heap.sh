#!/usr/bin/env bash
# an arena on a heap whose size isn't a multiple of 64 (heap = "10000" in zs.toml): its blocks
# are rounded to 8, so the heap's blocks after them stay aligned (a Cortex-M0+ faults on an
# unaligned word), under QEMU
set -u
zs="$(pwd)/${1:-bin/zs}"; t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$t/odd/src"
printf '[package]\nname = "odd"\nversion = "0.1.0"\n\n[target.cortex-m0plus]\nheap = "10000"\n' > "$t/odd/zs.toml"
cat > "$t/odd/src/main.zs" <<'ZS'
type Tree =
  | Leaf
  | Node of Tree * Tree

let rec make d = if d = 0 then Node(Leaf, Leaf) else Node(make (d - 1), make (d - 1))

let rec check t =
  match t with
  | Leaf -> 0
  | Node(l, r) -> 1 + check l + check r

let main () =
  let a = Arena.with (fun () -> check (make 2))
  let t = make 3
  println $"{a} {check t}"
  0
ZS
cd "$t/odd" && "$zs" build --target cortex-m0plus -o "$t/odd.elf" || exit 1
timeout 60 qemu-system-arm -M microbit -nographic -semihosting-config enable=on,target=native -kernel "$t/odd.elf" 2>&1 | grep -v '^#zs'
