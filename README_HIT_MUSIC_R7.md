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
- SLIDE notes use large cyan chevrons and a large outlined star.
- TAP hits use layered diamonds.
- Song video is shown in the central horizontal rectangle.
- Each song has its own colors, pattern, BPM, lane sequence, easy chart and hard chart.

## Controls

Selector:

- `input_a`: next song.
- `input_b`: switch easy/hard.
- `input_start`: play.

Gameplay:

- `input_a` through `input_h`: TAP and HOLD lanes.
- Touch/mouse: TAP, HOLD and SLIDE.
- Result: START replays, B returns to selector.

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