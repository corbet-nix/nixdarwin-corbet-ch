# SPDX-License-Identifier: MIT OR Apache-2.0
# checks/default.nix
#
# EVAL-TIME tests, the same posture as the sibling nixluks/nixiam projects. No VM, no
# build of anything darwin-specific: every `darwinSystem` composed below is evaluated for
# `system = "aarch64-darwin"` (every current Apple Silicon Mac, and the only target this repo
# makes any claim about -- see experiments/README.md for x86_64-darwin) from whatever ordinary
# Linux system this check itself runs and builds under.
# That split is safe and requires no builder, emulator, or IFD for aarch64-darwin at all: a
# derivation's own `drvPath`/`outPath` are plain strings the Nix evaluator can compute for ANY
# `system` value without ever invoking that system's builder -- the same reason
# `nix eval nixpkgs#legacyPackages.aarch64-darwin.hello.drvPath` runs fine on any host. Forcing
# `.config.system.build.toplevel` (never realising it -- `builtins.seq`, not `nix build`) is what
# actually runs nix-darwin's own assertion check, empirically confirmed against the real
# `github:LnL7/nix-darwin` flake while writing this module: a deliberately-failing `assertions`
# entry throws `Failed assertions: - …` in well under a second, with no build attempted.
#
# The claims worth failing CI over:
#
#   1. `uid` has no default when neither it nor `fromIdentity` is set -- a hard build failure,
#      never a silent guess. Enforced by an EXPLICIT assertion, not incidental forcing: an early
#      version of this module assumed (by analogy with nixluks) that merely forcing
#      `.config.system.build.toplevel` would surface this the same way an unset `device`/`order`
#      does there -- it does not. nixluks's own `environment.etc."crypttab".text` is a real `/etc`
#      file whose *content* must be computed (forcing every volume's `device`) to build the
#      derivation that becomes part of `toplevel`'s closure; nix-darwin's own per-user uid/gid
#      table feeds its activation script instead, which a shallow `toplevel` force never reaches.
#      Caught by writing this check, not assumed from the sibling repos' pattern -- see
#      modules/nixdarwin.nix's own `unresolvedNames` for the fix.
#   2. `fromIdentity` resolves a real `nixiam.posix.identities.<name>.uid`, defensively, when that
#      module happens to be composed alongside nixdarwin -- and naming an entry that does not exist
#      there is a hard, clearly-messaged build failure, never a quiet fall-through.
#   3. An explicit `uid` always wins over whatever `fromIdentity` would have resolved to.
#   4. Two `nixdarwin.users` entries resolving to the same uid is a hard build failure.
#   5. Every name declared under `nixdarwin.users` ends up in `users.knownUsers` -- the actual fix
#      for this file's own header incident -- merged with, never replacing, whatever a host adds
#      to that list directly.
#   6. `darwinModules` is the ONLY backend this repo exports -- `nixosModules`/
#      `systemManagerModules` genuinely do not exist on `self`, checked structurally.
#   7. Nothing in the module's own source, or the shipped example, names a real host value
#      (hostname, IP, uid) -- the house "mechanism public, values private" rule, made mechanically
#      checkable the same way nixluks's own `structurally-safe` check works, rather than merely
#      asserted in prose.
#   8. `lib.probeFact` (`../lib/facts.nix`, vendored from nixhost's own copy) actually
#      distinguishes, THROUGH this real module's wiring, "nixiam not composed at all" from
#      "nixiam composed but `posix.identities` renamed" -- a naive check would report the
#      identical "not imported" hint for both, pointing at the wrong fix for the second case. The
#      renamed case warns exactly once, naming the option path, and never fails the build on its
#      own.
{ pkgs, lib, nixpkgs, system, nix-darwin, nixdarwinModule, flakeSelf }:

let
  check = name: ok: detail: { inherit name ok detail; };

  darwinSystemName = "aarch64-darwin";

  mkDarwin = extraModules: nix-darwin.lib.darwinSystem {
    system = darwinSystemName;
    modules = [
      { system.stateVersion = 6; nixpkgs.hostPlatform = darwinSystemName; }
      nixdarwinModule
    ] ++ extraModules;
  };

  evalDarwin = extraModules: (mkDarwin extraModules).config;

  # NixOS/nix-darwin enforce `assertions` when `system.build.toplevel` is forced, not on a bare
  # read of `config.assertions` (a passive list) -- proven empirically while writing this module
  # (see this file's own header). `seq` reaches the wrapping throw without deep-forcing the whole
  # system closure or building anything.
  darwinBuildFails = extraModules:
    !(builtins.tryEval (builtins.seq (mkDarwin extraModules).config.system.build.toplevel true)).success;

  # ── Fixtures ─────────────────────────────────────────────────────────────────────────────────
  # A stand-in for nixiam's own posix module -- deliberately NOT the real nixiam flake (this repo
  # never takes it as an input, see flake.nix's own header and modules/nixdarwin.nix's), just enough
  # option surface to prove the defensive read resolves a real value when present. The same
  # posture nixluks's own `fakeNixstorageDisksModule` fixture uses for `nixstorage.disks`.
  fakeNixiamPosixModule = {
    options.nixiam.posix.identities = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.uid = lib.mkOption { type = lib.types.int; };
      });
      default = { };
    };
  };

  withOneIdentity = {
    nixiam.posix.identities.app-foo.uid = 3001;
  };

  cfgFromIdentity = evalDarwin [
    fakeNixiamPosixModule
    withOneIdentity
    { nixdarwin.users.mac-app-foo.fromIdentity = "app-foo"; }
  ];

  cfgExplicitUidWins = evalDarwin [
    fakeNixiamPosixModule
    withOneIdentity
    { nixdarwin.users.mac-app-foo = { fromIdentity = "app-foo"; uid = 9999; }; }
  ];

  cfgTwoUsers = evalDarwin [
    { nixdarwin.users.alice.uid = 501; nixdarwin.users.bob.uid = 502; }
  ];

  cfgKnownUsersMerge = evalDarwin [
    { nixdarwin.users.alice.uid = 501; }
    { users.knownUsers = [ "someone-else" ]; }
  ];

  # ── fact-wiring fixtures: `lib.probeFact` proven THROUGH the real nixdarwin module ──────────
  #
  # One account declared in every fixture below (`cfg.users != { }`, gating `config.warnings`),
  # but never referencing `fromIdentity` -- so the only thing that could possibly produce a
  # warning is the probe itself, never the `fromIdentity`-resolution assertion reacting to an
  # unresolved name.
  quietUser = { nixdarwin.users.someone.uid = 501; };

  cfgFactsNoNixiamAtAll = evalDarwin [ quietUser ];

  cfgFactsNixiamFaithful = evalDarwin [ fakeNixiamPosixModule withOneIdentity quietUser ];

  # THE DECOY: nixiam's real option surface, renamed. Composes the SAME top-level `nixiam`
  # namespace the real sibling would (so `config ? nixiam` reads true -- state (a), "not
  # composed at all", must NOT be what this fixture exercises), with the specific path this
  # module's own probe reads (`posix.identities`) missing, renamed to a plausible neighbour.
  fakeNixiamPosixRenamedModule = {
    options.nixiam.posix.accounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
  };

  cfgFactsNixiamRenamed = evalDarwin [ fakeNixiamPosixRenamedModule quietUser ];

  results = [
    # --- 1. no default is a hard failure, never a silent guess ---------------------------------
    (check "uid/unset-fails-the-build"
      (darwinBuildFails [{ nixdarwin.users.someone = { }; }])
      "expected an account with neither uid nor fromIdentity to fail the build, but it succeeded")

    (check "uid/literal-value-builds-fine"
      (!(darwinBuildFails [{ nixdarwin.users.someone.uid = 501; }]))
      "a complete, valid declaration should never fail the build")

    (check "uid/disabled-empty-attrset-still-builds"
      (!(darwinBuildFails [{ }]))
      "declaring no nixdarwin.users at all should never force anything, let alone fail the build")

    # --- 2. fromIdentity resolves defensively, and an unknown name is a hard failure -----------
    (check "fromIdentity/resolves-from-nixiam-posix-identities-table"
      (cfgFromIdentity.users.users.mac-app-foo.uid == 3001)
      "got uid=${builtins.toJSON (cfgFromIdentity.users.users.mac-app-foo.uid or null)}, expected the fixture's nixiam.posix.identities.app-foo.uid value")

    (check "fromIdentity/unknown-name-fails-the-build"
      (darwinBuildFails [
        fakeNixiamPosixModule
        withOneIdentity
        { nixdarwin.users.someone.fromIdentity = "does-not-exist"; }
      ])
      "expected fromIdentity naming an entry absent from nixiam.posix.identities to fail the build, but it succeeded")

    (check "fromIdentity/absent-nixiam-module-still-fails-clearly-not-crash-differently"
      (darwinBuildFails [{ nixdarwin.users.someone.fromIdentity = "app-foo"; }])
      "fromIdentity naming anything at all, with nixiam.posix not imported, must still fail the build (there is nothing to resolve against)")

    # --- 3. explicit uid always wins over fromIdentity ------------------------------------------
    (check "fromIdentity/explicit-uid-still-wins"
      (cfgExplicitUidWins.users.users.mac-app-foo.uid == 9999)
      "got uid=${builtins.toJSON (cfgExplicitUidWins.users.users.mac-app-foo.uid or null)}, expected the explicitly-typed 9999 to win over fromIdentity's resolved 3001")

    # --- 4. duplicate uid across two accounts is a hard failure ---------------------------------
    (check "uid/duplicate-across-two-accounts-fails-the-build"
      (darwinBuildFails [{ nixdarwin.users.alice.uid = 700; nixdarwin.users.bob.uid = 700; }])
      "expected two accounts sharing a uid to fail the build, but it succeeded")

    (check "uid/distinct-values-build-fine"
      (!(darwinBuildFails [{ nixdarwin.users.alice.uid = 700; nixdarwin.users.bob.uid = 701; }]))
      "distinct uid values should never fail the build")

    # --- 5. every declared name lands in users.knownUsers, merged not replaced ------------------
    # `contains`, not exact-equality: nix-darwin's own `nix` module populates `knownUsers` with
    # its build-user pool (`nixbld1..32`/`_nixbld1..32`) by default -- confirmed empirically while
    # writing this check -- so this list is never expected to be exactly what nixdarwin itself added.
    (check "knownUsers/every-declared-name-is-known"
      (lib.all (n: lib.elem n cfgTwoUsers.users.knownUsers) [ "alice" "bob" ])
      "got users.knownUsers=${builtins.toJSON cfgTwoUsers.users.knownUsers}, expected it to contain both alice and bob")

    (check "knownUsers/merges-with-a-hosts-own-additions"
      (lib.all (n: lib.elem n cfgKnownUsersMerge.users.knownUsers) [ "alice" "someone-else" ])
      "got users.knownUsers=${builtins.toJSON cfgKnownUsersMerge.users.knownUsers}, expected it to contain BOTH nixdarwin's own \"alice\" AND the host's directly-declared \"someone-else\" -- neither should silently drop the other")

    # --- 6. darwinModules is the ONLY backend exported, checked structurally, not by prose ------
    (check "scope/nixosModules-does-not-exist-on-self"
      (!(flakeSelf ? nixosModules))
      "self.nixosModules exists -- modules/nixdarwin.nix's own header claims this repo is darwin-only; that claim is now false")

    (check "scope/systemManagerModules-does-not-exist-on-self"
      (!(flakeSelf ? systemManagerModules))
      "self.systemManagerModules exists -- modules/nixdarwin.nix's own header claims this repo is darwin-only; that claim is now false")

    (check "scope/darwinModules-default-points-at-the-real-module"
      (flakeSelf.darwinModules.default == flakeSelf.darwinModules.nixdarwin)
      "darwinModules.default has drifted from darwinModules.nixdarwin")

    # --- 8. fact-wiring: lib.probeFact proven through the real module, not just lib/facts.nix's own
    (check "fact-wiring/nixiam-not-composed-has-no-warnings"
      (cfgFactsNoNixiamAtAll.warnings == [ ])
      "got warnings=${builtins.toJSON cfgFactsNoNixiamAtAll.warnings}, expected none: state (a) -- nixiam never imported at all -- must stay silent")

    (check "fact-wiring/nixiam-faithful-has-no-warnings"
      (cfgFactsNixiamFaithful.warnings == [ ])
      "got warnings=${builtins.toJSON cfgFactsNixiamFaithful.warnings}, expected none: nixiam composed with its real, un-renamed shape must produce zero warnings even when no account references fromIdentity at all")

    (check "fact-wiring/nixiam-posix-renamed-warns-exactly-once"
      (
        let w = cfgFactsNixiamRenamed.warnings; in
        lib.length w == 1
        && lib.hasInfix "nixiam.posix.identities" (lib.head w)
        && lib.hasInfix "nixiam" (lib.head w)
      )
      "got warnings=${builtins.toJSON cfgFactsNixiamRenamed.warnings}, expected exactly one, naming nixiam.posix.identities -- the decoy renames it to nixiam.posix.accounts while nixiam itself IS composed, and no account references fromIdentity at all, so nothing but the probe itself can be the source")

    (check "fact-wiring/nixiam-posix-renamed-does-not-fail-the-build"
      (!(darwinBuildFails [ fakeNixiamPosixRenamedModule quietUser ]))
      "state (c) must warn, not fail the build -- lib.probeFact defaults to mode = \"warn\", never \"assert\", for this read; a renamed nixiam is no different from an absent one for an account that never sets fromIdentity")
  ];

  # ── 7. mechanism public, values private: no real host identifier anywhere in the module's own
  # source or the shipped example -- the house rule made mechanically checkable, the same posture
  # nixluks's own `structurally-safe` check uses for a different invariant.
  forbiddenStrings = [
    "corbet"
    "Corbet"
    "CORBET"
    "192.168.42."
    "100.64.42."
    "richc"
  ];
  scanText = text: lib.filter (w: lib.hasInfix w text) forbiddenStrings;
  scanFile = path: scanText (builtins.readFile path);
  scannedPaths = [ ../modules/nixdarwin.nix ../lib/facts.nix ../examples/host/configuration.nix ];
  leaks = lib.concatMap (p: map (w: { inherit p w; }) (scanFile p)) scannedPaths;

  publicValuesResults = [
    (check "public-repo/no-real-host-identifier-in-shipped-files"
      (leaks == [ ])
      "found forbidden string(s): ${builtins.toJSON leaks}")

    # Both directions on the DETECTOR itself, against synthetic text -- not just "the real files
    # happen to be clean today," which would pass just as well with a detector that flags nothing
    # at all. The same distinction nixluks's own forbidden-operation grep never separately proves;
    # closed here instead of copied uncritically.
    (check "public-repo/detector-fires-on-a-planted-host-identifier"
      (scanText "# this example lives at corbet-server.example" != [ ])
      "the detector did not flag a planted real host identifier -- it would silently pass a real leak too")

    (check "public-repo/detector-is-silent-on-generic-text"
      (scanText "# a generic, fictional example host with no real host identifier" == [ ])
      "the detector flagged text containing no forbidden string at all")
  ];

  allResults = results ++ publicValuesResults;

  failed = builtins.filter (r: !r.ok) allResults;
  report = lib.concatMapStringsSep "\n" (r: "  - ${r.name}: ${r.detail}") failed;
in
if failed != [ ]
then
  throw ''
    nixdarwin eval-tests FAILED (${toString (builtins.length failed)}/${toString (builtins.length allResults)}):
    ${report}
  ''
else {
  # Depending on `passedCount` forces `allResults`, so the tests genuinely run under
  # `nix flake check` rather than merely being defined.
  eval-tests = pkgs.runCommand "nixdarwin-eval-tests"
    { passedCount = toString (builtins.length allResults); }
    ''
      echo "all $passedCount nixdarwin eval tests passed"
      touch $out
    '';

  # The shipped example (examples/host) evaluates standalone -- it is meant to be internally
  # consistent by construction, not dependent on any check-only fixture.
  example-evaluates = pkgs.runCommand "nixdarwin-example-evaluates"
    {
      # `toString` on a Nix bool is NOT "true"/"false" (it is "1"/"" -- a real gotcha), hence the
      # explicit if/then/else rather than `toString (...).success` directly.
      passed =
        if (builtins.tryEval (builtins.seq
          (evalDarwin [ fakeNixiamPosixModule withOneIdentity ../examples/host/configuration.nix ]).system.build.toplevel
          true)).success
        then "true" else "false";
    }
    ''
      if [ "$passed" != "true" ]; then
        echo "examples/host/configuration.nix failed to evaluate against a real darwinSystem" >&2
        exit 1
      fi
      touch $out
    '';
}
