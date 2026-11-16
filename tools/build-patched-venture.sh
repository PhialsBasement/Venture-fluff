#!/usr/bin/env bash
set -euo pipefail

readonly REPO_URL="https://github.com/Villagers654/Venture.git"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly PATCH_FILE="$SCRIPT_DIR/frida-compat.patch"
readonly DESTINATION="${1:-$PWD/venture-patched}"

if [[ ! -f "$PATCH_FILE" ]]; then
  echo "Missing compatibility patch: $PATCH_FILE" >&2
  exit 1
fi
for command in git python3 clang++; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Required command not found: $command" >&2
    exit 1
  fi
done
if [[ -e "$DESTINATION" && ! -d "$DESTINATION" ]]; then
  echo "Destination exists and is not a directory: $DESTINATION" >&2
  exit 1
fi
if [[ -d "$DESTINATION" && -n "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Destination is not empty: $DESTINATION" >&2
  echo "Choose an empty directory to avoid overwriting local work." >&2
  exit 1
fi

mkdir -p "$(dirname -- "$DESTINATION")"
git clone --depth 1 "$REPO_URL" "$DESTINATION"
git -C "$DESTINATION" apply --check "$PATCH_FILE"
git -C "$DESTINATION" apply "$PATCH_FILE"

python3 "$DESTINATION/tools/bootstrap.py" --jdk

cmake_bin="$DESTINATION/.deps/cmake/bin/cmake"
openssl_args=()
# Some distributions default to OpenSSL 4 while also retaining OpenSSL 3.
if [[ -d /usr/include/openssl-3 && -d /usr/lib/openssl-3 ]]; then
  openssl_args+=(
    -DOPENSSL_INCLUDE_DIR=/usr/include/openssl-3
    -DOPENSSL_SSL_LIBRARY=/usr/lib/openssl-3/libssl.so
    -DOPENSSL_CRYPTO_LIBRARY=/usr/lib/openssl-3/libcrypto.so
  )
fi
"$cmake_bin" --preset linux-release "${openssl_args[@]}"
"$cmake_bin" --build --preset linux-release

"$DESTINATION/.deps/cmake/bin/ctest" --preset linux-release \
  -R '^(replacement_exports_a64|replacement_exports_a32|guest_module_iteration|java_script_loader|output_mirror)$'
"$DESTINATION/build/linux-release/bin/venture_tests" '--source-file=*ovrplatform_test.cpp'
"$DESTINATION/build/linux-release/bin/venture_tests" '--source-file=*test_launcher.cpp'

cat <<EOF

Patched Venture is ready:
  $DESTINATION/build/linux-release/bin/venture
EOF
