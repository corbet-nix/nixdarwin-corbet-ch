# nixmac

**The darwin sibling of [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (Arch under
system-manager) and [nixnas](https://github.com/julian-corbet/nixnas-corbet-ch)/nixvps (NixOS
flavours): the OS-flavour layer for a Mac host, managed by upstream
[nix-darwin](https://github.com/LnL7/nix-darwin).**

## Name

This project was scoped as "nixdarwin." It ships as **nixmac** instead, and that rename was a
deliberate decision made before writing anything, not a style preference -- worth stating clearly
rather than picked silently.

[`nix-darwin`](https://github.com/LnL7/nix-darwin) (`LnL7/nix-darwin`, migrating to
`nix-darwin/nix-darwin`) is the large, extremely well-known upstream project that brings the
NixOS module system to macOS -- described by its own flake as "a collection of darwin modules,"
tens of thousands of installs, the standard answer to "how do I manage a Mac with Nix" for years.
A repo in *this* family called `nixdarwin` would not just sound similar to that name; it is the
thing this repo actually **builds on top of** (nix-darwin is this repo's real, checks-only flake
input -- see `flake.nix`). Every other `nix<domain>` name in this family names the *domain*
(storage, boot, GPU, identity, …), never the *backend* it runs under -- nixarch is named for Arch,
not for system-manager; nixnas/nixvps are named for what they are, not for NixOS. Naming this one
after the backend it wraps, `nixdarwin`, would have been the one repo in the family that broke
that convention *and* collided with a large upstream project's own name at the same time. Renamed
to **nixmac** -- naming the thing it is (the Mac flavour), consistent with nixarch/nixnas/nixvps,
and no longer confusable with `nix-darwin` itself in a sentence, a search result, or an issue
tracker.

## What this actually is

The honest scope, decided *before* writing a module: most of this family is Linux-specific by
construction (LUKS, ZFS, zram, cgroups, Wayland, systemd units -- see
[`docs/portability.md`](docs/portability.md) for the full domain-by-domain audit). A large
"nixmac module" padded out with speculative darwin ports of those domains would be exactly the
kind of invented content this family's own house rules exist to prevent, and there is no live,
already-running Mac host yet to extract real incident-driven glue from the way nixarch's
own modules were extracted from a real Arch box's real failures.

So this repo is deliberately thin:

1. **[`docs/portability.md`](docs/portability.md)** -- the audit itself: which family domains
   already compose under nix-darwin unmodified, which are portable in principle but missing a
   backend file, and which cannot land here at all, with the concrete Linux/XNU primitive each
   verdict rests on. Two of those findings were verified empirically against the real
   `github:LnL7/nix-darwin` flake while writing this repo, closing an open question each of
   [nixmachines](https://github.com/julian-corbet/nixmachines-corbet-ch) and
   [nixid](https://github.com/julian-corbet/nixid-corbet-ch) had left untested.
2. **`modules/nixmac.nix`** -- the one piece of real glue nothing else in the family provides:
   bridging nixid's cross-host identity registry (`nixid.posix.identities`, read defensively --
   see below) onto a real nix-darwin `users.users.<name>` account, closing a genuine, ground-
   truthed silent failure mode that bridge would otherwise reopen (see the module's own header for
   the incident, straight from nix-darwin's own source).

## The model

```nix
nixmac.users.<name> = {
  fromIdentity = "app-foo";  # resolve uid from nixid.posix.identities.<name>.uid, or:
  uid = 504;                 # a literal uid, which always wins if both are set
};
```

Every name declared here is automatically added to `users.knownUsers` -- see
`modules/nixmac.nix`'s own header for exactly why that is not optional. `gid` is deliberately never
touched by this bridge; see the same header for why nixid's Linux User-Private-Group convention
has no honest translation onto macOS's own `staff`-group default.

## Usage

```nix
{
  inputs.nixmac.url = "github:julian-corbet/nixmac-corbet-ch";

  outputs = { self, nix-darwin, nixmac, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        nixmac.darwinModules.default
        # ... your own nixid.posix import too, if you want cross-host uid consistency ...
        {
          nixmac.users.me.fromIdentity = "me";
          system.stateVersion = 6;
        }
      ];
    };
  };
}
```

## Repository layout

| Path | Purpose |
|---|---|
| `flake.nix` | Flake entry point: `darwinModules.nixmac`/`.default`. `nix-darwin` is a checks-only input -- see the flake's own header for why. |
| `modules/nixmac.nix` | The module: `nixmac.users.<name>`, its assertions, and the `users.knownUsers` fix. Pure data plus the one real config it emits -- see its own header. |
| `docs/portability.md` | The audit this repo's scope was decided from. |
| `examples/host/configuration.nix` | The one generic, fictional example this public repo ships -- exercises both `uid` and `fromIdentity`. |
| `checks/` | Eval-time tests: a real `darwinSystem` composition against `github:LnL7/nix-darwin`, every assertion proven in both directions, and a structural check that `nixosModules`/`systemManagerModules` genuinely do not exist on this flake. |
| `experiments/` | Open questions and runnable trials -- see [`experiments/README.md`](experiments/README.md). |
| `studies/` | Written investigations, once one of the experiments above closes -- see [`studies/README.md`](studies/README.md). |

## Related projects

Part of the same family: [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (the Arch/
system-manager flavour this repo's own README structure and "thin, honest about scope" posture
follows), [nixid](https://github.com/julian-corbet/nixid-corbet-ch) (owns the `posix.<name>`
identity registry this repo's own `fromIdentity` reads defensively -- nixmac never takes it as a
flake input), and [nixmachines](https://github.com/julian-corbet/nixmachines-corbet-ch) (the
machine registry this Mac should also be registered in, `management = "nix-darwin"` already a
first-class value there). nixmac depends on none of them at the Nix level -- see `flake.nix`'s own
header for why crossing that line is exactly the mistake this family's own house rules forbid.

## License

[MIT License](LICENSE) &copy; 2026 Julian Corbet
