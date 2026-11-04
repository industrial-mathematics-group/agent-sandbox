# shellcheck shell=bash
# Sourced by the base entrypoint (as root, before dropping to `agent`).
# Starts a virtual X display for GLMakie & co. Local unix socket only.
# VIRTUAL_DISPLAY=0 turns it off, XVFB_RESOLUTION changes the size.
if [ "${VIRTUAL_DISPLAY:-1}" != "0" ] && command -v Xvfb >/dev/null; then
    export DISPLAY=${DISPLAY:-:99}
    disp_num=${DISPLAY#:}
    disp_num=${disp_num%%.*}
    rm -f "/tmp/.X${disp_num}-lock" "/tmp/.X11-unix/X${disp_num}"
    drop_to_agent Xvfb "$DISPLAY" -screen 0 "${XVFB_RESOLUTION:-1920x1080x24}" \
        -nolisten tcp >/tmp/xvfb.log 2>&1 &
    for _ in $(seq 50); do
        [ -S "/tmp/.X11-unix/X${disp_num}" ] && break
        sleep 0.1
    done
    [ -S "/tmp/.X11-unix/X${disp_num}" ] || echo "WARN: Xvfb did not start, see /tmp/xvfb.log" >&2
else
    unset DISPLAY
fi
