#!/usr/bin/env bash
# Đóng gói Helm chart insighthub thành archive DETERMINISTIC: cùng source →
# cùng sha256, byte-for-byte. Dùng cho source binding của pipeline
# (infra/SPEC.md Mục 12, DAY3-CHECKLIST O.9).
#
# `helm package` KHÔNG deterministic: nhúng mtime của từng file vào tar và
# timestamp vào header gzip. Ở đây tự đóng gói:
#   tar --sort=name  → thứ tự entry cố định (không phụ thuộc readdir)
#   --format=gnu     → không sinh PAX header chứa atime/ctime
#   --mtime=@EPOCH   → mọi entry cùng mtime
#   --owner/--group 0 --numeric-owner → không nhúng uid/gid/tên user của máy build
#   chmod 755/644    → không nhúng umask của máy build
#   gzip -n          → không ghi tên file + mtime vào header gzip
#
# SOURCE_DATE_EPOCH: lấy từ env, nếu không có thì dùng commit time của HEAD
# (cố định theo source, tái lập được trên máy khác).
#
# Dùng:
#   bash scripts/package-chart.sh                 # gói 1 lần, in sha256
#   bash scripts/package-chart.sh --verify        # gói 2 lần, so sha256
#   OUT_DIR=/tmp/x bash scripts/package-chart.sh  # đổi thư mục output
set -euo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHART_DIR=${CHART_DIR:-"$REPO_ROOT/infra/helm/insighthub"}
# evidence/ nằm trong .gitignore → artifact không lọt vào commit.
OUT_DIR=${OUT_DIR:-"$REPO_ROOT/evidence/day3-helm"}
VERIFY=0
[ "${1:-}" = "--verify" ] && VERIFY=1

command -v tar >/dev/null || { echo "FAIL: thiếu tar" >&2; exit 2; }
tar --version 2>/dev/null | head -1 | grep -qi "gnu tar" || {
    echo "FAIL: cần GNU tar (--sort/--mtime/--numeric-owner)" >&2; exit 2; }
[ -f "$CHART_DIR/Chart.yaml" ] || { echo "FAIL: không thấy $CHART_DIR/Chart.yaml" >&2; exit 2; }

CHART_NAME=$(awk '$1=="name:"{print $2; exit}' "$CHART_DIR/Chart.yaml")
CHART_VERSION=$(awk '$1=="version:"{print $2; exit}' "$CHART_DIR/Chart.yaml")
[ -n "$CHART_NAME" ] && [ -n "$CHART_VERSION" ] || {
    echo "FAIL: Chart.yaml thiếu name/version" >&2; exit 2; }

if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
    SOURCE_DATE_EPOCH=$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || echo 0)
fi
export SOURCE_DATE_EPOCH

# Đóng gói vào $1. Staging đặt ngoài repo để .helmignore/chmod không đụng source.
package_to() {
    local dest=$1 stage
    stage=$(mktemp -d)
    trap 'rm -rf "$stage"' RETURN

    # -L: giải symlink (tar sẽ không nhúng đường dẫn tuyệt đối của máy build).
    cp -RL "$CHART_DIR" "$stage/$CHART_NAME"

    # Bỏ file rác + thứ .helmignore loại trừ. Giữ danh sách bám .helmignore của chart.
    find "$stage/$CHART_NAME" \( -name '.DS_Store' -o -name '*.tgz' -o -name '*.bak' \
        -o -name '*.swp' -o -name '*.orig' \) -delete
    rm -rf "$stage/$CHART_NAME/.git" "$stage/$CHART_NAME/.idea" "$stage/$CHART_NAME/.vscode"

    # Chuẩn hóa quyền: không để umask của máy build lọt vào archive.
    find "$stage/$CHART_NAME" -type d -exec chmod 755 {} +
    find "$stage/$CHART_NAME" -type f -exec chmod 644 {} +

    tar --sort=name \
        --format=gnu \
        --mtime="@$SOURCE_DATE_EPOCH" \
        --owner=0 --group=0 --numeric-owner \
        -cf - -C "$stage" "$CHART_NAME" \
        | gzip -n -9 > "$dest"
}

mkdir -p "$OUT_DIR"
TARGET="$OUT_DIR/${CHART_NAME}-${CHART_VERSION}.tgz"

if [ "$VERIFY" -eq 1 ]; then
    tmp_a=$(mktemp) ; tmp_b=$(mktemp)
    package_to "$tmp_a"
    package_to "$tmp_b"
    sha_a=$(sha256sum "$tmp_a" | cut -d' ' -f1)
    sha_b=$(sha256sum "$tmp_b" | cut -d' ' -f1)
    mv "$tmp_a" "$TARGET" ; rm -f "$tmp_b"
    echo "chart:              $CHART_NAME-$CHART_VERSION"
    echo "SOURCE_DATE_EPOCH:  $SOURCE_DATE_EPOCH"
    echo "run 1 sha256:       $sha_a"
    echo "run 2 sha256:       $sha_b"
    echo "archive:            $TARGET"
    if [ "$sha_a" = "$sha_b" ]; then
        echo "DETERMINISTIC: OK"
    else
        echo "DETERMINISTIC: FAIL — 2 lần đóng gói cho sha256 khác nhau" >&2
        exit 1
    fi
else
    package_to "$TARGET"
    echo "chart:             $CHART_NAME-$CHART_VERSION"
    echo "SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH"
    echo "sha256:            $(sha256sum "$TARGET" | cut -d' ' -f1)"
    echo "archive:           $TARGET"
fi
