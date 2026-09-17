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

## Opening it in Studio

```bash
rojo build -o codebot.rbxlx && open codebot.rbxlx
```

Press Play. The room, the robot and the panel are all built by code at run time —
there is nothing to assemble by hand in Studio, and nothing in this repository is a
binary you cannot read.

To edit with Studio open, run `rojo serve` and connect from the Rojo plugin; files
saved here appear in Studio a second later.

## Working on it

```bash
for f in tests/*.spec.luau; do lune run "$f"; done   # 232 checks, Studio closed
stylua src/ tests/ tools/            # format
selene src/ tools/                   # lint

lune run tools/show_tokens.luau '<code>'   # how the code is cut up
lune run tools/show_tree.luau   '<code>'   # the shape the parser makes
lune run tools/run_code.luau    '<code>'   # watch it run, step by step
```

The interpreter is plain Luau with no Roblox API in it, so the whole of it can be
built and tested from the terminal before Studio is ever opened. So are the rooms and
the rules of the world — `RobotWorld.luau` knows where the walls are and `RoomView.luau`
only draws the result, which is why a test can prove every room is solvable without
anyone pressing Play.

## The rooms

Rooms are drawn as pictures in `src/shared/Rooms.luau` — `#` wall, `.` floor, `R` the
robot, `G` the goal — so a room is readable in a diff and editing one means moving a
character. Each introduces exactly one new idea, and a test runs every room's own
intended solution and fails if it does not reach the goal.
