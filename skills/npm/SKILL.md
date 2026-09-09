---
name: npm
description: Answer questions about npm package adoption and current state — how many times a package was downloaded last week, whether it is still widely used, what version npm install resolves to now, and under what licence. Use for "is this package still popular", "how much is X used", "what's the latest version of Y", "what licence is Z", or any question about npm download momentum or the current published state of a dependency.
---

# npm adoption, and when to use it

OpenSSF scorecards tell you whether a package is well run. They say nothing about
whether anyone still uses it. This realm answers the other half — momentum and
current state — for packages you name by their exact npm name.

## Run a view

| The question | The view |
|---|---|
| How used is each package, and what am I on the hook for? | `PackagePopularity` |
| Which of my dependencies does the ecosystem lean on most? | `AdoptionRanking` |
| How do my dependencies break down by licence? | `LicenceSpread` |

## The two things to get right

**Downloads are momentum, not virtue.** A high count means widely used, not well
run; pair it with the OpenSSF score from realm-oss-health before drawing a
conclusion about risk. A spike is often a release or a CI mirror, and a decline
can simply mean the ecosystem moved to a successor.

**Read the licence from the registry, not the README.** `PackagePopularity` and
`LicenceSpread` report the SPDX id the published version actually carries. A
licence of `unstated` means the version document declared none — worth a look,
not an assumption that it is permissive.

## Saying it properly

- **Weekly, not total.** Every count is the last seven days. Say "last week", not
  "downloads", so nobody reads it as all-time.
- **Exact names only.** The key is the precise npm name; a typo produces no
  reading rather than a wrong one. Unscoped names only in this version — a scoped
  `@org/pkg` will not resolve.
- **A missing package is "not tracked", never "unpopular".** Only seeded
  `NpmPackage` anchors are fetched; absence from a table means it was never named.
