# Auslender

**Auslender** — A satirical, motion-controlled action and fitness game about Swiss society.
It is an original game: its hero, its worlds, its opponents and its music are our own, and it neither uses nor imitates any existing character, nor is it affiliated with or endorsed by any artist.
Using real-time body-pose estimation, you run and box your way through three worlds of our own: the Ice Age, Switzerland and a Swiss winter.
You run as fast as you lift your knees, and steer by leaning; you jump over holes and fallen trees, duck under branches, climb ladders, and smash barriers with your punches and kicks.
On the road, you box sabre-toothed tigers and mammoths, Bünzlis and nationalists, white sheep and the scientists of the fictional pharma giant Rochartis, until you face the boss of each world: the cave bear, the Rochartis CEO and the Nörgeli.
No controllers, no walking around — just your body on one spot!

![Playing Auslender: running through the jungle and jumping, then boxing a sabre-toothed tiger with hooks, uppercuts and jabs, while the camera panel shows the player's pose, the hero on it and the halo around his head](docs/gameplay.gif)

See [DESIGN.md](DESIGN.md) for the game design, and [CONTRIBUTING.md](CONTRIBUTING.md) for how to develop it, and how to record more moves and retrain the move classifier.

**No network access.**
The game runs entirely on your computer and works offline.
The webcam images are processed locally, in memory, and are never saved or sent anywhere.

## Setting up

![The setup seen from above: the laptop on a chair, you 2.5 to 3 m away on your home spot, in a free space of 2 x 2 m](docs/setup_from_above.svg)

* **Put the laptop on a chair or a low table, so that the camera is at about the height of your hips (60 to 100 cm).**
  Do not put it on the floor: the camera would look steeply up at you, and leaning or stepping forward would move your head up and down in the picture, which looks like a duck or a jump.
* **Stand 2.5 to 3 m away from the camera, facing it.**
  The camera must see all of you, from your head to your feet (for the kicks), with some room above your head (for the jumps).
* **Clear a space of about 2 × 2 m around you.**
* **Stay on your spot.**
  The spot where you stand at the start is your home spot: hold still there for a second, and the game remembers it.
  You never need to walk: you lean, duck, jump, punch and kick on the spot.

You need a webcam which supports 640x480.
