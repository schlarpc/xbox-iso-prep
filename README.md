# xbox-iso-prep

This is a tool for preparing Xbox ISOs for use on a hardmodded Xbox.

## Building

Install a version of nix with flake support, then run:

```
$ nix build .
```

The build output will be in the `./result` directory.

## Kernel patch

A kernel patch is included based on nkpatcher, but stripped down to only support ISO mounting.
This must be loaded before prepared ISOs will run.

To use it, place `./result/patcher.xbe` in a location where your BIOS looks for a dashboard XBE.
By default, the patcher chainloads `E:\XBMC\default.xbe` after patching.

I've tested it with the EvoX M8+ BIOS (including with the XboxHD+ 1.0.2 patch). "Compatible" IGR
is recommended so that you can actually reset to the dashboard.

## Prep tool

The prep tool performs the following steps to your ISOs for usage on the Xbox:
* repacks the ISO using `extract-xiso` to ensure a standard format and no garbage data
* creates a customized launcher XBE for the ISO, copying its game title, icon, etc
* splits the ISO into multiple parts if larger than 4GB

To use it, execute `./result/prepare-xiso` with an input ISO file and an output base directory:

```
$ ./result/prepare-xiso some-game.iso games
$ ls games/some-game
```

I've tested this with a few Redump ISOs. I do not know (or care, really) if this will work with
ISOs in other formats.
