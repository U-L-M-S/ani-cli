#!/bin/sh
# Offline tests for the history and the continue menu of ani-cli. Run: sh tests/history.sh

cd "$(dirname "$0")/.." || exit 1

grep -q '^# MAIN$' ani-cli || {
    printf 'the "# MAIN" marker is missing in ani-cli, refusing to load it\n'
    exit 1
}
# shellcheck disable=SC2312
eval "$(sed -n '1,/^# MAIN$/p' ani-cli)"

# no network: episode lists per anime id, and a fixed playlist length
# shellcheck disable=SC2317,SC2329
hianime_episodes() {
    case "$1" in
        three-episodes-1) printf '11\t1\n12\t2\n13\t3\n' ;;
        one-episode-2) printf '21\t1\n' ;;
        *) ;;
    esac
}
# shellcheck disable=SC2317,SC2329
playlist_length() {
    printf "1440"
}

tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
# the loaded functions use these
# shellcheck disable=SC2034
histfile="$tmp/ani-hsts"
# shellcheck disable=SC2034
hist_dir="$tmp"
# shellcheck disable=SC2034
now=1700000000
failed=0

# $1 = name, $2 = expected, $3 = actual
check() {
    if [ "$2" = "$3" ]; then
        printf 'ok   %s\n' "$1"
    else
        printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
        failed=1
    fi
}

actual=$(clock 754)
check "clock formats minutes" "12:34" "$actual"
actual=$(clock 3725)
check "clock formats hours" "1:02:05" "$actual"
actual=$(time_ago $((now - 30)))
check "time_ago just now" "just now" "$actual"
actual=$(time_ago $((now - 300)))
check "time_ago minutes" "5 minutes ago" "$actual"
actual=$(time_ago $((now - 3700)))
check "time_ago one hour" "1 hour ago" "$actual"
actual=$(time_ago $((now - 90000)))
check "time_ago yesterday" "yesterday" "$actual"
actual=$(time_ago $((now - 3 * 86400)))
check "time_ago days" "3 days ago" "$actual"
actual=$(time_ago $((now - 40 * 86400)))
check "time_ago month" "1 month ago" "$actual"
actual=$(time_ago 0)
check "time_ago unknown is empty" "" "$actual"

# old 3 column line, a line with a resume position, an up to date show and one the site no longer knows
printf '1\tthree-episodes-1\tThree Episodes\t%s\t754\n1\tone-episode-2\tOne: Episode (TV)\t%s\t0\n5\tgone-3\tGone Show\t%s\t0\n' "$((now - 60))" "$((now - 3 * 86400))" "$((now - 90000))" >"$histfile"
expected="$(printf 'three-episodes-1\tThree Episodes\tep 1 @ 12:34      1 minute ago    \t1\t754\t%s\tresume\none-episode-2\tOne: Episode (TV)\tup to date        3 days ago      \t1\t0\t%s\tuptodate' "$((now - 60))" "$((now - 3 * 86400))")"
actual=$(hist_menu_entries)
check "continue menu: resume first, up to date kept, unknown show dropped" "$expected" "$actual"

printf '1\tthree-episodes-1\tThree Episodes\n' >"$histfile"
expected="$(printf 'three-episodes-1\tThree Episodes\tep 2                              \t2\t0\t0\tnext')"
actual=$(hist_menu_entries)
check "continue menu: old line without time offers the next episode" "$expected" "$actual"

# shellcheck disable=SC2034
anime_id="three-episodes-1"
# shellcheck disable=SC2034
anime_title="Three Episodes"
# shellcheck disable=SC2034
ep_no=2
printf '1\tthree-episodes-1\tThree Episodes\n9\tother-4\tOther\t5\t0\n' >"$histfile"
update_history
expected="$(printf '9\tother-4\tOther\t5\t0\n2\tthree-episodes-1\tThree Episodes\t%s\t0' "$now")"
actual=$(cat "$histfile")
check "update_history replaces the line with 5 columns and keeps the rest" "$expected" "$actual"

# finish_episode: no resume file means played through
resume="$tmp/resume/three-episodes-1/2"
finish_episode three-episodes-1 2 "$resume" "playlist"
actual=$(grep three-episodes "$histfile")
check "finished episode keeps position 0" "2	three-episodes-1	Three Episodes	$now	0" "$actual"

mkdir -p "$resume" && printf 'start=754.123456\nvolume=100\n' >"$resume/8A0B"
finish_episode three-episodes-1 2 "$resume" "playlist"
actual=$(grep three-episodes "$histfile")
check "closed early stores the position" "2	three-episodes-1	Three Episodes	$now	754" "$actual"
actual=$(ls "$tmp/resume/three-episodes-1" 2>/dev/null)
check "resume file is removed" "" "$actual"

mkdir -p "$resume" && printf 'start=1400.5\n' >"$resume/8A0B"
finish_episode three-episodes-1 2 "$resume" "playlist"
actual=$(grep three-episodes "$histfile")
check "closed in the last tenth counts as watched" "2	three-episodes-1	Three Episodes	$now	0" "$actual"

mkdir -p "$resume" && printf 'start=100\n' >"$resume/8A0B"
finish_episode three-episodes-1 3 "$resume" "playlist"
actual=$(grep three-episodes "$histfile")
check "another episode started meanwhile leaves the history alone" "2	three-episodes-1	Three Episodes	$now	0" "$actual"

exit "$failed"
