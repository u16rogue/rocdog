{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        nixpkgs-pin.url = "github:nixos/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6";
        roc-overlay = { url = "github:roc-lang/roc-overlay"; inputs.nixpkgs.follows = "nixpkgs"; inputs.nixpkgs-darwin.follows = "nixpkgs"; };
    };

    outputs = inputs@{ nixpkgs, ... }: let
        inherit (nixpkgs) lib;
        systems = [ "x86_64-linux" ];
        overlays = [
            inputs.roc-overlay.overlays.default
        ];
        perSystem = attr: lib.genAttrs systems (system: attr { pkgs = import nixpkgs { inherit system overlays; }; inherit system; });
        subprojects = [
            ./host
            ./bridge
        ];
        callEach = pkgs: file: lib.pipe subprojects [
            (lib.filter (path: builtins.pathExists (path + "/${file}")))
            (map (path: lib.nameValuePair (baseNameOf path) (pkgs.callPackage (path + "/${file}") {})))
            lib.listToAttrs
        ];
    in {
        description = "roc platform for rocdogging roc";
        packages = perSystem ({ pkgs, ... }: callEach pkgs "package.nix");
        devShells = perSystem ({ pkgs, ... }: let shells = callEach pkgs "shell.nix"; in shells // {
            default = pkgs.mkShellNoCC {
                inputsFrom = lib.attrValues shells;
                packages = with pkgs; [ git jujutsu nil bash-language-server shellcheck lua-language-server ];
                shellHook = /*bash*/ ''
                    export NIX_FRAGMENT="default"
                    if [ -f "$PWD/.jj.toml" ]; then
                        export JJ_CONFIG="''${JJ_CONFIG:-''${XDG_CONFIG_HOME:-$HOME/.config}/jj/config.toml}:$PWD/.jj.toml"
                    fi
                '';
            };
        });
    };
}
