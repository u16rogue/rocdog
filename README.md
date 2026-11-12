# rocdog
roc platform for rocdogging roc

> [!IMPORTANT]
> This platform is being developed for `roc-nightly`

## Using the rocdog platform

### Using the platform from pre-built binaries

### Using the platform with nix flakes
```roc
app [main!] { pf: platform "" }

main! = |_| {
    Ok({})
}
```

### [Examples](./examples/)

## Developing the rocdog platform

### Components
* [host](./host/) - The host platform in zig that's linked with the roc runtime.
* [bridge](./bridge/) - The Roc source bridge for the host platform.

### Environment (with nix)
1. Get [nix](https://nixos.org/download/#nix)
2. Run `nix develop` (or if you dont have experimental turned on run `nix --extra-experimental-features "nix-command flakes" develop`)

### Environment (without nix)
1. Read the *.nix files or ask a clanker

### Building
***TODO***

## Maintainer Verification
[minisign](https://jedisct1.github.io/minisign/) is used to create and verify signatures
```
-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

rocdog maintainer minisign pubkey: `RWRLVHlE0m6ia/agZpBElZOSlO5er4iTIE8jeNzi3tdwq5UhFujxD+AN`

-----BEGIN PGP SIGNATURE-----

iHUEARYKAB0WIQTJs5jAXl3pZ+QrlCfitMGnOvZcvwUCavWBtwAKCRDitMGnOvZc
v0nYAQCjd98kma7QKgbcotnxnXdTRQbW3qw6Yrx0Kb8qCIYppgD/WWozNTOP0iWc
q6AA3KyD1IdMM68SuY2ZO2CV7Gnevww=
=RrWQ
-----END PGP SIGNATURE-----
```

## License
[LGPL v2.1](./LICENSE)
