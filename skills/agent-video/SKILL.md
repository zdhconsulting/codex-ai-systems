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
- Put subtitles under the video in the lower black area.
- Use large, bold, comic-caption-style subtitles.
- Use bright neon green subtitles unless Zev asks for another color.
- Make the first read of the frame: logo on top, comedy clip in the middle, punchy subtitles below.

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
   - Reserve the lower black area for subtitles.

3. Subtitles
   - Generate subtitles from the actual clip source when VEED offers source choices.
   - If "Full project" transcription fails, retry with the uploaded clip source.
   - Keep speaker detection off unless it is available without an upgrade.
   - Use one subtitle color for the whole video unless Zev explicitly asks otherwise.

4. Subtitle Cleanup
   - Remove all periods.
   - Capitalize the first letter of every subtitle block.
   - Keep question marks, commas, apostrophes, and useful comedic punctuation.
   - Fix obvious transcript errors only when they hurt comprehension or the punchline.
   - Preserve joke rhythm over literal transcript cleanup.

5. Style
   - Use bright neon green by default.
   - Use large, bold, comic-caption-style text.
   - Place subtitles below the video in the lower black area.
   - Keep subtitles readable on mobile and clear of faces, the logo, and key action.

6. Verification
   - Verify subtitle block count before and after cleanup.
   - Verify zero periods.
   - Verify zero lowercase-starting subtitle blocks.
   - Verify the logo starts at 00:00.0 and ends at the final project duration.
   - Verify the project duration matches Zev's intended cut.
   - Visually check the start, middle, and end of the reel before final handoff.

## Subtitle Text Rules

- Start every subtitle line with a capital letter.
- Remove all periods from subtitles.
- Keep question marks, commas, apostrophes, and useful comedic punctuation unless Zev asks otherwise.
- Keep lines short and scannable for Instagram.
- Preserve joke rhythm over transcript literalism.
- Fix obvious AI transcript mistakes when they hurt comprehension or the punchline.

## VEED Safety Rules

- Do not bulk paste a full subtitle transcript into VEED's subtitle editor; it can collapse many subtitle blocks into one timed subtitle frame.
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
- Confirm video is centered and not cropped awkwardly.
- Confirm subtitles sit below the video, not over faces or the logo.
- Confirm subtitles are bold, high contrast, and readable on mobile.
- Confirm no editor UI artifacts are part of the export.
- Confirm final timeline matches Zev's intended cut length.

## Final QA Report

At handoff, report:

- Duration: `MM:SS.s`
- Subtitle blocks: `N`
- Periods: `0`
- Lowercase starts: `0`
- Logo: full duration or issue noted
- Canvas: 9:16 black or issue noted
- Subtitle style: color, approximate size/font, and placement
- Status: ready for Zev review, or exact blocker

## Conduct

- Treat Zev's approved video as the house style.
- Prefer simple VEED workflows Zev can understand and repeat.
- Avoid paid-plan features unless Zev approves the cost.
- Use one subtitle color for the full video unless speaker coloring is available without an upgrade.
- If VEED behaves unpredictably, stop after the smallest test edit, repair any test damage, then continue only with a verified safer method.
- When the project is already close to perfect, make minimal edits and verify carefully.
- Keep the system improving: when Zev approves a new style decision, add it to the project rules and this reusable skill.
