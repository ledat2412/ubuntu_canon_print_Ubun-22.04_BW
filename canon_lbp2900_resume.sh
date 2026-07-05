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

restart_print_stack() {
	service ccpd restart 2> /dev/null
	service cups restart 2> /dev/null
}

clear_stuck_jobs() {
	local queue_name=$1

	cancel -a "$queue_name" 2> /dev/null
	cupsenable "$queue_name" 2> /dev/null
	cupsaccept "$queue_name" 2> /dev/null
}

launch_status_monitor() {
	local queue_name=$1

	killall captstatusui 2> /dev/null
	sudo -u "$LOGIN_USER" nohup captstatusui -P "$queue_name" > /dev/null 2>&1 &
}

main() {
	local queue_name

	queue_name=$(find_queue_name "${1:-}" ) || {
		echo 'Khong tim thay queue may in LBP2900.'
		exit 1
	}

	echo "Recovering printer queue: $queue_name"
	echo 'Clearing stuck jobs and re-enabling the queue'
	clear_stuck_jobs "$queue_name"
	echo 'Restarting CUPS and ccpd'
	restart_print_stack
	echo 'Launching status monitor'
	launch_status_monitor "$queue_name"
	echo 'If the printer was out of paper, insert paper and send the job again.'
}

main "$@"