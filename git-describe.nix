#
# This file contains a function that returns a string
# that is the output of `outputCmd` executed in a
# nix store path that contains only the `.git` directory
# of the `gitProjectRoot` parameter.
#
# This script is pretty complicated, because it will
# also detect if the given project root directory is
# a _git worktree_.
#
# In case it is a _git worktree_ it will lookup the
# parent worktree, and use that as project directory instead.
# This is required because nix builds are isolated, and
# access to the parent directory is not possible.
#
# The `outputCmd` value is a function that takes two
# parameters and returns a shell command string.
#
# The what ever that shell command writes to STDOUT
# is written into the output derivation.
#
# The parameters specify the name of Bash variables
# bound to
#  1.) the nix store path of the pre-processed git repo
#      intended for the `-C` parameter of `git`, and
#  2.) the Git ref of the worktree - if any - that
#      the Git repo specified by the `gitProjectRoot`
#      contains (see the description of Git Worktrees),
#      or just `HEAD` otherwise.
{ lib
, runCommandNoCCLocal
, git
, gitProjectRoot
, outputCmd
, extraInputs ? [ ]
}:
let
  filterSourceDotGit = src:
    (fp: ty:
      let
        relPath =
          lib.removePrefix
            (toString src + "/")
            (toString fp);
      in
      lib.hasPrefix ".git" relPath);

  srcDotGit = builtins.filterSource (filterSourceDotGit gitProjectRoot) gitProjectRoot;
  dirEntries = builtins.readDir srcDotGit;
  dotGit = dirEntries.".git" or "missing";
  dotGitWorktreeMatches = builtins.match "gitdir: (.+)/.git(/worktrees/.+)$" (builtins.readFile "${srcDotGit}/.git");

  gitParentWorktree =
    if dotGit == "missing"
    then abort "${gitProjectRoot} does not contain .git"
    else {

      parent =
        if dotGit == "regular" then
          builtins.path
            {
              path =
                builtins.replaceStrings [ "\n" " " ] [ "" "" ]
                  (builtins.elemAt dotGitWorktreeMatches 0);
              name = "parent-workspace";
              filter = fp: _:
                let
                  m = builtins.match "(.*/\.git.*)" fp;
                in
                m != null && builtins.length m > 0;
            } else srcDotGit;
      worktree =
        if dotGit == "regular" && builtins.length dotGitWorktreeMatches > 1 then
          builtins.replaceStrings [ "\n" " " ] [ "" "" ]
            (builtins.elemAt dotGitWorktreeMatches 1)
        else
          null;
    };
in
builtins.replaceStrings [ "\n" " " ] [ "" "" ] (
  builtins.readFile (
    runCommandNoCCLocal "git-description"
      {
        nativeBuildInputs = [ git ] ++ extraInputs;
      }
      (
        let
          rootVarName = "NIREGI_ROOT";
          workTreeRefVarName = "NIREGI_WORKTREE_REF";
        in
        ''
          ${rootVarName}="${gitParentWorktree.parent}"
        '' +
        (if gitParentWorktree.worktree != null then
          "${workTreeRefVarName}=$(gawk -e '{print $2}' ${gitParentWorktree.parent}/.git/${gitParentWorktree.worktree})"
        else
          "${workTreeRefVarName}=HEAD") +
        ''
          ${outputCmd rootVarName workTreeRefVarName} > $out
        ''
      )
  ))

