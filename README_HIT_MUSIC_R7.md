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
- HOLD notes are a thin yellow energy ribbon with a draining core and
  travelling pulses. In the last 0.16 s the ribbon retracts into the target
  and the burst picks it up from there, so there is no visual jump between
  note and effect.
- SLIDE notes use chevrons and a star drawn in the note's own tazo color
  (cyan/yellow/red). Four arrow silhouettes and four star silhouettes rotate
  between slides; the color never changes family, only the shape does.
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
- SLIDE on the cabinet: press the path lanes in order. The LED lights only the
  next lane of the path, so the drag is playable without a touch screen.
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

Easy and hard are genuinely different charts, not the same chart thinned out:
easy walks in whole beats and only lands on strong beats, hard walks in eighths
and uses offbeats and syncopation. They also use different lane steps (3 vs 5,
both coprime with 8, so all eight buttons are used) and separate RNG seeds.

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