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

The fights are **free fights**, as in a beat 'em up: no chart and no notes; both box when they like, until one goes down (`scenes/fight/brawl.gd`). The hero meets the minor opponents on the road of the runs (see [Run]): each charges at him and crashes into him, the run turns into a fight, and after the knock-out it goes on. The boss of a world waits at its end, in a level of his own, to music.
Commanded fights (the rhythm fight, below) were not fun: the players wanted to box freely.

The opponent keeps his guard up, but it is open somewhere, and he moves the opening now and then: his arms wide for a jab, one side of his head bare for a hook from that side, his chin for an uppercut. A punch into the opening lands; any other is blocked and only scratches him. Now and then he attacks: a jab (dodged with the cover, or a slip to either side: in the first free fights, the players slipped the jabs) or a hook from one side (dodged with a slip to the other); a duck dodges both. After his strike he is open for a moment: long, winded, if the player dodged it (a counter hits one and a half times as hard), short, if it landed (he cheers). A player who hides behind his cover gets hooks; one who leans aside all the time gets jabs. A kick (a knee raised high, as the classifier reads it; only in a fight, since running lifts the knees, too) goes to his body, under his guard: it lands whenever he does not wind up or strike, but hurts less (0.6 of a clean punch). A minor opponent goes down after 12 clean punches (about 30 s), a boss after 24 (about a minute); a boss winds up sooner and attacks more often, and throws two in a row now and then.

**The telegraphing is delicate** for the minor opponents: there are no calls, arrows or red glows on the screen. A boss telegraphs his attacks plainly: through his whole wind-up the screen calls the dodge ("COVER!", "SLIP LEFT!", "SLIP RIGHT!") with an arrow from where it comes. In a boss fight, the two circle each other as in a real match: now and then they turn smoothly around the middle between them to another angle, at random (up to about 55° either way), so that the land swings past behind the boss; the view stays the hero's own, and the circling slows down while the boss winds up. The wind-up itself is the tell: he draws the arm back slowly over the whole wind-up and shifts his weight, a faint warm glint creeps over him in its second half, and a soft breath sounds as he starts it; the circle on the camera panel glows in its second half. Since the camera and the classifier see a move late (about a second from a cue to a recognized dodge in the first free fight, which was unplayable with short wind-ups), the wind-ups are long (1.35 s, a boss 1.05 s), a dodge counts from the second half of the wind-up until 0.55 s after the strike, and a punch counts against his guard as it was a moment before the vision saw it.

#### The rhythm fight (dropped)

##### The player's moves

| Move | How the player does it | Effect |
|---|---|---|
| Straight | A fist shoots towards the camera from the guard | Fast; bounces off the opponent's guard, lands when he is open |
| Hook | A fist swings across at chin height | Gets half around the guard |
| Uppercut | A fist rises fast from below the chin | Goes under the guard; staggers |
| Slip left / right | The head and the shoulders lean to one side | Dodges a punch which comes from the other side |
| Duck | A squat: the head drops | Dodges anything high |
| Jump | Both feet off the floor | Dodges a low sweep |
| Cover | Both gloves against the forehead and temples, elbows in | Takes a jab with little damage |

A classifier trained on labelled recordings finds all of these from the body pose on every frame (see [Pose pipeline](#pose-pipeline) and `dev/moves/ml/README.md`). The cover is a distinct gesture, not the plain guard: on the recordings, a player's normal guard already held the fists at the face, so "hands up" could not tell a cover from the guard; covering the head lifts the wrists above the eyes and the elbows above the shoulders, which the pose tells apart clearly.

##### The opponent and the chart

A fight has no jumps and no ducks (they are the runs'): the player punches, slips and covers. His guard shows where the next punch is to land: before a hook he covers one side of his head with one arm, the side of the hook open; before a jab he opens his arms wide; before an uppercut he holds a high guard, his chin open. A wrong move is punished at once: a wrong punch (a jab for a hook, the other hand) or a wrong dodge (a slip the wrong way, a slip for a jab) close to the beat, and the opponent counters with a quick jab, which costs energy and the combo as an attack which landed (at most every 0.6 s, so that a misread of the vision does not cost too much). The opponent bobs to the beat; for every attack note he winds up in the last stretch before its beat and strikes on it, glowing red, while the screen calls the dodge with an arrow from where it comes. A punch which lands snaps his head (aside from a hook, back from a straight, up from an uppercut). He is never still: he bounces on the beat and sways over the bars, steps in as he winds up, slips aside mocking when the player misses, stumbles past when the player dodges, throws up his arms when his attack lands, and beckons the player in during the breathers, with a line now and then.

| Attack | Note | Dodge |
|---|---|---|
| Jab | a purple glove at the face | Cover |
| Hook from the left | a purple glove from the left | Slip right |
| Hook from the right | a purple glove from the right | Slip left |

The song (synthesized in code, 90 BPM, about two and a half minutes) **teaches the moves one by one**: after a count-in, each section brings one move only (jabs, hooks, uppercuts, ducks, jumps, slips, the cover), then a section mixes them, and the final round, too: one a bar, each move twice in a row (in a play-test, every player-move learned alone was met, but a new move in every bar, and two a bar in the final round, were mostly missed). A section has six bars, five with a note and a breather. Every note has a symbol: an arrow of the punch's path (a jab straight at him, a hook sweeping in from the side, an uppercut up) or of the dodge (a slip to the side, a duck down, a jump up, the cover two gloves up). The notes are a bar (2.7 s) apart (in a fight, every second bar has a second note on its third beat) and show two seconds ahead; in the play-tests, a note on every beat, and then on every other beat, was too fast. There are no kicks: the vision saw them too late and too seldom.

Meeting notes in a row builds a **combo**, which multiplies the score. The punches drain the opponent's health so that a player who meets about three quarters of them knocks him out in the final section (he holds on until then); a missed attack hurts the player. The fight ends with a K.O., when the song ends ("TIME"), or when the player goes down, with the score, the accuracy, the best combo and a grade.

Every fight writes a **log** of its events (no pictures), to study how it plays: see `dev/fight/README.md`.

#### Fitness

- The song is the interval: about two minutes of steady work at the pace of the beat, with a breather bar between the sections.
- Difficulty is the chart (how dense the notes, which moves) and the tempo, not only the opponent's health.
- The ducks are squats and the jumps are jumps, so the legs work, too.

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

The hero runs straight ahead into the picture, towards the horizon, as the penguin of Antarctic Adventure: the land rolls towards him to the beat of a song, and the run is a rhythm level as the fights are (the same notes, the same forgiving judging), without an opponent.

- **Running:** the player runs on the spot, and the hero runs as fast as he lifts his knees (the knees lifted a second, as the walk meter counts them: about 1.7 a second is the normal pace, up to one and a half times as fast; he gets up to speed within a fraction of a second, but slows down very gradually, about 12 s from the normal pace to a stop, and not at all while he jumps or ducks, so that he keeps rolling through them). The obstacles stand on the road, and he reaches them at his own pace; his time is the song and some (1.3 times as long, the music looping), as the timer of Antarctic Adventure: he must arrive before it ends, which takes about 0.7 of the normal pace on average; a speedometer shows his pace against it.
- **Left and right:** absolute, as a mouse: where the player's torso is across the camera picture is where the hero is across the wide road (three lanes), continuously; in the middle of the picture, he runs in the middle lane. A glowing strip on the floor ahead of the hero, as wide as his body and all the way to the horizon, shows the path he is heading on. The camera picture never lies over the scene while he plays (it was tried, faintly, with the lanes marked on it, but it got in the way): only the panel in the corner shows it; the camera picture behind the buttons is for the menus. Obstacles (boulders, ice blocks, barriers with cones, snowmen) leave a free gap of their own width anywhere across the road; there is nothing to collect, so that nothing distracts from the obstacles.
- **Opponents:** the minor opponents of the world (four a run, eight before its boss) wait on the road, in the breathers between the sections, each in random colors and a size of his own. Each charges at the hero, weaving across the road from side to side, and homes in on him in the last meters to meet him: there is no way around him. When he reaches the hero, the run turns into a free fight (see [Fight]): the clock of the run holds and the land stops, and after the knock-out the opponent is dragged to the roadside, some of the hero's energy comes back (35), and the run goes on.
- **Jump:** over holes in the road (crevasses on the ice); a jump is a flight of a second and a half up and down, as in Quake, so that it is forgiving. The obstacles stay as they are: the hero ducks under a branch and flies over a hole, and they roll on past him. **Duck:** under branches across the road (in the city, a striped beam); a duck goes way down. The punches count only in a fight.
- **The road:** in the prehistoric runs (the jungle, the glacier, the cave) a dusty path without lanes (a shader of dust, stones and worn tracks); in the city and the suburbs, a road with its dashes.
- **Energy:** an obstacle which the player does not jump, duck or steer around costs energy (as an attack in a fight), breaks the combo and costs the grade; with no energy left he is down. The run is won with a grade of C or better.
- **Fitness:** steps, jumps and squats, the most cardio-heavy scene.
- **Boosters** (`scenes/run/boosters.gd`): things of the land float over the road (one late in every section) and on the platforms; the hero picks one up by running through it. Each works one of four ways: **speed** (he runs 1.4 times as fast for 6 s, however fast his knees go), **health** (25 energy back), **power** (his punches hit twice as hard in the next fight on the road) and **shield** (the obstacles and the platforms do not hurt him for 8 s). The HUD shows what works, with the time left, above the speedometer. Each run has three of its own:

  | Run | Speed | Health | Power | Shield |
  |---|---|---|---|---|
  | Through the jungle | banana | berries | mammoth steak | |
  | Over the glacier | | fish | mammoth steak | fur |
  | Through the streets | espresso | apple | chocolate | |
  | To the Rochartis campus | espresso | | chocolate | helmet |
  | Through the gardens | mandarin | Grittibänz | | scarf |
  | Past the meadow | mandarin | Grittibänz | peanuts in their shells | |

- **Platforms** (`scenes/run/platforms.gd`): in every other section, in a lane at random, raised blocks one level (0.5 m) or two levels high, with gaps: logs in the jungle, ice on the glacier, rock in the cave, crates in the city, a snowy wall of bricks in the suburbs. He need not jump up: running into a platform, he steps up onto it, a level or two, and runs on above the road; a booster floats on each block of the upper level. A gap goes one level down (a notch in the upper level, or down to the road from the lower one) or two (through both levels, down to the road); "JUMP!" is called before it, and a gap jumped over gives points. If he does not jump, he falls through to the level below and goes on there: falling one level does not hurt, falling two at once (or off the side of the upper level) hurts as an obstacle. The road under and around a platform is free of obstacles.
- **Forks** (`scenes/run/forks.gd`): in the other sections, a side road branches off to the left or the right, with a signpost, the edge of the road glowing on its side, and "SHORTCUT!" called with an arrow to it. If he runs all the way to that side (beyond the outer lane) as the fork reaches him, he takes it: a white flash, and he comes out three bars further ahead, past the obstacles and the boosters in between. No fork leads past an opponent.
- **Barriers** (`scenes/run/barriers.gd`): as the car in the bonus stage of the old fighting games, a barrier spans the whole road, and there is no way around, over or under it: as the hero reaches it, the run stops (as for a fight, the clock holds), and he smashes it with his punches and kicks, which knock chunks off it that fly away. A hook hits it on its side (a left hook to his left), a jab or an uppercut straight ahead, a kick on its side. One part of it glows as a target, and the screen calls the punch which hits it ("LEFT HOOK!", "JAB!", "RIGHT HOOK!"): a hit into the target counts twice, and the target moves on. Its bar shows how much is left, and a clock of 15 s counts down: what is left of it when he smashes it is a bonus (50 points a second); after it, no bonus, but he must still smash it. The power booster works on it, too. Two a run, in the spirit of the songs: one in the middle of the fourth section (instead of its fork), one just before the end of the road:

  | Run | Middle | End |
  |---|---|---|
  | Through the jungle | the palisade of the first ones ("WE WERE HERE FIRST!") | the wall of boulders ("OURS!") |
  | Over the glacier | the ice wall ("MAMMOTHS ONLY") | the palisade, frosted |
  | Through the streets | the laundry-room roster ("WASCHPLAN", "NOT YOUR DAY!") | the Bünzli's car ("ORDNUNG MUSS SEIN", a garden gnome on its roof) |
  | To the Rochartis campus | the crates of patents ("PATENTED") | the gate of Rochartis ("AUTHORIZED PERSONNEL ONLY") |
  | Through the gardens | the Thuja hedge ("PRIVAT", garden gnomes on guard) | the Bünzli's car |
  | Past the meadow | the Thuja hedge | the poster of the herd (smug white sheep, "WE STAY AMONG OURSELVES"; the black sheep cheers him on) |

- **Combined obstacles** (`RhythmNote.COMBOS`): in the sections which mix the steering with the jumps or the ducks, most of their jumps and ducks ask for both a way and a move: a fence across the road, low in one part only (go there and jump); a wall with a hole in it (go there and duck); the road split by a post, a beam to duck under on one side and a hurdle to jump on the other (he picks); a hole across the road with a plank over it (run over the plank, or jump anywhere). The way through is marked with warning stripes and a word over it ("JUMP", "DUCK", "RUN"), and the call says what to do with an arrow towards it ("LOW PART: JUMP!", "HOLE: DUCK!", "PLANK OR JUMP!", "DUCK OR JUMP!"). As it reaches him, he must be clear of its blocks and have made the move of his part of it (from a little before its beat on).
- **Climbs** (`scenes/run/climbs.gd`): once a run (in the third section, instead of its platform), the road goes 3 m up over a climb across its whole width, and he climbs it just by running (lifting his knees): up stacked stones, stairs or a slope at a part of his pace (60 %), up a ladder straight up (the road holds, as in a fight, while he climbs as fast as he runs). The view looks up the climb and down it. On the top waits a booster, and the top gives 100 points; down the other side he goes quickly, down the stairs or down a slide (1.8 times his pace, "WHEEE!"). Each land has its own:

  | Run | Climb |
  |---|---|
  | Jungle | boulders stacked into rough steps, moss, vines and ferns, and a slide of mud down |
  | Glacier | a snowy mountain with rocks on its slopes and a banner of hide on its summit (no flags in the ice age), and a slide of ice down |
  | Streets | concrete stairs up to a footbridge ("PASSERELLE") and down |
  | Campus | ladders up the scaffold of the new Rochartis tower ("COMING SOON: MORE PATENTS"), and the chute for the rubble down |
  | Gardens | ladders up a garden shed ("PRIVAT", a gnome on its roof), and a sledge run down |
  | Meadow | a snowy hill with firs, a summit cross and a Swiss flag (with its white cross), and a sledge run down |
- **Curves:** the road curves now and then to the left or the right, gently, and straightens again (every 25 to 45 m). It is only the look, as in Out Run: the shaders bend everything ahead to the side by the square of its distance (`scenes/flat/bend.gdshaderinc`), while the game measures everything on the straight road; the view follows the hero, straight ahead.
- **The code of a run:** `scenes/run/run.gd` runs the road: his pace, the ground under him, the curves, the calls and the judging of the obstacles. `RoadPlan` lays out the road as the run starts (the opponents, the combined obstacles, the platforms, the climb, the forks, the barriers and the boosters); `Encounters` moves the opponents on the road, `Boosts` keeps the boosters which work. While the road holds, the run is in a mode (`scenes/run/modes/`): a `BrawlMode` against an opponent, a `SmashMode` at a barrier, a `LadderMode` up a ladder; each says how he moves, what is called and what his punches do, until it is over. A new kind of stop on the road is a new mode.

### Which signals each scene reads

| Signal | Fight | Race | Sledge | Run |
|---|---|---|---|---|
| Punches (hand boxes) | ✔ | boost | — | — |
| Kicks (pose) | ✔ | — | — | — |
| Lean of the head (sideways offset) | slip | — | — | lane |
| Head down / up | duck, jump | — | — | duck, jump |
| Cover (wrists over the eyes, elbows up) | stops a jab | — | — | — |
| Angle between the hands | — | steer | — | — |
| Hands' sideways position | — | — | steer | — |
| Hands' vertical swing | — | — | speed | — |

Every scene uses at most a handful of signals, and the signals which share the body (e.g., the lean and the duck) are already proven together in the fights.

## Worlds

Each world parodies a facet of Swiss life (or of what came before it), has its hero (one of the three models of the camera panel; the first-person gloves and sleeves are dressed as him), and its surroundings: no ring, but the land itself. A world has two runs through its land, on which the hero meets its minor opponents (four a run, eight before the boss, each in random colors), and ends with its boss, in a level of his own. Every run teaches its obstacles in sections of one each before mixing them (see `scenes/levels/levels.gd`).

| World | Hero | Surroundings | Levels | Satirical target |
|---|---|---|---|---|
| Ice Age | prehistoric | the jungle and the glacier (the runs), the cave (the bear) | the run through the jungle and the run over the glacier, with sabre-tooth tigers (guard open for hooks; jabs and hooks) and mammoths (open for jabs and hooks; jabs); **boss:** the cave bear, in his cave | Prehistoric "we were here first" thinking |
| Switzerland | the classic hero in his yellow suit | the city (the runs), the Rochartis laboratory (the boss) | the run through the streets, with laundry-room Bünzlis (open for jabs and hooks; jabs) and nationalists (hooks and uppercuts; hooks); the run to the Rochartis campus, with Rochartis scientists (uppercuts and jabs; jabs and hooks), a Bünzli and a nationalist; **boss:** the Rochartis CEO | Bünzli conformity, nationalism, big pharma greed (a fictional company) |
| Winter | Samichlaus | the suburbs on a winter's evening | the run through the gardens, with snow-shovel Bünzlis (open for jabs and uppercuts; jabs) and hedge Bünzlis (hooks; jabs and hooks); the run past the meadow, with white sheep (uppercuts and hooks; hooks) and the Bünzlis; **boss:** the Nörgeli | Neighbourly pettiness, the herd which pushes out the one who differs, and grumbling |

The white sheep turns a notorious political poster around (on which white sheep kick out a black one): the player boxes the smug white sheep, and the black sheep cheers him on from the roadside.

Enemy and obstacle design principles:

- Every attack and every obstacle is announced by its note about two seconds ahead, so the player can move with their body in time.
- Each opponent teaches two or three moves before he mixes them.
- Enemies are caricatures of types, not depictions of real people; the animals box upright, as boxers.

## Sessions and saving

The levels are played with the body only: there are no keys in them (but Esc, twice, to leave a level), and no text about keys. The menus take the hands, the mouse and the keys.

As in The Steppe Rescue and Bird Dog: a **session** is a named playthrough, like a save slot (its name is the date and the time by default, so that OK alone is enough), and the player keeps as many as he likes. Each session is one JSON file in `user://saves/`, written whole on every change (to a temporary file, then renamed). Only the best result of every level is stored; a level **opens** once the one before it is won, and any open level can be played again.

The screens: the sessions (continue the last, start a new one, pick another; every session has a Delete button with a bin beneath it, as in Bird Dog, which asks before it deletes), the naming of a new session, the levels of the session (the worlds side by side, each level with a small picture of its land and its opponent, rendered by the game itself; the locked levels dim, the next one crimson, the won ones with their best grade), and the level, whose end offers the next level, the same again, or the levels. The camera picture shows dim and mirrored behind the buttons, so that the player sees where his hands point. A glove is drawn exactly on each hand which the hand detector finds in the picture (smoothed with a 1€ filter); a button glows while a hand or the mouse is over it (a gold rim and a sweeping sheen, a shader), and a hand held on it for three seconds clicks it (as in The Steppe Rescue), and it keeps its button until it goes clearly beyond its edge. A resting hand (below the hips) does not click. The mouse and the keys work, too. Esc goes back; on the first screen Esc twice quits, and in a level Esc twice leaves it.

## Presentation

- **Fights:** the first person, with the gloves in the foreground playing an animation for every move read, and the opponent close in front.
- **Race, sledge, run:** the third person, from behind and above the hero, so that the player sees the road ahead and the hero mirrors their moves.
- **The camera picture:** a panel in the upper left corner (under the health bar; the lower corners are where the hero's arms swing and knees come up), as in Bird Dog: the mirrored webcam picture, the player's body pose drawn on it as a wire, and a circle around the head with the hero's unibrow and mladež (mole). On top of the panel stands, big, the command which the body gives now: a strike for a moment ("LEFT HOOK", in gold), the dodge which counts ("COVER", "SLIP LEFT", "DUCK", "JUMP", in green), else "READY" (nothing going on; not "GUARD", which sounded like a defense next to "COVER"); "STEP IN FRONT" when the camera does not see the player, and "HOLD STILL" while the game sets the home spot (with an arc filling up around the head). The circle glows orange while an attack winds up and turns green while a dodge counts. A full-screen dim mirror, as in Splash 'n' Splat, was tried first, but the body was not visible enough on it. F1 hides the panel.
- **Art style:** flat-shaded, low-poly shapes in strong colours, built in code from boxes and balls; cheap to produce, readable at a glance, and comedic.
- **Audio:** An original soundtrack in a similar spirit (see [Relationship to Müslüm](#relationship-to-müslüm)). **TODO:** the music direction.
- **Language:** Swiss German flavour in dialogue and UI; **TODO:** decide on supported languages (de-CH, de, en, fr, it?).

## Pose pipeline

We reuse the vision of The Steppe Rescue (`scenes/vision/` there): ONNX Runtime on the CPU, in C#, without Godot dependencies except `VisionService`.

- **YOLOX-Body-Head-Hand** (nano, Apache-2.0) finds the head and the hands on **every camera frame** (about 15 ms). The overlay on the face, the wheel and the sledge arms are read from it.
- **YuNet** (MIT) gives the face landmarks: the eyes give the player's unit of length and the height of the head, as in `HeadGauge`.
- **RTMPose-t** (Apache-2.0, top-down) gives the 17 key points of the body on **every camera frame**: it only looks at the box around the player, which it takes from its own pose of the previous frame (`RtmPoseTracker`), in about 13 ms on a 2-core laptop from 2016 (an i7-6600U).
- **RTMO-t** (Apache-2.0) finds the persons in the whole picture, but takes about 70 ms (100 ms next to the face tracker), so it only runs to find the player at the start or when he was lost.
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

1. **Fight prototype.** The fight scene with one opponent: the punches, the slips, the duck, the jump and the cover; as rhythm boxing to a synthesized song, the opponent's attacks as notes to dodge. **Second cut done** (`scenes/fight/`), with RTMPose-t on every frame and the trained move classifier; the first cut (the opponent stepping in and out on his own) played too late for the latency of the vision. Next: play-testing the rhythm fight with its logs, more songs and charts, more recordings (other players, above all children; other days and camera places; more time without moves).
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
