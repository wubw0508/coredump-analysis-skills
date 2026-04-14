#!/usr/bin/env bash
set -eo pipefail

# 从 centralized 配置加载 Metabase 信息
WORKSPACE="$(dirname "$(dirname "$(realpath "$0")")")"
if [ -f "$WORKSPACE/centralized/config.env" ]; then
    . "$WORKSPACE/centralized/config.env"
fi

# 确保所有变量都有默认值
BASE_URL="${BASE_URL:-${METABASE_BASE_URL:-https://metabase.cicd.getdeepin.org}}"
USERNAME="${USERNAME:-${METABASE_USERNAME:-app@deepin.org}}"
PASSWORD="${PASSWORD:-${METABASE_PASSWORD:-deepin123}}"
DATABASE_ID="${DATABASE_ID:-${METABASE_DATABASE_ID:-10}}"
DEFAULT_DATE="$(date +%Y%m%d-%H%M)"

usage() {
  cat <<'USAGE'
Usage:
  ./download_metabase_csv.sh [options] <package> <arch> [data_type]
  ./download_metabase_csv.sh [options] --batch <targets_file>

Options:
  --output-dir DIR          Output directory (default: auto-created timestamped dir)
  --file-date LABEL         File date label (default: YYYYMMDD-HHmm)
  --start-date YYYY-MM-DD   Filter start date (field dt)
  --end-date YYYY-MM-DD     Filter end date (field dt)
  --sys-version N[-M]       Filter sys_v_number, single value or range (e.g. 1070 or 1070-1075)
  --version VERSION         Filter package version, exact match (e.g. 5.7.41.11)

Environment variables:
  METABASE_BASE_URL   — Metabase base URL
  METABASE_USERNAME   — Login username
  METABASE_PASSWORD   — Login password

Examples:
  ./download_metabase_csv.sh --sys-version 1070-1075 dde-dock x86 crash
  ./download_metabase_csv.sh --version 5.7.41.11 dde-control-center x86_64 crash
  ./download_metabase_csv.sh --start-date 2025-09-01 --end-date 2025-09-30 --sys-version 1070-1075 dde-dock x86 crash
  ./download_metabase_csv.sh --sys-version 1070-1075 --batch batch_targets.txt

Batch file format:
  One target per line, comma separated:
    package,arch[,data_type[,start_date[,end_date[,version]]]]
  Lines starting with # are ignored.
USAGE
}

trim() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  printf '%s' "$value"
}

sanitize() {
  printf '%s' "$1" | sed 's/[[:space:]]\+/_/g; s#[/\\]#_#g'
}

normalize_arch() {
  local arch
  arch="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$arch" in
    ""|all)
      printf '%s' ""
      ;;
    x86|x86_64|amd64)
      printf '%s' "x86_64"
      ;;
    arm64|aarch64)
      printf '%s' "aarch64"
      ;;
    loong64|loongarch64)
      printf '%s' "loongarch64"
      ;;
    *)
      printf '%s' "$arch"
      ;;
  esac
}

arch_label() {
  local arch
  arch="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  if [[ -z "$arch" ]]; then
    printf '%s' "ALL"
  else
    printf '%s' "$arch"
  fi
}

validate_date() {
  local value="$1"
  local field_name="$2"

  if [[ -z "$value" ]]; then
    return 0
  fi

  if [[ ! "$value" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    echo "invalid ${field_name}: ${value} (expected YYYY-MM-DD)" >&2
    exit 1
  fi
}

build_output_file() {
  local package="$1"
  local arch="$2"
  local data_type="$3"
  local file_date="$4"

  printf '%s_%s_%s_%s.csv' \
    "$(sanitize "$package")" \
    "$(sanitize "$(arch_label "$arch")")" \
    "$(sanitize "$data_type")" \
    "$(sanitize "$file_date")"
}

login() {
  local payload
  payload="$(jq -cn --arg username "$USERNAME" --arg password "$PASSWORD" '{username: $username, password: $password}')"

  curl -fsS \
    -H 'Content-Type: application/json' \
    -d "$payload" \
    "${BASE_URL}/api/session" \
    | jq -r '.id'
}

build_card_query_payload() {
  local package="$1"
  local normalized_arch="$2"
  local start_date="$3"
  local end_date="$4"
  local sys_version="$5"
  local version="$6"

  local filters="[]"

  if [[ -n "$package" ]]; then
    filters="$(echo "$filters" | jq --arg v "$package" \
      '. + [["=", {"base-type": "type/Text"}, ["field", 3536, null], $v]]')"
  fi

  if [[ -n "$normalized_arch" ]]; then
    filters="$(echo "$filters" | jq --arg v "$normalized_arch" \
      '. + [["=", {"base-type": "type/Text"}, ["field", 6661, null], $v]]')"
  fi

  if [[ -n "$start_date" && -n "$end_date" ]]; then
    filters="$(echo "$filters" | jq --arg s "$start_date" --arg e "$end_date" \
      '. + [["between", {"base-type": "type/Date"}, ["field", 4905, null], $s, $e]]')"
  elif [[ -n "$start_date" ]]; then
    filters="$(echo "$filters" | jq --arg s "$start_date" \
      '. + [[">=", {"base-type": "type/Date"}, ["field", 4905, null], $s]]')"
  elif [[ -n "$end_date" ]]; then
    filters="$(echo "$filters" | jq --arg e "$end_date" \
      '. + [["<=", {"base-type": "type/Date"}, ["field", 4905, null], $e]]')"
  fi

  if [[ -n "$sys_version" ]]; then
    if [[ "$sys_version" == *-* ]]; then
      local sv_start="${sys_version%-*}"
      local sv_end="${sys_version#*-}"
      filters="$(echo "$filters" | jq --argjson s "$sv_start" --argjson e "$sv_end" \
        '. + [["between", {"base-type": "type/Integer"}, ["field", 6663, null], $s, $e]]')"
    else
      filters="$(echo "$filters" | jq --argjson v "$sys_version" \
        '. + [["=", {"base-type": "type/Integer"}, ["field", 6663, null], $v]]')"
    fi
  fi

  if [[ -n "$version" ]]; then
    filters="$(echo "$filters" | jq --arg v "$version" \
      '. + [["=", {"base-type": "type/Text"}, ["field", 3576, null], $v]]')"
  fi

  filters="$(echo "$filters" | jq '. + [["not-null", {"base-type": "type/Text"}, ["field", 3538, null]]]')"

  local filter_expr
  if [[ "$(echo "$filters" | jq 'length')" -eq 1 ]]; then
    filter_expr="$(echo "$filters" | jq '.[0]')"
  else
    filter_expr="$(echo "$filters" | jq '["and"] + .')"
  fi

  jq -cn --argjson filter "$filter_expr" '{
    database: 10,
    type: "query",
    query: {
      "lib/type": "mbql/query",
      "source-table": 196,
      filter: $filter
    }
  }'
}

export_card_csv() {
  local session_id="$1"
  local card_id="$2"
  local payload="$3"
  local output_file="$4"

  json_response="$(curl -fsS \
    -H 'Content-Type: application/json' \
    -H "X-Metabase-Session:${session_id}" \
    -d "$payload" \
    "${BASE_URL}/api/dataset")"

  echo "$json_response" | jq -r '
    [.data.cols[].display_name] as $headers |
    $headers,
    (.data.rows[] | [.[] |
      tostring |
      gsub("\r\n"; "\n") |
      gsub("\r"; "\n") |
      gsub("\t"; " ") |
      gsub("\""; "\"\"")
    ]) |
    @csv
  ' > "$output_file"
}

export_one() {
  local session_id="$1"
  local package="$2"
  local arch="$3"
  local data_type="$4"
  local file_date="$5"
  local start_date="$6"
  local end_date="$7"
  local sys_version="${8:-}"
  local version="${9:-}"
  local output_dir="${10:-.}"
  local normalized_arch output_file payload

  validate_date "$start_date" "start_date"
  validate_date "$end_date" "end_date"

  normalized_arch="$(normalize_arch "$arch")"
  output_file="$(build_output_file "$package" "$arch" "$data_type" "$file_date")"

  mkdir -p "$output_dir"
  output_file="${output_dir}/${output_file}"

  payload="$(build_card_query_payload "$package" "$normalized_arch" "$start_date" "$end_date" "$sys_version" "$version")"

  export_card_csv "$session_id" "" "$payload" "$output_file"

  echo "saved to ${output_file}"
}

parse_batch_file() {
  local session_id="$1"
  local targets_file="$2"
  local default_file_date="$3"
  local global_start_date="$4"
  local global_end_date="$5"
  local global_sys_version="$6"
  local global_version="$7"
  local output_dir="$8"
  local line package arch data_type start_date end_date version

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"

    if [[ -z "$line" || "${line:0:1}" == "#" ]]; then
      continue
    fi

    IFS=',' read -r package arch data_type start_date end_date version _ <<< "$line"
    package="$(trim "${package:-}")"
    arch="$(trim "${arch:-all}")"
    data_type="$(trim "${data_type:-crash}")"
    start_date="$(trim "${start_date:-$global_start_date}")"
    end_date="$(trim "${end_date:-$global_end_date}")"
    version="$(trim "${version:-$global_version}")"

    if [[ -z "$package" ]]; then
      echo "skip invalid line: $line" >&2
      continue
    fi

    export_one "$session_id" "$package" "$arch" "$data_type" "$default_file_date" "$start_date" "$end_date" "$global_sys_version" "$version" "$output_dir"
  done < "$targets_file"
}

main() {
  local session_id package arch data_type file_date targets_file start_date end_date sys_version version output_dir

  command -v curl >/dev/null 2>&1 || { echo "missing dependency: curl" >&2; exit 1; }
  command -v jq >/dev/null 2>&1 || { echo "missing dependency: jq" >&2; exit 1; }

  file_date="$DEFAULT_DATE"
  start_date=""
  end_date=""
  sys_version=""
  version=""
  output_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --output-dir)
        output_dir="${2:-}"
        shift 2
        ;;
      --file-date)
        file_date="${2:-}"
        shift 2
        ;;
      --start-date)
        start_date="${2:-}"
        shift 2
        ;;
      --end-date)
        end_date="${2:-}"
        shift 2
        ;;
      --sys-version)
        sys_version="${2:-}"
        shift 2
        ;;
      --version)
        version="${2:-}"
        shift 2
        ;;
      --batch)
        targets_file="${2:-}"
        shift 2

        session_id="$(login)"

        if [[ -z "$session_id" || "$session_id" == "null" ]]; then
          echo "failed to get Metabase session id" >&2
          exit 1
        fi

        if [[ -z "$targets_file" || ! -f "$targets_file" ]]; then
          echo "batch targets file not found: ${targets_file:-}" >&2
          exit 1
        fi

        validate_date "$start_date" "start_date"
        validate_date "$end_date" "end_date"

        if [[ -z "$output_dir" ]]; then
          output_dir="download_${file_date}"
        fi
        mkdir -p "$output_dir"

        parse_batch_file "$session_id" "$targets_file" "$file_date" "$start_date" "$end_date" "$sys_version" "$version" "$output_dir"
        echo ""
        echo "all files saved to ${output_dir}/"
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        echo "unknown option: $1" >&2
        exit 1
        ;;
      *)
        break
        ;;
    esac
  done

  package="${1:-dde-dock}"
  arch="${2:-x86}"
  data_type="${3:-crash}"

  if [[ $# -ge 4 ]]; then
    file_date="$4"
  fi

  session_id="$(login)"

  if [[ -z "$session_id" || "$session_id" == "null" ]]; then
    echo "failed to get Metabase session id" >&2
    exit 1
  fi

  if [[ -z "$output_dir" ]]; then
    output_dir="download_${file_date}"
  fi
  mkdir -p "$output_dir"

  export_one "$session_id" "$package" "$arch" "$data_type" "$file_date" "$start_date" "$end_date" "$sys_version" "$version" "$output_dir"
  echo ""
  echo "all files saved to ${output_dir}/"
}

main "$@"
