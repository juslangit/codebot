--!strict
--[[
	The server. There is almost nothing here yet, and that is correct for now:
	each player has their own room, drawn on their own client, so nothing needs
	to be agreed between them.

	Two things change that later:

	  * M7, when the room becomes shared and the server builds it.
	  * The scoring rule from D-004 — when a player claims a solve, the server
	    re-runs their program with the same interpreter before recording it, so
	    a modified client cannot invent a score.
]]

local Players = game:GetService("Players")

-- There is no avatar in this game. The player is the code they write, and a
-- character wandering through the room would only be in the way of the camera.
Players.CharacterAutoLoads = false
