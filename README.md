# tic-80-demo

a small demo with tic-80

## demo2.lua

A multi-scene demo driven by a small scene director.

### scenes

1. **copper bars** — four sine-driven gradient bars behind a bevelled logo and
   a DYCP scroller. The bars cost nothing per pixel: colour 0 is the
   background, and `SCN()` repokes palette entry 0 once per scanline, so the
   framebuffer stays empty while the gradient is produced at scanout. This is
   the Amiga copper trick, and it is also how you get past the 16-colour limit.
   The scroller is a C64 DYCP ("Different Y Char Position") — every character
   takes its own Y from a sine table.
2. **wireframe cube** — a rotating cube with perspective projection, back-to-
   front edge sorting and depth shading, plus a colour-cycling scroller and a
   bouncing sprite.

### adding a scene

Scenes are entries in the `scenes` table:

```lua
{name="...", dur=<frames>, enter=fn, update=fn(t), draw=fn(t), scanline=fn(line)}
```

`enter` resets the scene's state so it is restartable, `update`/`draw` get the
scene-local frame count, and `scanline` is optional — supply it only for
palette work that has to happen mid-frame. The director handles sequencing and
fades to black over 30 frames at each boundary by scaling the whole palette,
which is how the originals did transitions.

The cart is a plain-text TIC-80 cartridge, so the code and its sprite data live
together in one file. The tile data is at the bottom in the `<TILES>` section.

## tests

```sh
lua5.4 test/run.lua
```

`test/tic80.lua` is a headless fake of the TIC-80 API — enough of it to load the
cart and step it frame by frame under plain Lua. It reproduces the render order
that matters: `TIC()` draws the whole frame, then the frame is scanned out a
line at a time with `SCN(line)` running before each line.

`test/run.lua` checks that the cart loads and runs, that the scene table is
well formed, that scenes sequence and fade without jumps, that each scene draws
identically on every loop (the director's restartability contract), that every
palette write is an integer byte inside `0x3FC0..0x3FEF`, that no draw call gets
a NaN coordinate or an out-of-range colour, that the demo allocates nothing per
frame, and that the copper bars have no brightness cliffs.

Point it at a different cart with `CART=path lua5.4 test/run.lua`. That is how
the checks themselves are verified: copy the cart, reintroduce a bug, and
confirm the matching check goes red. Every check here has been confirmed to fail
against a deliberate reintroduction of the bug it covers.

### what the tests cannot tell you

The fake cannot run the emulator, so it checks that the cart *asks* for the
right things, not that TIC-80 obliges. In particular it cannot confirm that
palette writes are sampled per scanline (which is what makes the copper bars
work at all), that `0x3FC0` is the palette, or that the tile hex decodes to the
intended sprite. Load the cart in TIC-80 for those.

### running it

```sh
tic80 demo2.lua
```

Or from the TIC-80 console:

```
load demo2.lua
run
```

Note that the extension matters: `.tic` is TIC-80's *binary* cartridge format,
so a text cart must be saved as `.lua` or TIC-80 will refuse to load it.
