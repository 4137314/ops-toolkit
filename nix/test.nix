{ pkgs, self }:
pkgs.testers.runNixOSTest {
  name = "ops-toolkit-module";
  nodes.machine =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.curl ];
      imports = [ self.nixosModules.default ];
      services.prometheus.exporters.node.enable = true;
      services.ops-toolkit = {
        enable = true;
        checks.disks.command = [
          "disk-report"
          "-w"
          "95"
        ];
      };
    };
  testScript = ''
    machine.wait_for_unit("prometheus-node-exporter.service")
    machine.succeed("systemctl start ops-toolkit-disks.service")
    machine.succeed("grep -q 'ops_check_status{check=\"disk-report\"}' /var/lib/prometheus-node-exporter-textfile/disks.prom")
    machine.wait_until_succeeds("curl -sf localhost:9100/metrics | grep -q ops_disk_used_percent")
  '';
}
