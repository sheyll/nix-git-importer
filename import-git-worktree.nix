# This file contains a function that imports the .git
# directory of a given path into the nix store.
#
# This function is useful, because it will
# also detect if the given project root directory is
# a non-parent _git worktree_ and if so will instead
# import the parent worktree.
#
# Background: The non-parent git worktrees contain
# a `.git` which isn't a directory with git stuff,
# but a text file with a path to the `.git` directory.
#
# This is required because nix builds are isolated, and
# access to the parent directory is not possible.
#
# The derivation will contain a clone of the given repo
# with `HEAD` pointing to the git reference of the worktree,
# or just the same `HEAD` that the given `gitProjectRoot` has.
{ lib
, runCommandNoCCLocal
, git
, gitProjectRoot
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

  srcDotGit =
    builtins.filterSource
      (filterSourceDotGit gitProjectRoot)
      gitProjectRoot;

  dirEntries = builtins.readDir srcDotGit;

  dotGit = dirEntries.".git" or "missing";

  dotGitWorktreeMatches =
    builtins.match
      "gitdir: (.+)/.git(/worktrees/.+)$"
      (builtins.readFile "${srcDotGit}/.git");

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
runCommandNoCCLocal "imported-git-worktree"
{
  nativeBuildInputs = [ git ];
}
  # Read the reference that a git worktree uses
  ((if gitParentWorktree.worktree != null then
    ''

      declare WORKTREE_HEAD="${gitParentWorktree.worktree}/HEAD"

    ''
  else
    ''

      declare WORKTREE_HEAD="HEAD"

    '') +
  ''
    set -x

    # try to identify the branch that the worktree has checked out...
    declare WORKTREE_BRANCH

    if [[ -e "${gitParentWorktree.parent}/.git/$WORKTREE_HEAD" ]]
    then
      local WORKTREE_REF_NEXT=$(gawk -e '/^ref: / {print $2}' "${gitParentWorktree.parent}/.git/$WORKTREE_HEAD")
      if [[ -n "$WORKTREE_REF_NEXT" ]]; then
         WORKTREE_BRANCH=$(basename $WORKTREE_REF_NEXT)
      else
        echo "Error: The worktree head does not refer to a branch ${gitParentWorktree.parent}/.git/$WORKTREE_HEAD" >&2
        exit 1
      fi
    fi

    if [[ -z "$WORKTREE_BRANCH" ]]
    then
      echo "Error: Cannot resolve the branch for: ${if gitParentWorktree.worktree != null then "${gitParentWorktree.worktree} in " else ""}${gitParentWorktree.parent}" >&2
      exit 1
    fi

    git clone \
     --no-hardlinks \
     --dissociate \
     --no-checkout \
     --verbose \
     --progress \
     --branch $WORKTREE_BRANCH \
     "${gitParentWorktree.parent}" \
    $out

    set +x
  '')

