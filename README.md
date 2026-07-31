# nixdarwin

**The darwin sibling of [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (Arch under
system-manager) and [nixnas](https://github.com/julian-corbet/nixnas)/nixvps (NixOS
flavours): the OS-flavour layer for a Mac host, managed by upstream
[nix-darwin](https://github.com/LnL7/nix-darwin).**

## Name

This project shipped for a time as **nixmac**. It is **nixdarwin** now, and that rename was a
deliberate decision, not a style preference -- worth recording rather than left silent.

"Mac" names Apple's hardware brand, not the operating system this repo's own module declares
facts about. Every other `nix<domain>` name in this family names the *domain* or the *flavour*
(storage, boot, GPU, identity, Arch, NixOS, VPS, …), never a hardware brand -- `nixmac` was the one
name in the family that broke that convention. Unlike
[`system-manager`](https://github.com/numtide/system-manager), which manages several different
Linux flavours under one name (so naming a repo after IT would say nothing about which flavour),
[`nix-darwin`](https://github.com/LnL7/nix-darwin) (`LnL7/nix-darwin`, migrating to
`nix-darwin/nix-darwin`) only ever manages one OS: darwin. Naming this repo for the flavour it
actually is therefore reads as `nixdarwin` -- the same word as the backend it builds on
(nix-darwin is this repo's real, checks-only flake input -- see `flake.nix`), with the hyphen the
one thing left distinguishing the two in a sentence, a search result, or an issue tracker.

## What this actually is

The honest scope, decided *before* writing a module: most of this family is Linux-specific by
construction (LUKS, ZFS, zram, cgroups, Wayland, systemd units -- see
[`docs/portability.md`](docs/portability.md) for the full domain-by-domain audit). A large
"nixdarwin module" padded out with speculative darwin ports of those domains would be exactly the
kind of invented content this family's own house rules exist to prevent, and there is no live,
already-running Mac host yet to extract real incident-driven glue from the way nixarch's
own modules were extracted from a real Arch box's real failures.

So this repo is deliberately thin:

1. **[`docs/portability.md`](docs/portability.md)** -- the audit itself: which family domains
   already compose under nix-darwin unmodified, which are portable in principle but missing a
   backend file, and which cannot land here at all, with the concrete Linux/XNU primitive each
   verdict rests on. One of those findings was verified empirically against the real
   `github:LnL7/nix-darwin` flake while writing this repo, closing an open question
   [nixiam](https://github.com/julian-corbet/nixiam-corbet-ch) had left untested.
2. **`modules/nixdarwin.nix`** -- the one piece of real glue nothing else in the family provides:
   bridging nixiam's cross-host identity registry (`nixiam.posix.identities`, read defensively --
   see below) onto a real nix-darwin `users.users.<name>` account, closing a genuine, ground-
   truthed silent failure mode that bridge would otherwise reopen (see the module's own header for
   the incident, straight from nix-darwin's own source).

## The model

```nix
nixdarwin.users.<name> = {
  fromIdentity = "app-foo";  # resolve uid from nixiam.posix.identities.<name>.uid, or:
  uid = 504;                 # a literal uid, which always wins if both are set
};
```

Every name declared here is automatically added to `users.knownUsers` -- see
`modules/nixdarwin.nix`'s own header for exactly why that is not optional. `gid` is deliberately never
touched by this bridge; see the same header for why nixiam's Linux User-Private-Group convention
has no honest translation onto macOS's own `staff`-group default.

## Usage

```nix
{
  inputs.nixdarwin.url = "github:julian-corbet/nixdarwin-corbet-ch";

  outputs = { self, nix-darwin, nixdarwin, ... }: {
    darwinConfigurations.my-mac = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      modules = [
        nixdarwin.darwinModules.default
        # ... your own nixiam.posix import too, if you want cross-host uid consistency ...
        {
          nixdarwin.users.me.fromIdentity = "me";
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
| `flake.nix` | Flake entry point: `darwinModules.nixdarwin`/`.default`. `nix-darwin` is a checks-only input -- see the flake's own header for why. |
| `modules/nixdarwin.nix` | The module: `nixdarwin.users.<name>`, its assertions, and the `users.knownUsers` fix. Pure data plus the one real config it emits -- see its own header. |
| `lib/facts.nix` | `lib.probeFact` -- vendored from [nixhost](https://github.com/julian-corbet/nixhost-corbet-ch)'s own copy, not reinvented here. Distinguishes "nixiam not composed" from "nixiam composed but `posix.identities` renamed" for the read above -- see its own header. |
| `docs/portability.md` | The audit this repo's scope was decided from. |
| `examples/host/configuration.nix` | The one generic, fictional example this public repo ships -- exercises both `uid` and `fromIdentity`. |
| `checks/` | Eval-time tests: a real `darwinSystem` composition against `github:LnL7/nix-darwin`, every assertion proven in both directions, and a structural check that `nixosModules`/`systemManagerModules` genuinely do not exist on this flake. |
| `experiments/` | Open questions and runnable trials -- see [`experiments/README.md`](experiments/README.md). |
| `studies/` | Written investigations, once one of the experiments above closes -- see [`studies/README.md`](studies/README.md). |

## Related projects

Part of the same family: [nixarch](https://github.com/julian-corbet/nixarch-corbet-ch) (the Arch/
system-manager flavour this repo's own README structure and "thin, honest about scope" posture
follows), and [nixiam](https://github.com/julian-corbet/nixiam-corbet-ch) (owns the `posix.<name>`
identity registry this repo's own `fromIdentity` reads defensively -- nixdarwin never takes it as a
flake input). nixdarwin depends on neither at the Nix level -- see `flake.nix`'s own
header for why crossing that line is exactly the mistake this family's own house rules forbid.

## License

[MIT License](LICENSE) &copy; 2026 Julian Corbet
