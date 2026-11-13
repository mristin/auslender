# Auslender

**Auslender** — A satirical, motion-controlled beat ’em up and kickboxing fitness game inspired by the Swiss cult character Müslüm.
Using real-time body-pose estimation, punch, kick and dodge your way through worlds inspired by his songs: battle mammoths and sabre-toothed tigers, evil scientists at the fictional pharma giant Rochartis, Nörgeli, and hordes of Bünzlis and nationalists.
No controllers, minimal locomotion — just your body and your Üsländer power!

See [DESIGN.md](DESIGN.md) for the game design.

**No network access.**
The game runs entirely on your computer and works offline.
The webcam images are processed locally, in memory, and are never saved or sent anywhere.

## Setting up

![The setup seen from above: the laptop on a chair, you 2.5 to 3 m away on your home spot, in a free space of 2 x 2 m](docs/setup_from_above.svg)

* **Put the laptop on a chair or a low table, so that the camera is at about the height of your hips (60 to 100 cm).**
  Do not put it on the floor: the camera would look steeply up at you, and stepping forward or back would move your head up and down in the picture, which confuses the steering.
* **Stand 2.5 to 3 m away from the camera, facing it.**
  The camera must see all of you, from your head to your feet (for the kicks), with some room above your head (for the jumps).
* **Clear a space of about 2 × 2 m around you.**
  The spot where you stand at the start is your home spot: hold still there for a second, and the game remembers it.
* **Step to move.**
  One step towards the camera closes in on the opponent, one step back retreats, and a step to the left or right circles around him.
  Step back onto your home spot to stand still and box.

You need a webcam which supports 640x480.
