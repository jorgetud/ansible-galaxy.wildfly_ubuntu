#!/bin/sh
#
# /etc/init.d/wildfly -- startup script for WildFly
#
# Written by Jorge Solorzano
#
### BEGIN INIT INFO
# Provides:             wildfly
# Required-Start:       $remote_fs $network
# Required-Stop:        $remote_fs $network
# Should-Start:         $named
# Should-Stop:          $named
# Default-Start:        2 3 4 5
# Default-Stop:         0 1 6
# Short-Description:    WildFly Application Server
# Description:          Provide WildFly startup/shutdown script
### END INIT INFO

NAME=wildfly
DESC="WildFly Application Server"
DEFAULT="/etc/default/$NAME"

# Check privileges
if [ `id -u` -ne 0 ]; then
	echo "You need root privileges to run this script"
	exit 1
fi

# Make sure wildfly is started with system locale
if [ -r /etc/default/locale ]; then
	. /etc/default/locale
	export LANG
fi

. /lib/lsb/init-functions

if [ -r /etc/default/rcS ]; then
	. /etc/default/rcS
fi

# Overwrite settings from default file
if [ -f "$DEFAULT" ]; then
	. "$DEFAULT"
fi

# Location of JDK
if [ -n "$JAVA_HOME" ]; then
	export JAVA_HOME
fi

# Setup the JVM
if [ -z "$JAVA" ]; then
	if [ -n "$JAVA_HOME" ]; then
		JAVA="$JAVA_HOME/bin/java"
	else
		JAVA="java"
	fi
fi

# Location of wildfly
if [ -z "$WILDFLY_HOME" ]; then
	WILDFLY_HOME="{{wildfly_home}}"
fi
export WILDFLY_HOME

# Check if wildfly is installed
if [ ! -f "$WILDFLY_HOME/jboss-modules.jar" ]; then
	log_failure_msg "$NAME is not installed in \"$WILDFLY_HOME\""
	exit 1
fi

# Run as wildfly user
# Example of user creation for Debian based:
# adduser --system --group --no-create-home --home $WILDFLY_HOME --disabled-login wildfly
if [ -z "$WILDFLY_USER" ]; then
	WILDFLY_USER="{{wildfly_user}}"
fi

# Check wildfly user
id $WILDFLY_USER > /dev/null 2>&1
if [ $? -ne 0 -o -z "$WILDFLY_USER" ]; then
	log_failure_msg "User \"$WILDFLY_USER\" does not exist..."
	exit 1
fi

# Check owner of WILDFLY_HOME
if [ ! $(stat -L -c "%U" "$WILDFLY_HOME") = $WILDFLY_USER ]; then
	log_failure_msg "The user \"$WILDFLY_USER\" is not owner of \"$WILDFLY_HOME\""
	exit 1
fi

# Startup mode of wildfly
if [ -z "$WILDFLY_MODE" ]; then
	WILDFLY_MODE=standalone
fi

# Startup mode script
if [ "$WILDFLY_MODE" = "standalone" ]; then
	WILDFLY_SCRIPT="$WILDFLY_HOME/bin/standalone.sh"
	if [ -z "$WILDFLY_CONFIG" ]; then
		WILDFLY_CONFIG=standalone.xml
	fi
else
	WILDFLY_SCRIPT="$WILDFLY_HOME/bin/domain.sh"
	if [ -z "$WILDFLY_DOMAIN_CONFIG" ]; then
		WILDFLY_DOMAIN_CONFIG=domain.xml
	fi
	if [ -z "$WILDFLY_HOST_CONFIG" ]; then
		WILDFLY_HOST_CONFIG=host.xml
	fi
fi

# Check startup file
if [ ! -x "$WILDFLY_SCRIPT" ]; then
	log_failure_msg "$WILDFLY_SCRIPT is not an executable!"
	exit 1
fi

# Check cli file
WILDFLY_CLI="$WILDFLY_HOME/bin/jboss-cli.sh"
if [ ! -x "$WILDFLY_CLI" ]; then
	log_failure_msg "$WILDFLY_CLI is not an executable!"
	exit 1
fi

# The amount of time to wait for startup
if [ -z "$STARTUP_WAIT" ]; then
	STARTUP_WAIT=30
fi

# The amount of time to wait for shutdown
if [ -z "$SHUTDOWN_WAIT" ]; then
	SHUTDOWN_WAIT=30
fi

# Location to keep the console log
if [ -z "$WILDFLY_CONSOLE_LOG" ]; then
	WILDFLY_CONSOLE_LOG="/var/log/$NAME/console.log"
fi
export WILDFLY_CONSOLE_LOG

# Location to set the pid file
WILDFLY_PIDFILE="/var/run/$NAME/$NAME.pid"
export WILDFLY_PIDFILE

# Launch wildfly in background
LAUNCH_WILDFLY_IN_BACKGROUND=1
export LAUNCH_WILDFLY_IN_BACKGROUND

# Helper function to check status of wildfly service
check_status() {
	pidofproc -p "$WILDFLY_PIDFILE" "$JAVA" >/dev/null 2>&1
}

case "$1" in
 start)
	log_daemon_msg "Starting $DESC" "$NAME"
	check_status
	status_start=$?
	if [ $status_start -eq 3 ]; then
		mkdir -p $(dirname "$WILDFLY_PIDFILE")
		mkdir -p $(dirname "$WILDFLY_CONSOLE_LOG")
		chown $WILDFLY_USER $(dirname "$WILDFLY_PIDFILE") || true
		cat /dev/null > "$WILDFLY_CONSOLE_LOG"

		if [ "$WILDFLY_MODE" = "standalone" ]; then
			start-stop-daemon --start --user "$WILDFLY_USER" \
			--chuid "$WILDFLY_USER" --chdir "$WILDFLY_HOME" --pidfile "$WILDFLY_PIDFILE" \
			--exec "$WILDFLY_SCRIPT" -- -c $WILDFLY_CONFIG >> "$WILDFLY_CONSOLE_LOG" 2>&1 &
		else
			start-stop-daemon --start --user "$WILDFLY_USER" \
			--chuid "$WILDFLY_USER" --chdir "$WILDFLY_HOME" --pidfile "$WILDFLY_PIDFILE" \
			--exec "$WILDFLY_SCRIPT" -- --domain-config=$WILDFLY_DOMAIN_CONFIG \
			--host-config=$WILDFLY_HOST_CONFIG >> "$WILDFLY_CONSOLE_LOG" 2>&1 &
		fi

		count=0
		launched=0
		until [ $count -gt $STARTUP_WAIT ]
		do
			grep 'JBAS015874:' "$WILDFLY_CONSOLE_LOG" > /dev/null
			if [ $? -eq 0 ] ; then
				launched=1
				break
			fi
			sleep 1
			count=$((count + 1));
		done

		if check_status; then
			log_end_msg 0
		else
			log_end_msg 1
		fi

		if [ $launched -eq 0 ]; then
			log_warning_msg "$DESC hasn't started within the timeout allowed"
			log_warning_msg "please review file \"$WILDFLY_CONSOLE_LOG\" to see the status of the service"
		fi
	elif [ $status_start -eq 1 ]; then
		log_failure_msg "$DESC is not running but the pid file exists"
		exit 1
	elif [ $status_start -eq 0 ]; then
		log_success_msg "$DESC (already running)"
	fi
 ;;
 stop)
	check_status
	status_stop=$?
	if [ $status_stop -eq 0 ]; then
		read kpid < "$WILDFLY_PIDFILE"
		log_daemon_msg "Stopping $DESC" "$NAME"

		start-stop-daemon --start --chuid "$WILDFLY_USER" \
		--exec "$WILDFLY_CLI" -- --connect --command=:shutdown \
		>/dev/null 2>&1

		if [ $? -eq 1 ]; then
			kill -15 $kpid
		fi

		count=0
		until [ $count -gt $SHUTDOWN_WAIT ]
		do
			check_status
			if [ $? -eq 3 ]; then
				break
			fi
			sleep 1
			count=$((count + 1));
		done

		if [ $count -gt $SHUTDOWN_WAIT ]; then
			kill -9 $kpid
		fi
		
		log_end_msg 0
	elif [ $status_stop -eq 1 ]; then
		log_action_msg "$DESC is not running but the pid file exists, cleaning up"
		rm -f $WILDFLY_PIDFILE
	elif [ $status_stop -eq 3 ]; then
		log_action_msg "$DESC is not running"
	fi
 ;;
 restart)
	check_status
	status_restart=$?
	if [ $status_restart -eq 0 ]; then
		$0 stop
	fi
	$0 start
 ;;
 reload|force-reload)
	check_status
	status_reload=$?
	if [ $status_reload -eq 0 ]; then
		log_daemon_msg "Reloading $DESC config" "$NAME"

		if [ "$WILDFLY_MODE" = "standalone" ]; then
			RELOAD_CMD=":reload"; else
			RELOAD_CMD=":reload-servers"; fi

		start-stop-daemon --start --chuid "$WILDFLY_USER" \
		--exec "$WILDFLY_CLI" -- --connect --command=$RELOAD_CMD >/dev/null 2>&1

		if [ $? -eq 0 ]; then
			log_end_msg 0
		else
			log_end_msg 1
		fi
	else
		log_failure_msg "$DESC is not running"
	fi
 ;;
 status)
	check_status
	status=$?
	if [ $status -eq 0 ]; then
		read pid < $WILDFLY_PIDFILE
		log_action_msg "$DESC is running with pid $pid"
		exit 0
	elif [ $status -eq 1 ]; then
		log_action_msg "$DESC is not running and the pid file exists"
		exit 1
	elif [ $status -eq 3 ]; then
		log_action_msg "$DESC is not running"
		exit 3
	else
		log_action_msg "Unable to determine $NAME status"
		exit 4
	fi
 ;;
 *)
 log_action_msg "Usage: $0 {start|stop|restart|reload|force-reload|status}"
 exit 2
 ;;
esac

exit 0
