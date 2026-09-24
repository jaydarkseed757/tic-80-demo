# tic-80-demo

a small demo with tic-80

## demo2.lua

Three classic effects layered on one screen:

- a colour-cycling text scroller across the top
- a wireframe 3D cube with perspective projection and depth shading
- an 8×8 sprite bouncing around the playfield

The cart is a plain-text TIC-80 cartridge, so the code and its sprite data live
together in one file. The tile data is at the bottom in the `<TILES>` section.

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
