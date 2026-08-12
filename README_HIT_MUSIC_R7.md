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
- HOLD notes are thick yellow hollow capsules.
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
- Result: START replays, B returns to selector.

Every song generates slides on both difficulties (`slide_every` is 6–10 in all
profiles, and every pack ships `slides_easy`/`slides_hard`). A 90 s track
produces roughly 9–13 slides on easy and 29–49 on hard, all crossing the
inside of the circle between lane markers.

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