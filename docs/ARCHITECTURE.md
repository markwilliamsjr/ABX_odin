# Game Architecture

## Gameplay

The standard gameplay loop is bacteria spawn in procedurally generated formations and after each level the player levels up and is presented with a Path of Exile like skill tree to upgrade their antibiotic. 

As the player moves through levels different types of bacteria are able to spawn. 

To end the level the player either has to destroy all the bacteria or the bacteria has to flee.

The next waves bacteria is determined by what the player is not killing. If a player is not destroying a certain type of bacteria it has a higher chance of spawning.

There is also a hidden boss fight meter that is building that as the player finishes more levels there is a higher likelyhood that a boss fight will occur. The gauge then resets after there is one.

Formations of bacteria, how many of the differing types of bacteria, total bacteria spawned, and the layout is all procedurally generated based on a set of rules.

A wave determines:

- number of enemies
- formation
- formation bounds
- enemy types
- spawn information

Formation generation happens before spawning.
