#! /bin/sh

partition_recipe=
partition_pending_lvm_recipe=
partition_leave_free_space=1
partition_raid=
partition_final_done=

partition_recipe_append () {
	if [ -z "$partition_recipe" ]; then
		partition_recipe='Kickstart-supplied partitioning scheme :'
	fi

	partition_recipe="$partition_recipe $1 ."
}

partition_handler () {
	recommended=
	size=
	grow=
	maxsize=
	format=1
	asprimary=
	fstype=
	ondisk=

	eval set -- "$(getopt -o '' -l recommended,size:,grow,maxsize:,noformat,onpart:,usepart:,ondisk:,ondrive:,asprimary,fstype:,start:,end: -- "$@")" || { warn_getopt partition; return; }
	while :; do
		case $1 in
			--recommended)
				# Apparently only used for swap, but
				# Anaconda doesn't error if you try to use
				# it for something else, so we won't either.
				recommended=1
				shift
				;;
			--size)
				size="$2"
				shift 2
				;;
			--grow)
				grow=1
				shift
				;;
			--maxsize)
				maxsize="$2"
				shift 2
				;;
			--noformat)
				format=
				shift
				;;
			--asprimary)
				asprimary=1
				shift
				;;
			--fstype)
				fstype="$2"
				shift 2
				;;
			--onpart|--usepart|--start|--end)
				warn "unsupported restriction '$1'"
				shift 2
				;;
			--ondisk|--ondrive)
				ondisk="${2#/dev/}"
				shift 2
				;;
			--)	shift; break ;;
			*)	warn_getopt partition; return ;;
		esac
	done

	if [ $# -ne 1 ]; then
		warn "partition command requires a mountpoint"
		return
	fi
	mountpoint="$1"

	parttype=normal
	case $mountpoint in
		swap)
			filesystem=linux-swap
			mountpoint=
			;;
		pv.*)
			# LVM physical volume
			parttype=lvm
			pvname="$mountpoint"
			format=
			if [ "$fstype" ]; then
				filesystem="$fstype"
			else
				filesystem=ext3
			fi
			mountpoint=
			;;
		raid.*)
			# RAID physical volume
			parttype=raid
			raidname="$mountpoint"
			format=
			if [ "$fstype" ]; then
				filesystem="$fstype"
			else
				filesystem=ext3
			fi
			mountpoint=
			;;
		*)
			if [ "$fstype" ]; then
				filesystem="$fstype"
			else
				filesystem=ext3
			fi
			;;
	esac

	if [ "$parttype" != raid ] && [ "$ondisk" ]; then
		# TODO: --ondisk/--ondrive supported with LVM too
		warn "unsupported restriction 'ondisk' for non-RAID"
		return
	fi
	if [ "$parttype" = raid ] && [ -z "$ondisk" ]; then
		warn "RAID partitioning requires --ondisk"
		return
	fi

	if [ "$filesystem" = linux-swap ] && [ "$recommended" ]; then
		size=96
		priority=512
		maxsize=300%
		partition_leave_free_space=
	else
		if [ -z "$size" ]; then
			warn "partition command requires a size"
			return
		fi
		if [ "$grow" ]; then
			partition_leave_free_space=
			if [ -z "$maxsize" ]; then
				priority=$((1024 * 1024 * 1024))
				# requires partman-auto 84, partman-auto-lvm 32
				maxsize=-1
			else
				priority="$maxsize"
			fi
		else
			maxsize="$size"
			priority="$size"
		fi
	fi
	new_recipe="$size $priority $maxsize $filesystem"

	if [ "$asprimary" ]; then
		new_recipe="$new_recipe \$primary{ }"
	fi

	if [ "$parttype" = lvm ]; then
		new_recipe="$new_recipe \$defaultignore{ } method{ lvm }"
	elif [ "$parttype" = raid ]; then
		new_recipe="$new_recipe \$lvmignore{ } method{ raid } \$raidname{ $raidname }"
	elif [ "$filesystem" = linux-swap ]; then
		new_recipe="$new_recipe method{ swap }"
	elif [ "$format" ]; then
		new_recipe="$new_recipe method{ format }"
	else
		new_recipe="$new_recipe method{ keep }"
	fi

	if [ "$format" ]; then
		new_recipe="$new_recipe format{ }"
	fi

	if [ "$parttype" = normal ] && [ "$filesystem" != linux-swap ]; then
		new_recipe="$new_recipe use_filesystem{ }"
		new_recipe="$new_recipe filesystem{ $filesystem }"
	fi

	if [ "$mountpoint" ]; then
		new_recipe="$new_recipe mountpoint{ $mountpoint }"
	fi

	case $parttype in
		normal)
			partition_recipe_append "$new_recipe"
			;;
		lvm)
			partition_pending_lvm_recipe="$partition_pending_lvm_recipe $new_recipe \$pending_lvm{ $pvname } ."
			;;
		raid)
			echo "$new_recipe" >>"$SPOOL/parse/partition.raid.$ondisk"
			partition_recipe_append "$new_recipe \$raid_ondisk{ $ondisk }"
			partition_raid=1
			;;
	esac
}

part_handler () {
	partition_handler "$@"
}

partition_final () {
	# guard so that raid_final can make sure we've been run
	[ -z "$partition_final_done" ] || return

	if [ "$partition_raid" ]; then
		compare=
		for file in "$SPOOL/parse/partition.raid".*; do
			[ -f "$file" ] || continue
			recipe="$(sed 's/ \$raidname{ [^}]* }//' "$file")"
			raidnames=
			for raidname in $(sed -n 's/.* \$raidname{ \([^}]*\) }.*/\1/p' "$file"); do
				raidnames="${raidnames:+$raidnames }$raidname"
			done
			if [ "$compare" ]; then
				if [ "$recipe" != "$compare" ]; then
					warn "RAID recipes for each disk must be identical: '$recipe' != '$compare'"
					return
				fi
			else
				compare="$recipe"
				want_ondisk="${file#$SPOOL/parse/partition.raid.}"
				primary_raidnames="$raidnames"
			fi
			for primary_raidname in $primary_raidnames; do
				echo "${raidnames%% *}" >>"$SPOOL/parse/partition.raidnames.$primary_raidname"
				raidnames="${raidnames#* }"
			done
		done

		# leave only one "ondisk" set, but preserve the ordering
		partition_new_recipe=
		set -- $partition_recipe
		got_ondisk=
		got_raidname=
		raidid=1
		line=
		rest=
		while [ "$1" ]; do
			case $1 in
				\$raidname{)
					shift
					got_raidname="$1"
					shift
					;;
				\$raid_ondisk{)
					shift
					got_ondisk="$1"
					shift
					;;
				.)
					if [ -z "$got_ondisk" ] || [ "$want_ondisk" = "$got_ondisk" ]; then
						if [ "$got_raidname" ]; then
							line="${line:+$line }raidid{ $raidid }"
							for raidname in $(cat "$SPOOL/parse/partition.raidnames.$got_raidname"); do
								echo "$raidid" >>"$SPOOL/parse/partition.raididmap.$raidname"
							done
							raidid="$(($raidid + 1))"
						fi
						partition_new_recipe="${partition_new_recipe:+$partition_new_recipe }$line ."
					fi
					line=
					got_raidname=
					got_ondisk=
					;;
				*)
					line="${line:+$line }$1"
					;;
			esac
			shift
		done
		partition_recipe="$partition_new_recipe"
	fi

	if [ "$partition_recipe" ]; then
		if [ "$partition_leave_free_space" ]; then
			# This doesn't quite work; it leaves a dummy
			# partition at the end of the disk. Bug filed on
			# partman-auto.
			bignum=$((1024 * 1024 * 1024))
			# requires partman-auto 84, partman-auto-lvm 32
			partition_recipe="$partition_recipe 0 $bignum -1 free ."
		fi
		ks_preseed d-i partman-auto/expert_recipe string \
			"$partition_recipe"
		ks_preseed d-i partman/choose_partition string \
			'Finish partitioning and write changes to disk'
		ks_preseed d-i partman/confirm boolean true
		ks_preseed d-i partman/confirm_nooverwrite boolean true
	fi

	partition_final_done=1
}

register_final partition_final
