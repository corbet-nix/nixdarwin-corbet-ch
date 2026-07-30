{
  description = "nixdarwin -- the darwin sibling of nixarch (Arch/system-manager) and nixnas/nixvps (NixOS flavours): the OS-flavour layer for a Mac host, managed by upstream nix-darwin (https://github.com/LnL7/nix-darwin -- a different project; see README's own \"Name\" section for why this repo is called nixdarwin and not nix-darwin). Ships exactly one piece of real glue nothing else in the family provides -- bridging nixiam's cross-host identity registry onto a real macOS account without reopening the one silent failure nix-darwin's own users.knownUsers gate creates for it -- plus the domain-by-domain portability audit (docs/portability.md) this repo's own scope was decided from.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Used by `checks` only -- nixdarwin's own module (modules/nixdarwin.nix) takes no `pkgs` argument
    # and never references this input (see that file's own header), so a consumer who imports
    # `darwinModules.nixdarwin` into THEIR OWN nix-darwin flake pays no second nix-darwin fetch
    # through this one. Brought in for real here anyway, unlike nixluks's `system-manager` input or
    # the untested `nix-darwin` alias every sibling pure-data repo in this family offers instead:
    # this repo's entire reason to exist IS the darwin backend, so docs/portability.md's claims are
    # backed by an actual `darwinSystem` composition in checks/, not left as an unproven alias (see
    # any sibling pure-data repo's own experiments/README.md #001 for exactly what staying unproven
    # there costs).
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-darwin }:
    let
      lib = nixpkgs.lib;

      # The systems `checks`/`formatter` actually BUILD under -- ordinary Linux CI/dev machines,
      # exactly like nixluks/nixiam. NOT the same list as "systems this module runs
      # on": `darwinModules.nixdarwin` targets aarch64-darwin (see checks/default.nix's own header
      # for why evaluating that FOREIGN system from here is safe and requires no builder for it
      # at all), a fact `nixosModules`/`systemManagerModules`-style repos never have to think
      # about because their target and their CI system are the same one.
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = lib.genAttrs supportedSystems;
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      # darwinModules ONLY -- see modules/nixdarwin.nix's own header for exactly why this module is
      # not also exported as nixosModules/systemManagerModules (`users.knownUsers` is a
      # nix-darwin-only primitive; composing this under either other backend fails loudly, by
      # design, rather than silently doing nothing). checks/default.nix's `scope/*` group proves
      # this structurally -- these two attributes genuinely do not exist on `self` -- rather than
      # leaving it as a claim only this comment makes.
      darwinModules.nixdarwin = ./modules/nixdarwin.nix;
      darwinModules.default = self.darwinModules.nixdarwin;

      checks = forAllSystems (system:
        import ./checks {
          pkgs = pkgsFor system;
          inherit lib nixpkgs system nix-darwin;
          nixdarwinModule = self.darwinModules.nixdarwin;
          flakeSelf = self;
        });

      formatter = forAllSystems (system: (pkgsFor system).nixpkgs-fmt);
    };
}
