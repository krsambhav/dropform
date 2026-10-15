#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
app="${1:-$PWD/dist/Dropform.app}"
[[ -d "$app/Contents/Resources/Engines" ]]
profile=$(mktemp)
trap 'rm -f "$profile"' EXIT
cat > "$profile" <<'POLICY'
(version 1)
(allow default)
(deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local") (subpath "/Applications/LibreOffice.app"))
(deny network-outbound (remote ip "*:*"))
POLICY
# No engine lookup fallback; additionally deny Homebrew, external Office and network access.
env PATH=/usr/bin:/bin /usr/bin/sandbox-exec -f "$profile" "$app/Contents/MacOS/Dropform" --self-test
env PATH=/usr/bin:/bin /usr/bin/sandbox-exec -f "$profile" "$app/Contents/MacOS/Dropform" --preview-self-test
