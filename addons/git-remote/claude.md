## Git hosting (`git-remote`)

git is set up to push and pull over HTTPS to one Git hosting account; credentials are
filled in automatically. Use HTTPS remote URLs (`git-remote url owner/repo` prints one;
`git@host:` URLs are rewritten to HTTPS).

```bash
git-remote info                                   # host, service, account, API base
git-remote clone owner/repo                       # clone into ./repo
git-remote api GET /user                          # authenticated API call (JSON out)
git-remote api POST /repos/owner/repo/pulls '{"title":"…","head":"branch","base":"main"}'
git-remote gh pr create --fill                    # GitHub only: gh with the token
```

API paths are relative to the service's API base (GitHub REST, Forgejo/Gitea `/api/v1`,
GitLab `/api/v4`). Work on branches and open pull/merge requests rather than pushing to
the default branch unless asked. Never print, copy or commit the token. If a push or API
call fails with an authentication or permission error, report it instead of working
around it.
