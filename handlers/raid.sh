#! /bin/sh

raid_recipe=
raid_current_device=0

raid_recipe_append () {
	raid_recipe="${raid_recipe:+$raid_recipe }$1 ."
}

raid_handler () {
	level=
	device=
	spares=0
	fstype=

	# TODO --bytes-per-inode=, --fsoptions=, --noformat, --useexisting
	eval set -- "$(getopt -o '' -l level:,device:,spares:fstype: -- "$@")" || { warn_getopt raid; return; }
	while :; do
		case $1 in
			--level)
				level="$2"
				shift 2
				;;
			--device)
				device="$2"
				shift 2
				;;
			--spares)
				spares="$2"
				shift 2
				;;
			--fstype)
				fstype="$2"
				shift 2
				;;
			--)	shift; break ;;
			*)	warn_getopt raid; return ;;
		esac
	done

	if [ -z "$level" ]; then
		warn "raid command requires a level"
		return
	fi
	if [ -z "$device" ]; then
		warn "raid command requires a device"
		return
	fi
	if [ $# -lt 2 ]; then
		warn "raid comment requires mountpoint and partition(s)"
		return
	fi

	# TODO support out-of-order
	if [ "$device" != "md$raid_current_device" ]; then
		warn "raid devices specified out of order; expecting md$raid_current_device"
		return
	fi
	raid_current_device="$(($raid_current_device + 1))"

	mountpoint="$1"
	shift
	raid_recipe_append "$level $# $spares $mountpoint $*"
}

raid_final () {
	if [ "$raid_recipe" ]; then
		partition_final

		devs=
		raid_new_recipe=
		set -- $raid_recipe
		while [ "$1" ]; do
			dev_count="$2"
			spare_count="$3"
			raid_new_recipe="${raid_new_recipe:+$raid_new_recipe }$1 $2 $3 $4"
			shift 4

			raidids=
			while [ "$1" ] && [ "$1" != . ] && [ "$dev_count" -gt "$spare_count" ]; do
				if [ -e "$SPOOL/parse/partition.raididmap.$1" ]; then
					raidids="${raidids:+$raidids$NL}$(cat "$SPOOL/parse/partition.raididmap.$1")"
				else
					warn "no partition command issued for $1"
					return
				fi
				dev_count="$(($dev_count - 1))"
				shift
			done
			active_devs=
			for raidid in $(echo "$raidids" | sort -u); do
				active_devs="${active_devs:+$active_devs#}raidid=$raidid"
			done
			if [ "$active_devs" ]; then
				raid_new_recipe="${raid_new_recipe:+$raid_new_recipe }$active_devs"
			fi

			raidids=
			while [ "$1" ] && [ "$1" != . ] && [ "$dev_count" -gt 0 ]; do
				if [ -e "$SPOOL/parse/partition.raididmap.$1" ]; then
					raidids="${raidids:+$raidids$NL}$(cat "$SPOOL/parse/partition.raididmap.$1")"
				else
					warn "no partition command issued for $1"
					return
				fi
				dev_count="$(($dev_count - 1))"
				shift
			done
			spare_devs=
			for raidid in $(echo "$raidids" | sort -u); do
				spare_devs="${spare_devs:+$spare_devs#}raidid=$raidid"
			done
			if [ "$spare_devs" ]; then
				raid_new_recipe="${raid_new_recipe:+$raid_new_recipe }$spare_devs"
			fi

			while [ "$1" ] && [ "$1" != . ]; do
				shift
			done
			raid_new_recipe="${raid_new_recipe:+$raid_new_recipe }."
			shift
		done
		raid_recipe="$raid_new_recipe"

		ks_preseed d-i partman-auto/method string raid
		ks_preseed d-i partman-auto-raid/recipe "$raid_recipe"
	fi
}

register_final raid_final
