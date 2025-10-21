#!/bin/bash

# Configuration
home_dir=$(dirname $(realpath "$0"))
server_name=$(hostname)
log_dir=${home_dir}/logs
lock_dir=${home_dir}/lock
lock_file=${lock_dir}/$(basename $0 .sh).pid
log_file=${log_dir}/shorts-maker.log

# Ensure directories exist
[[ -d ${log_dir} ]] || mkdir -p ${log_dir}
[[ -d ${lock_dir} ]] || mkdir -p ${lock_dir}

# Uvicorn configuration
UVICORN_HOST="0.0.0.0"
UVICORN_PORT="8000"
APP_MODULE="main:app"

function __check_port {
    local port=$1
    if lsof -Pi :${port} -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is available
    fi
}

function __kill_port {
    local port=$1
    echo "Checking for processes using port ${port}..."
    
    local pids=$(lsof -ti:${port} 2>/dev/null)
    
    if [ -z "${pids}" ]; then
        echo "No process found using port ${port}"
        return 0
    fi
    
    echo "Found processes using port ${port}: ${pids}"
    echo "Killing processes..."
    
    # Kill all processes using the port
    for pid in ${pids}; do
        echo "Killing process tree for PID: ${pid}"
        # Kill the process and all its children
        pkill -9 -P ${pid} 2>/dev/null
        kill -9 ${pid} 2>/dev/null
    done
    
    # Also kill any uvicorn processes
    pkill -9 -f "uvicorn.*${port}" 2>/dev/null
    
    sleep 2
    
    if __check_port ${port}; then
        echo "Failed to free port ${port}"
        return 1
    else
        echo "Port ${port} is now available"
        return 0
    fi
}

function __start {
    # Check if port is already in use
    if __check_port ${UVICORN_PORT}; then
        echo "Error: Port ${UVICORN_PORT} is already in use."
        echo "Run '$0 kill-port' or '$0 force-start' to resolve this."
        lsof -i :${UVICORN_PORT}
        return 1
    fi
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting uvicorn server..." | tee -a ${log_file}
    
    # Start uvicorn with process group creation
    # Use setsid to create a new session
    setsid uvicorn ${APP_MODULE} \
        --host ${UVICORN_HOST} \
        --port ${UVICORN_PORT} \
        --reload \
        >> ${log_file} 2>&1 &
    
    local pid=$!
    echo ${pid} > ${lock_file}
    
    # Wait and check if process is still running
    sleep 3
    if ps -p ${pid} > /dev/null 2>&1; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server started successfully (PID: ${pid})" | tee -a ${log_file}
        echo "Server is running at http://${UVICORN_HOST}:${UVICORN_PORT}"
        echo "Log file: ${log_file}"
        return 0
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Server failed to start. Check ${log_file}" >&2
        tail -20 ${log_file}
        rm -f ${lock_file}
        return 1
    fi
}

function __stop {
    local stopped=false
    
    # Try to stop using PID file
    if [ -f ${lock_file} ]; then
        local pid=$(cat ${lock_file})
        
        if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
            echo "Stopping server (PID: ${pid})..."
            
            # Get the process group ID
            local pgid=$(ps -o pgid= -p ${pid} | tr -d ' ')
            
            # Try graceful shutdown first (SIGTERM)
            kill -TERM -${pgid} 2>/dev/null || kill -TERM ${pid} 2>/dev/null
            
            # Wait up to 10 seconds
            local count=0
            while ps -p ${pid} > /dev/null 2>&1 && [ ${count} -lt 10 ]; do
                sleep 1
                count=$((count + 1))
                echo -n "."
            done
            echo ""
            
            # Force kill if still running
            if ps -p ${pid} > /dev/null 2>&1; then
                echo "Forcing shutdown..."
                kill -9 -${pgid} 2>/dev/null || kill -9 ${pid} 2>/dev/null
                # Kill all child processes
                pkill -9 -P ${pid} 2>/dev/null
                sleep 1
            fi
            
            if ! ps -p ${pid} > /dev/null 2>&1; then
                echo "Server stopped successfully."
                stopped=true
            fi
        fi
        
        rm -f ${lock_file}
    fi
    
    # Also check and clean up any processes on the port
    if __check_port ${UVICORN_PORT}; then
        echo "Port ${UVICORN_PORT} is still in use. Cleaning up..."
        __kill_port ${UVICORN_PORT}
        stopped=true
    fi
    
    if [ "$stopped" = false ]; then
        echo "Server was not running."
        return 1
    fi
    
    return 0
}

function __status {
    echo "=== Server Status ==="
    
    if [ -f ${lock_file} ]; then
        local pid=$(cat ${lock_file})
        
        if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
            echo "✓ Server is running (PID: ${pid})"
            echo ""
            ps -f -p ${pid}
            
            # Show child processes
            local children=$(pgrep -P ${pid})
            if [ -n "${children}" ]; then
                echo ""
                echo "Child processes:"
                ps -f -p ${children}
            fi
        else
            echo "✗ PID file exists, but process is not running."
        fi
    else
        echo "✗ Server is not running (no PID file)."
    fi
    
    echo ""
    echo "=== Port ${UVICORN_PORT} Status ==="
    if __check_port ${UVICORN_PORT}; then
        echo "⚠ Port ${UVICORN_PORT} is IN USE:"
        lsof -i :${UVICORN_PORT}
    else
        echo "✓ Port ${UVICORN_PORT} is available."
    fi
    
    echo ""
    echo "=== All uvicorn processes ==="
    local uvicorn_procs=$(pgrep -f uvicorn)
    if [ -n "${uvicorn_procs}" ]; then
        ps -f -p ${uvicorn_procs}
    else
        echo "No uvicorn processes found."
    fi
}

function __restart {
    echo "Restarting server..."
    __stop
    sleep 2
    __start
}

function __force_start {
    echo "Force starting server..."
    __stop
    sleep 2
    __start
}

function __cleanup {
    echo "Cleaning up all uvicorn processes and port ${UVICORN_PORT}..."
    
    # Kill all uvicorn processes
    pkill -9 -f uvicorn
    
    # Kill all processes on the port
    __kill_port ${UVICORN_PORT}
    
    # Remove PID file
    rm -f ${lock_file}
    
    echo "Cleanup completed."
}

# Main execution
case "$1" in
    start)
        if [ -f ${lock_file} ]; then
            local pid=$(cat ${lock_file})
            if [ -n "${pid}" ] && ps -p ${pid} > /dev/null 2>&1; then
                echo "Server is already running (PID: ${pid})."
                exit 1
            else
                echo "Stale PID file found. Removing..."
                rm -f ${lock_file}
            fi
        fi
        __start
        ;;
    
    stop)
        __stop
        ;;
    
    status)
        __status
        ;;
    
    restart)
        __restart
        ;;
    
    force-start)
        __force_start
        ;;
    
    kill-port)
        __kill_port ${UVICORN_PORT}
        ;;
    
    cleanup)
        __cleanup
        ;;
    
    *)
        echo "Usage: $0 {start|stop|restart|status|force-start|kill-port|cleanup}"
        echo ""
        echo "Commands:"
        echo "  start       - Start the server"
        echo "  stop        - Stop the server gracefully"
        echo "  restart     - Restart the server"
        echo "  status      - Show detailed status"
        echo "  force-start - Clean up and start fresh"
        echo "  kill-port   - Kill processes on port ${UVICORN_PORT}"
        echo "  cleanup     - Kill all uvicorn processes and clean up"
        exit 1
        ;;
esac

exit $?
