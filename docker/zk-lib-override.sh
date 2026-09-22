#!/bin/sh
#
# Swap the CVE-fixed jars resolved by docker/zk-deps/pom.xml into the ZooKeeper
# image's lib directory, replacing the vulnerable versions the base image ships.
#
# Usage: zk-lib-override.sh <lib-dir> <overrides-dir>
#
# Exits non-zero (failing the docker build) if any artifact we expect to
# override is not found in <lib-dir> - that means the base image changed its
# bundled dependency set and this override list needs to be revisited.

set -eu

LIB="${1:?lib dir required}"
SRC="${2:?overrides dir required}"

# Artifacts that MUST be present in the base image and get replaced.
# logback-classic's transitive slf4j-api is included here too (see
# docker/zk-deps/pom.xml) - it's copied to $SRC and processed by the loop
# below like any other override jar, but without it in REQUIRED a future
# base image dropping/renaming its bundled slf4j-api wouldn't fail the
# build, silently leaving logback/slf4j mismatched at runtime.
REQUIRED="netty-buffer netty-codec netty-common netty-handler netty-resolver
netty-transport netty-transport-classes-epoll netty-transport-native-epoll
netty-transport-native-unix-common jackson-annotations jackson-core
jackson-databind jline logback-classic logback-core slf4j-api"

replaced_list=""

# artifact id = filename with the trailing -<version>[-classifier].jar removed
# (version always starts with -<digit>, so the longest -<digit>* suffix is it).
artifact_id() {
	base=$1
	echo "${base%%-[0-9]*}"
}

for new in "$SRC"/*.jar; do
	[ -e "$new" ] || continue
	newbase=$(basename "$new")
	artifact=$(artifact_id "$newbase")

	matched=0
	for old in "$LIB/$artifact"-*.jar; do
		[ -e "$old" ] || continue
		oldbase=$(basename "$old")
		# exact artifact-id match, so e.g. netty-transport does not eat
		# netty-transport-native-epoll
		[ "$(artifact_id "$oldbase")" = "$artifact" ] || continue
		echo "  override: $oldbase -> $newbase"
		rm -f "$old"
		matched=1
	done

	if [ "$matched" = 1 ]; then
		cp "$new" "$LIB/$newbase"
		replaced_list="$replaced_list $artifact"
	else
		echo "  skip (no match in image): $newbase"
	fi
done

rc=0
for r in $REQUIRED; do
	case " $replaced_list " in
		*" $r "*) ;;
		*)
			echo "ERROR: expected to override '$r' but no matching jar exists in $LIB" >&2
			rc=1
			;;
	esac
done

[ "$rc" -eq 0 ] && echo "zk-lib-override: all ${0##*/} replacements applied"
exit "$rc"
