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

## Installing an addon manually

Example: installing **Gatherer**.

1. Download this repo: click **Code > Download ZIP** on GitHub, then extract it.
2. Open the extracted `addons` folder and find the `Gatherer` folder.
3. Copy the whole `Gatherer` folder into your WoW AddOns folder:

   ```
   World of Warcraft\<game version folder>\Interface\AddOns\
   ```

   `<game version folder>` is the folder your Forever client runs from.

4. Check the result. The file should be at:

   ```
   ...\Interface\AddOns\Gatherer\Gatherer.toc
   ```

   If it's one level deeper (e.g. `AddOns\addons\Gatherer\...`), move it up. WoW won't find the addon otherwise.

5. Start the game, or type `/reload` if you're already in. At the character select screen, click **AddOns** to confirm Gatherer is listed and enabled.

If Gatherer shows as "out of date," tick **Load out of date AddOns** on that screen.

The same steps work for any other folder under `addons/`.

## Conventions

- Addon folder name must match its `.toc` filename (`Gatherer/Gatherer.toc`).
- Every file an addon loads must be listed in its `.toc`, in load order.
- Each addon uses a single global table named after the addon.
- Set `## Interface:` in each `.toc` to the Forever client's build number.

## Addons

| Addon | Description |
|-------|-------------|
| Gatherer | Gathering helper (work in progress) |
