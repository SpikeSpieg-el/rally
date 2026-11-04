"""Numerical mirror of scripts/road_profile.gd for authoring/tests."""
import math


def roll(index, seed, salt):
    n = (index % 1000003) * 92821 + (seed % 1000003) * 68917 + salt * 2833
    return (((n ^ (n >> 13)) * 127) % 1000003) / 1000003


def ease(t):
    t = max(0., min(1., t))
    return t * t * t * (t * (t * 6 - 15) + 10)


def lobe(t, peak=.5):
    if t <= 0 or t >= 1:
        return 0.
    return ease(t / peak) if t < peak else 1 - ease((t - peak) / (1 - peak))


def shape(t, kind):
    if kind == 0:
        return lobe(t, .63)
    if kind == 1:
        return -lobe(t, .42)
    if kind == 2:
        return ease(t / .3) * (1 - ease((t - .72) / .28))
    if kind == 3:
        return -.65 * lobe(t / .6, .55) + .75 * lobe((t - .4) / .6, .6)
    return .8 * lobe(t / .7, .42) + .45 * lobe((t - .48) / .52, .6)


def sample(along, seed=2024, feature_height=.9, feature_spacing=320.,
           amplitude=.05, roughness=.015, wavelength=9., length=math.inf):
    spacing = max(240., feature_spacing)
    block, local = math.floor(along / spacing), along % spacing
    value = 0.
    if roll(block, seed, 1) < .68:
        start = spacing * (.1 + .12 * roll(block, seed, 2))
        span = spacing * (.28 + .33 * roll(block, seed, 3))
        t = (local - start) / span
        if 0 < t < 1:
            kind = min(4, int(roll(block, seed, 4) * 5))
            value = feature_height * (.45 + .55 * roll(block, seed, 5)) * shape(t, kind)
    patch = math.floor(along / 96)
    if roll(patch, seed, 11) < .32:
        start = 18 + 22 * roll(patch, seed, 12)
        span = max(18., min(38., wavelength * (2.2 + 1.2 * roll(patch, seed, 13))))
        t = (along % 96 - start) / span
        if 0 < t < 1:
            sign = -1 if roll(patch, seed, 14) < .5 else 1
            value += sign * amplitude * lobe(t, .38 + roll(patch, seed, 15) * .24)
            value += roughness * shape(t, 3) * .5
    return value * ease((along - 65) / 55) * ease((length - along - 65) / 55)
