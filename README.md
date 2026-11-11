# rocdog
roc platform for rocdogging roc

## Using rocdog

### Using the platform from pre-built binaries

### Using the platform with nix flakes
```roc
app [main!] { pf: platform "" }

main! = |_| {
    Ok({})
}
```

### [Examples](./examples/)

## Developing rocdog

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

## License
[LGPL v2.1](./LICENSE)
