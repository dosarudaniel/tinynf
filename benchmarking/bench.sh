#!/bin/sh
# See ReadMe.md in this directory for documentation.

LOG_FILE='bench.log'
REMOTE_FOLDER_NAME='nf-benchmarking-scripts'

if [ -z "$1" ]; then
  echo "[ERROR] Please provide the directory of the NF as the first argument to $0"
  exit 1
fi
NF_DIR="$1"

shift
if [ $# -lt 2 ]; then
  echo "[ERROR] Please provide at least the type of benchmark and layer as arguments to $0"
  exit 1
fi

THIS_DIR="$(dirname "$(readlink -f "$0")")"

if [ ! -f "$THIS_DIR/config" ]; then
  echo "[ERROR] Please create a 'config' file from the 'config.template' file in the same directory as $0"
  exit 1
fi
. "$THIS_DIR/config"

echo '[bench] Setting up the benchmark...'

# Ensure there are no outdated (and thus misleading) results/logs
rm -rf results *.log

# Get NF name
NF_NAME="$(make -C "$NF_DIR" -s print-nf-name)" # -s to not print 'Entering directory...'

# Convenience function, now that we know what to clean up
cleanup() { sudo pkill -x -9 "$NF_NAME" >/dev/null 2>&1; }

# Kill the NF in case some old instance is still running
cleanup

# Delete any hugepages in case some program left them around
sudo rm -f "$(grep hugetlbfs /proc/mounts  | awk '{print $2}')"/*

# Initialize DPDK if needed, as explained in the script header
make -C "$NF_DIR" -q is-dpdk >/dev/null 2>&1
if [ $? -eq 2 ]; then
  ./unbind-devices.sh $DUT_DEVS
else
  ./bind-devices-to-uio.sh $DUT_DEVS
fi

git submodule update --init --recursive
if [ $? -ne 0 ]; then
  echo '[FATAL] Could not update submodules'
  exit 1
fi

rsync -a -q . "$TESTER_HOST:$REMOTE_FOLDER_NAME"
if [ $? -ne 0 ]; then
  echo '[FATAL] Could not copy scripts'
  exit 1
fi

echo '[bench] Building and running the NF...'

TN_ARGS="$DUT_DEVS" make -C "$NF_DIR" >"$LOG_FILE" 2>&1
if [ $? -ne 0 ]; then
  echo "[FATAL] Could not build; the $LOG_FILE file in the same directory as $0 may be useful"
  exit 1
fi

# Before running the NF, ensure we'll clean up even on Ctrl+C
trap_cleanup()
{
  echo '[bench] Ctrl+C detected, cleaning up'
  cleanup
  exit 1
}
trap 'trap_cleanup' 2

TN_ARGS="$DUT_DEVS" taskset -c "$DUT_CPUS" make -C "$NF_DIR" run >>"$LOG_FILE" 2>&1 &
# Sleep (as little as possible) if the NF needs a while to start
for i in $(seq 1 30); do
  sleep 1
  NF_PID="$(pgrep -x "$NF_NAME")"
  if [ ! -z "$NF_PID" ]; then
    break
  fi
done
if [ -z "$NF_PID" ]; then
  echo "[FATAL] Could not launch the NF; the $LOG_FILE file in the same directory as $0 may be useful"
  exit 1
fi

ssh "$TESTER_HOST" "cd $REMOTE_FOLDER_NAME; ./bench-tester.sh $@"
if [ $? -eq 0 ]; then
  scp -r "$TESTER_HOST:$REMOTE_FOLDER_NAME/results" . >/dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "[bench] Done! Results are in the results/ folder, and the log in $LOG_FILE, in the same directory as $0"
    RESULT=0
  else
    echo '[FATAL] Could not fetch result'
    RESULT=1
  fi
else
  echo '[FATAL] Run failed'
  RESULT=1
fi

# Ensure we always kill the NF at the end, even in cases of failure
cleanup

exit $RESULT
