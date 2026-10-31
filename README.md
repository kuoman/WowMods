# WowMods

World of Warcraft Forever addons.

## Layout

```
addons/    One folder per addon, laid out as it sits in Interface\AddOns\
docs/      Notes, API references, conventions
shared/    Code reused across addons (copy into an addon's Libs/ to use)
tools/     Install/package scripts
dist/      Built zips (git-ignored)
```

## Conventions

- Addon folder name must match its `.toc` filename (`Gatherer/Gatherer.toc`).
- Every file an addon loads must be listed in its `.toc`, in load order.
- Each addon uses a single global table named after the addon.
- Set `## Interface:` in each `.toc` to the Forever client's build number.

## Addons

| Addon | Description |
|-------|-------------|
| Gatherer | Gathering helper (work in progress) |
