#!/bin/sh
mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
exec qs -c pill ipc call pill quickRecord "$mon"
