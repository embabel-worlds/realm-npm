# realm-npm

**When to run it.** The adoption side of your dependencies — how many times a
package was pulled last week, what `npm install` resolves to now, and under what
licence. The half an OpenSSF scorecard leaves out.

```
NpmPackage ──HAS_WEEKLY_DOWNLOADS──▶ NpmDownloads   per package
NpmPackage ──HAS_LATEST_RELEASE────▶ NpmRelease     per package
```

## Source

Two, both open and keyless, no account:

- **npm download counts** — `https://api.npmjs.org/downloads/point/last-week/{name}`
- **the registry itself** — `https://registry.npmjs.org/{name}/latest`

Only the fixed-window operations are declared. The download API offers arbitrary
`from..to` ranges, but a producer's arguments are static — there is no way to say
"the last 30 days from today" — so this realm answers about the last **seven
days** (a fixed path segment) rather than 400ing on a range it cannot express.

## Getting an answer

```javascript
gateway.repository.createEntry({ type: "NpmPackage", data: {
  name: "react", notes: "front-end of the console",
}})
```

Then run `PackagePopularity`, `AdoptionRanking` or `LicenceSpread`.

## One decision worth knowing about

**Both readings are keyed per package, and their identity is the package name,
never a value from the response.** Two packages downloaded the same number of
times are two readings, not one — so the identity is `key` (the name fetched),
and using `downloads` as an identity would silently collapse them. This is the
same shape as any per-anchor reading: the key distinguishes; the body does not.

## Pairs with

**realm-oss-health.** Downloads answer "is it used"; the scorecard answers "is it
well run". A package that is heavily used and poorly scored is where your
attention belongs — the two realms together say so, neither alone.

## Licence

Apache 2.0. Data © npm, Inc., used under its public API terms.
