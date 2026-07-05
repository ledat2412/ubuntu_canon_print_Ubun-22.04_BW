#!/usr/bin/env bash

set -u

normalize_name() {
	tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9'
}

known_model_match() {
	local detected_name=$1
	local normalized_detected
	local model
	local normalized_model

	normalized_detected=$(printf '%s' "$detected_name" | normalize_name)
	for model in LBP-810 LBP1120 LBP1210 LBP2900 LBP3000 LBP3010 LBP3018 LBP3050 LBP3100 LBP3108 LBP3150 LBP3200 LBP3210 LBP3250 LBP3300 LBP3310 LBP3500 LBP5000 LBP5050 LBP5100 LBP5300 LBP6000 LBP6018 LBP6020 LBP6020B LBP6200 LBP6300n LBP6300 LBP6310 LBP7010C LBP7018C LBP7200C LBP7210C LBP9100C LBP9200C; do
		normalized_model=$(printf '%s' "$model" | normalize_name)
		case "$normalized_detected" in
			*"$normalized_model"*)
				echo "$model"
				return 0
				;;
		esac
	done

	echo "$detected_name"
	return 0
}

detect_from_udev() {
	local node_device
	local detected_name

	for node_device in /dev/usb/lp*; do
		[ -e "$node_device" ] || continue
		detected_name=$(udevadm info --query=property --name="$node_device" 2>/dev/null | awk -F= '/^(ID_MODEL|ID_MODEL_FROM_DATABASE)=/{print $2; exit}')
		if [ -n "$detected_name" ]; then
			known_model_match "$detected_name"
			return 0
		fi
	done

	return 1
}

detect_from_lpinfo() {
	local uri
	local model_part

	uri=$(lpinfo -v 2>/dev/null | awk '/usb:\/\/Canon\// {print $2; exit}')
	[ -z "$uri" ] && return 1

	model_part=$(printf '%s' "$uri" | sed -n 's#.*usb://Canon/\([^?]*\).*#\1#p')
	[ -z "$model_part" ] && return 1

	known_model_match "$model_part"
	return 0
}

detect_from_cups() {
	lpstat -e 2>/dev/null | awk 'NF {print; exit}'
}

main() {
	local printer_name

	printer_name=$(detect_from_udev || true)
	if [ -n "${printer_name:-}" ]; then
		echo "$printer_name"
		return 0
	fi

	printer_name=$(detect_from_lpinfo || true)
	if [ -n "${printer_name:-}" ]; then
		echo "$printer_name"
		return 0
	fi

	printer_name=$(detect_from_cups || true)
	if [ -n "${printer_name:-}" ]; then
		echo "$printer_name"
		return 0
	fi

	echo 'Khong tim thay ten may in' >&2
	return 1
}

main "$@"