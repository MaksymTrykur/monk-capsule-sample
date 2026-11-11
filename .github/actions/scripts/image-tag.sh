#!/bin/sh
# Per-branch image tags for a shared registry. Sourced by build-images.sh and dynenv-deploy.sh, which
# must agree: build-images pushes each MANIFEST image as <tag>-<suffix> and deploy points the
# templates the MANIFEST loads at that tag before `monk load`.

# The template files a MANIFEST loads: its LOAD files, and those of the sub-MANIFESTs named by
# DIR/DIRS, each relative to the MANIFEST that names it. A missing sub-MANIFEST adds nothing.
# $2 is the nesting depth, which stops a DIRS loop.
manifest_templates() {
    [ -f "$1/MANIFEST" ] || return 0
    sed 's/#.*//' "$1/MANIFEST" | awk 'toupper($1) == "LOAD" { for (i = 2; i <= NF; i++) print $i }' |
        while read -r file; do printf '%s/%s\n' "$1" "$file"; done
    [ "${2:-0}" -lt 8 ] || return 0
    sed 's/#.*//' "$1/MANIFEST" |
        awk 'toupper($1) == "DIR" || toupper($1) == "DIRS" { for (i = 2; i <= NF; i++) print $i }' |
        while read -r sub; do manifest_templates "$1/$sub" $((${2:-0} + 1)); done
}

# $1 is a MANIFEST image as written. Prints its name, without the tag.
image_name() {
    case "$1" in
        *:*) case "${1##*:}" in */*) printf '%s' "$1" ;; *) printf '%s' "${1%:*}" ;; esac ;;
        *) printf '%s' "$1" ;;
    esac
}

# $1 is a MANIFEST image as written. Prints its tag, `latest` when it has none.
image_tag_of() {
    case "$1" in
        *:*) case "${1##*:}" in */*) printf 'latest' ;; *) printf '%s' "${1##*:}" ;; esac ;;
        *) printf 'latest' ;;
    esac
}

# $1 is a MANIFEST image as written, $2 the suffix (the capsule environment). Prints
# <name>:<tag>-<suffix>. Fails, printing nothing, when the suffix isn't usable in a tag, the image
# is pinned by digest, or the result is longer than the 128 characters a tag may have.
branch_image_tag() {
    case "$2" in
        ""|*[!A-Za-z0-9_.-]*) return 1 ;;
    esac
    case "$1" in
        *@*) return 1 ;;
    esac
    name=$(image_name "$1")
    tag="$(image_tag_of "$1")-$2"
    [ "${#tag}" -le 128 ] || return 1
    printf '%s:%s' "$name" "$tag"
}

# $1 is a MANIFEST image as written, $2 the suffix, $3 a template file. Points the file at the
# branch tag. An `image:` value without a tag is `latest`, so it matches too when the MANIFEST
# image is. Prints 1 when the file changed, else 0.
rewrite_image_in_file() {
    new=$(branch_image_tag "$1" "$2") || return 1
    name=$(image_name "$1")
    tag=$(image_tag_of "$1")
    # Escape what is special in a basic regular expression, and the delimiter.
    esc_name=$(printf '%s' "$name" | sed 's/[][\.*^$|/]/\\&/g')
    esc_tag=$(printf '%s' "$tag" | sed 's/[][\.*^$|/]/\\&/g')
    esc_new=$(printf '%s' "$new" | sed 's/[&/\]/\\&/g')
    before=$(cksum < "$3")
    # name:tag as a whole word: not part of a longer name or tag. Twice, because two matches
    # separated by one character share it.
    tmp=$(mktemp)
    for _ in 1 2; do
        sed -E "s/(^|[^A-Za-z0-9_.\/:-])${esc_name}:${esc_tag}(\$|[^A-Za-z0-9_.-])/\1${esc_new}\2/g" "$3" > "$tmp"
        cat "$tmp" > "$3"
    done
    if [ "$tag" = "latest" ]; then
        # `image: name` only: the name alone also appears as a namespace or a runnable path.
        sed -E "s/^([[:space:]]*-?[[:space:]]*image:[[:space:]]*[\"']?)${esc_name}([\"']?[[:space:]]*(#.*)?\$)/\1${esc_new}\2/" "$3" > "$tmp"
        cat "$tmp" > "$3"
    fi
    rm -f "$tmp"
    [ "$before" != "$(cksum < "$3")" ] && echo 1 || echo 0
}

# $1 is the suffix. Points the templates the MANIFEST in the working directory loads at the branch
# tag of every image it builds. Warns for an image no template names literally, which can't be
# rewritten and would run whatever another branch pushed under the tag.
rewrite_templates_for_branch() {
    suffix="$1"
    [ -f MANIFEST ] || return 0
    images=$(sh "${PARSE_MANIFEST:-/opt/monk-actions/scripts/parse-manifest.sh}" get-images)
    [ -n "$images" ] || return 0
    templates=$(manifest_templates . | while read -r file; do [ -f "$file" ] && echo "$file"; done)
    for image in $images; do
        if ! branch_image_tag "$image" "$suffix" > /dev/null; then
            echo "Warning: image '$image' can't get a branch tag (digest, or a tag longer than 128 characters); it is shared by every branch." >&2
            continue
        fi
        changed=0
        for file in $templates; do
            n=$(rewrite_image_in_file "$image" "$suffix" "$file")
            changed=$((changed + n))
        done
        if [ "$changed" -eq 0 ]; then
            echo "Warning: no template the MANIFEST loads names image '$image' literally, so it can't be pointed at its branch tag; a node that has it already runs the image another branch pushed." >&2
        else
            echo "Image '$image' -> '$(branch_image_tag "$image" "$suffix")' in $changed template file(s)"
        fi
    done
}
