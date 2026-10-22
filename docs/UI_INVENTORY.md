# Musify — Pages & Items

Simple list of every screen and what's on it, top to bottom.

---

## Global (on every screen)

- Bottom tab bar: HOME · SEARCH · LIBRARY · SETTINGS
- Mini player (above tab bar, when a song is loaded): artwork, title, artist, 8D button, play/pause, next
- Toast messages (small pop-ups for confirmations)
- Offline strip (only when there's no connection)

---

## 1. HOME

- Header: " // HOME" + refresh button
- Filter pills: ALL / MUSIC / 8D SPATIAL PICKS / OFFLINE READY
- Jump Back In — 6 tiles (Liked Songs, Offline Vault + 4 recent collections)
- Continue Listening rail
- Made For You rail (daily mixes, when available)
- Trending Now rail
- Top Charts rail
- New Releases rail
- Browse Genres — grid of 8 tiles
- Mood Playlists rail
- Recently Cached rail (when cache has songs)
- Footer text

**Other filters:**
- MUSIC → All Music rail + the catalogue rails (no personal stuff)
- 8D SPATIAL PICKS → 8D songs rail + "what is 8D" text + "MORE TO ORBIT" rail
- OFFLINE READY → Offline Vault rail + Recently Cached rail, or an empty message with an "OPEN LIBRARY" button

---

## 2. SEARCH

- Header: " SEARCH"
- Search field
- Facet pills (after searching): ALL / SONGS / ARTISTS / ALBUMS / PLAYLISTS
- Before typing: Recent Searches (up to 6) + Browse Genres grid (8 tiles)
- Results: Top Result card, Songs list, LOAD MORE button, Artists rail, Albums rail, Playlists rail

---

## 3. LIBRARY

- Header: " LIBRARY" + import button + grid/list toggle
- Counts line: "N items // N liked // N offline"
- Filter pills: ALL / PLAYLISTS / LIKED / DOWNLOADS / ALBUMS / ARTISTS
- Filter field (search inside library)
- Sort button: PLAYED / ADDED / A–Z
- Import progress strip (while importing a playlist)
- Download strip (while downloading)
- List or grid of entries: Liked Songs, Offline Vault, playlists, downloads, albums, artists
  - each entry: artwork, title, subtitle; playlists have a ⋮ menu
- Empty message per filter + "IMPORT A PLAYLIST" button

---

## 4. SETTINGS

8 sections, top to bottom:

1. **STREAMING QUALITY** — Wi-Fi, Mobile data, Downloads; each with 320 / 160 / 96 kbps
2. **SPATIAL 8D ENGINE** — 8D on/off, calibrate, orbit speed, room size, rear low-pass, auto 8D on headphones, reset
3. **EQUALISER** — EQ on/off, presets (Flat, Bass Boost, Vocal, Electronic, Phonk, Acoustic), 10 band sliders, bass boost
4. **PLAYBACK BEHAVIOUR** — crossfade, gapless preload, prefetch, instant play, spectrum mode (FFT / WAVE / OFF)
5. **INTERFACE** — theme (Carbon / Alabaster / System), haptics
6. **STORAGE** — stream cache size, offline vault size, clear cache, delete downloads
7. **BACKUP & RESTORE** — export .json, import .json
8. **ABOUT & SOURCES** — build version, data source info

---

## 5. COLLECTION PAGE (album / playlist / chart / mix / genre / artist / Liked Songs / Offline Vault)

- Back bar with title
- Artwork, kind label, title, subtitle
- Stats: tracks, total duration, offline count, year
- PLAY ALL button + Shuffle button
- DOWNLOAD ALL + add-all-to-queue + ⋮ options (save as playlist, share link, etc.)
- Liner notes (when present)
- Track list (number, title, artist, duration, tag, ⋮ menu)
- Artist pages only: bio + Similar Artists rail

---

## 6. MY PLAYLIST PAGE

- Back bar with playlist name + ⋮ menu
- Mosaic artwork, "YOUR PLAYLIST", name
- Stats: tracks, duration, updated
- PLAY ALL + Shuffle
- MAKE AVAILABLE OFFLINE + add-all-to-queue
- Track list with drag handles → play now, move up/down, play next, track options, remove
- Empty message when no tracks

---

## 7. NOW PLAYING (full screen)

- Top bar: back, "NOW PLAYING" + source, queue button, ⋮
- Big artwork + PLAYING badge + 8D badge (when on)
- Title, artist, album · year
- Heart (like) + download buttons
- Status line (error / saving offline % / headphone hint)
- 8D module: 8D AUDIO button, CALIBRATE button, orbit info line
- Seek bar with elapsed / total times
- Transport: shuffle, previous, play/pause, next, repeat
- Buttons: LYRICS / QUEUE / SLEEP timer
- Volume slider
- Spectrum analyser (FFT / waveform / off)

---

## Sheets (pop up from bottom)

- **TRACK OPTIONS** (the ⋮ anywhere): resume/play now, play next, add to queue, like, add to playlist, download, go to artist, go to album, share
- **ADD TO PLAYLIST**: new playlist + all playlists
- **IMPORT PLAYLIST**: paste URL, scan, then choose save-as-new / add-to-existing
- **8D CALIBRATION**: orbit speed, room size, rear low-pass, auto 8D, reset
- **QUEUE**: list of queued songs, clear, shuffle, repeat
- **LYRICS**: synced lines (LRCLIB), tap a line to jump
- **SLEEP TIMER**: 5/10/15/30/45/60 min + end of track, cancel
- **PLAYLIST OPTIONS**: rename, download all, delete
- **COLLECTION OPTIONS**: shuffle, add all to queue, download all, save as playlist, share
- **SAVE COLLECTION**: name new playlist or pick an existing one
- **IMPORT BACKUP**: paste .json, restore
- **RENAME PLAYLIST** (dialog): name field, cancel / save
