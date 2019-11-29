#!/bin/bash
# LinuxGSM command_stop.sh function
# Author: Daniel Gibbs
# Contributors: UltimateByte
# Website: https://linuxgsm.com
# Description: Stops the server.

local commandname="STOP"
local commandaction="Stopping"
local function_selfname="$(basename "$(readlink -f "${BASH_SOURCE[0]}")")"

# Attempts graceful shutdown by sending 'CTRL+c'.
fn_stop_graceful_ctrlc(){
	fn_print_dots "Graceful: CTRL+c"
	fn_script_log_info "Graceful: CTRL+c"
	# Sends quit.
	tmux send-keys -t "${servicename}" C-c  > /dev/null 2>&1
	# Waits up to 30 seconds giving the server time to shutdown gracefuly.
	for seconds in {1..30}; do
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok "Graceful: CTRL+c: ${seconds}: "
			fn_print_ok_eol_nl
			fn_script_log_pass "Graceful: CTRL+c: OK: ${seconds} seconds"
			break
		fi
		sleep 1
		fn_print_dots "Graceful: CTRL+c: ${seconds}"
	done
	check_status.sh
	if [ "${status}" != "0" ]; then
		fn_print_error "Graceful: CTRL+c: "
		fn_print_fail_eol_nl
		fn_script_log_error "Graceful: CTRL+c: FAIL"
	fi
	fn_sleep_time
}

# Attempts graceful shutdown by sending a specified command.
# Usage: fn_stop_graceful_cmd "console_command" "timeout_in_seconds"
# e.g.: fn_stop_graceful_cmd "quit" "30"
fn_stop_graceful_cmd(){
	fn_print_dots "Graceful: sending \"${1}\""
	fn_script_log_info "Graceful: sending \"${1}\""
	# Sends specific stop command.
	tmux send -t "${servicename}" "${1}" ENTER > /dev/null 2>&1
	# Waits up to ${seconds} seconds giving the server time to shutdown gracefully.
	for ((seconds=1; seconds<=${2}; seconds++)); do
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok "Graceful: sending \"${1}\": ${seconds}: "
			fn_print_ok_eol_nl
			fn_script_log_pass "Graceful: sending \"${1}\": OK: ${seconds} seconds"
			break
		fi
		sleep 1
		fn_print_dots "Graceful: sending \"${1}\": ${seconds}"
	done
	check_status.sh
	if [ "${status}" != "0" ]; then
		fn_print_error "Graceful: sending \"${1}\": "
		fn_print_fail_eol_nl
		fn_script_log_error "Graceful: sending \"${1}\": FAIL"
	fi
	fn_sleep_time
}

# Attempts graceful shutdown of goldsource using rcon 'quit' command.
# There is only a 3 second delay before a forced a tmux shutdown
# as Goldsource servers 'quit' command does a restart rather than shutdown.
fn_stop_graceful_goldsource(){
	fn_print_dots "Graceful: sending \"quit\""
	fn_script_log_info "Graceful: sending \"quit\""
	# sends quit
	tmux send -t "${servicename}" quit ENTER > /dev/null 2>&1
	# Waits 3 seconds as goldsource servers restart with the quit command.
	for seconds in {1..3}; do
		sleep 1
		fn_print_dots "Graceful: sending \"quit\": ${seconds}"
	done
	fn_print_ok "Graceful: sending \"quit\": ${seconds}: "
	fn_print_ok_eol_nl
	fn_script_log_pass "Graceful: sending \"quit\": OK: ${seconds} seconds"
}

# telnet command for sdtd graceful shutdown.
fn_stop_graceful_sdtd_telnet(){
	if [ -z "${telnetpass}" ]||[ "${telnetpass}" == "NOT SET" ]; then
		sdtd_telnet_shutdown=$( expect -c '
		proc abort {} {
			puts "Timeout or EOF\n"
			exit 1
		}
		spawn telnet '"${telnetip}"' '"${telnetport}"'
		expect {
			"session."  { send "shutdown\r" }
			default         abort
		}
		expect { eof }
		puts "Completed.\n"
		')
	else
		sdtd_telnet_shutdown=$( expect -c '
		proc abort {} {
			puts "Timeout or EOF\n"
			exit 1
		}
		spawn telnet '"${telnetip}"' '"${telnetport}"'
		expect {
			"password:"     { send "'"${telnetpass}"'\r" }
			default         abort
		}
		expect {
			"session."  { send "shutdown\r" }
			default         abort
		}
		expect { eof }
		puts "Completed.\n"
		')
	fi
}

# Attempts graceful shutdown of 7 Days To Die using telnet.
fn_stop_graceful_sdtd(){
	fn_print_dots "Graceful: telnet"
	fn_script_log_info "Graceful: telnet"
	if [ "${telnetenabled}" == "false" ]; then
		fn_print_info_nl "Graceful: telnet: DISABLED: Enable in ${servercfg}"
	elif [ "$(command -v expect 2>/dev/null)" ]; then
		# Tries to shutdown with both localhost and server IP.
		for telnetip in 127.0.0.1 ${ip}; do
			fn_print_dots "Graceful: telnet: ${telnetip}:${telnetport}"
			fn_script_log_info "Graceful: telnet: ${telnetip}:${telnetport}"
			fn_stop_graceful_sdtd_telnet
			completed=$(echo -en "\n ${sdtd_telnet_shutdown}" | grep "Completed.")
			refused=$(echo -en "\n ${sdtd_telnet_shutdown}" | grep "Timeout or EOF")
			if [ -n "${refused}" ]; then
				fn_print_error "Graceful: telnet: ${telnetip}:${telnetport} : "
				fn_print_fail_eol_nl
				fn_script_log_error "Graceful: telnet:  ${telnetip}:${telnetport} : FAIL"
			elif [ -n "${completed}" ]; then
				break
			fi
		done

		# If telnet shutdown was successful will use telnet again to check
		# the connection has closed, confirming that the tmux session can now be killed.
		if [ -n "${completed}" ]; then
			for seconds in {1..30}; do
				fn_stop_graceful_sdtd_telnet
				refused=$(echo -en "\n ${sdtd_telnet_shutdown}" | grep "Timeout or EOF")
				if [ -n "${refused}" ]; then
					fn_print_ok "Graceful: telnet: ${telnetip}:${telnetport} : "
					fn_print_ok_eol_nl
					fn_script_log_pass "Graceful: telnet: ${telnetip}:${telnetport} : ${seconds} seconds"
					break
				fi
				sleep 1
				fn_print_dots "Graceful: telnet: ${seconds}"
			done
		# If telnet shutdown fails tmux shutdown will be used, this risks loss of world save.
		else
			if [ -n "${refused}" ]; then
				fn_print_error "Graceful: telnet: "
				fn_print_fail_eol_nl
				fn_script_log_error "Graceful: telnet: ${telnetip}:${telnetport} : FAIL"
			else
				fn_print_error_nl "Graceful: telnet: Unknown error"
				fn_script_log_error "Graceful: telnet: Unknown error"
			fi
			echo -en "\n" | tee -a "${lgsmlog}"
			echo -en "Telnet output:" | tee -a "${lgsmlog}"
			echo -en "\n ${sdtd_telnet_shutdown}" | tee -a "${lgsmlog}"
			echo -en "\n\n" | tee -a "${lgsmlog}"
		fi
	else
		fn_print_warn "Graceful: telnet: expect not installed: "
		fn_print_fail_eol_nl
		fn_script_log_warn "Graceful: telnet: expect not installed: FAIL"
	fi
	fn_sleep_time
}

# Attempts graceful shutdown of Rust server using 'quit' command via websocket rcon.
# This method requires websocat pre-installed on system
# https://github.com/vi/websocat#installation
fn_send_webrcon_cmd(){
	echo "{\"Identifier\":-1,\"Message\":\"${1}\",\"Name\":\"webrcon\"}" | websocat ws://$ip:$rconport/$rconpassword -1 > /dev/null 2>&1
}

fn_stop_graceful_webrcon(){
	# sends notice messages
	for ((seconds=${1}; seconds >= 1; seconds--)); do
		if [ "$(($seconds % 10))" == "0" ]; then
			fn_send_webrcon_cmd "say Server will go down for maintenance in ${seconds} seconds"
		fi
		fn_print_dots "Graceful: Stopping in ${seconds}"
		sleep 1
	done
	fn_send_webrcon_cmd "say Maintenance is in progress"

	fn_print_dots "Graceful: sending \"quit\""
	fn_script_log_info "Graceful: sending \"quit\""
	#fn_send_webrcon_cmd "quit"
	# Waits up to 10 seconds giving the server time to shutdown gracefully.
	for ((seconds=1; seconds<=10; seconds++)); do
		check_status.sh
		if [ "${status}" == "0" ]; then
			fn_print_ok "Graceful: sending \"quit\": ${seconds}: "
			fn_print_ok_eol_nl
			fn_script_log_pass "Graceful: sending \"quit\": OK: ${seconds} seconds"
			break
		fi
		sleep 1
		fn_print_dots "Graceful: sending \"quit\": ${seconds}"
	done
	check_status.sh
	if [ "${status}" != "0" ]; then
		fn_print_error "Graceful: sending \"quit\": "
		fn_print_fail_eol_nl
		fn_script_log_error "Graceful: sending \"quit\": FAIL"
	fi
	fn_sleep_time
}


fn_stop_graceful_select(){
	if [ "${stopmode}" == "1" ]; then
		fn_stop_tmux
	elif [ "${stopmode}" == "2" ]; then
		fn_stop_graceful_ctrlc
	elif [ "${stopmode}" == "3" ]; then
		fn_stop_graceful_cmd "quit" 30
	elif [ "${stopmode}" == "4" ]; then
		fn_stop_graceful_cmd "quit" 120
	elif [ "${stopmode}" == "5" ]; then
		fn_stop_graceful_cmd "stop" 30
	elif [ "${stopmode}" == "6" ]; then
		fn_stop_graceful_cmd "q" 30
	elif [ "${stopmode}" == "7" ]; then
		fn_stop_graceful_cmd "exit" 30
	elif [ "${stopmode}" == "8" ]; then
		fn_stop_graceful_sdtd
	elif [ "${stopmode}" == "9" ]; then
		fn_stop_graceful_goldsource
	elif [ "${stopmode}" == "10" ]; then
		fn_stop_teamspeak3
	elif [ "${stopmode}" == "11" ]; then
		fn_stop_graceful_webrcon 300
	fi
}

fn_stop_teamspeak3(){
	fn_print_dots "${servername}"
	"${serverfiles}"/ts3server_startscript.sh stop > /dev/null 2>&1
	check_status.sh
	if [ "${status}" == "0" ]; then
		rm -f "${rootdir}/${lockselfname}"
		fn_print_ok_nl "${servername}"
		fn_script_log_pass "Stopped ${servername}"
	else
		fn_print_fail_nl "Unable to stop ${servername}"
		fn_script_log_error "Unable to stop ${servername}"
	fi
}

fn_stop_tmux(){
	fn_print_dots "${servername}"
	fn_script_log_info "tmux kill-session: ${servername}"
	# Kill tmux session.
	tmux kill-session -t "${servicename}" > /dev/null 2>&1
	fn_sleep_time
	check_status.sh
	if [ "${status}" == "0" ]; then
		fn_print_ok_nl "${servername}"
		fn_script_log_pass "Stopped ${servername}"
	else
		fn_print_fail_nl "Unable to stop ${servername}"
		fn_script_log_fatal "Unable to stop ${servername}"
	fi
}

# Checks if the server is already stopped.
fn_stop_pre_check(){
	if [ "${status}" == "0" ]; then
		fn_print_info_nl "${servername} is already stopped"
		fn_script_log_error "${servername} is already stopped"
	elif [ "${shortname}" == "ts3" ]; then
		fn_stop_teamspeak3
	else
		# Select graceful shutdown.
		fn_stop_graceful_select
	fi
	# Check status again, a kill tmux session if graceful shutdown failed.
	check_status.sh
	if [ "${status}" != "0" ]; then
		fn_stop_tmux
	fi
}

fn_print_dots "${servername}"
check.sh
info_config.sh
fn_stop_pre_check
# Remove lockfile.
if [ -f "${rootdir}/${lockselfname}" ]; then
	rm -f "${rootdir}/${lockselfname}"
fi
if [ -z "${exitbypass}" ]; then
	core_exit.sh
fi
