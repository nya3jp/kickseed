#! /bin/sh

iscsi_handler () {
	ipaddr=
	target=
	port=

	eval set -- "$(getopt -o '' -l ipaddr:,target:,port: -- "$@")" || { warn_getopt iscsi; return; }
	while :; do
		case $1 in
			--ipaddr)
				ipaddr="$2"
				shift 2
				;;
			--target)
				# TODO
				shift 2
				;;
			--port)
				port="$2"
				shift 2
				;;
			# TODO?
			--)	shift; break ;;
			*)	warn_getopt iscsi; return ;;
		esac
	done

	# TODO
}
