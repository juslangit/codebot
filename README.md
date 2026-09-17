# codebot

A Roblox game where you learn Luau by writing it.

Your code is the controller. There is no joystick and no jump button — you write
`move()` and a robot walks one tile. Each room introduces exactly one new idea, and
other players solve the same room beside you with their robots visible.

## Why the code is not run with `loadstring`

It can't be. Roblox gates `loadstring` behind `ServerScriptService.LoadStringEnabled`,
which defaults to `false`, exists only on the server, and turns any player-supplied
string into remote code execution the moment it is switched on.

So this repository contains a small Luau interpreter, written in Luau, in three parts:

| Part | File | Job |
|---|---|---|
| Tokenizer | `src/shared/Interpreter/Tokenizer.luau` | Cut the code into the smallest pieces that mean something |
| Parser | `src/shared/Interpreter/Parser.luau` | Work out the shape of the program those pieces make |
| Interpreter | `src/shared/Interpreter/Interp.luau` | Run that shape, one step at a time |

Owning the interpreter is better than `loadstring` would have been anyway: it can
pause on line 4, highlight it, show `i = 3` and move the robot a single tile. That
stepping is what teaches.

## Working on it

```bash
lune run tests/Tokenizer.spec.luau   # run the tests, Studio closed
stylua src/ tests/                   # format
selene src/                          # lint
rojo serve                           # live-sync into Studio
rojo build -o codebot.rbxlx          # build a place file without Studio
```

The interpreter is plain Luau with no Roblox API in it, so the whole of it can be
built and tested from the terminal before Studio is ever opened.
