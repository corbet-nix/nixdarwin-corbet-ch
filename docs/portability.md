# Portability audit: which family domains work under nix-darwin

This is the audit nixdarwin's own scope was decided from. It exists because the honest answer to
"build the darwin flavour repo" turned out to be "a thin bridge module plus this document," not a
large one -- most of this family is Linux-specific by construction, and padding this repo with
speculative modules for domains that cannot land on macOS would be exactly the kind of invented
content the house rules exist to prevent.

## Method

Two different kinds of evidence below, and each entry says which it is:

- **Verified** -- actually run, in this session, against the real upstream flakes
  (`github:NixOS/nixpkgs/nixos-unstable`, `github:LnL7/nix-darwin`), not assumed. Where a module's
  own source was inspected, the file and the specific primitive it depends on are named.
- **Reasoned** -- the conclusion follows from what primitive the domain depends on (systemd unit
  types, `/dev/dri`, ZFS, cryptsetup, Wayland, cgroups, IPMI, …) and general, well-documented facts
  about what XNU/nix-darwin does and does not provide, without a from-scratch reimplementation of
  that domain to prove it. Nothing here was verified by actually building the domain's own module
  under nix-darwin -- that would be that repo's job, not this one's.

One concrete, unplanned thing got verified along the way, worth stating up front because it
answers an open question a sibling repo already had:

1. **`nixiam`'s `posix.nix` composes into a real `darwinSystem` and builds
   `.config.system.build.toplevel` without incident** (a cross-host uid/gid registry, `attrsOf
   submodule` + `assertions`, no `pkgs`, no `systemd`) -- composed against real `nix-darwin`, a
   deliberately broken fixture (`domain = ""`) fails the build with the expected message, a
   correct one succeeds. `posix.nix` was mid-edit by a concurrent session while this audit ran
   (staged for deletion in that repo's own working tree, uncommitted -- that repo was still named
   nixid at the time) -- the probe used a local snapshot of the file as read earlier in this
   session, not the live path, specifically so this work would not collide with that other
   change.

That result supports the same general claim the rest of this audit rests on: a module that is genuinely pure data --
`options`/`config.assertions` only, no `pkgs` argument, no `systemd`/`environment.etc`/anything
NixOS-primitive -- composes under nix-darwin exactly as advertised. That is the property nixdarwin's
own `modules/nixdarwin.nix` is built to (see that file's header), and the property every domain
marked "portable" below actually has.

## Verdicts

| Domain | Verdict | Why |
|---|---|---|
| nixsh (home-manager backend) | **Portable, verified pattern, ships today** | `modules/home.nix` writes only `xdg.configFile`, `programs.bash.initExtra`, `programs.zsh.initExtra` -- home-manager options, and home-manager itself runs on darwin. Nothing to add. |
| nixsh (`nixos.nix`/`arch.nix` backends) | **Portable in principle, no darwin file shipped** | `environment.systemPackages` is the same option name on nix-darwin; a `modules/darwin.nix` mirroring `modules/nixos.nix` almost verbatim would work, but that file does not exist in that repo today. |
| nixdev / nixoffice / nixfont | **Portable in principle, no darwin file shipped** | Same shape as nixsh above: a pure catalogue (`modules/<name>.nix`, no `pkgs`) plus a `modules/nixos.nix` that only calls `environment.systemPackages`. The catalogue itself is platform-neutral by the file's own design comment; only the backend file is missing. |
| nixiam (`posix.nix` only -- NOT `lldap.nix`/`pocket-id.nix`) | **Portable, verified** | See "Method" above. `podSecurity`'s generated Kubernetes securityContext is simply inert, unconsumed data on a Mac -- costs nothing, does nothing. |
| nixluks | **Not portable -- structural** | Every real action is `cryptsetup`/`systemd-cryptsetup@`/`/etc/crypttab`. XNU has no LUKS2, no device-mapper equivalent, and no declarative crypttab-style surface; FileVault is a closed, unrelated mechanism with no comparable Nix module. |
| nixvault | **Not portable -- structural** | Built on f2fs (`lib/f2fs-vault-opts.nix`) -- a Linux kernel-only filesystem, independent of whatever crypto layer sits under it. |
| nixstorage (ZFS shape/delivery/reconciler) | **Not portable -- structural** | `boot.zfs`-style pool import and the systemd mount-unit generation it drives are NixOS primitives with no nix-darwin equivalent in the base module set (confirmed: no `zfs` directory anywhere under nix-darwin's own `modules/`). OpenZFS exists as an independent third-party project on macOS, but nothing here integrates with it. |
| nixboot | **Not portable -- structural** | UEFI/lanzaboote/systemd-boot entry management. A Mac's firmware handoff (T2 or Apple Silicon secure boot) is Apple's own closed chain; nix-darwin ships no bootloader module at all -- the OS is pre-installed, not assembled by Nix the way a NixOS root is. |
| nixram | **Not portable -- structural** | zram/zswap and the `vm.*`/cgroup-memory-pressure sysctls it tunes are Linux kernel features. XNU has its own, entirely different, non-Nix-exposed compressed-memory and swap system. |
| nixgpu | **Not portable -- structural** | Stable `/dev/dri` device paths, cgroup device-arbitration rules, udev -- all Linux-only. Metal/IOKit is a different device model with no cgroup equivalent at all. |
| nixk3s / nixpods / nixvm | **Not portable -- structural** | cgroups v2, Linux namespaces, KVM. Apple Silicon virtualization goes through `Virtualization.framework`, structurally unrelated. |
| nixniri / nixscroll / nixdesktop | **Not portable -- structural** | Wayland compositor protocol and home-manager modules built against it. Darwin's window server (Quartz) shares nothing with Wayland. |
| nixnet | **Not portable as shipped** | `services.netbird`-style systemd units and NixOS network config. NetBird itself ships a real macOS client, but that is a completely different integration surface (a launchd-managed Homebrew/App install, not this module), so the mechanism does not transfer even though the underlying VPN client exists on both. |
| nixbmc | **N/A** | IPMI/BMC hardware management. No BMC on a consumer Mac; the domain does not apply, not merely "doesn't port." |
| nixpower | **Not portable -- structural** | Linux power-governor/TLP-style tuning against sysfs. macOS power management is closed (`pmset`), with no comparable declarative surface. |
| nixremote | **Not portable -- structural** | `home/sunshine.nix`: a game-streaming host tied to a Linux/Wayland capture pipeline. |
| nixrescue | **Not portable -- structural** | UEFI rescue-image boot chain, inherits nixboot's own non-portability. |
| nixprint | **Not portable as shipped** | Wraps NixOS's `services.printing` (CUPS); nix-darwin does not manage macOS's own already-integrated CUPS stack at all, so there is no landing surface for this module's option shape even though CUPS itself exists on both. |
| nixshare | **Not portable -- structural** | SMB/NFS mount-unit generation via NixOS primitives (`systemd.mounts`/automount). macOS can mount the same protocols, but not through this module's mechanism. |
| nixbackup | **Not portable -- structural** | znapzend / ZFS send-recv; inherits nixstorage's ZFS dependency. |
| nixpush, nixvibe, nixapps, nixllm, nixmail | **Not portable -- structural** | systemd-service- or podman/k3s-workload-shaped; server/pod runtime concepts with no darwin equivalent nix-darwin manages. |
| nixhost | **Portable by mandate, not yet verifiable** | The namespace-root spec this family is converging on (see its own authoritative spec) explicitly requires `nixosModules`/`systemManagerModules`/`darwinModules` and forbids any NixOS-only primitive in its option surface -- by design, before a line of it is written. Not audited further here because no repo exists yet to point at; the mandate itself is the finding. |
| nixcpu | **Portable, reasoned (not verified here)** | Now a real repo, extracted following nixgpu's own catalogue-fact shape (vendor/microarch strings, no device nodes). Its module is pure data (no `pkgs`, no `systemd`) and it already ships an unverified `darwinModules` alias of its own (see its `experiments/README.md` #001) -- not composed against real nix-darwin in this audit, so reasoned portable rather than verified, the same distinction the Method section draws above. |

## What this means for a real Mac

Almost nothing from the Linux side of this family lands here, and that is not a gap in this
repo -- it is what a Mac genuinely is. The two things worth actually composing on
`nixhost.stance.backend = "nix-darwin"` today are:

1. **nixiam's `posix.nix`**, for uid consistency with the other hosts wherever that matters
   (this repo's own `nixdarwin.users.<name>.fromIdentity` exists specifically to consume it).
2. **nixsh's home-manager backend**, for shell config, unmodified.

Nothing else in the current family has a real landing surface here. A future domain that wants
one has a template to follow: stay pure data (no `pkgs`, no `systemd`) and it composes under
nix-darwin for free, exactly as verified above -- reach for `environment.systemPackages` and
nothing darwin-specific, and it is a small, mechanical backend file away, the same distance
nixdev/nixoffice/nixfont/nixsh's own system-level backend already is.

## Deliberately not built here

- **A `homebrew.casks`/`homebrew.brews` bridge** for nixdev/nixoffice/nixfont's own
  `unavailableOnNixos`-shaped selections. Real and useful in principle (nix-darwin's own
  `homebrew.nix`, ground-truthed while writing this audit, is exactly the escape valve those
  selections would want) -- but none of those repos' `lib/tools.nix` catalogues carry a cask name
  today, only `arch`/`nixpkgs`/`aur`. Building this bridge here would mean either modifying those
  repos (out of this task's scope) or inventing cask names nobody asked for (exactly the kind of
  fabricated data the house rules forbid). Left as a recommendation, not a module.
- **macOS `system.defaults.*` tuning, launchd services, or any other "what a Mac should look like"
  policy.** There is no live, already-running Mac host to extract real incident-driven
  glue from the way nixarch's own modules were extracted from a real Arch box's real failures --
  the one Mac this family has is not yet in active management. Inventing tuning values with no
  ground truth behind them would be exactly the "no invented rules" failure this family's own
  house rules call out. This repo ships the one piece of glue that IS ground-truthed (the
  `knownUsers` gap, verified directly against nix-darwin's own source -- see
  `modules/nixdarwin.nix`'s header) and stops there.
