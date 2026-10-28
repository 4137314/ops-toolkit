# ops-toolkit

Small, dependency-light sysadmin checks that plug into the monitoring you already run.

| Tool | Checks |
| --- | --- |
| `cert-expiry` | TLS certificates of remote endpoints (`host[:port]`) or local PEM files |
| `disk-report` | Block **and inode** usage per filesystem |
| `ssh-key-audit` | `authorized_keys`: DSA/RSA-1 keys, short RSA keys, keys shared between accounts |
| `backup-verify` | restic: age of the newest snapshot, optional `restic check --read-data-subset` |

Every tool uses the same contract:

- **Nagios/Icinga exit codes:** `0` OK, `1` WARNING, `2` CRITICAL, `3` UNKNOWN. You can use them as Icinga/Nagios/Zabbix/Checkmk plugins without a wrapper.
- **`-f text | json | prom`:** human output, JSON for scripts/CI, or the Prometheus [textfile collector](https://github.com/prometheus/node_exporter#textfile-collector) format.
- **No secrets in output.** For example, credentials in `RESTIC_REPOSITORY` URLs are stripped.

```console
$ cert-expiry -w 30 example.com mail.example.com:465 /etc/ssl/certs/internal.pem
cert-expiry OK
  [OK] example.com: expires in 74 days (2027-01-10)
  ...
$ disk-report -f prom > /var/lib/node_exporter/textfile/disk.prom
$ RESTIC_REPOSITORY=s3:... RESTIC_PASSWORD_FILE=/etc/restic/pass backup-verify -w 26 -s 1%
```

## Install

**Plain Linux (Debian, RHEL, ...):** needs bash ≥ 4.4, coreutils and openssl. `ssh-key-audit` needs `ssh-keygen`, and `backup-verify` needs `restic` and `jq`.

```bash
git clone https://github.com/4137314/ops-toolkit /opt/ops-toolkit
ln -s /opt/ops-toolkit/bin/* /usr/local/bin/
```

**Nix:** `nix run github:4137314/ops-toolkit#default -- example.com` or add `packages.default`.

**NixOS module:** runs the checks on a systemd timer and exports them through node_exporter.

```nix
{
  inputs.ops-toolkit.url = "github:4137314/ops-toolkit";
  # in your host configuration:
  imports = [ inputs.ops-toolkit.nixosModules.default ];
  services.prometheus.exporters.node.enable = true;
  services.ops-toolkit = {
    enable = true;
    checks = {
      certs.command = [ "cert-expiry" "example.com" "vpn.example.com:443" ];
      disks.command = [ "disk-report" "-w" "85" ];
      backup = {
        command = [ "backup-verify" "-w" "26" ];
        environmentFile = "/run/secrets/restic.env";
      };
    };
  };
}
```

**Ansible / cron:** the same `-f prom` output works with any scheduler. See [ansible-baseline](https://github.com/4137314/ansible-baseline) and the alert rules in [observability-stack](https://github.com/4137314/observability-stack), which consume the `ops_*` metrics.

## Metrics

| Metric | Meaning |
| --- | --- |
| `ops_cert_expiry_seconds{target}` | Seconds until expiry (negative when expired) |
| `ops_disk_used_percent{target}` / `ops_disk_inodes_used_percent{target}` | Usage of a mount point |
| `ops_ssh_keys_total{target}` | Keys per `authorized_keys` file |
| `ops_backup_age_seconds{target}` / `ops_backup_check_ok{target}` | Snapshot age and data-check result |
| `ops_check_status{check}` | Overall status (0–3) of each tool |

## Development

```bash
nix develop
bats tests            # offline tests with stubbed commands
nix flake check       # shellcheck, bats and a NixOS VM test of the module
```

Contributions are welcome. New checks must source `lib/common.sh`, follow the exit-code contract and come with bats tests.

## License

MIT. Need help integrating this into your infrastructure? Open an issue or contact me through [my GitHub profile](https://github.com/4137314).
