{

  description = "Nix utility to strip and import a local git repo into the nix store, even if it the user specified a (non-parent) git worktree";

  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, flake-utils, nixpkgs }:
    flake-utils.lib.eachDefaultSystem
      (system:
        {
          overlay = final: prev: {
            gitWorktreeDescribe = gitProjectRoot:
              let
                repo = final.gitCloneWorktree gitProjectRoot;
              in
              builtins.replaceStrings [ "\n" " " ] [ "" "" ] (
                builtins.readFile (
                  prev.runCommandNoCCLocal "git-describe-worktree"
                    {
                      nativeBuildInputs = [ repo final.git ];
                    }
                    ''
                      git -C ${repo} describe --tags --long --first-parent > $out
                    ''));
            gitCloneWorktree = gitProjectRoot:
              prev.callPackage ./import-git-worktree.nix { inherit gitProjectRoot; };
          };
        });
}
