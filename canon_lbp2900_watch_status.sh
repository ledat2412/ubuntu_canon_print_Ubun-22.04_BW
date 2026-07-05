#!/bin/bash

set -u

[ "$USER" != 'root' ] && exec sudo "$0" "$@"

LOGIN_USER=$(logname 2> /dev/null)
[ -z "$LOGIN_USER" ] && LOGIN_USER=$(who | head -1 | awk '{print $1}')
[ -z "$LOGIN_USER" ] && LOGIN_USER=${SUDO_USER:-root}

find_queue_name() {
	local requested_name=${1:-}
	local queue_name

	if [ -n "$requested_name" ]; then
		echo "$requested_name"
		return 0
	fi

	queue_name=$(ccpdadmin 2> /dev/null | awk '/LBP2900/ {print $3; exit}')
	if [ -n "$queue_name" ]; then
		echo "$queue_name"
		return 0
	fi

	queue_name=$(lpstat -p 2> /dev/null | awk '/printer / {print $2; exit}')
	if [ -n "$queue_name" ]; then
		echo "$queue_name"
		return 0
	fi

	return 1
}

has_pending_jobs() {
	local queue_name=$1

	lpstat -o "$queue_name" 2> /dev/null | awk 'NF {found=1} END {exit !found}'
}

captstatusui_is_running() {
	local queue_name=$1

	pgrep -f "captstatusui -P $queue_name" > /dev/null 2>&1
}

launch_captstatusui() {
	local queue_name=$1

	if ! captstatusui_is_running "$queue_name"; then
		sudo -u "$LOGIN_USER" nohup captstatusui -P "$queue_name" > /dev/null 2>&1 &
	fi
}

main() {
	local queue_name
	local delay_seconds=3

	queue_name=$(find_queue_name "${1:-}") || {
		echo 'Khong tim thay queue LBP2900.'
		exit 1
	}

	echo "Watching printer queue: $queue_name"
	echo 'The script will open captstatusui whenever there is a print job.'

	while true; do
		if has_pending_jobs "$queue_name"; then
			launch_captstatusui "$queue_name"
		fi
		sleep "$delay_seconds"
	done
}

main "$@"