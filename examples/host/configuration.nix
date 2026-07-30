# A generic nixmac-composed nix-darwin host, used by the `example-evaluates` check.
#
# Not a real operator's actual Mac -- see the repo README for why a public repo ships an invented
# example instead. Every name and uid below is fictional. Composed here alongside a STAND-IN for
# nixid's own posix module (the check's own `fakeNixidPosixModule`/`withOneIdentity` fixture,
# declaring one identity: `app-foo`, uid 3001) -- exercising both ways `nixmac.users` resolves a
# uid:
#
#   - `laptop-admin` -- a literal uid, typed directly. No cross-host identity involved.
#   - `svc-app-foo`  -- `fromIdentity = "app-foo"`, resolving the SAME uid this identity carries
#                       on every other machine (see modules/nixmac.nix's own header
#                       for the NFSv4-style drift this exists to prevent).
{ ... }:
{
  nixmac.users = {
    laptop-admin.uid = 504;
    svc-app-foo.fromIdentity = "app-foo";
  };

  # ── Stubs nix-darwin's own module system checks for on every evaluation ──────────────────────
  # Not hardware -- this only exists to type-check the module, the same posture nixmachines' own
  # examples/host/configuration.nix uses for NixOS's fileSystems/bootloader stubs.
  system.stateVersion = 6;
}
