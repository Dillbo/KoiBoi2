KoiBoi2 Concept

KoiBoi transforms a simple visual metaphor into a rich musical experience:

Koi swim in circular orbits around a pond, each at its own radius and speed

Koi eat the food to trigger notes using the PolyPerc engine

Uneaten food ages and fades into a drone layer over time

MIDI input allows you to place food at specific pitches

Softcut delay adds rhythmic and textural depth

The result is an ever-changing, meditative composition that balances predictability (orbital motion) with randomness (food placement and koi behaviour).

Features

Core Gameplay

Up to 8 koi fish are swimming in circular orbits

Radial pitch mapping: distance from center = pitch (2 octaves)

Dual pitch modes: Linear chromatic or quantised to musical scales

32 food items maximum with brightness-based aging visualisation

MIDI food input: play notes to spawn food at corresponding radii

Sound Engine

PolyPerc synthesis for food notes with adjustable filter, release, and amplitude

Drone layer with a note buffer that loops aged food at adjustable intervals

Tempo-synced delay via Softcut with note division control (1/32 to 4/1)

LFO modulation of delay feedback for evolving textures

Delay filter with adjustable cutoff and resonance

Reverse and overdub modes for creative delay effects

Control & Customization

8-page menu system for deep parameter control

11 musical scales, including major, minor, pentatonic, blues, and modes

Adjustable root note and octave (2-6)

Tempo control (60-200 BPM) with synchronised delay divisions

Per-koi speed and radius control for fine-tuning movement

MIDI input and output on separate channels for food and drone layers

Controls

Main Screen (Page 0)



Control

Function

K1

Enter/exit menu system

K2

Play/Pause

K3

Scatter food into the pond

E1

Select koi (1-8)

E2

Change the selected koi's orbit radius

E3

Change selected koi's speed (positive = clockwise, negative = counter-clockwise)

Menu Navigation

Control

Function

K1

Return to main screen

K2

Test note mapping (prints debug info)

E1

Change menu page (1-8)

E2

Select parameter on the current page

E3

Adjust selected parameter

Instructions Screen

Any encoder scrolls up/down. Press K1 or K2 to exit and start playing.

Menu System

Page 1: Scale & Tempo

Scale: Choose from 11 scales (major, minor, dorian, etc.)

Root Note: Set the root note (C-B)

Octave: Set the base octave (2-6) • Default: 5

Tempo: Set BPM for delay sync (60-200) • Default: 120

Pitch Mode: Linear (chromatic) or Scale (quantised)

Page 2: Koi Behaviour

Number of Koi: 1-8 koi in the pond • Default: 4

Global Speed: Speed multiplier for all koi (0.1-4.0)

Displays selected koi's individual speed and direction

Page 3: PolyPerc Synth

Cutoff: Filter cutoff frequency (50-5000 Hz) • Default: 800 Hz

Release: Note release time (0.1-5.0s) • Default: 0.3s

Amplitude: Note volume (0.0-1.0) • Default: 0.5

Page 4: Softcut Delay

Division: Note value for delay time • Default: 1/4. (dotted quarter)

Options: 1/32, 1/16, 1/8, 1/8., 1/4, 1/4., 1/2, 1/2., 1/1, 2/1, 4/1

Feedback: Delay feedback amount (0.0-0.95) • Default: 0.45

Mix: Wet/dry mix (0.0-1.0) • Default: 0.4

LFO Rate: Feedback modulation rate (0.1-2.0 Hz) • Default: 0.0 (off)

Page 5: Softcut Creative

LFO Depth: Feedback modulation depth (0.0-0.5) • Default: 0.2

Filter Cutoff: Delay filter frequency (200-8000 Hz) • Default: 2000 Hz

Reverse: Enable reverse delay playback • Default: Off

Overdub: Enable delay overdubbing • Default: On

Page 6: Drone Layer

Buffer Bars: Loop length in bars (1-8) • Default: 2

Buffer Notes: Number of note slots (1-16) • Default: 8

Fade Chance: Probability of food becoming drone (0.0-1.0) • Default: 0.25

Amplitude: Drone volume (0.0-0.3) • Default: 0.3

Cutoff: Drone filter frequency (50-500 Hz) • Default: 200 Hz

Page 7: MIDI Settings

MIDI Input: Enable/disable MIDI input • Default: On

MIDI Output: Enable/disable MIDI output • Default: Off

Input Device: Select MIDI input device (1-4)

Output Device: Select MIDI output device (1-4)

Page 8: MIDI Channels

Food Channel: MIDI channel for food notes (1-16) • Default: 1

Drone Channel: MIDI channel for drone notes (1-16) • Default: 2

Displays current note range based on root/octave settings

MIDI Implementation

MIDI Input

When MIDI Input is enabled, incoming MIDI notes spawn food in the pond:

Note value determines radial position (pitch mapping)

Velocity affects food brightness

MIDI food appears as small squares (vs. dots for random food)

Food is placed at random angles at the calculated radius

MIDI Output

When MIDI Output is enabled:

Food notes are sent on the Food Channel when koi eat

Drone notes are sent on the Drone Channel when drones play

Note-off messages sent 100ms after note-on

Output respects the current pitch mapping and scale settings

Note Mapping

The pond uses a 2-octave radial mapping:

Center (1 pixel): Root note

Edge (29 pixels): Root note + 23 semitones (2 octaves up)

Linear Mode: Chromatic mapping across the radius

Scale Mode: Quantized to the selected scale

Requirements

Monome Norns (any version)

PolyPerc engine (included with Norns)

Softcut (built into Norns)

Optional: MIDI input device (keyboard, sequencer, etc.)

Optional: MIDI output device (synth, DAW, etc.)

Technical Details

Performance Optimization

Pre-calculated trigonometric values

Local references to math functions

Collision detection uses squared distance (avoids sqrt)

Separate clock threads for game logic (60 FPS) and screen refresh (15 FPS)

Food table is capped at 32 items

Note Mapping Algorithm

semitone_offset = note - root_midi_note
radius = MIN_RADIUS + (semitone_offset / 23) * RADIUS_RANGE

Where:
- MIN_RADIUS = 1 pixel (center)
- MAX_RADIUS = 29 pixels (edge)
- RADIUS_RANGE = 28 pixels
- NOTE_RANGE = 24 semitones (2 octaves)

Drone Buffer System

Ring buffer with configurable size (1-16 notes)

Notes added based on fade chance probability

Oldest notes replaced when buffer is full

Each note loops at the specified bar interval

Separate long release (4.0s) for sustained drone texture

Credits

Created by: DillboDate: August 2025Platform: Monome NornsEngine: PolyPerc (Norns built-in)

Special thanks to the Monome community and the Norns platform developers.

License

This script is released as open source. Feel free to modify, share, and build upon it!

Philosophy

"A pond is never the same twice, yet always itself."

KoiBoi embraces the Japanese concept of ma (間) - the space between things - where meaning emerges from what is not played as much as what is. The koi swim endlessly, the food appears and fades, and the drones remember what has passed. It is a meditation on time, pattern, and the beauty of simple systems creating complex outcomes.

Sit with your pond. Watch it breathe. Listen to it sing.

Version: 1.0Last Updated: 2025

Swim well
