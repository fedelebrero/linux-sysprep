#!/bin/sh
# sysprep.sh - Prepare machine for use as template
#
# This script was designed to be compatible with all Linux systems with a
# GNU-based userspace, but was only tested on RHEL7
#
usage() {
	cat 1>&2 <<EOF
Usage $0 [OPTIONS]
Prepare system for use as template.

  -f            Actually do something, don't just say it
  -h            Print this help message
EOF
}

verbose() {
    echo "$@"
}

do_cmd() {
    verbose "    [ $@ (noop) ]"
}

really_do_cmd() {
    verbose "    [ $@ ]"
    cmd="$1"
    shift
    $cmd "$@"
}

main() {
    parse_args "$@"
    remove_rhn_id
    remove_unwanted_pkgs
    stop_services
    remove_ssh_keys
    remove_net_identifiers
    remove_net_persistent
    remove_hostname
    remove_machine_id
    build_generic_initrd
    force_logrotate
    remove_tmpfiles
    clean_logs
    remove_history
}

parse_args() {
    while getopts 'fh' opt; do
        case "$opt" in
        f)
            do_cmd() {
                really_do_cmd "$@"
            }
            ;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
        esac	
    done
}

stop_services() {
    verbose 'Stopping services'
        do_cmd service rsyslog stop
        do_cmd service auditd stop
}

remove_rhn_id() {
    local rhn_id='/etc/sysconfig/rhn/systemid'
    [[ -x "$rhn_id" ]] || return
    verbose 'Revoming RHN system ID'
    do_cmd rm -f "$rhn_id"
}

remove_unwanted_pkgs() {
    verbose 'Removing net identifiers'
        do_cmd package-cleanup --oldkernels --count=1 -y
}

remove_ssh_keys() {
    verbose 'Removing ssh keys'
    for key in /etc/ssh/ssh_host_*; do 
        [ -f "$key" ] || continue
        verbose "- $key"
        do_cmd rm -f "$key"
    done
    do_cmd rm -rf "/root/.ssh/"
    do_cmd rm -f "/root/anaconda-ks.cfg"
}

remove_net_identifiers() {
    verbose 'Removing net identifiers'
        do_cmd sed -i '/^(HWADDR|UUID)=/d' /etc/sysconfig/network-scripts/ifcfg-e*
}

remove_net_persistent() {
    rules='/etc/udev/rules.d/70*'
    [ -f "$rules" ] || return
    verbose 'Removing persistent net UDEV rules'
    do_cmd rm -f "$rules"
}

remove_hostname() {
    verbose 'Removing fixed hostname'
    do_cmd rm -f '/etc/hostname'
}

remove_machine_id() {
    local machine_id='/etc/machine-id'
    [[ -r "$machine_id" ]] || return
    # If the system is setup woth a machine-id bind-mounted from a tempfs, we
    # can't and don't need to empty it
    grep -qF "$machine_id" /proc/mounts && return
    verbose 'Removing machine-id'
    do_cmd write_file "$machine_id" < /dev/null
}

build_generic_initrd() {
    [[ -x '/sbin/dracut' ]] || return
    verbose 'Building a generic initrd image'
    verbose '- This may take a while...'
    do_cmd dracut --no-hostonly --force
    verbose '- done!'
}

force_logrotate() {
    verbose 'Rotating logs'
    logrotatecfg='/etc/logrotate.conf'
    [ -f "$logrotatecfg" ] || return
    do_cmd /usr/sbin/logrotate –f "$logrotatecfg"
}

clean_logs() {
    verbose 'Cleaning up logfiles'
    find /var/log -type f | while read log; do
        [ -f "$log" ] || continue
        verbose "- $log"
        do_cmd rm -f "$log"
    done
}

remove_tmpfiles() {
    verbose 'Removing tmp files'
        do_cmd rm -rf "/tmp/*"
        do_cmd rm -rf "/var/tmp/*"
}

remove_history() {
    verbose 'Removing bash history'
        do_cmd rm -f "/root/.bash_history"
        do_cmd unset HISTFILE
        do_cmd history –c all
}


write_file() {
    cat > "$1"
}

main "$@"
exit 0

