# Auslender — Design

Status: **draft**. Items marked **TODO** or listed under [Open questions](#open-questions) are not decided yet.

## Vision

A satirical, motion-controlled action game that doubles as a workout.
The player stands in front of a webcam and plays with their whole body: they box their way through fights, steer a car with an invisible steering wheel, push a sledge down the mountain with their arms, and run, dodge, jump and duck through obstacle courses — while the game's worlds parody Swiss society through the lens of the cult character Müslüm.

The game is a sequence of short, different **scenes**, as in a party game or a road movie: a race takes the hero to the next town, a fight waits there, a sledge ride takes them down to the valley, and so on.
Each scene type uses the body differently, so a session works the whole body, and no scene lasts long enough to get boring or exhausting.

Pillars:

1. **Your body is the controller.** No gamepad, no keyboard during play. A webcam is the only required hardware.
2. **Stay on your spot.** The player never walks around the room. Every move happens on the spot: punches, leans, ducks, jumps, arm swings. The game moves; the player does not.
3. **One idea per scene.** Each scene type has one simple, physical metaphor (a steering wheel, sledge poles, a dodge) which a player understands in five seconds without a tutorial.
4. **A real workout.** A session should leave the player sweaty. The moves map to real exercises (boxing, squats, jumps, arm work), and the game rewards good form, not just flailing.
5. **Satire with heart.** The humour punches up — at bigotry, pettiness and corporate greed — never at the people who are the target of them.

### What we dropped, and why

The first prototype was a boxing ring in which the player moved by stepping around the room (the "room as a joystick") or by walking in place and turning the body.
Neither steered well: a step is slow and imprecise as a control, the camera confuses a step forward with a lean, and the player loses the sense of where their home spot is.
We drop locomotion in the room altogether (pillar 2): in the fights, the opponent comes to the player; in the other scenes, the vehicle moves and the player steers it with the upper body.

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

## Structure

```
World (one theme, one workout session of 10–15 minutes)
 └─ Stage 1: Race     → Fight
 └─ Stage 2: Sledge   → Fight
 └─ Stage 3: Run      → Fight
 └─ Finale:  Boss fight
```

- A **world** is a short journey with one satirical theme (see [Worlds](#worlds)), e.g., the hero races to the Rochartis campus, fights the lab assistants at the gate, sledges down the cooling pipes, runs through the corridors and fights the CEO.
- A **stage** is a travel scene (race, sledge or run, about 1–2 minutes) followed by a fight (about 1–2 minutes).
- The **travel scenes** are the cardio and the breather in one: they keep the heart rate up but give the arms and the legs something different to do than the fights.
- The **fights** are the heart of the game and the most intense part.
- Each world starts with a warm-up (the calibration and an easy first scene) and ends with a cool-down (the post-session summary: score, the moves performed and a rough, clearly labelled calorie estimate).

Between the scenes, a short comic-strip panel tells the story in one or two lines, so that the player can catch their breath.

## Calibration

Every scene relies on the same **home pose**: the player stands on their spot, facing the camera.
At the start of a session (and whenever the player comes back into the picture), they hold still for about one second; the game remembers where the head is and how big it looks.
All the thresholds are then relative to the player: the leans in shoulder widths, the duck and the jump in head heights, the hands in head widths. So it does not matter how tall the player is or how far from the camera they stand.

The home spot slowly follows the player while they stand still, so that a player who drifts half a step does not end up leaning all the time. **TODO:** validate this with recordings.

## Scene types

### Fight

The player boxes against one opponent, in the first person: the opponent stands in front of the camera, and the player's red gloves are in the foreground.
The player stays on their spot; the **opponent** moves: he steps in to attack and steps back out.

#### The player's moves

| Move | How the player does it | Effect |
|---|---|---|
| Straight | A fist shoots towards the camera from the guard | Fast; bounces off the opponent's guard, lands when he is open |
| Hook | A fist swings across at chin height | Gets half around the guard |
| Uppercut | A fist rises fast from below the chin | Goes under the guard; staggers |
| Kick | A knee comes up high (the camera need not see the whole leg, so a kick is a knee raise) | Reaches farther than the punches; pushes the opponent back |
| Slip left / right | The head and the shoulders lean to one side | Dodges a punch which comes from the other side |
| Duck | A squat: the head drops | Dodges anything high |
| Jump | Both feet off the floor | Dodges a low sweep |
| Cover | Both gloves against the forehead and temples, elbows in | Takes a jab with little damage |

A classifier trained on labelled recordings finds all of these from the body pose on every frame (see [Pose pipeline](#pose-pipeline) and `dev/moves/ml/README.md`). The cover is a distinct gesture, not the plain guard: on the recordings, a player's normal guard already held the fists at the face, so "hands up" could not tell a block from the guard; covering the head lifts the wrists above the eyes and the elbows above the shoulders, which the pose tells apart clearly.

#### The opponent

The opponent alternates between two distances:

- **Out** (about 2.2 m): only the player's kicks reach him. He taunts, bounces, and walks in after a few seconds.
- **In** (about 1.3 m): the punches reach him. He guards his face, attacks once or a few times, and steps back out, or is driven out by a kick.

Each attack is **telegraphed**: a wind-up of about 0.9 s at normal difficulty (never less than about 0.6 s), during which he glows red and an arrow on the screen shows where it comes from.

| Attack | Telegraph | Dodge | Also works |
|---|---|---|---|
| Jab | Pulls the lead hand back, straight at the camera | Cover | Slip either way, duck |
| Hook from the left | Swings his right arm wide (on the player's left) | Slip right | Duck |
| Hook from the right | Swings his left arm wide (on the player's right) | Slip left | Duck |
| Sweep | Lifts his leg back low | Jump | — |

After each attack, hit or miss, he stands **open** for a moment: punches land harder then.
A dodged attack opens him even longer, so the rhythm the game teaches is **dodge, then counter**: the core of boxing.

As the fight goes on, he attacks more often, chains two attacks, and shortens the open window; each opponent type has its own mix of attacks (see [Worlds](#worlds)).

#### Fitness

- The fights are intervals: about 20–40 s of attacks, a short breather while the opponent taunts or the round changes.
- Difficulty adapts the pace (attacks per minute, wind-up length) rather than only the opponent's health.
- The ducks are squats and the kicks are knee raises, so the legs work as much as the arms.

### Race

The player drives a car in the third person, on a road which winds towards the horizon, against a handful of rivals.

- **Steering:** the player holds both fists in front of their chest, as if gripping a steering wheel, and turns it: the angle of the line between the two hands is the angle of the wheel. Nothing else is needed; the metaphor is instantly clear (as in "El Volante Virtual").
- **Speed:** the car accelerates by itself. Both fists pushed forward towards the camera give a short boost (nitro), which recharges; pulling the hands back to the chest brakes.
- **Obstacles and rivals:** traffic, roadworks, a Bünzli strictly at the speed limit in the fast lane, cows on the road; bumping into them slows the car.
- **What the vision needs:** both hands, on every frame (the YOLOX hand boxes, told left from right by the pose), and the size of the boxes for the boost. The hands are not near the face here, so the wheel does not interfere with the head.
- **Fitness:** the arms are held up the whole time (shoulders), and the boost is a double punch.

### Sledge

The player rides a sledge down a snowy slope in the third person, from behind.

- **Speed:** the player swings both arms up and down, as if pushing off with poles or paddling; the faster and the bigger they swing, the faster the sledge goes. Without swinging, it slows down to a crawl.
- **Steering:** the player moves both hands to one side, as if pushing off the snow on that side: the sledge goes to the **opposite** side. Hands to the left, sledge to the right.
- **Obstacles:** trees, rocks, snowmen, other sledgers; gates and flags to pass through for points.
- **What the vision needs:** both hands, on every frame: their vertical speed (the swing) and their average sideways position against the shoulders (the steering).
- **Fitness:** a sustained arm and shoulder workout, like rowing; the speed reward makes the player push.

### Run

The hero runs straight ahead into the picture, towards the horizon, on a course with ice holes, fences, low bars and crevasses (in the genre of the classic penguin-on-the-ice games).

- **Running:** the hero runs by himself. **TODO:** decide whether jogging in place speeds him up (the walk meter of the first prototype measures the cadence), or whether the pace is set by the game.
- **Left and right:** the player leans their upper body (or takes half a step) to one side; the hero switches between three lanes. Leaning is the same signal as the slip in the fights.
- **Jump:** over holes and low fences.
- **Duck:** under bars and swinging signs.
- **Pickups:** fish, coins or the world's equivalent, placed so that collecting them asks for one more jump or lean.
- **Fitness:** jumps and squats, the most cardio-heavy scene; the runs are therefore the shortest.

### Which signals each scene reads

| Signal | Fight | Race | Sledge | Run |
|---|---|---|---|---|
| Punches (hand boxes) | ✔ | boost | — | — |
| Kicks (pose) | ✔ | — | — | — |
| Lean of the head (sideways offset) | slip | — | — | lane |
| Head down / up | duck, jump | — | — | duck, jump |
| Cover (wrists over the eyes, elbows up) | block | — | — | — |
| Angle between the hands | — | steer | — | — |
| Hands' sideways position | — | — | steer | — |
| Hands' vertical swing | — | — | speed | — |

Every scene uses at most a handful of signals, and the signals which share the body (e.g., the lean and the duck) are already proven together in the fights.

## Worlds

Each world is inspired by Müslüm's songs and parodies a facet of Swiss life. **TODO:** map each world to a specific song and its music/visual cues.

| World | Travel scenes | Fight opponents | Boss | Satirical target |
|---|---|---|---|---|
| Ice Age | Sledge down the glacier, run over the ice | Mammoths (charge: jump, sweep), sabre-toothed tigers (swipes: slip) | **TODO** | Prehistoric "we were here first" thinking |
| Rochartis | Race to the campus, run through the corridors | Lab assistants, test-tube minions, evil scientists | **TODO:** the CEO | Big pharma greed (fictional company) |
| Nörgeli | Race through the village, sledge to the valley | Nörgeli (grumblers) and complainers | **TODO** | Petty grumbling and nitpicking |
| Bünzli-Land | Race against Bünzlis at exactly the speed limit, run past laundry-room schedules | Rule-obsessed neighbours, laundry-room schedule keepers | **TODO** | Bünzli conformity and pettiness |
| Nationalists | **TODO** | Flag-waving nationalists | **TODO** | Xenophobia and nationalism |

Enemy and obstacle design principles:

- Every attack and every obstacle is telegraphed clearly (a wind-up, a sound, or simply enough distance), so the player can react with their body in time: at least about 600 ms at normal difficulty.
- Each opponent type teaches or tests one or two moves (e.g., mammoths charge low → jump; tigers swipe → slip).
- Enemies are caricatures, not depictions of real people.

## Presentation

- **Fights:** the first person, with the gloves in the foreground following the player's hands, and the opponent close in front.
- **Race, sledge, run:** the third person, from behind and above the hero, so that the player sees the road ahead and the hero mirrors their moves.
- **The camera picture:** the webcam shows dimly over the whole game like a mirror, as in Splash 'n' Splat, and nowhere else: no separate camera window, no body gauge. A glowing circle sits around the player's head, with the hero's unibrow and mladež (mole) on the face; it glows orange while an attack winds up, turns green while a dodge counts (with its name, e.g., "SLIP LEFT", under it), and fills up with an arc while the game sets the home spot. So the player reads everything about their body from their own reflection.
- **Art style:** flat-shaded, low-poly shapes in strong colours, built in code from boxes and balls; cheap to produce, readable at a glance, and comedic.
- **Audio:** An original soundtrack in a similar spirit (see [Relationship to Müslüm](#relationship-to-müslüm)). **TODO:** the music direction.
- **Language:** Swiss German flavour in dialogue and UI; **TODO:** decide on supported languages (de-CH, de, en, fr, it?).

## Pose pipeline

We reuse the vision of The Steppe Rescue (`scenes/vision/` there): ONNX Runtime on the CPU, in C#, without Godot dependencies except `VisionService`.

- **YOLOX-Body-Head-Hand** (nano, Apache-2.0) finds the head and the hands on **every camera frame** (about 15 ms). The overlay on the face, the wheel and the sledge arms are read from it.
- **YuNet** (MIT) gives the face landmarks: the eyes give the player's unit of length and the height of the head, as in `HeadGauge`.
- **RTMPose-t** (Apache-2.0, top-down) gives the 17 key points of the body on **every camera frame**: it only looks at the box around the player, which it takes from its own pose of the previous frame (`RtmPoseTracker`), in about 13 ms on a 2-core laptop from 2016 (an i7-6600U).
- **RTMO-t** (Apache-2.0) finds the persons in the whole picture, but takes about 70 ms (100 ms next to the face tracker), so it only runs to find the player at the start or when she was lost.
- **The move classifier** (XGBoost, evaluated in plain C#, `MoveClassifier`) reads the last 4 poses, 0.1 s apart, normalised by the torso length (so it is scale invariant, for children and adults alike), and gives the punches by type and side, the knees, the ducks, the jumps, the slips and the cover. It takes less than 0.1 ms. See `dev/moves/ml/README.md` for the training and the evaluation.

Consequences for the design:

- The whole body must be in the picture (the player stands about 2.5–3 m from the camera), since the classifier reads the knees, too (a kick is a knee raised high).
- A camera low on the floor worked best on the recordings: it sees the punches rise towards it. The thresholds on the head alone (the duck and the jump against the home spot) are fooled by where the camera stands; the classifier, on the whole body, is not.
- The size of a hand's box grows as the fist comes towards the camera, which gives us the depth of a straight punch (and of the boost in the race) that the 2D position alone does not.

Architecture sketch:

```
Webcam → head & hands (every frame) + pose (every frame, RTMPose-t; RTMO to find the player) → HandTracker, HeadGauge, 1€ filters
       → Recognizers (the move classifier for the fights; the wheel, the sledge arms, …)
       → game events and continuous values
       → Scenes (GDScript): Fight, Race, Sledge, Run
```

The recognizers are plain C# classes, unit-tested on recordings of real players replayed in the tests.
To find their rules, we record what the vision measures while a player follows a plan of moves (`dev/moves/`), and replay videos through the vision offline (`dev/replay/`).

## Safety and accessibility

- Show a clear-space check at the start (the whole body must be visible and the area free).
- Warm-up before intense scenes; pause automatically when the player leaves the picture.
- Seated mode: the race and the sledge work seated as they are; the fights without kicks, jumps and ducks; the run is skipped.
- Difficulty and intensity settings independent of each other.
- Colour-blind-safe UI (the attack arrows use shape and position, not only colour) and subtitles for all dialogue.

## Milestones

1. **Fight prototype.** The fight scene with one opponent: the punches and the kicks, the slips, the duck, the jump and the block; the opponent stepping in and out, telegraphing his four attacks. Keyboard controls to play without a camera. **First cut done** (`scenes/fight/`), with RTMPose-t on every frame and the trained move classifier; next: more recordings (other players, above all children; other days and camera places; more time without moves), and play-testing the fight.
2. **Race prototype.** The virtual steering wheel on a simple winding road.
3. **Sledge prototype.** The arm swing and the side push on a slope.
4. **Run prototype.** Lanes, jumps and ducks on a straight course.
5. **One world end to end.** The scene flow (race → fight → sledge → fight → run → boss), the story panels and the summary.

## Open questions

- What is the hero called, and what does he look like (our own character, not Müslüm)?
- Which themes in the spirit of the songs map to which worlds?
- Does the run need running in place for its speed, or is leaning, jumping and ducking enough?
- In the race, is the boost (both fists forward) reliable enough next to the steering, or should the car only steer?
- Single-player only, or local co-op / versus later (e.g., two players racing side by side in one camera picture)?
- Business model: free / open source (the repository is MIT-licensed), paid, or donation-based? How are assets licensed?
