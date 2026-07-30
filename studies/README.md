# studies

Written-up findings: things that were tried in [`../experiments/`](../experiments/README.md),
worked (or failed instructively), and are worth recording properly -- with the reasoning, not just
the result.

A study earns its place here once it changed a decision in the main project. Nothing has closed
yet. `nix flake check` proves `modules/nixdarwin.nix`'s option surface and assertions behave as
documented against real `darwinSystem` evaluations (real `nix-darwin`, real `nixpkgs`) -- including
both directions of every assertion, the `users.knownUsers` fix actually landing, and the structural
"darwin-only" claim. It does not prove `../experiments/README.md`'s open questions: whether this
actually converges a real macOS account when run for real (experiment 001), or whether
`fromIdentity` is the shape a real Mac's real accounts turn out to want (experiment 002).

Nothing invented below -- this is a list of what would be worth writing up if one of those
experiments closes, not a result:

- **`darwin-rebuild switch` proven against the real Mac host** (experiment 001) -- once
  this Mac is under nix-darwin management at all, the finding (activation matched evaluation, or a
  genuine gap found and fixed) belongs here.
- **Whether `fromIdentity` matched real account usage** (experiment 002) -- the answer only means
  something once real accounts exist to look at.

None of these have been run. Until one is, this directory stays empty of findings by design -- see
`../experiments/README.md` for the reasoning behind each open question in the meantime.
