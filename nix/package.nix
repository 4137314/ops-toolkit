{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  gnugrep,
  openssl,
  openssh,
  jq,
  restic,
  getent,
}:
stdenvNoCC.mkDerivation {
  pname = "ops-toolkit";
  version = "0.1.0";
  src = lib.cleanSource ../.;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/lib/ops-toolkit
    cp lib/common.sh $out/lib/ops-toolkit/
    for tool in bin/*; do
      install -Dm755 "$tool" "$out/libexec/ops-toolkit/$(basename "$tool")"
      makeWrapper "$out/libexec/ops-toolkit/$(basename "$tool")" "$out/bin/$(basename "$tool")" \
        --set OPS_LIB "$out/lib/ops-toolkit" \
        --prefix PATH : ${
          lib.makeBinPath [
            coreutils
            gnugrep
            openssl
            openssh
            jq
            restic
            getent
          ]
        }
    done
    runHook postInstall
  '';
  meta = {
    description = "Monitoring-ready sysadmin checks with Nagios exit codes and Prometheus output";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "cert-expiry";
  };
}
