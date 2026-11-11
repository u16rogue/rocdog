{ lib, stdenvNoCC, rocpkgs, ... }: stdenvNoCC.mkDerivation {
    pname = "bridge";
    version = "0.1.0";

    # local builds would clash
    src = lib.cleanSourceWith {
        src = ./.;
        filter = path: _: baseNameOf path != ".build";
    };

    nativeBuildInputs = [
        rocpkgs.nightly
    ];

    # roc caches into $HOME
    preBuild = ''
        export ROC_CACHE_DIR="$TMPDIR/roc"
    '';

    buildPhase = ''
        runHook preBuild
        bash ./do build-release
        runHook postBuild
    '';

    installPhase = ''
        runHook preInstall
        install -Dm755 -t "$out/bin" .build/release/bridge
        runHook postInstall
    '';

    meta = {
        description = "";
        mainProgram = "bridge";
        platforms = lib.platforms.linux;
    };
}
