# lib/facts.nix -- `lib.probeFact`, vendored from nixhost's `lib/facts.nix`
#
# THIS IS A DELIBERATE LOCAL COPY, not a fork. The canonical version -- full defect-class
# writeup, the two evaluation traps, and the test suite that proves them -- lives in nixhost's
# own `lib/facts.nix`; nothing about the mechanism is reinvented here. If this ever needs to
# change, change it in nixhost first and re-vendor the file verbatim; do not patch a variant in
# just this repo.
#
# WHY THIS REPO STAYS VENDORED WHILE ITS SIBLINGS (nixlxc, nixvm, nixscroll, nixvault) SWITCHED TO
# CONSUMING `nixhost` AS A FLAKE INPUT (2026-07-31 pass). Re-examined explicitly rather than
# converted by default, because the old across-the-board justification -- "vendoring a small pure
# function matches this family's posture toward defensively-read siblings" -- does NOT survive
# scrutiny: it was exactly as true of nixlxc/nixvm/nixscroll/nixvault before that pass, and every
# one of them still reads its OWN siblings (nixstorage/nixiam/nixdesktop) with zero flake
# dependency afterwards. Taking `nixhost` as an input there was never about the DATA those repos
# read defensively; it was about consuming a shared MECHANISM as a real value, the same category
# nixvault already put nixfs in for its f2fs catalogue. That distinction is what actually decides
# this repo's case, and it comes out the other way:
#
#   - nixlxc and nixvm each already read `nixhost.environments.<name>.resources` directly --
#     `nixhost` is an existing, load-bearing domain concept in their own option surface, not a
#     name introduced solely to fetch a utility function.
#   - nixvault already breaks the "zero sibling flake inputs" posture once, for nixfs, because it
#     needs that repo's actual f2fs recipe VALUE -- adding nixhost for `probeFact` is the same
#     category of dependency it already carries, not a new one.
#   - THIS repo (nixdarwin) reads only `nixiam.posix.identities` through `lib.probeFact` --
#     `nixhost`'s own namespace never appears anywhere in `modules/nixdarwin.nix`. And unlike
#     nixvault, nixdarwin has NEVER taken a flake dependency on ANY sibling it reads defensively,
#     not even nixiam -- the ONE thing this whole repo exists to bridge (see flake.nix's own
#     input comment: "nixdarwin never takes nixiam as a flake input"). That is a deliberate,
#     doubly-stated design floor this repo holds itself to more strictly than any other in the
#     family, driven by docs/portability.md's own minimal-footprint mandate: the darwin flavour
#     layer stays the smallest possible bridge, nix-darwin plus nothing else, precisely so it
#     depends on as little of the rest of this Linux-centric family as structurally possible.
#     Taking `nixhost` as a flake input here would be adding the family's namespace-root HUB as a
#     dependency of a repo that has no other reason to know it exists, purely to de-duplicate an
#     80-line comment-heavy utility -- exactly the "otherwise-standalone repo depending on a hub it
#     has no organic reason to know about" case worth leaving alone. If nixdarwin ever grows a
#     real reason to read `nixhost`'s own facts (as nixlxc/nixvm already do), re-examine this
#     then -- that would tip the balance the other way.
#
# THE DEFECT CLASS THIS CLOSES (full writeup: nixhost's `lib/facts.nix`). A defensive
# cross-namespace read of the shape `config.nixfoo.bar or fallback` -- exactly the idiom this
# repo's own `modules/nixdarwin.nix` used for `nixiam.posix.identities` before this file
# existed -- conflates THREE states that are not one state:
#
#   (a) the sibling module (`nixfoo`) is not composed on this host at all   -- legitimate, silent
#   (b) it IS composed, and the fact is genuinely absent/empty              -- legitimate, silent
#   (c) it IS composed, but the specific LEAF moved, was renamed, or its
#       value was rejected by its own type, so the read silently falls back -- a DEFECT
#
# A bare `or` cannot tell (c) from (a)/(b): all three routes land on the identical fallback value
# with no trace of which one was taken. `probeFact` probes the NAMESPACE (`config ? nixfoo`)
# separately from the LEAF (`lib.attrByPath` forced inside `builtins.tryEval`, with a THROWING
# fallback so `tryEval` has something real to catch -- a bare `x.y or fallback` resolves before
# `tryEval` ever runs, and `x.y or null` alone does not catch a mandatory-unset option's own throw
# either, both measured directly, not theorised -- see nixhost's own header for the two traps in
# full). State (c), and only state (c), produces a warning -- or, opt-in via `mode = "assert"`, a
# build-failing assertion, for a read a caller considers load-bearing enough to fail over.
{ lib }:

let
  # `lib.attrByPath` never forces the value it eventually returns -- it only forces enough of each
  # INTERMEDIATE attrset to test `? nextSegment` as it walks deeper, which is unavoidable (you
  # cannot ask an attrset for its keys without evaluating it to WHNF) and is exactly the cost of
  # reading a fact that genuinely IS there. The `throw` is the `default` argument: if any segment
  # of `path` is missing, this is what comes back, UNFORCED -- so it is `builtins.tryEval` below
  # that actually triggers and catches it, never the `attrByPath` call itself.
  attemptLeaf = path: namespaceValue:
    builtins.tryEval
      (lib.attrByPath path (throw "lib.probeFact: leaf did not resolve") namespaceValue);

  normalisePath = path: if builtins.isList path then path else lib.splitString "." path;
in
rec {
  # { config, namespace, path, fallback, mode ? "warn" }:
  #
  #   config     -- the attrset to read from (a real NixOS/system-manager/nix-darwin `config`, or
  #                 plain data in a test -- this function touches nothing module-system-specific,
  #                 only `?` and ordinary attribute access, so either works identically).
  #   namespace  -- the SINGLE top-level attribute name whose presence means "the sibling module
  #                 is composed here", e.g. "nixstorage". Never a dotted path: state (a) is a
  #                 question about one sibling module, and `path` below is where the depth
  #                 belongs.
  #   path       -- the leaf's path INSIDE that namespace, as a list (`[ "delivery"
  #                 "categories" ]`) or a dot-separated string (`"delivery.categories"`) -- both
  #                 spellings normalise to the same list before use, so a caller uses whichever
  #                 reads better at its own call site.
  #   fallback   -- the value substituted for states (a) and (c). Never inspected to help decide
  #                 which state occurred (see this file's header on why a value-based test is
  #                 unsound the moment a leaf can legitimately resolve to the same value used as
  #                 the fallback).
  #   mode       -- "warn" (default) -- an unresolved leaf becomes one string in the returned
  #                 `warnings`, meant to be spliced into the caller's own `config.warnings`.
  #              -- "assert" -- an unresolved leaf becomes one `{ assertion = false; message; }`
  #                 record in the returned `assertions`, meant to be spliced into the caller's own
  #                 `config.assertions`, for a read the caller considers load-bearing enough to
  #                 fail the build over. Absence (state a) and genuine emptiness (state b) never
  #                 produce a warning OR an assertion, in either mode.
  #
  # Returns `{ state; value; optionPath; warnings; assertions; }`. `state` is one of
  # `"absent"` / `"resolved"` / `"unresolved"` -- the three-way answer this whole file exists to
  # make available, for a caller that wants to report or count them rather than only render a
  # message.
  probeFact =
    { config
    , namespace
    , path
    , fallback
    , mode ? "warn"
    }:
    assert lib.assertMsg (mode == "warn" || mode == "assert")
      "lib.probeFact: mode must be \"warn\" or \"assert\", got ${builtins.toJSON mode} -- a third, silently-ignored mode would be this same defect class one layer up.";
    let
      pathList = normalisePath path;
      dotted = lib.concatStringsSep "." pathList;
      optionPath = "${namespace}.${dotted}";

      # STATE (a), decided before anything about `nixfoo` is opened -- see this file's header.
      composed = config ? ${namespace};

      # Lazy on the `if` itself, not merely inside `attemptLeaf`: when `composed` is false this
      # binding is never forced, so `config.${namespace}` is never touched at all.
      attempt = if composed then attemptLeaf pathList config.${namespace} else null;

      resolved = composed && attempt.success;

      state =
        if !composed then "absent"
        else if resolved then "resolved"
        else "unresolved";

      value = if resolved then attempt.value else fallback;

      # `toPretty` can itself choke on an exotic fallback (a function, say); a probe reporting an
      # unresolved fact must never itself become the thing that fails a build over a rendering
      # problem, so this degrades to a plain placeholder rather than propagating a throw.
      fallbackRendered =
        let attempt' = builtins.tryEval (lib.generators.toPretty { } fallback);
        in if attempt'.success then attempt'.value else "<a value this probe cannot render>";

      message = ''
        ${optionPath} did not resolve, even though the `${namespace}` namespace IS composed on
        this host. One of three things is true: the option moved or was renamed somewhere inside
        `${namespace}`, it was declared with no default and never given a value, or the value it
        was given was rejected by its own type -- evaluate `config.${optionPath}` directly to see
        which. Falling back to ${fallbackRendered} in the meantime: that is what this host is
        actually doing right now, not what its configuration appears to say.
      '';
    in
    {
      inherit state value optionPath;
      warnings = lib.optional (state == "unresolved" && mode == "warn") message;
      assertions = lib.optional (state == "unresolved" && mode == "assert") {
        assertion = false;
        inherit message;
      };
    };

  # A caller probing several facts at once folds every probe's `warnings`/`assertions` into the
  # one pair of lists `config.warnings`/`config.assertions` already expect, rather than writing
  # this fold at every call site.
  collectProbes = probes: {
    warnings = lib.concatMap (p: p.warnings) probes;
    assertions = lib.concatMap (p: p.assertions) probes;
  };
}
