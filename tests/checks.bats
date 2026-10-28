#!/usr/bin/env bats
# Offline tests: external commands are replaced by stubs on PATH.

setup() {
	ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
	STUBS=$BATS_TEST_TMPDIR/stubs
	mkdir -p "$STUBS"
	PATH="$STUBS:$ROOT/bin:$PATH"
}

stub() {
	printf '#!%s\n%s\n' "$BASH" "$2" >"$STUBS/$1"
	chmod +x "$STUBS/$1"
}

pem() {
	openssl req -x509 -newkey rsa:2048 -nodes -subj /CN=test -days "$1" \
		-keyout "$BATS_TEST_TMPDIR/key.pem" -out "$BATS_TEST_TMPDIR/cert$1.pem" 2>/dev/null
	printf '%s' "$BATS_TEST_TMPDIR/cert$1.pem"
}

@test "cert-expiry: healthy certificate file is OK" {
	run cert-expiry "$(pem 365)"
	[ "$status" -eq 0 ]
	[[ $output == *"expires in 36"* ]]
}

@test "cert-expiry: thresholds raise WARNING and CRITICAL" {
	run cert-expiry -w 30 -c 5 "$(pem 20)"
	[ "$status" -eq 1 ]
	run cert-expiry -w 30 -c 5 "$(pem 2)"
	[ "$status" -eq 2 ]
}

@test "cert-expiry: unreadable target is CRITICAL with JSON output" {
	run cert-expiry -f json "$BATS_TEST_TMPDIR/missing.pem"
	[ "$status" -eq 2 ]
	[[ $output == '{"check":"cert-expiry","status":"CRITICAL"'* ]]
	[[ $output == *'"value":null'* ]]
}

@test "cert-expiry: invalid options are UNKNOWN" {
	run cert-expiry -w abc host
	[ "$status" -eq 3 ]
	run cert-expiry
	[ "$status" -eq 3 ]
}

@test "disk-report: classifies blocks and inodes, prom output" {
	stub df 'printf "Mounted on Use%% IUse%%\n/ 42%% 10%%\n/var 85%% 95%%\n/btrfs 50%% -\n/mnt/my disk 10%% 1%%\n"'
	run disk-report -f prom
	[ "$status" -eq 2 ]
	[[ $output == *'ops_disk_used_percent{target="/var"} 85'* ]]
	[[ $output == *'ops_disk_inodes_used_percent{target="/var"} 95'* ]]
	[[ $output != *'inodes_used_percent{target="/btrfs"}'* ]]
	[[ $output == *'ops_disk_used_percent{target="/mnt/my disk"} 10'* ]]
	[[ $output == *'ops_check_status{check="disk-report"} 2'* ]]
}

@test "disk-report: below thresholds is OK" {
	stub df 'printf "Mounted on Use%% IUse%%\n/ 42%% 10%%\n"'
	run disk-report
	[ "$status" -eq 0 ]
	[[ $output == *"[OK] /: blocks 42%"* ]]
}

@test "ssh-key-audit: flags short RSA, DSA and shared keys" {
	stub ssh-keygen '
case $3 in
*alice) printf "4096 SHA256:aaa alice@x (RSA)\n256 SHA256:shared ops (ED25519)\n" ;;
*bob) printf "2048 SHA256:bbb bob@x (RSA)\n256 SHA256:shared ops (ED25519)\n" ;;
*carol) printf "1024 SHA256:ccc carol@x (DSA)\n" ;;
esac'
	touch "$BATS_TEST_TMPDIR/alice" "$BATS_TEST_TMPDIR/bob" "$BATS_TEST_TMPDIR/carol"
	run ssh-key-audit "$BATS_TEST_TMPDIR/alice" "$BATS_TEST_TMPDIR/bob"
	[ "$status" -eq 1 ]
	[[ $output == *"RSA-2048 key SHA256:bbb"* ]]
	[[ $output == *"SHA256:shared: shared by"* ]]
	[[ $output != *"SHA256:aaa"* ]]
	run ssh-key-audit "$BATS_TEST_TMPDIR/carol"
	[ "$status" -eq 2 ]
}

@test "backup-verify: fresh snapshot OK, stale CRITICAL, credentials hidden" {
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	stub restic "printf '[{\"time\":\"$now\"}]'"
	RESTIC_REPOSITORY='rest:https://user:secret@backup/repo' run backup-verify
	[ "$status" -eq 0 ]
	[[ $output == *"rest:https://backup/repo"* ]]
	[[ $output != *secret* ]]
	stub restic "printf '[{\"time\":\"2020-01-01T00:00:00Z\"}]'"
	run backup-verify
	[ "$status" -eq 2 ]
}

@test "backup-verify: empty repository and failed data check are CRITICAL" {
	stub restic 'printf "[]"'
	run backup-verify
	[ "$status" -eq 2 ]
	[[ $output == *"no snapshots found"* ]]
	now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	stub restic "[ \"\$1\" = check ] && exit 1; printf '[{\"time\":\"$now\"}]'"
	run backup-verify -s 1%
	[ "$status" -eq 2 ]
	[[ $output == *"check of 1% FAILED"* ]]
}

@test "disk-report: partial df failure still reports, empty output is UNKNOWN" {
	stub df 'printf "Mounted on Use%% IUse%%\n/ 42%% 10%%\n"; echo "df: /secret: Permission denied" >&2; exit 1'
	run disk-report
	[ "$status" -eq 0 ]
	stub df 'echo "df: no file systems processed" >&2; exit 1'
	run disk-report
	[ "$status" -eq 3 ]
}

@test "prom output keeps each metric family contiguous" {
	stub df 'printf "Mounted on Use%% IUse%%\n/ 42%% 10%%\n/var 50%% 20%%\n"'
	run disk-report -f prom
	[ "$status" -eq 0 ]
	[ "$(grep -c '^# TYPE' <<<"$output")" -eq 3 ]
	[ "$(grep -v '^#' <<<"$output" | cut -d'{' -f1 | uniq | wc -l)" -eq 3 ]
}
