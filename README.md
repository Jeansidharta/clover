# ⚠️ This is still a work in progress. There are no relases. It will not work at this stage ⚠️

# Clover

Clover is a stenography software used to translate input from stenography
machines into words on your computer.

It was heavily inspired from
[Plover](https://github.com/openstenoproject/plover) (another software with the
same purpose)

## Differences from Plover

- **Written in Zig instead of python:** This makes it easier to target multiple
  platforms, such as microcontrollers and web browsers through WASM. It also
  makes it more portable, not depending on the python environment to work.
- **More composable:** It is primarily made to be simpler and more modular,
  making it easier to create plugins, or to build other tools on top of it.

## Limitations

- Only works on Linux
- Only works with X11
- Only works with certain protols
  - Gemini PR
  - Stenura serial protocol

## Roadmap

- [ ] Properly support the entire plover dictionary syntax
- [ ] Well tested with unit tests ans integration tests
- [ ] Allow for plugins
- [ ] Make the daemon be controllable through a CLI
- [ ] Support all machines also supported by Plover
- [ ] Support the usage of regular keyboards, and not only steno machin
- [ ] Support Wayland
