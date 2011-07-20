#! /bin/sh

iscsi_handler () {
	ipaddr=
	port=
	user=
	password=
	reverse_user=
	reverse_password=

	eval set -- "$(getopt -o '' -l ipaddr:,target:,port:,user:,password:,reverse-user:,reverse-password: -- "$@")" || { warn_getopt iscsi; return; }
	while :; do
		case $1 in
			--ipaddr)
				ipaddr="$2"
				shift 2
				;;
			--target)
				# TODO: this doesn't appear to do anything
				# in Anaconda?
				shift 2
				;;
			--port)
				port="$2"
				shift 2
				;;
			--user)
				user="$2"
				shift 2
				;;
			--password)
				password="$2"
				shift 2
				;;
			--reverse-user)
				reverse_user="$2"
				shift 2
				;;
			--reverse-password)
				reverse_password="$2"
				shift 2
				;;
			--)	shift; break ;;
			*)	warn_getopt iscsi; return ;;
		esac
	done

	bad_options=
	if [ -z "$ipaddr" ]; then
		warn "iscsi command requires --ipaddr"
		bad_options=1
	fi
	if [ "$user" ]; then
		if [ -z "$password" ]; then
			warn "iscsi --user requires --password as well"
			bad_options=1
		fi
	fi
	if [ "$reverse_user" ]; then
		if [ -z "$reverse_password" ]; then
			warn "iscsi --reverse-user requires --reverse-password as well"
			bad_options=1
		fi
		if [ -z "$user" ]; then
			warn "iscsi --reverse-user requires --user as well"
			bad_options=1
		fi
	fi
	if [ "$bad_options" ]; then
		return
	fi

	ks_preseed d-i partman-iscsi/login/address string "$ipaddr${port:+:$port}"
	if [ "$user" ]; then
		ks_preseed d-i partman-iscsi/login/username string "$user"
		ks_preseed d-i partman-iscsi/login/password password "$password"
		if [ "$reverse_user" ]; then
			ks_preseed d-i partman-iscsi/login/incoming_username string "$reverse_user"
			ks_preseed d-i partman-iscsi/login/incoming_password password "$reverse_password"
		fi
	fi
	ks_preseed d-i partman-iscsi/login/all_targets boolean true
}
