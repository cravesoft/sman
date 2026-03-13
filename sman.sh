#!/bin/sh

# sman -- a wrapper around the man command that searches for struct definitions
# in on-line reference manuals.

bindir='/usr/bin'
case $1 in
--__bindir) bindir=${2?}; shift; shift;;
esac
PATH=$bindir:$PATH

man='${MAN-'\''/usr/bin/man'\''}'

MANPATH=$(eval $man -w)
DEFAULTSECT='2 3 3posix 3pm 3perl 3am 7 4 5'
OTHERSECT='n l 8 1 9 6'

version='sman 1.0

Copyright (C) 2020 Olivier Crave'

usage="Usage: sman [OPTIONS]... [-A] STRUCT
Search for the definition of STRUCT in manual pages.

OPTIONS are the same as for 'man'.

-A: search all sections.
--update-index: build or rebuild the search index (~/.cache/sman/index)
                for faster subsequent lookups.

Report bugs to <cravesoft@gmail.com>."

# sed script to escape all ' for the shell, and then (to handle trailing
# newlines correctly) append ' to the last line.
escape='
  s/'\''/'\''\\'\'''\''/g
  $s/$/'\''/
'
index_file="${XDG_CACHE_HOME:-$HOME/.cache}/sman/index"
operands=
all_sections=0
ignore_case=1
update_index=0
where=0

while [ $# -ne 0 ]; do
  option=$1
  shift
  optarg=

  case $option in
  ([123456789])
    specific_section=$option;;
  (-M | --manpath)
    case ${1?"$option option requires an argument"} in
    (*\'*)
      optarg=" '"$(printf '%s\n' "$1" | sed "$escape");;
    (*)
      optarg=" '$1'";;
    esac
    MANPATH=$1
    shift;;
  (-[CELMPRSep] | --config-file | --extension | --locale | --manpath | --pager | --preprocessor | --recode | --sections)
    case ${1?"$option option requires an argument"} in
    (*\'*)
      optarg=" '"$(printf '%s\n' "$1" | sed "$escape");;
    (*)
      optarg=" '$1'";;
    esac
    shift;;
  (--)
    break;;
  (-?*)
    ;;
  (*)
    case $option in
    (*\'*)
      operands="$operands '"$(printf '%s\n' "$option" | sed "$escape");;
    (*)
      operands="$operands '$option'";;
    esac
    ${POSIXLY_CORRECT+break}
    continue;;
  esac

  case $option in
  (-i | --ignore-case)
    ignore_case=1;;
  (-I | --match-case)
    ignore_case=0;;
  (-[wW] | --where* | --path | --location*)
    where=1;;
  (-[Kafklr] | --all | --whatis | --*apropos | --local-file | --prompt)
    printf >&2 '%s: %s: option not supported\n' "$0" "$option"
    exit 2;;
  (-A)
    all_sections=1
    continue;;
  (--update-index)
    update_index=1
    continue;;
  (-\? | -h | --h | --he | --hel | --help | -u | --usage)
    echo "$usage" || exit 2
    exit;;
  (-V | -v | --v | --ve | --ver | --vers | --versi | --versio | --version)
    echo "$version" || exit 2
    exit;;
  esac

  case $option in
  (*\'?*)
    option=\'$(printf '%s\n' "$option" | sed "$escape");;
  (*)
    option="'$option'";;
  esac

  man="$man $option$optarg"
done

eval "set -- $operands "'${1+"$@"}'

if [ $update_index -eq 1 ]; then
  mkdir -p "$(dirname "$index_file")"
  printf >&2 'Building sman index...\n'
  set -f; IFS=:
  for path in $MANPATH; do
    set +f; unset IFS
    for section in $DEFAULTSECT $OTHERSECT; do
      secdir=$path/man$section
      [ -e "$secdir" ] || continue
      find "$secdir" ! -name "$(printf "*\n*")" -name '*.gz'
    done
  done | xargs -P "$(nproc)" -n 50 zgrep -H 'struct [^ {]* {' 2>/dev/null > "$index_file"
  set +f; unset IFS
  printf 'Index written to %s\n' "$index_file"
  exit 0
fi

entry=
case ${1?"missing entry; try \`$0 --help' for help"} in
(*)
  entry="$1";;
esac
shift

if [ $# -eq 0 ]; then
  set -- -
fi

if [ ! -z "$specific_section" ]; then
  sections=$specific_section
else
  sections="$DEFAULTSECT"
  if [ $all_sections -eq 1 ]; then
    sections="$sections $OTHERSECT"
  fi
fi

zgrep_opts="--files-with-matches --max-count=1"
if [ $ignore_case -eq 1 ]; then
  zgrep_opts="$zgrep_opts --ignore-case"
fi

pattern="struct $entry {"

if [ -f "$index_file" ]; then
  grep_opts=
  if [ $ignore_case -eq 1 ]; then
    grep_opts="-i"
  fi
  sect_re=$(printf '%s' "$sections" | tr ' ' '|')
  line=$(grep $grep_opts "$pattern" "$index_file" \
    | grep -E "/man($sect_re)/[^/]+$" | head -1)
  if [ -n "$line" ]; then
    file="${line%%:*}"
    page=$(basename "${file%%.*}")
    if [ $where -eq 1 ]; then
      eval "$man" -- "$page"
    else
      eval "$man" -- "$page" | less -I "+/$(echo "$pattern" | sed 's/{/\\\{/')"
    fi
    exit 0
  fi
fi

set -f; IFS=:
for path in $MANPATH; do
  set +f; unset IFS
  for section in $sections; do
    secdir=$path/man$section
    if [ ! -e "$secdir" ]; then
      continue
    fi
    file=$(find "$secdir" ! -name "$(printf "*\n*")" -name '*.gz' \
      | xargs -P "$(nproc)" -n 50 zgrep $zgrep_opts "$pattern" 2>/dev/null \
      | head -1)
    if [ -n "$file" ]; then
      page=$(basename "${file%%.*}")
      if [ $where -eq 1 ]; then
        eval "$man" -- "$page"
      else
        eval "$man" -- "$page" | less -I "+/$(echo "$pattern" | sed 's/{/\\\{/')"
      fi
      exit 0
    fi
  done
done
set +f; unset IFS

printf >&2 'No manual entry for %s' "$entry"
if [ -z "$specific_section" ]; then
  printf >&2 '\n'
else
  printf >&2 ' in section %s\n' "$specific_section"
fi
exit 2
