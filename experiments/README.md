# Experiments

Throwaway trials: spikes, one-off scripts, measurements not yet worth writing up properly.
Nothing here is guaranteed to work, be maintained, or survive the next cleanup pass. If something
in here turns out to matter, distill the actual finding into [`../studies/`](../studies/README.md)
and let the experiment stay disposable (or delete it).

This is also the open-questions ledger for nixdarwin's own judgment calls -- every entry below
corresponds to a claim reasoned in a module, README, or `docs/portability.md` comment but not
actually measured against a real Mac.

All open.

## 001 -- does this actually run `darwin-rebuild switch` on real hardware?

**Question:** every check in this repo evaluates a `darwinSystem` (real `nix-darwin`, real
`nixpkgs`, `system = "aarch64-darwin"`) and forces `.config.system.build.toplevel` far enough to
run nix-darwin's own assertion check, proven to work and to be fast, with no builder or emulator
for aarch64-darwin needed for evaluation alone (see `checks/default.nix`'s own header for how that
was established). None of that builds the toplevel's actual closure, boots it, or runs
`darwin-rebuild activate` against a real macOS system -- there is no real, already-managed Mac
host to run that against yet (see README's "What this actually is").

**Hypothesis:** the module only touches `users.users`/`users.knownUsers`/`assertions` -- ordinary,
long-stable nix-darwin option surface -- so activation should behave exactly as evaluation
predicts. But "should" is exactly the word this family's own house rules distrust without a
measurement.

**Method sketch:** once the Mac is actually put under nix-darwin management, wire
`nixdarwin.darwinModules.default` into its real flake, declare one real account through
`nixdarwin.users`, and confirm `darwin-rebuild switch` actually creates it (or, for an account that
already exists, actually converges its uid) -- not just that the config evaluates.

**Status:** open.

## 002 -- is `fromIdentity` the right shape for a Mac account that ISN'T a cross-host identity?

**Question:** `nixdarwin.users.<name>` requires either `uid` or `fromIdentity` -- there is no
declared preference for which macOS accounts on a real Mac (the interactive owner's own login, an
admin account, a service account) would actually want cross-host uid parity versus a uid that only
ever needs to make sense locally.

**Hypothesis:** the interactive owner's own account is the one most likely to want
`fromIdentity` (the same login shows up as an SMB/NFS client elsewhere); a
throwaway local admin account probably never should. This has not been weighed against how a real
Mac actually gets used.

**Method sketch:** once real accounts are declared (see 001), check whether the `fromIdentity`
users actually needed it or whether every account on this one Mac ended up a plain literal `uid`
in practice, making the option surface bigger than the real usage ever needed.

**Status:** open.
