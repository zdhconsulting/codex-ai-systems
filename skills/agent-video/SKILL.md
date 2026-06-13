---
name: agent-video
description: Conduct English Comedy TLV-style VEED Instagram Reel video edits. Use when Zev asks Agent Video to create, inspect, polish, subtitle, format, export, or conduct short comedy/interview clips for Instagram Reels, especially old comedy clips with a black 9:16 frame, English Comedy TLV logo, centered source video, and bold bright subtitles.
---

# Agent Video

Use this skill to conduct VEED edits in Zev's English Comedy TLV house style.

## Target Format

- Set the project to Instagram Reel, vertical 9:16.
- Use a solid black background.
- Place the source clip in the middle of the vertical frame.
- Place the English Comedy TLV logo centered at the top in the black area.
- Keep the logo fully in the top black band. It must not touch, cover, or overlap the source video.
- Put subtitles under the video in the lower black area.
- Keep subtitles below the video. They must not sit on top of the source video unless Zev explicitly asks.
- Use large, bold, comic-caption-style subtitles.
- Use `72px` subtitle size by default when using Komika Axis; `60px` is still too small for this font.
- Use bright neon green subtitles unless Zev asks for another color.
- Use a comic-style font such as Komika Axis or the closest VEED equivalent.
- Do not use cursor, karaoke, active-word, or moving highlight subtitle effects.
- Never use periods in subtitle text.
- Make the first read of the frame: logo on top, comedy clip in the middle, punchy subtitles below.

## Approved Reference Geometry

Use Zev's approved export `C:\Users\2026\Downloads\English Comedy TLV_s Video - Jun 12, 2026.mp4` as the source of truth for the current house style.

- Canvas: `720x1280`, black, `9:16`.
- Logo: centered near the top, about `153x147px`, from roughly `y=40` to `y=186`.
- Video: full-width middle strip, starting around `y=237`.
- Logo/video gap: visible black gap required. Approved reference is about `50px`.
- Subtitles: neon green, centered below the video, around `y=891-940`.
- Hard fail: logo touching video, logo overlaying video, subtitles overlaying video, or two visible subtitle sources.

## Always-On Launch Protocol

Run this auto setup at the start of every Agent Video launch before handoff:

1. Load this skill and treat it as the checklist for the session.
2. Confirm the project is a 9:16 Instagram Reel with a black background.
3. Confirm the video stays in Zev's chosen placement unless he explicitly asks to move it.
4. Confirm the English Comedy TLV logo is centered at the top and spans the full video.
5. Confirm the logo is entirely above the video with visible black space between them.
6. Confirm subtitles are below the video, `72px` for Komika Axis, large, bold, comic-style, neon green, and have no cursor or active-word effect.
7. Confirm there is exactly one visible subtitle source.
8. Run subtitle text QA twice:
   - First pass before cleanup: count subtitle blocks, periods, and lowercase starts.
   - Second pass after cleanup/style changes: confirm block count is stable, periods are `0`, and lowercase starts are `0`.
9. Visually check start, middle, and end frames before saying the video is ready.
10. If any rule fails, fix it before handoff or report the exact blocker.

## Production Pipeline

1. Intake
   - Identify the source clip, VEED project link, and total duration.
   - Confirm whether Zev wants the full clip or a trimmed joke segment.
   - Check whether the clip has dialogue worth subtitling.
   - Note any owner-only actions, such as uploads, login prompts, billing prompts, or export/download buttons.

2. Layout
   - Set or verify a 9:16 black canvas.
   - Center the source video in the middle of the vertical frame.
   - Keep faces and action visible; do not crop awkwardly.
   - Add the English Comedy TLV logo at the top center for the full project duration.
   - Keep a visible black gap between the logo and source video.
   - Fail QA if the logo overlaps or touches the source video.
   - Reserve the lower black area for subtitles.

3. Subtitles
   - Generate subtitles from the actual clip source when VEED offers source choices.
   - If "Full project" transcription fails, retry with the uploaded clip source.
   - Keep speaker detection off unless it is available without an upgrade.
   - Use one subtitle color for the whole video unless Zev explicitly asks otherwise.
   - Use exactly one visible subtitle source. Delete duplicate subtitle layers or burned-in duplicates before handoff.

4. Subtitle Cleanup
   - Remove all periods.
   - Capitalize the first letter of every subtitle block.
   - Keep question marks, commas, apostrophes, and useful comedic punctuation.
   - Fix obvious transcript errors only when they hurt comprehension or the punchline.
   - Preserve joke rhythm over literal transcript cleanup.

5. Style
   - Use bright neon green by default.
   - Use large, bold, comic-caption-style text.
   - Set subtitle size to `72px` by default when using Komika Axis.
   - Use Komika Axis or the closest comic-style VEED font available.
   - Disable cursor, karaoke, active-word, and moving highlight effects.
   - Place subtitles below the video in the lower black area.
   - Keep subtitles readable on mobile and clear of faces, the logo, and key action.

6. Verification
   - Run the auto setup checklist for every launch.
   - Verify subtitle block count before and after cleanup.
   - Verify zero periods.
   - Verify zero lowercase-starting subtitle blocks.
   - Re-check zero periods and zero lowercase starts a second time after all style/layout edits.
   - Verify the logo starts at 00:00.0 and ends at the final project duration.
   - Verify the logo is entirely above the video with a visible black gap.
   - Verify there is exactly one visible subtitle source.
   - Verify the project duration matches Zev's intended cut.
   - Visually check the start, middle, and end of the reel before final handoff.

## Subtitle Text Rules

- Hard rule: subtitles must contain zero periods.
- Start every subtitle line with a capital letter.
- Remove all periods from subtitles.
- Keep question marks, commas, apostrophes, and useful comedic punctuation unless Zev asks otherwise.
- Keep lines short and scannable for Instagram.
- Preserve joke rhythm over transcript literalism.
- Fix obvious AI transcript mistakes when they hurt comprehension or the punchline.

## VEED Safety Rules

- Do not bulk paste a full subtitle transcript into VEED's subtitle editor; it can collapse many subtitle blocks into one timed subtitle frame.
- Prefer VEED's generated timing or a cleaned imported SRT over manually recreated subtitles.
- For period removal at scale, export/download the SRT, remove periods in text only while preserving timestamps, then import the cleaned SRT back into VEED.
- Preserve subtitle timing unless Zev explicitly asks to retime.
- Edit subtitle text one block at a time.
- Before broad subtitle edits, test one subtitle block and verify:
  - The subtitle block count stays the same.
  - The edited block changed exactly as intended.
  - No subtitle text was duplicated or deleted.
- For capitalization cleanup, replace only the first character of each affected subtitle block.
- After subtitle edits, verify:
  - No subtitle block starts with lowercase.
  - No periods remain.
  - Subtitle block count is stable.

## Visual QA

- Confirm canvas is 9:16.
- Confirm background is black.
- Confirm logo is visible, centered, and not too large.
- Confirm logo sits only in the top black band and does not overlap or touch the video.
- Confirm video is centered and not cropped awkwardly.
- Confirm subtitles sit below the video, not over faces or the logo.
- Confirm there is exactly one visible subtitle source.
- Confirm subtitles are bold, high contrast, and readable on mobile.
- Confirm subtitles do not use cursor, karaoke, active-word, or moving highlight effects.
- Confirm no editor UI artifacts are part of the export.
- Confirm final timeline matches Zev's intended cut length.

## Final QA Report

At handoff, report:

- Duration: `MM:SS.s`
- Subtitle blocks: `N`
- Periods: `0`
- Lowercase starts: `0`
- Logo: full duration or issue noted
- Logo/video gap: confirmed or issue noted
- Canvas: 9:16 black or issue noted
- Subtitle style: color, approximate size/font, and placement
- Subtitle source count: one visible source confirmed or issue noted
- Status: ready for Zev review, or exact blocker

## Conduct

- Treat Zev's approved video as the house style.
- Prefer simple VEED workflows Zev can understand and repeat.
- Avoid paid-plan features unless Zev approves the cost.
- Use one subtitle color for the full video unless speaker coloring is available without an upgrade.
- If VEED behaves unpredictably, stop after the smallest test edit, repair any test damage, then continue only with a verified safer method.
- When the project is already close to perfect, make minimal edits and verify carefully.
- Keep the system improving: when Zev approves a new style decision, add it to the project rules and this reusable skill.
