self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ops-toolkit;
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.services.ops-toolkit = {
    enable = mkEnableOption "periodic ops-toolkit checks exported to the node_exporter textfile collector";
    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "ops-toolkit.packages.\${system}.default";
    };
    directory = mkOption {
      type = types.str;
      default = "/var/lib/prometheus-node-exporter-textfile";
      description = "Directory read by node_exporter's textfile collector.";
    };
    interval = mkOption {
      type = types.str;
      default = "*:0/15";
      description = "systemd OnCalendar expression for running the checks.";
    };
    checks = mkOption {
      description = "Checks to run; the attribute name becomes <name>.prom.";
      default = { };
      example = lib.literalExpression ''
        {
          certs.command = [ "cert-expiry" "example.com" "mail.example.com:465" ];
          disks.command = [ "disk-report" "-w" "85" ];
        }
      '';
      type = types.attrsOf (
        types.submodule {
          options = {
            command = mkOption {
              type = types.nonEmptyListOf types.str;
              description = "Tool and arguments; `-f prom` is inserted after the tool name.";
            };
            environmentFile = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Optional EnvironmentFile (e.g. restic credentials).";
            };
          };
        }
      );
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus.exporters.node = {
      enabledCollectors = [ "textfile" ];
      extraFlags = [ "--collector.textfile.directory=${cfg.directory}" ];
    };
    systemd.tmpfiles.rules = [ "d ${cfg.directory} 0755 root root -" ];

    systemd.services = lib.mapAttrs' (
      name: check:
      lib.nameValuePair "ops-toolkit-${name}" {
        description = "ops-toolkit check ${name}";
        path = [ cfg.package ];
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = lib.mkIf (check.environmentFile != null) check.environmentFile;
          ProtectSystem = "strict";
          ReadWritePaths = [ cfg.directory ];
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
        # Exit codes 1-3 are check results, not unit failures; the metric carries the status.
        script = ''
          out=${cfg.directory}/${name}.prom
          ${lib.escapeShellArg (lib.head check.command)} -f prom ${lib.escapeShellArgs (lib.tail check.command)} > "$out.tmp" || true
          mv "$out.tmp" "$out"
        '';
      }
    ) cfg.checks;

    systemd.timers = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "ops-toolkit-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.interval;
          Persistent = true;
          RandomizedDelaySec = "60";
        };
      }
    ) cfg.checks;
  };
}
