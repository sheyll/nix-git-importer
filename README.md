# Clone Git Repos into Nix

This clones local git repo dirs into the nix store,
care is taken to find the parent worktree if the given
path points to a worktree create using `git worktree add ...`.

One condition: HEAD must point to a branch.

## Usage

Include this into a `flake.nix` and add the given overlay to
a package set;

Then use `gitWorktreeDescribe` and `gitCloneWorktree`.

TODO provide examples.
