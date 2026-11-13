# Auslender — Design

Status: **draft**. Items marked **TODO** or listed under [Open questions](#open-questions) are not decided yet.

## Vision

A satirical, motion-controlled beat ’em up that doubles as a kickboxing workout.
The player stands in front of a webcam and fights with their whole body — punches, kicks, dodges and blocks — while the game's worlds parody Swiss society through the lens of the cult character Müslüm.

Pillars:

1. **Your body is the controller.** No gamepad, no keyboard during play. A webcam is the only required hardware.
2. **Minimal locomotion.** The player stays roughly on the spot (a living-room footprint of about 2 × 2 m). Enemies come to the player, not the other way round.
3. **A real workout.** A session should leave the player sweaty. Moves map to real kickboxing technique, and the game rewards good form, not just flailing.
4. **Satire with heart.** The humour punches up — at bigotry, pettiness and corporate greed — never at the people who are the target of them.

## Relationship to Müslüm

The game is **independent**. It is inspired by the spirit of Müslüm, but it is neither affiliated with nor endorsed by him or his creator.
We do not use his name in the game, his likeness, his voice or his songs.
The hero, the characters, the music and the lyrics are all our own; the worlds take up themes in the spirit of the songs, not the songs themselves.

## Target platform and tech

- **Engine:** Godot 4 (.NET), as in [The Steppe Rescue](../steppe-rescue): the vision in C#, the game in GDScript.
- **Platforms:** Desktop (Linux, Windows, macOS).
- **Input:** A single webcam supporting 640×480.
- **Vision:** The ONNX models of The Steppe Rescue, on the CPU. See [Pose pipeline](#pose-pipeline).
- **No network access.** The camera images are processed locally, in memory, and are never saved or sent anywhere.

## Core loop

1. Pick a world (one per song-inspired theme).
2. Fight a series of waves; enemies approach from the front, left and right.
3. Hit enemies with the right move at the right time; dodge or block their attacks.
4. Defeat the world's boss.
5. See the post-session summary: score, combos, calories estimate, moves performed.

A wave lasts about 1–2 minutes; a world (several waves + boss) about 10–15 minutes, so that one world is one workout session.

## Moves

Moves are detected from the pose stream. Each move has a detection rule, an in-game effect and a fitness rationale.

| Move | Detection (sketch) | Game effect |
|---|---|---|
| Jab | Lead wrist extends quickly forward/up away from the shoulder | Fast, low-damage hit on the nearest enemy |
| Cross | Rear wrist extends with torso rotation | Stronger hit, short cooldown |
| Hook | Wrist travels in a horizontal arc at shoulder height | Hits enemies to the side |
| Uppercut | Wrist rises sharply from below the chin | Launches small enemies |
| Front kick | Knee lifts, then ankle extends forward | Pushes back an enemy |
| Side / roundhouse kick | Ankle rises laterally above hip height | Area hit on one side |
| Dodge left/right | Head and shoulders shift sideways beyond a threshold | Avoids an incoming attack |
| Duck | Head drops below a calibrated threshold (squat) | Avoids high attacks |
| Block | Both wrists held in front of the face | Reduces damage, charges power |
| **Üsländer power** (special) | **TODO:** a signature pose or sequence | Screen-clearing super move once the power meter is full |

Detection must work from a frontal camera view, so moves along the depth axis (jab, cross, front kick) rely on velocity and apparent limb length rather than true depth.

### Calibration

Before each session the player performs a short calibration: stand in a neutral guard, raise arms, squat once. This gives body proportions, a neutral head height and the play area, and is used to normalise all thresholds.

### Fitness

- Difficulty adapts the pace (attacks per minute) rather than only enemy health.
- Each world mixes upper-body, lower-body and cardio-heavy (dodge/duck) segments.
- Warm-up and cool-down segments are part of every world.
- Calorie estimates are rough and clearly labelled as estimates.

## Worlds

Each world is inspired by Müslüm's songs and parodies a facet of Swiss life. **TODO:** map each world to a specific song and its music/visual cues.

| World | Enemies | Boss | Satirical target |
|---|---|---|---|
| Ice Age | Mammoths, sabre-toothed tigers | **TODO** | Prehistoric "we were here first" thinking |
| Rochartis | Lab assistants, test-tube minions, evil scientists | **TODO:** the CEO | Big pharma greed (fictional company) |
| Nörgeli | Nörgeli (grumblers) and complainers | **TODO** | Petty grumbling and nitpicking |
| Bünzli-Land | Hordes of Bünzlis: rule-obsessed neighbours, laundry-room schedule keepers | **TODO** | Bünzli conformity and pettiness |
| Nationalists | Flag-waving nationalists | **TODO** | Xenophobia and nationalism |

Enemy design principles:

- Every enemy type telegraphs its attack clearly (wind-up animation + sound) so the player can react with their body in time — at least about 600 ms before impact at normal difficulty.
- Each enemy type teaches or tests one or two moves (e.g., mammoths charge → dodge; tigers pounce high → duck).
- Enemies are caricatures, not depictions of real people.

## Presentation

- **Camera view:** **TODO:** decide between a third-person view with a stylised avatar of the player or a first-person view with fists/feet in the foreground. A small webcam silhouette in a corner helps the player trust the tracking.
- **Art style:** **TODO.** Something cheap to produce and comedic, e.g., flat cut-out / collage style.
- **Audio:** An original soundtrack in a similar spirit (see [Relationship to Müslüm](#relationship-to-müslüm)). **TODO:** the music direction.
- **Language:** Swiss German flavour in dialogue and UI; **TODO:** decide on supported languages (de-CH, de, en, fr, it?).

## Pose pipeline

We reuse the vision of The Steppe Rescue (`scenes/vision/` there): ONNX Runtime on the CPU, in C#, without Godot dependencies except `VisionService`.

- **YOLOX-Body-Head-Hand** (nano, Apache-2.0) finds the head and the hands on **every camera frame**. The fast moves (punches, guard, slips, ducks) are read from it.
- **YuNet** (MIT) gives the face landmarks: the eyes give the player's unit of length and the height of the head, as in `HeadGauge`.
- **RTMO-t** (Apache-2.0) gives the 17 key points of the body, but only 4 to 20 times a second on a modest laptop (`PoseScheduler`). It tells the left hand from the right (`HandTracker`) and sees the hips, knees and ankles, which the kicks need; it is too slow to time a fast move frame by frame.

Consequences for the design:

- Punches, the guard, slips and ducks must be readable from the head and the hands alone.
- Kicks come from the slow pose, so they get a generous timing window, and the whole body must be in the picture (the player stands farther from the camera, about 3 m).
- The size of a hand's box grows as the fist comes towards the camera, which gives us the depth of a straight punch that the 2D position alone does not.

Architecture sketch:

```
Webcam → head & hands (every frame) + pose (slower) → HandTracker, HeadGauge, 1€ filters
       → Move recognizers (one state machine per move) → game events (Jab, Slip, Duck, …)
       → Gameplay (GDScript)
```

The recognizers are plain C# classes, unit-tested on recordings of real players replayed in the tests, as `SquatMeter` and `Reins` are in The Steppe Rescue.

## Safety and accessibility

- Show a clear-space check at the start (the whole body must be visible and the area free).
- Warm-up before intense segments; pause automatically when the player leaves the frame.
- Seated mode with upper-body moves only.
- Difficulty and intensity settings independent of each other.
- Colour-blind-safe UI and subtitles for all dialogue.

## Scope of the first milestone (prototype)

1. Webcam + pose pipeline running in Godot, showing the skeleton overlay.
2. Calibration flow.
3. Recognition of jab, cross, dodge left/right and duck.
4. A single test arena with one enemy type that attacks and can be hit.
5. Recording and replaying landmark streams for tests.

## Open questions

- What is the hero called, and what does he look like (our own character, not Müslüm)?
- Which themes in the spirit of the songs map to which worlds?
- Boxing (one opponent) or beat ’em up (a street), and how does the player move in a beat ’em up?
- Third-person avatar or first-person view?
- Single-player only, or local co-op / versus later?
- Business model: free / open source (the repository is MIT-licensed), paid, or donation-based? How are assets licensed?
