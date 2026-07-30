# checks/default.nix
#
# EVAL-TIME tests, the same posture as the sibling nixluks/nixmachines/nixid projects. No VM, no
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
#      version of this module assumed (by analogy with nixluks/nixmachines) that merely forcing
#      `.config.system.build.toplevel` would surface this the same way an unset `device`/`order`
#      does there -- it does not. nixluks's own `environment.etc."crypttab".text` is a real `/etc`
#      file whose *content* must be computed (forcing every volume's `device`) to build the
#      derivation that becomes part of `toplevel`'s closure; nix-darwin's own per-user uid/gid
#      table feeds its activation script instead, which a shallow `toplevel` force never reaches.
#      Caught by writing this check, not assumed from the sibling repos' pattern -- see
#      modules/nixmac.nix's own `unresolvedNames` for the fix.
#   2. `fromIdentity` resolves a real `nixid.posix.identities.<name>.uid`, defensively, when that
#      module happens to be composed alongside nixmac -- and naming an entry that does not exist
#      there is a hard, clearly-messaged build failure, never a quiet fall-through.
#   3. An explicit `uid` always wins over whatever `fromIdentity` would have resolved to.
#   4. Two `nixmac.users` entries resolving to the same uid is a hard build failure.
#   5. Every name declared under `nixmac.users` ends up in `users.knownUsers` -- the actual fix
#      for this file's own header incident -- merged with, never replacing, whatever a host adds
#      to that list directly.
#   6. `darwinModules` is the ONLY backend this repo exports -- `nixosModules`/
#      `systemManagerModules` genuinely do not exist on `self`, checked structurally.
#   7. Nothing in the module's own source, or the shipped example, names a real host value
#      (hostname, IP, uid) -- the house "mechanism public, values private" rule, made mechanically
#      checkable the same way nixluks's own `structurally-safe` check works, rather than merely
#      asserted in prose.
{ pkgs, lib, nixpkgs, system, nix-darwin, nixmacModule, flakeSelf }:

let
  check = name: ok: detail: { inherit name ok detail; };

  darwinSystemName = "aarch64-darwin";

  mkDarwin = extraModules: nix-darwin.lib.darwinSystem {
    system = darwinSystemName;
    modules = [
      { system.stateVersion = 6; nixpkgs.hostPlatform = darwinSystemName; }
      nixmacModule
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
  # A stand-in for nixid's own posix module -- deliberately NOT the real nixid flake (this repo
  # never takes it as an input, see flake.nix's own header and modules/nixmac.nix's), just enough
  # option surface to prove the defensive read resolves a real value when present. The same
  # posture nixluks's own `fakeNixstorageDisksModule` fixture uses for `nixstorage.disks`.
  fakeNixidPosixModule = {
    options.nixid.posix.identities = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.uid = lib.mkOption { type = lib.types.int; };
      });
      default = { };
    };
  };

  withOneIdentity = {
    nixid.posix.identities.app-foo.uid = 3001;
  };

  cfgFromIdentity = evalDarwin [
    fakeNixidPosixModule
    withOneIdentity
    { nixmac.users.mac-app-foo.fromIdentity = "app-foo"; }
  ];

  cfgExplicitUidWins = evalDarwin [
    fakeNixidPosixModule
    withOneIdentity
    { nixmac.users.mac-app-foo = { fromIdentity = "app-foo"; uid = 9999; }; }
  ];

  cfgTwoUsers = evalDarwin [
    { nixmac.users.alice.uid = 501; nixmac.users.bob.uid = 502; }
  ];

  cfgKnownUsersMerge = evalDarwin [
    { nixmac.users.alice.uid = 501; }
    { users.knownUsers = [ "someone-else" ]; }
  ];

  results = [
    # --- 1. no default is a hard failure, never a silent guess ---------------------------------
    (check "uid/unset-fails-the-build"
      (darwinBuildFails [{ nixmac.users.someone = { }; }])
      "expected an account with neither uid nor fromIdentity to fail the build, but it succeeded")

    (check "uid/literal-value-builds-fine"
      (!(darwinBuildFails [{ nixmac.users.someone.uid = 501; }]))
      "a complete, valid declaration should never fail the build")

    (check "uid/disabled-empty-attrset-still-builds"
      (!(darwinBuildFails [{ }]))
      "declaring no nixmac.users at all should never force anything, let alone fail the build")

    # --- 2. fromIdentity resolves defensively, and an unknown name is a hard failure -----------
    (check "fromIdentity/resolves-from-nixid-posix-identities-table"
      (cfgFromIdentity.users.users.mac-app-foo.uid == 3001)
      "got uid=${builtins.toJSON (cfgFromIdentity.users.users.mac-app-foo.uid or null)}, expected the fixture's nixid.posix.identities.app-foo.uid value")

    (check "fromIdentity/unknown-name-fails-the-build"
      (darwinBuildFails [
        fakeNixidPosixModule
        withOneIdentity
        { nixmac.users.someone.fromIdentity = "does-not-exist"; }
      ])
      "expected fromIdentity naming an entry absent from nixid.posix.identities to fail the build, but it succeeded")

    (check "fromIdentity/absent-nixid-module-still-fails-clearly-not-crash-differently"
      (darwinBuildFails [{ nixmac.users.someone.fromIdentity = "app-foo"; }])
      "fromIdentity naming anything at all, with nixid.posix not imported, must still fail the build (there is nothing to resolve against)")

    # --- 3. explicit uid always wins over fromIdentity ------------------------------------------
    (check "fromIdentity/explicit-uid-still-wins"
      (cfgExplicitUidWins.users.users.mac-app-foo.uid == 9999)
      "got uid=${builtins.toJSON (cfgExplicitUidWins.users.users.mac-app-foo.uid or null)}, expected the explicitly-typed 9999 to win over fromIdentity's resolved 3001")

    # --- 4. duplicate uid across two accounts is a hard failure ---------------------------------
    (check "uid/duplicate-across-two-accounts-fails-the-build"
      (darwinBuildFails [{ nixmac.users.alice.uid = 700; nixmac.users.bob.uid = 700; }])
      "expected two accounts sharing a uid to fail the build, but it succeeded")

    (check "uid/distinct-values-build-fine"
      (!(darwinBuildFails [{ nixmac.users.alice.uid = 700; nixmac.users.bob.uid = 701; }]))
      "distinct uid values should never fail the build")

    # --- 5. every declared name lands in users.knownUsers, merged not replaced ------------------
    # `contains`, not exact-equality: nix-darwin's own `nix` module populates `knownUsers` with
    # its build-user pool (`nixbld1..32`/`_nixbld1..32`) by default -- confirmed empirically while
    # writing this check -- so this list is never expected to be exactly what nixmac itself added.
    (check "knownUsers/every-declared-name-is-known"
      (lib.all (n: lib.elem n cfgTwoUsers.users.knownUsers) [ "alice" "bob" ])
      "got users.knownUsers=${builtins.toJSON cfgTwoUsers.users.knownUsers}, expected it to contain both alice and bob")

    (check "knownUsers/merges-with-a-hosts-own-additions"
      (lib.all (n: lib.elem n cfgKnownUsersMerge.users.knownUsers) [ "alice" "someone-else" ])
      "got users.knownUsers=${builtins.toJSON cfgKnownUsersMerge.users.knownUsers}, expected it to contain BOTH nixmac's own \"alice\" AND the host's directly-declared \"someone-else\" -- neither should silently drop the other")

    # --- 6. darwinModules is the ONLY backend exported, checked structurally, not by prose ------
    (check "scope/nixosModules-does-not-exist-on-self"
      (!(flakeSelf ? nixosModules))
      "self.nixosModules exists -- modules/nixmac.nix's own header claims this repo is darwin-only; that claim is now false")

    (check "scope/systemManagerModules-does-not-exist-on-self"
      (!(flakeSelf ? systemManagerModules))
      "self.systemManagerModules exists -- modules/nixmac.nix's own header claims this repo is darwin-only; that claim is now false")

    (check "scope/darwinModules-default-points-at-the-real-module"
      (flakeSelf.darwinModules.default == flakeSelf.darwinModules.nixmac)
      "darwinModules.default has drifted from darwinModules.nixmac")
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
  scannedPaths = [ ../modules/nixmac.nix ../examples/host/configuration.nix ];
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
    nixmac eval-tests FAILED (${toString (builtins.length failed)}/${toString (builtins.length allResults)}):
    ${report}
  ''
else {
  # Depending on `passedCount` forces `allResults`, so the tests genuinely run under
  # `nix flake check` rather than merely being defined.
  eval-tests = pkgs.runCommand "nixmac-eval-tests"
    { passedCount = toString (builtins.length allResults); }
    ''
      echo "all $passedCount nixmac eval tests passed"
      touch $out
    '';

  # The shipped example (examples/host) evaluates standalone -- it is meant to be internally
  # consistent by construction, the same posture nixmachines' own `example/modules-evaluate`
  # check uses.
  example-evaluates = pkgs.runCommand "nixmac-example-evaluates"
    {
      # `toString` on a Nix bool is NOT "true"/"false" (it is "1"/"" -- a real gotcha), hence the
      # explicit if/then/else rather than `toString (...).success` directly.
      passed =
        if (builtins.tryEval (builtins.seq
          (evalDarwin [ fakeNixidPosixModule withOneIdentity ../examples/host/configuration.nix ]).system.build.toplevel
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
