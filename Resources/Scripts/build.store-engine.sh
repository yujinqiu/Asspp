#!/bin/bash
set -euo pipefail
store_repo_dir=$(cd "$(dirname "$0")/../.." && pwd)
store_output_dir=${1:?Destination directory required}
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
store_go=$(command -v go)
mkdir -p "$store_output_dir"
cd "$store_repo_dir/StoreEngine"
store_build_dir=$(mktemp -d)
trap 'rm -rf "$store_build_dir"' EXIT
for store_arch in ${ARCHS:-arm64}; do
    GOOS=darwin GOARCH="$store_arch" CGO_ENABLED=1 "$store_go" build -trimpath -o "$store_build_dir/$store_arch" .
done
store_inputs=()
for store_arch in ${ARCHS:-arm64}; do store_inputs+=("$store_build_dir/$store_arch"); done
if [ "${#store_inputs[@]}" -eq 1 ]; then
    cp "${store_inputs[0]}" "$store_output_dir/AssppStore"
else
    /usr/bin/lipo -create "${store_inputs[@]}" -output "$store_output_dir/AssppStore"
fi
chmod 755 "$store_output_dir/AssppStore"
store_resources_dir="$(dirname "$store_output_dir")/Resources"
mkdir -p "$store_resources_dir"
cp "$store_repo_dir/Resources/Document/IPATOOL-LICENSE.txt" "$store_resources_dir/IPATOOL-LICENSE.txt"
