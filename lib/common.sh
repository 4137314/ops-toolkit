# shellcheck shell=bash
# Shared helpers for ops-toolkit checks.
# Exit codes follow the Nagios/Icinga plugin convention so every check can be
# dropped into an existing monitoring system without a wrapper.

# shellcheck disable=SC2034 # used by the sourcing scripts
readonly OPS_OK=0 OPS_WARN=1 OPS_CRIT=2 OPS_UNKNOWN=3
OPS_STATUS=$OPS_OK
OPS_FORMAT=text
OPS_ROWS=()

ops_die() {
	printf '%s: %s\n' "${0##*/}" "$*" >&2
	exit "$OPS_UNKNOWN"
}

# ops_raise <status>: keep the most severe status seen so far.
ops_raise() {
	if (($1 > OPS_STATUS)); then
		OPS_STATUS=$1
	fi
}

ops_label() {
	case $1 in
	0) printf OK ;;
	1) printf WARNING ;;
	2) printf CRITICAL ;;
	*) printf UNKNOWN ;;
	esac
}

ops_json_string() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	s=${s//$'\t'/\\t}
	printf '"%s"' "$s"
}

ops_prom_label() {
	local s=$1
	s=${s//\\/\\\\}
	s=${s//\"/\\\"}
	s=${s//$'\n'/\\n}
	printf '%s' "$s"
}

# ops_row <status> <target> <metric-name> <value> <message>
ops_row() {
	ops_raise "$1"
	OPS_ROWS+=("$1"$'\x1f'"$2"$'\x1f'"$3"$'\x1f'"$4"$'\x1f'"$5")
}

ops_set_format() {
	case $1 in
	text | json | prom) OPS_FORMAT=$1 ;;
	*) ops_die "unknown format: $1 (expected text, json or prom)" ;;
	esac
}

# ops_emit <check-name>: print collected rows and exit with the overall status.
ops_emit() {
	local check=$1 row status target metric value message first=1
	case $OPS_FORMAT in
	text)
		printf '%s %s\n' "$check" "$(ops_label "$OPS_STATUS")"
		for row in "${OPS_ROWS[@]}"; do
			IFS=$'\x1f' read -r status target metric value message <<<"$row"
			printf '  [%s] %s: %s\n' "$(ops_label "$status")" "$target" "$message"
		done
		;;
	json)
		printf '{"check":%s,"status":%s,"results":[' "$(ops_json_string "$check")" "$(ops_json_string "$(ops_label "$OPS_STATUS")")"
		for row in "${OPS_ROWS[@]}"; do
			IFS=$'\x1f' read -r status target metric value message <<<"$row"
			((first)) || printf ','
			first=0
			printf '{"target":%s,"status":%s,"metric":%s,"value":%s,"message":%s}' \
				"$(ops_json_string "$target")" "$(ops_json_string "$(ops_label "$status")")" \
				"$(ops_json_string "$metric")" "${value:-null}" "$(ops_json_string "$message")"
		done
		printf ']}\n'
		;;
	prom)
		# The exposition format requires all samples of a metric to be contiguous.
		local metrics=() name
		for row in "${OPS_ROWS[@]}"; do
			IFS=$'\x1f' read -r status target metric value message <<<"$row"
			[[ -n $metric && " ${metrics[*]} " != *" $metric "* ]] && metrics+=("$metric")
		done
		for name in "${metrics[@]}"; do
			printf '# TYPE %s gauge\n' "$name"
			for row in "${OPS_ROWS[@]}"; do
				IFS=$'\x1f' read -r status target metric value message <<<"$row"
				[[ $metric == "$name" && -n $value ]] || continue
				printf '%s{target="%s"} %s\n' "$metric" "$(ops_prom_label "$target")" "$value"
			done
		done
		printf '# TYPE ops_check_status gauge\nops_check_status{check="%s"} %s\n' "$check" "$OPS_STATUS"
		;;
	esac
	exit "$OPS_STATUS"
}
