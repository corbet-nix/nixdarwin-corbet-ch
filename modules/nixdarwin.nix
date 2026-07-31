# modules/nixdarwin.nix
#
# nixdarwin's own real content: bridging a cross-host identity (nixiam.posix.identities.<name>, read
# DEFENSIVELY -- nixdarwin never takes nixiam as a flake input, see flake.nix's own header) onto a
# nix-darwin `users.users.<name>` account, and closing the one silent failure mode that bridge
# would otherwise reopen on THIS backend specifically. Nothing else in this file: see
# docs/portability.md for why the rest of the family's domains either cannot land here at all
# (nixluks, nixstorage's ZFS shape, nixboot, nixram, nixgpu -- each tied to a Linux-only
# primitive) or already land here unmodified without this repo doing anything at all (nixsh's
# home-manager backend, nixiam.posix itself).
#
# THE INCIDENT THIS CLOSES, GROUND-TRUTHED AGAINST NIX-DARWIN'S OWN SOURCE
# (modules/users/default.nix, `isCreated`/`isDeleted`): nix-darwin does NOT create, delete, or
# otherwise touch ANY account declared under `users.users.<name>` unless that same name ALSO
# appears in `users.knownUsers` -- every uid/gid table entry and every activation-script
# user/group mutation is gated on `knownUsers` membership, and nothing in nix-darwin itself checks
# that a declared user is also a known one. A fully valid `uid`, evaluated fine, activated fine --
# and the account is simply never created. Discovered, if ever, only when whoever expected to log
# in as it can't. NixOS has no equivalent gap: `users.users.<name>` alone is enough there, which
# is exactly why this is a NEW failure mode this backend introduces, not one inherited from
# elsewhere in the family.
#
# WHY THIS DOES NOT ALSO TOUCH `gid`. nixiam.posix's own User-Private-Group convention -- an unset
# `gid` resolves to that identity's own `uid` -- has no equivalent meaning on macOS: nix-darwin's
# own `gid` default is 20 (`staff`, the ordinary interactive-account group; also ground-truthed
# from modules/users/user.nix), and forcing a Linux-style UPG number over that would silently
# replace a real, recognised macOS group membership with a numeric group nothing else on the
# system knows about. A consumer that genuinely wants group parity too sets
# `users.users.<name>.gid` directly -- this module resolves `uid` only, on purpose, rather than
# invent a translation nobody asked for.
#
# darwinModules ONLY -- never nixosModules/systemManagerModules (see flake.nix). `users.knownUsers`
# is itself a nix-darwin-only option; NixOS and system-manager have no equivalent list at all, so
# composing this file under either backend fails immediately with "the option `users.knownUsers`
# does not exist" -- loudly, at eval time, never silently.
{ config, lib, ... }:

with lib;

let
  cfg = config.nixdarwin;
  factsLib = import ../lib/facts.nix { inherit lib; };
  inherit (factsLib) probeFact;

  # nixiam.posix.identities: read through lib.probeFact -- see this file's own header, and
  # flake.nix's own input comment, for why nixdarwin never takes nixiam as a flake input. Used to
  # be `options ? nixiam && (options.nixiam ? posix) && (options.nixiam.posix ? identities)`, an
  # options-tree check that could not tell "nixiam not imported here" from "nixiam IS imported but
  # `posix.identities` moved or was renamed underneath this exact read" -- both reported the same
  # "not imported" hint below, which is a wrong message pointing at the wrong fix when the real
  # problem is a rename. `identitiesProbe.state` answers "is nixiam composed" from `config`
  # itself, and a genuine rename additionally warns (`config.warnings` below) even on a host
  # where no account currently sets `fromIdentity` at all -- see `checks/default.nix`'s
  # `fact-wiring/*` group for the proof.
  identitiesProbe = probeFact {
    inherit config;
    namespace = "nixiam";
    path = [ "posix" "identities" ];
    fallback = { };
  };
  identitiesDeclared = identitiesProbe.state != "absent";
  identities = identitiesProbe.value;

  knownIdentities =
    if identities == { } then "(none declared)" else concatStringsSep ", " (attrNames identities);

  notImportedHint = optionalString (!identitiesDeclared) ''

    nixiam does not appear to be composed into this configuration at all (checked via
    lib.probeFact against the `nixiam` namespace). Either import it alongside nixdarwin, or set
    `nixdarwin.users."<name>".uid` directly instead of `fromIdentity`.'';

  userNames = attrNames cfg.users;

  # A user whose uid is genuinely unresolved (`fromIdentity` unset AND no default landed on
  # `uid` at all -- see the submodule below) is excluded from THIS comparison, not exempted from
  # failing the build -- the identical reasoning nixluks's own `safeDevice`/`devDups` uses:
  # forcing the merged `assertions` list must never itself throw NixOS's generic "used but not
  # defined" error and bury the much clearer `fromIdentity`-not-found assertion below it.
  safeUid = name:
    let r = builtins.tryEval cfg.users.${name}.uid;
    in if r.success then r.value else null;

  uidDups = filter
    (name:
      let u = safeUid name;
      in u != null && length (filter (m: safeUid m == u) userNames) > 1)
    userNames;

  # Which declared names fail to resolve a uid AT ALL (neither `uid` nor a resolvable
  # `fromIdentity` given). MUST be checked with `tryEval`, not a plain `!= null` comparison: `uid`
  # is typed `int` (never `nullOr int`), so an unresolved, default-less option THROWS the instant
  # it is read at all, rather than returning `null` -- the same reason `safeUid` above exists.
  #
  # This is an explicit check, not incidental: composing this module under a real `darwinSystem`
  # and forcing `.config.system.build.toplevel` (exactly the mechanism nixluks relies on
  # for its own "required option, no default" cases) does NOT, on its own, force an unresolved
  # `nixdarwin.users.<name>.uid` -- confirmed empirically while writing this module. Unlike
  # nixluks's `environment.etc."crypttab".text` (a real `/etc` file, whose *content* must be
  # computed, forcing every volume's `device`, to construct the derivation that becomes part of
  # `toplevel`'s own closure), nix-darwin's per-user uid/gid table
  # (`users.uids`/`users.gids` in its own `modules/users/default.nix`) feeds the activation
  # script rather than anything `toplevel`'s own WHNF happens to reach. Relying on that same
  # incidental-forcing trick here would have silently done nothing -- this assertion is the actual
  # safety net, not a belt-and-suspenders restatement of one.
  #
  # Excludes names `fromIdentity`'s own dedicated assertion (below) already reports on: a
  # `fromIdentity` naming an unresolvable identity gets exactly one, specific message instead of
  # this generic one on top of it.
  unresolvedNames = filter
    (name: !(builtins.tryEval cfg.users.${name}.uid).success && cfg.users.${name}.fromIdentity == null)
    userNames;
in
{
  options.nixdarwin.users = mkOption {
    # `{ name, config, ... }`'s own `config` below is THIS ONE USER's submodule config
    # (`config.fromIdentity`), a different value than the outer `cfg = config.nixdarwin` above --
    # the same double meaning nixluks's own `volumeModule = { name, config, ... }:` already
    # relies on for `fromDisk`/`device`.
    type = types.attrsOf (types.submodule ({ name, config, ... }:
      let
        resolvedUid =
          if config.fromIdentity == null then null
          else if identities ? ${config.fromIdentity} then identities.${config.fromIdentity}.uid
          else null;
      in
      {
        options = {
          fromIdentity = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "app-foo";
            description = ''
              Name of an entry in `nixiam.posix.identities` (the cross-host uid/gid registry) whose
              `uid` this macOS account should share, so a login account on this Mac and every
              other identity carrying the same name elsewhere resolve to the SAME numeric
              uid -- the same reason nixiam's own header cares about a shared NFSv4 `domain`: two
              different numbers meaning "the same identity" on two machines is exactly the drift
              that turns a shared SMB/NFS mount into a silently-wrong-permission bug on whichever
              side drifted.

              When set, `uid` DEFAULTS to that identity's own `uid` instead of the same number
              being typed a second time here. Leave `null` to type `uid` directly -- a Mac not
              sharing identities with other hosts, or nixiam not being imported at all,
              is unaffected: nixdarwin never imports nixiam and reads it defensively
              (`config.nixiam.posix.identities or { }`). Setting `uid` explicitly always wins over
              whatever `fromIdentity` would have resolved to.
            '';
          };

          uid = mkOption ({
            type = types.int;
            description = ''
              This account's uid. Required unless `fromIdentity` names a resolvable
              `nixiam.posix.identities` entry -- see that option. There is deliberately no
              fallback default when neither is given: an account nixdarwin does not know how to
              number is a configuration error to catch at build time, never a value to guess at.
            '';
          } // optionalAttrs (resolvedUid != null) {
            default = resolvedUid;
            defaultText = literalExpression
              "nixiam.posix.identities.<fromIdentity>.uid, resolved via this account's own fromIdentity";
          });
        };
      }));
    default = { };
    description = ''
      macOS accounts the operator wants nix-darwin to actually create/manage, bridged from the
      cross-host identity registry when one exists. Every name declared here is automatically
      added to `users.knownUsers` (see this file's own header for the silent no-op that closes)
      -- never something a consumer has to remember as a second, separate step.

      This does NOT create the account on a system where it never existed if macOS itself refuses
      to (nix-darwin's own `users.users` documents that boundary); it declares uid/knownUsers
      membership for whatever account lifecycle nix-darwin's own module already provides.
    '';
  };

  config = mkIf (cfg.users != { }) {
    assertions =
      (map
        (name: {
          assertion = false;
          message = ''
            nixdarwin.users."${name}": neither uid nor fromIdentity is set. Set one of the two --
            there is deliberately no fallback default here, see modules/nixdarwin.nix's own header.
          '';
        })
        unresolvedNames)
      ++ (map
        (name: {
          assertion = identities ? ${cfg.users.${name}.fromIdentity};
          message = ''
            nixdarwin.users."${name}".fromIdentity = "${cfg.users.${name}.fromIdentity}" names an
            entry that does not exist in nixiam.posix.identities. Known identities: ${knownIdentities}.${notImportedHint}
            Fix the name, or set users."${name}".uid directly instead of using fromIdentity.
          '';
        })
        (filter (name: cfg.users.${name}.fromIdentity != null) userNames))
      ++ (optionals (uidDups != [ ]) [{
        assertion = false;
        message = ''
          nixdarwin.users: ${concatStringsSep ", " uidDups} resolve to the SAME uid -- each declared
          account must have its own. Two macOS accounts sharing a uid is invisible at declaration
          time and stays invisible at login: both exist, and each can silently read and overwrite
          the other's files.
        '';
      }]);

    # THE SHARED READ CONTRACT'S OWN OUTPUT: state (c) on `nixiam.posix.identities` -- composed
    # but renamed -- warns here even when no account currently sets `fromIdentity` at all, the
    # case the `fromIdentity` assertion above can never catch because nothing forces it to look.
    # See `identitiesProbe`'s own comment above and `checks/default.nix`'s `fact-wiring/*` group.
    warnings = identitiesProbe.warnings;

    users.users = mapAttrs (name: u: { uid = u.uid; }) cfg.users;

    # THE FIX ITSELF: every declared account is automatically known, so the knownUsers omission
    # this file's header describes cannot happen for anything declared through nixdarwin. Merges
    # with any names a host adds directly -- `users.knownUsers` is a plain `listOf`, concatenated
    # across modules exactly like `environment.systemPackages` is -- never a replacement for them.
    users.knownUsers = userNames;
  };
}
