## GitHub (`github-app`)

git and `gh` are authenticated to GitHub as a GitHub App (commits and pull requests
show up as its bot). Tokens are fetched automatically and expire after an hour; you
never need to log in. Use HTTPS remote URLs (`git@github.com:` URLs are rewritten).

```bash
github-app info                    # host, App, commit identity, repositories, permissions
github-app clone owner/repo        # clone into ./repo
git push -u origin my-branch       # credentials are filled in by git
gh pr create --fill                # gh gets a fresh token on every call
gh api repos/owner/repo/pulls
```

The App can only reach the repositories and permissions shown by `github-app info`.
Some `gh` commands that need a user account (`gh auth status`, `gh api user`) fail with
"Resource not accessible by integration"; that is expected. Work on branches and open
pull requests rather than pushing to the default branch unless asked. Never print, copy
or commit a token (`github-app token` is for tools that can't use git or gh). If a push
or API call fails with an authentication or permission error, report it instead of
working around it.
