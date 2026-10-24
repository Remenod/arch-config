#!/usr/bin/env bash
# Waybar's notification module: swaync's own Waybar stream, one JSON line per
# change, with the count hidden at zero and capped at "9+" so the module keeps
# a fixed width.
#
# Waybar stops a module by killing this shell only, so both ends of the pipe
# ask the kernel to stop them when it dies; otherwise swaync-client and jq
# would linger after every Waybar reload.

setpriv --pdeathsig TERM swaync-client --subscribe-waybar \
    | setpriv --pdeathsig TERM jq --unbuffered -c \
        '.text |= (tonumber? // 0 | if . == 0 then "" elif . > 9 then " 9+" else " \(.)" end)'
