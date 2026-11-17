"""Create original, deterministic game audio. No external samples or melodies."""
import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
RATE = 22050

def save(name, samples):
    ROOT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x)) * 28000)) for x in samples))

def bell(buffer, start, note, length, amplitude):
    freq = 440 * 2 ** ((note - 69) / 12)
    for n in range(int(length * RATE)):
        index = int(start * RATE) + n
        if index >= len(buffer):
            break
        t = n / RATE
        envelope = min(t / .012, 1) * math.exp(-t * 3.5) * min((length - t) / .1, 1)
        tone = math.sin(math.tau * freq * t) + .24 * math.sin(math.tau * freq * 2 * t) + .07 * math.sin(math.tau * freq * 3 * t)
        buffer[index] += tone * envelope * amplitude

def main():
    for name, notes in [('chime', [76, 79, 83, 88]), ('hit', [43, 40])]:
        data = [0.] * int(RATE * (1.8 if name == 'chime' else .45))
        for i, note in enumerate(notes):
            bell(data, i * .13, note, 1.2 if name == 'chime' else .4, .25)
        save(name, data)
    rng = random.Random(731)
    data = []
    previous = 0.
    for i in range(int(RATE * .24)):
        previous = previous * .7 + rng.uniform(-1, 1) * .3
        t = i / (RATE * .24)
        data.append(previous * math.sin(math.pi * t) * .48)
    save('shovel', data)

if __name__ == '__main__':
    main()
