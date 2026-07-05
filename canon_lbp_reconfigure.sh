#!/bin/bash

##################################################
# Auto-detect Canon LBP printer, remove old config,
# and install a fresh CUPS/ccpd configuration.
##################################################

[ "$USER" != 'root' ] && exec sudo "$0" "$@"

LOGIN_USER=$(logname 2> /dev/null)
[ -z "$LOGIN_USER" ] && LOGIN_USER=$(who | head -1 | awk '{print $1}')
[ -z "$LOGIN_USER" ] && LOGIN_USER=${SUDO_USER:-root}

if [ -f ~/.config/user-dirs.dirs ]; then
	source ~/.config/user-dirs.dirs
else
	XDG_DESKTOP_DIR="$HOME/Desktop"
fi

DRIVER_VERSION='2.71-1'
DRIVER_VERSION_COMMON='3.21-1'

declare -A URL_DRIVER=([amd64_common]='https://github.com/hieplpvip/canon_printer/raw/master/Packages/cndrvcups-common_3.21-1_amd64.deb' \
[amd64_capt]='https://github.com/hieplpvip/canon_printer/raw/master/Packages/cndrvcups-capt_2.71-1_amd64.deb' \
[i386_common]='https://github.com/hieplpvip/canon_printer/raw/master/Packages/cndrvcups-common_3.21-1_i386.deb' \
[i386_capt]='https://github.com/hieplpvip/canon_printer/raw/master/Packages/cndrvcups-capt_2.71-1_i386.deb')

declare -A LASERSHOT=([LBP-810]=1120 [LBP1120]=1120 [LBP1210]=1210 \
[LBP2900]=2900 [LBP3000]=3000 [LBP3010]=3050 [LBP3018]=3050 [LBP3050]=3050 \
[LBP3100]=3150 [LBP3108]=3150 [LBP3150]=3150 [LBP3200]=3200 [LBP3210]=3210 \
[LBP3250]=3250 [LBP3300]=3300 [LBP3310]=3310 [LBP3500]=3500 [LBP5000]=5000 \
[LBP5050]=5050 [LBP5100]=5100 [LBP5300]=5300 [LBP6000]=6018 [LBP6018]=6018 \
[LBP6020]=6020 [LBP6020B]=6020 [LBP6200]=6200 [LBP6300n]=6300n [LBP6300]=6300 \
[LBP6310]=6310 [LBP7010C]=7018C [LBP7018C]=7018C [LBP7200C]=7200C [LBP7210C]=7210C \
[LBP9100C]=9100C [LBP9200C]=9200C)

NAMESPRINTERS=$(echo "${!LASERSHOT[@]}" | tr ' ' '\n' | sort -n -k1.4)

if [ "$(uname -m)" = 'x86_64' ]; then
	ARCH='amd64'
else
	ARCH='i386'
fi

if [[ $(ps -p1) == *systemd* ]]; then
	INIT_SYSTEM='systemd'
else
	INIT_SYSTEM='upstart'
fi

cd "$(dirname "$0")"

normalize_name() {
	tr '[:lower:]' '[:upper:]' | tr -cd 'A-Z0-9'
}

valid_ip() {
	local ip=$1
	local stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		ip=($(echo "$ip" | tr '.' ' '))
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi
	return $stat
}

check_error() {
	if [ $2 -ne 0 ]; then
		case $1 in
			'WGET') echo "Error while downloading file $3"
				[ -n "$3" ] && [ -f "$3" ] && rm "$3";;
			'PACKAGE') echo "Error installing package $3";;
			*) echo 'Error';;
		esac
		echo 'Press any key to exit'
		read -s -n1
		exit 1
	fi
}

known_model_match() {
	local detected_name=$1
	local normalized_detected
	local model_key
	local normalized_model

	normalized_detected=$(printf '%s' "$detected_name" | normalize_name)
	for model_key in $NAMESPRINTERS; do
		normalized_model=$(printf '%s' "$model_key" | normalize_name)
		case "$normalized_detected" in
			*"$normalized_model"*)
				echo "$model_key"
				return 0
				;;
		esac
	done
	echo "$detected_name"
	return 0
}

detect_printer_model() {
	local node_device
	local detected_name
	local raw_uri
	local uri_model

	for node_device in /dev/usb/lp*; do
		[ -e "$node_device" ] || continue
		detected_name=$(udevadm info --query=property --name="$node_device" 2> /dev/null | awk -F= '/^(ID_MODEL|ID_MODEL_FROM_DATABASE)=/{print $2; exit}')
		if [ -n "$detected_name" ]; then
			known_model_match "$detected_name"
			return 0
		fi
	done

	raw_uri=$(lpinfo -v 2> /dev/null | awk '/usb:\/\/Canon\// {print $2; exit}')
	if [ -n "$raw_uri" ]; then
		uri_model=$(printf '%s' "$raw_uri" | sed -n 's#.*usb://Canon/\([^?]*\).*#\1#p')
		if [ -n "$uri_model" ]; then
			known_model_match "$uri_model"
			return 0
		fi
	fi

	return 1
}

get_current_printer() {
	if [ -f /usr/sbin/ccpdadmin ]; then
		ccpdadmin 2> /dev/null | awk '/LBP/ {print $3; exit}'
	fi
}

remove_old_configuration() {
	local old_printer

	old_printer=$(get_current_printer)
	if [ -n "$old_printer" ]; then
		echo "Removing existing printer configuration: $old_printer"
		killall captstatusui 2> /dev/null
		service ccpd stop 2> /dev/null
		ccpdadmin -x "$old_printer" 2> /dev/null
		lpadmin -x "$old_printer" 2> /dev/null
		rm -f /etc/udev/rules.d/85-canon-capt.rules
		rm -f /etc/init/ccpd-start.conf
		rm -f "${XDG_DESKTOP_DIR}/${old_printer}.desktop"
		rm -f /usr/bin/autoshutdowntool
	fi
}

install_drivers() {
	COMMON_FILE=cndrvcups-common_${DRIVER_VERSION_COMMON}_${ARCH}.deb
	CAPT_FILE=cndrvcups-capt_${DRIVER_VERSION}_${ARCH}.deb

	if [ ! -f "$COMMON_FILE" ]; then
		sudo -u "$LOGIN_USER" wget -O "$COMMON_FILE" "${URL_DRIVER[${ARCH}_common]}"
		check_error WGET $? "$COMMON_FILE"
	fi
	if [ ! -f "$CAPT_FILE" ]; then
		sudo -u "$LOGIN_USER" wget -O "$CAPT_FILE" "${URL_DRIVER[${ARCH}_capt]}"
		check_error WGET $? "$CAPT_FILE"
	fi

	apt-get -y update
	apt-get -y install libglade2-0 libcanberra-gtk-module
	configure_ccpd_service() {
		cat > /etc/init.d/ccpd <<'EOF'
	#!/bin/bash
	# startup script for Canon Printer Daemon for CUPS (ccpd)
	### BEGIN INIT INFO
	# Provides:          ccpd
	# Required-Start:    $local_fs $remote_fs $syslog $network $named
	# Should-Start:      $ALL
	# Required-Stop:     $syslog $remote_fs
	# Default-Start:     2 3 4 5
	# Default-Stop:      0 1 6
	# Description:       Start Canon Printer Daemon for CUPS
	### END INIT INFO

	if [ `ps awx | grep cupsd | grep -v grep | wc -l` -eq 0 ]; then
		while [ `ps awx | grep cupsd | grep -v grep | wc -l` -eq 0 ]
		do
			sleep 3
		done
		sleep 5
	fi

	ccpd_start ()
	{
		echo -n "Starting ${DAEMON}: "
		start-stop-daemon --start --quiet --oknodo --exec ${DAEMON}
	}

	ccpd_stop ()
	{
		echo -n "Shutting down ${DAEMON}: "
		start-stop-daemon --stop --quiet --oknodo --retry TERM/30/KILL/5 --exec ${DAEMON}
	}

	DAEMON=/usr/sbin/ccpd
	case $1 in
		start)
			ccpd_start
			;;
		stop)
			ccpd_stop
			;;
		status)
			echo "${DAEMON}:" $(pidof ${DAEMON})
			;;
		restart)
			while true
			do
				ccpd_stop
				ccpd_start
				for (( i = 1 ; i <= 5 ; i++ ))
				do
					sleep 1
					set -- $(pidof ${DAEMON})
					[ -n "$1" -a -n "$2" ] && exit 0
				done
			done
			;;
		*)
			echo "Usage: ccpd {start|stop|status|restart}"
			exit 1
			;;
	esac
	exit 0
	EOF
	}

	configure_usb_rule() {
		local printer_name=$1
		local printer_serial=$2

		echo 'Creating a rule for the printer'
		echo 'KERNEL=="lp[0-9]*", SUBSYSTEMS=="usb", ATTRS{serial}=='"$printer_serial"', SYMLINK+="canon'"$printer_name"'"' > /etc/udev/rules.d/85-canon-capt.rules
		udevadm control --reload-rules
	}

	reconfigure_printer() {
		local nameprinter
		local connection
		local path_device
		local ip_address
		local node_device
		local printer_serial
		local installed_printer

		echo
		nameprinter=$(detect_printer_model)
		if [ -n "$nameprinter" ]; then
			echo "Detected printer: $nameprinter"
		else
			PS3='Please choose your printer: '
			select nameprinter in $NAMESPRINTERS
			do
				[ -n "$nameprinter" ] && break
			done
			echo "Selected printer: $nameprinter"
		fi
		echo

		remove_old_configuration

		PS3='How is the printer connected to the computer: '
		select connection in 'Via USB' 'Through network (LAN, NET)'
		do
			if [ "$REPLY" = '1' ]; then
				while true
				do
					node_device=$(ls -1t /dev/usb/lp* 2> /dev/null | head -1)
					if [ -n "$node_device" ]; then
						printer_serial=$(udevadm info --attribute-walk --name="$node_device" | sed '/./{H;$!d;};x;/ATTRS{product}=="Canon CAPT USB \(Device\|Printer\)"/!d;' | awk -F'==' '/ATTRS{serial}/{print $2}')
						[ -n "$printer_serial" ] && break
					fi
					echo -ne "Turn on the printer and plug in USB cable\r"
					sleep 2
				done
				path_device="/dev/canon$nameprinter"
				break
			elif [ "$REPLY" = '2' ]; then
				read -p 'Enter the IP address of the printer: ' ip_address
				until valid_ip "$ip_address"
				do
					echo 'Invalid IP address format, enter four decimal numbers'
					echo -n 'from 0 to 255, separated by dots: '
					read ip_address
				done
				path_device="net:$ip_address"
				echo 'Turn on the printer and press any key'
				read -s -n1
				sleep 5
				break
			fi
		done

		echo '************Driver Installation************'
		install_drivers
		configure_ccpd_service

		if [ "$ARCH" = 'amd64' ]; then
			echo 'Installing 32-bit libraries required to run 64-bit printer driver'
			apt-get -y install libatk1.0-0:i386 libcairo2:i386 libgtk2.0-0:i386 libpango1.0-0:i386 libstdc++6:i386 libpopt0:i386 libxml2:i386 libc6:i386
			check_error PACKAGE $?
		fi

		echo 'Installing the printer in CUPS'
		/usr/sbin/lpadmin -p "$nameprinter" -P "/usr/share/cups/model/CNCUPSLBP${LASERSHOT[$nameprinter]}CAPTK.ppd" -v ccp://localhost:59687 -E
		echo "Setting $nameprinter as the default printer"
		/usr/sbin/lpadmin -d "$nameprinter"
		echo 'Registering the printer in the ccpd daemon configuration file'
		/usr/sbin/ccpdadmin -p "$nameprinter" -o "$path_device"

		installed_printer=$(ccpdadmin 2> /dev/null | grep "$nameprinter" | awk '{print $3}')
		if [ -n "$installed_printer" ]; then
			if [ "$connection" = 'Via USB' ]; then
				configure_usb_rule "$nameprinter" "$printer_serial"
				until [ -e "$path_device" ]
				do
					echo -ne "Turn off the printer, wait 2 seconds, then turn on the printer\r"
					sleep 2
				done
			fi
			echo -e "\e[2KRunning ccpd"
			service ccpd restart
			if [ "$INIT_SYSTEM" = 'systemd' ]; then
				update-rc.d ccpd defaults
			else
				cat > /etc/init/ccpd-start.conf <<'EOF'
	description "Canon Printer Daemon for CUPS (ccpd)"
	author "LinuxMania <customer@linuxmania.jp>"
	start on (started cups and runlevel [2345])
	stop on runlevel [016]
	expect fork
	respawn
	exec /usr/sbin/ccpd start
	EOF
			fi
			cat > "${XDG_DESKTOP_DIR}/${nameprinter}.desktop" <<EOF
	#!/usr/bin/env xdg-open
	[Desktop Entry]
	Version=1.0
	Name=${nameprinter}
	GenericName=Status monitor for Canon CAPT Printer
	Exec=captstatusui -P ${nameprinter}
	Terminal=false
	Type=Application
	Icon=/usr/share/icons/Humanity/devices/48/printer.svg
	EOF
			chmod 775 "${XDG_DESKTOP_DIR}/${nameprinter}.desktop"
			chown "$LOGIN_USER:$LOGIN_USER" "${XDG_DESKTOP_DIR}/${nameprinter}.desktop"
			if [[ -n "$DISPLAY" ]]; then
				sudo -u "$LOGIN_USER" nohup captstatusui -P "$nameprinter" > /dev/null 2>&1 &
				sleep 5
			fi
			echo 'Reconfiguration completed. Press any key to exit'
			read -s -n1
			exit 0
		else
			echo "Driver for $nameprinter is not installed!"
			echo 'Press any key to exit'
			read -s -n1
			exit 1
		fi
	}

	clear
	echo 'Canon CAPT printer reconfigure tool for Ubuntu'
	echo 'This script detects a printer name, removes the old configuration, and installs a fresh one.'

	reconfigure_printer
+		exit 1
+	fi
+}
+
+clear
+echo 'Canon CAPT printer reconfigure tool for Ubuntu'
+echo 'This script detects a printer name, removes the old configuration, and installs a fresh one.'
+
+reconfigure_printer
