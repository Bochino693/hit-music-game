# Hit Music R7

This refactor keeps the original cabinet flow:

1. `scenes/opening.tscn`
2. `scenes/change_scenes.tscn`
3. One scene per song
4. Result screen
5. Return to selector

## Main layout

- Rectangular HUD at the top.
- Large circular playfield at the bottom.
- Continuous white outer ring.
- Eight fixed white lane markers.
- No stationary tazo at the target.
- The tazo entity is used only by moving TAP notes.
- HOLD notes are a thin energy ribbon in the note's own tazo color, with a
  draining core and travelling pulses. In the last 0.16 s the ribbon retracts into the target
  and the burst picks it up from there, so there is no visual jump between
  note and effect.
- SLIDE notes use chevrons and a star drawn in the note's own tazo color.
  Four arrow silhouettes and four star silhouettes rotate between slides; the
  color never changes family, only the shape does.
- The slide star has its own draw physics: the mechanical progress may jump
  (a fast finger covers several samples in one frame), but the drawn progress
  chases it at a capped speed, so the star always travels the path instead of
  teleporting. The rail and arrows fade in during the approach.
- Tazo colors follow the sprite sheet frame order: frame 0 yellow, frame 1 red,
  frame 2 cyan (`tap_palette.color_for_index`). Changing that order desyncs
  every effect from the art.
- TAP hits use layered diamonds.
- Every hit effect uses the color of the object that produced it — a cyan tazo
  can never burst in yellow.
- A note can be hit as soon as it appears; the burst is drawn where the object
  actually is at that moment, not at the ring marker. Hitting on time still
  scores more (see `_timing_quality` in `stage.gd`).
- Each song has its own full-screen universe drawn by `_draw_universe`
  (blades, ki aura, breathing waves, rune swarm, spiral seal, portal lab,
  moon hive) plus a matching cosmic sky. There is a single background layer —
  no overlays stacked on top of each other.
- The record sits in its own badge in the top-right corner of the HUD panel,
  auto-fitted so it never overlaps or truncates.
- Ambient dust is a parallax star field: particles are born near the middle,
  accelerate outward, grow and brighten, then fade at the rim, with two comets
  crossing on a slow cycle. Each universe sets its own swirl and speed.
- The result modal has its own palette (not the song's), green when the run
  qualifies and red when it does not, with a visible countdown.
- The 3-2-1 countdown cycles the three table colors, one second each: blue, red,
  yellow. The game sends `COUNT n` each second (it previously only sent
  `BLINKALL`, which left the firmware on `numero_contagem = 5` — the default
  cyan branch, which is why the countdown was always blue). The firmware palette
  in `cor_contagem` was aligned to the same three colors, and the on-screen
  number is tinted to match.
- Song video is shown in the central horizontal rectangle.
- Each song has its own colors, pattern, BPM, lane sequence, easy chart and hard chart.

## Controls

Selector:

- `input_a`: next song.
- `input_b`: switch easy/hard.
- `input_start`: play.

Gameplay:

- `input_a` through `input_h`: TAP and HOLD lanes.
- Touch/mouse: TAP, HOLD and SLIDE (the pointer has to sweep the whole
  corridor — jumping from start to end does not complete the note).
- SLIDE is a **gesture, not a button**. It only responds to the touch frame, and
  only completes when the finger actually sweeps the corridor from one point to
  the other (`_advance_slide_progress` samples the path between pointer positions
  and stops advancing the moment a sample falls outside it). Physical buttons do
  nothing to a slide: pressing the start lane and then the end lane used to close
  the note without drawing anything, which is exactly the shortcut that is gone.
  For the same reason a slide **lights no LED at all** — a lit button would be an
  invitation to press it. The path is shown on screen: the trail, the arrows and
  the star.
- Result modal: START (or a tap) takes the highlighted action, B opens the song
  selector. When the countdown runs out with nothing chosen, the game returns to
  the opening screen.
  - Free mode: continue to the next song (retry when the run failed), or pick
    another song.
  - Credit mode: both options require a credit and consume one; with no credit
    the buttons are hidden and the countdown goes straight to the opening.

The down button in the menus is `input_e` (physical lane 4). It is defined once,
in `led_client.gd` (`NAV_DOWN_ACTION` / `NAV_DOWN_LANE`), and the song selector,
the difficulty screen and their LEDs all read from there.

Difficulty screen (the mode screen): the cursor walks through **FACIL,
DIFICIL and VOLTAR** with the same three lit buttons as everywhere else —
`input_a` up, `input_e` down, `input_b` confirms — and the panel can also be
touched directly. VOLTAR goes back to the song selector, which is the way out
when the wrong song was picked. No credit is spent up to that point:
`_confirm_difficulty` is what consumes it.

Settings screen (F9 / SELECT): the same three buttons stay lit on the table
(A up, B start/confirm, E down). Entering the panel hands the serial over —
`LedClient.begin_settings()` drops the previous screen's state (the opening
writes `ATTRACT`) with a `CLEAR`, and the menu frame goes out right after it,
far enough apart for the bridge to see both. Leaving clears the table again so
the next screen writes its own frame in `_ready()`.

Every song generates slides on both difficulties. `slide_every` / `hold_every`
from the JSON now act as *weights* in the phrase draw rather than a fixed
cadence, so a 110 s track lands roughly 4–7 slides and 3–7 holds per difficulty,
spread across the song instead of clustered on a fixed interval. All slide paths
cross the inside of the circle between lane markers.

## Charts

`rhythm_profile.gd` derives everything about how a song plays from its BPM:
approach speed, hit windows, note density, lane sequence and slide shapes.
Anything present in the JSON overrides the derived value, so tuning by hand
still works.

`chart_factory_v9.gd` builds the chart in **bars**, not in "one event every N
notes". Every note lands exactly on a beat subdivision, so the gameplay sits on
the drums. The song is split into 4-bar phrases and each phrase draws a weighted
archetype — run, hold break, slide turn, two-hand pair, mixed — with a penalty
for repeating the previous one, which is what mixes the note types.

Charts are checked for **two-hand playability**: a long gesture (slide or hold)
blocks every other note for its whole duration plus a recovery beat, counted in
absolute slots so a gesture that overruns its phrase still protects the next one.
Simultaneous pairs only use lanes 3–5 apart on the ring, which is what two hands
can actually reach. Auditing the seven songs before this rule found 91 notes
landing inside an active gesture; it is now zero.

Easy and hard are genuinely different charts, not the same chart thinned out:
easy walks in whole beats and only lands on strong beats, hard walks in eighths
and uses offbeats and syncopation. They also use different lane steps (3 vs 5,
both coprime with 8, so all eight buttons are used) and separate RNG seeds.

## Operator-registered songs

The Settings screen (F9) can register a song from the cabinet: name, audio,
optional video, optional cover and BPM. The chosen files are copied into
`user://` (an exported build cannot write to `res://`), the entry goes to
`user://hit_music_user_songs.json`, and `catalog.all_songs()` merges it with the
factory list — same selector, same ranking, same chart generation. Colors are
sampled from the cover when there is one. All operator songs share
`scenes/user_song.tscn`, which resolves which song to play from the tree meta,
because a new `.tscn` cannot be generated at runtime.

### Importing a whole pen drive

The music screen lists every folder found on the removable drives and keeps
**IMPORTAR TODAS** as the first stop of the cursor. It imports the entire pen
drive in one go — one package per frame, so the panel keeps drawing and the
counter moves — and VOLTAR interrupts it at any point without losing what
already went in.

- Folders that are not valid packages are no longer hidden. They show up in the
  list as `ERRO` with what is missing (`1 OGV`, `ARQUIVO EXTRA`, `TXT SEM
  name="..."`) and are named again in the report at the end of the batch.
- Packages already on the machine are skipped and counted, never imported
  twice: the match is by audio hash, package id or title.
- Every attempt is written to `user://hit_music_import_log.json`
  (`user_catalog.import_log_record`). Running the batch again after swapping the
  pen drive, or after a cancel, picks up exactly where it stopped, and a package
  that failed before is flagged as `FALHOU ANTES` in the list.
- Packages without BPM in the file still go through the 16 s audio analysis; the
  batch waits for it and carries on by itself.

## Long song names

The operator names songs freely, and pen drive packages usually arrive with the
full title (`EVANGELION - A CRUEL ANGEL'S THESIS (OPENING COMPLETO)`). Shrinking
the font was not enough, because of how Godot sizes labels:

> A `Label` placed by hand — not inside a container — never accepts being smaller
> than the text it carries. `size` is always raised to the minimum computed from
> the content, and `clip_text` then clips nothing, because everything fits inside
> that inflated rectangle. A 74-character title ended up **659 px wide inside a
> 94 px card**, crossing the list and landing on top of the info panel.

`text_fit.gd` fixes it by shortening the text instead of trusting the clip. Order:
shrink the font to fit one line; if it still doesn't fit at the minimum size, wrap
into **two** lines when the box is tall enough; otherwise cut with an ellipsis —
a cut the player understands, unlike half a letter. The original text is kept in
the label's meta, so a later re-fit starts from the full name, and the `size` is
applied twice (once directly, once deferred) because Godot recomputes a label's
minimum size one idle frame later.

It is used by the selector cards and info panel, the in-game HUD title (two lines
inside its reserved box, above the difficulty row) and the new-record panel.

## No mouse pointer, anywhere

The table has no mouse — the touch frame emulates one. A single screen asking for
`MOUSE_MODE_VISIBLE` was enough to leave a white arrow parked on the glass where
the last finger touched, and `stage.gd` did exactly that, which is why the pointer
only ever showed up **during a song**. That call is gone (so is the one in the
legacy `selector.gd`), and `arcade_shell.gd` now enforces it for the whole game:
`MOUSE_MODE_HIDDEN` is re-asserted every frame (a cheap enum read; it only writes
when something changed), and every cursor shape gets a fully transparent image at
startup, so even a one-frame slip shows nothing. Touch feedback during a song is
the game's own, drawn by the playfield.

## Kiosk and the touch frame

The cabinet is a table with an IR touch frame: the player rests a hand on the
glass, brushes the edge, holds a finger still. Windows answers each of those
with something drawn **on top of the running song** — the gray contact circle,
the press-and-hold right-click ring, the Action Center sliding in from the
edge, an update toast, the pen drive AutoPlay window, the touch keyboard. None
of that can be removed from game code; they are Windows settings.

`QUIOSQUE_HIT_MUSIC.ps1` (project root, next to the LED bridge) turns them off:

| what | where |
| --- | --- |
| gray contact circle | `Control Panel\Cursors` → `ContactVisualization` |
| gesture trails | `Control Panel\Cursors` → `GestureVisualization` |
| hold = right click | `Wisp\Touch` → `TouchMode_hold` |
| toasts / notifications | `PushNotifications` → `ToastEnabled` (+ `NOC_GLOBAL_SETTING_TOASTS_ENABLED`) |
| pen drive AutoPlay window | `Explorer\AutoplayHandlers` → `DisableAutoplay` |
| touch keyboard | `TabletTip\1.7` → `EnableDesktopModeAutoInvoke` |
| screen saver, sleep, monitor off | `Control Panel\Desktop` + `powercfg` |
| edge swipe (Action Center) | `Policies\...\EdgeUI` → `AllowEdgeSwipe` (needs admin) |

Everything is per-user (`HKCU`) except the edge swipe, which is a machine
policy: without admin that single item is skipped and reported. The visual
settings are also pushed through `SystemParametersInfo`, so they take effect
immediately instead of at the next sign-in. The previous value of every item is
saved to `%APPDATA%\Hit Music\quiosque_backup.json`, and `-Restaurar` puts the
machine back:

```powershell
powershell -ExecutionPolicy Bypass -File .\QUIOSQUE_HIT_MUSIC.ps1 -Restaurar
```

`arcade_shell.gd` runs the script once at startup (Windows only, hidden window,
non-blocking) using the same res:// → user:// extraction as the LED bridge, so
it works from the exported .exe. The window itself now starts as exclusive
fullscreen, borderless and always-on-top from `project.godot` instead of only
being promoted at runtime, and the shell re-asserts foreground every 0.35 s —
on a touch table nobody clicks the game window back, they just watch the song
disappear.


### Smoke test

```powershell
godot --headless --path . res://tools/smoke_final.tscn
```

Checks the VOLTAR on the mode screen, the A/E/B LEDs plus the serial handover in
Settings, the batch import (including the second pass, which must import nothing
and count the songs already installed), the kiosk settings — window flags, the
re-assert interval, and that the script still turns off every item in the table
above — long-name fitting, the pointer rule, and the slide rule: a physical
button neither starts nor completes a slide, a swept finger does, and a slide
never lights a lane. It prints `SMOKE_FINAL_OK`.

Run it with a window (`xvfb-run` on Linux, or just the editor build on the
cabinet) to also cover the live pointer check: a headless display server does not
keep a mouse mode, so that one assertion reports itself as skipped instead of
failing.

## Song catalog

All packs are configured in:

`res://data/hit_music_songs.json`

Existing packs linked by the migration:

- Carmine
- Dragon Ball
- Demon
- Fairy
- Naruto
- Rick and Morty
- Soul

Each pack defines:

- scene
- audio
- video
- cover
- BPM
- theme colors
- background pattern
- easy timing/profile
- hard timing/profile
- lane patterns
- slide path patterns

## Adding another song

A new screen only needs `id`, `title`, `audio`, `video`, `cover` and `bpm`.
Everything else — the easy and hard profiles, the lane pattern and the slide
shapes — is derived from the BPM, so the song arrives with a rhythm of its own.
Add `easy` / `hard` blocks to the JSON only when you want to override something.

### Script helper

Run from the project root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\adicionar_musica_r7.ps1 `
  -Id "new_song" `
  -Title "NEW SONG" `
  -Audio "res://songs/new_song.mp3" `
  -Video "res://medias/new_song.ogv" `
  -Cover "res://images/new_song.jpg" `
  -Bpm 150
```

This creates the scene, wrapper script and catalog entry.

## Important synchronization note

The charts are deterministic and BPM-based. Easy and hard are genuinely different, but exact note-to-drum synchronization still depends on the BPM and `chart_start` values in the JSON catalog. Adjust those values per song after testing on the cabinet.