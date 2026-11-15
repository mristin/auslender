# Fight logs

Every start of the fight scene writes a log of what happened in it (see
`scenes/fight/fight_log.gd`): one JSON object per line, with the event and the
seconds of real time since the start (`t`); `song` is the time in the song.
It holds only game events, never pictures:

| Event | When | Fields |
|---|---|---|
| `scene` | the scene starts | the input (`camera`, `replay` or `keyboard`), the hero, the tempo |
| `fight_start`, `song_start` | a fight starts, its song starts (after the player was seen) | the notes, the punches among them |
| `section` | a section is announced (a bar ahead) | its number and title |
| `move` | the player throws a punch or a kick | the kind, the side, the source (`vision` or `keyboard`), the latency used, whether it met a note, and then the note, how far off its beat it was (`offset`, after the latency) and the result (`perfect`, `good`) |
| `note` | a punch note is missed, or an attack is judged | the kind, the side, the beat, the result (`miss`; `dodged` or `hit`), the dodge which counted, and when the player was last in each dodge (`poses`) |
| `dodge_move` | the classifier finds a slip, a duck or a jump | the kind, the side |
| `pose` | the dodge which counts changes | the pose, the one before |
| `pause`, `resume` | the camera lost and found the player | |
| `state` | every second | the phase, the player's and the opponent's health, the score, the combo, the latency learned, the lean and the pose, whether the camera sees the player |
| `brawl_start`, `brawl_end` | a free fight starts (the hero crashed into an opponent of a run, or a boss level started), and ends after the knock-out | the opponent |
| `punch` | the player throws a punch in a free fight | the kind, the side, the clock of the fight, how it went (`landed`, `counter`, `blocked`) |
| `attack`, `attack_end` | the opponent winds up an attack, and it is judged | the attack, its wind-up; the result (`dodged`, `hit`), whether the player covered |
| `knock_out` | an opponent goes down | the opponent |
| `run_on` | a run goes on after a fight | |
| `fight_end` | the fight ends | why (`knock_out`, `time`, `down`, `restarted`), the score, the grade, the accuracy, the counts, the best combo, the latency, the health |

The logs are in `~/.local/share/godot/app_userdata/Auslender/fight_logs/` on
Linux. Summarize the latest (or the given ones) with:

```
python3 dev/fight/summarize_log.py [<fight.jsonl> ...]
```
