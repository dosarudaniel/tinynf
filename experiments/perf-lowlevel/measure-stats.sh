#!/bin/sh

TINYNF_DIR='../../code'
DPDK_DIR='../baselines/dpdk/measurable-nop'
EXTRACFLAGS=''
LAYER='2'
RESULTS_SUFFIX='/nop'

if [ "$1" = 'write' ]; then
  EXTRACFLAGS='-DTN_DEBUG_PERF_DOWRITE'
  RESULTS_SUFFIX='/write'
elif [ "$1" = 'lookup' ]; then
  EXTRACFLAGS='-DTN_DEBUG_PERF_DOLOOKUP'
  RESULTS_SUFFIX='/lookup'
elif [ "$1" = 'pol' ]; then
  TINYNF_DIR='../baselines/policer/tinynf'
  DPDK_DIR='../baselines/policer/dpdk'
  LAYER='3'
  RESULTS_SUFFIX='/pol'
  export EXPIRATION_TIME='4000000'
  export POLICER_BURST='1000000000000'
  export POLICER_RATE='1000000000000'
  export RTE_SDK="$(pwd)/../baselines/vigor/dpdk"
  export RTE_TARGET=x86_64-native-linuxapp-gcc
elif [ ! -z "$1" ]; then
  echo 'Unknown parameter.'
  exit 1
fi

echo 'Measuring low-level stats; this will take less than an hour...'


# Ensure the papi submodule is cloned
git submodule update --init --recursive

# Get the absolute path to papi, we'll use it when building and running things from other dirs
PAPI_DIR="$(readlink -e papi)"

# Build papi if needed, but don't install it, we just want a local version
cd "$PAPI_DIR/src"
  if [ ! -e "libpapi.so" ]; then
    # Allow external code to link with internal PAPI functions, see TinyNF's util/perf.h
    sed -i 's/LIBCFLAGS += -fvisibility=hidden//' Rules.pfm4_pe
    ./configure
    make
  fi
cd - >/dev/null

# Ensure papi can read events
echo 0 | sudo dd status=none of=/proc/sys/kernel/perf_event_paranoid

# Ensure the results folder is deleted so we don't accidentally end up with stale results
mkdir -p results
RESULTS_DIR="$(readlink -f results$RESULTS_SUFFIX)"
rm -rf "$RESULTS_DIR"

# Ensure there are no leftover hugepages
sudo rm -rf /dev/hugepages/*

# Load the benchmark config
if [ -f ../../benchmarking/config ]; then
  . ../../benchmarking/config
else
  echo 'Please successfully run a benchmark at least once before running this'
  exit 1
fi

# Start a packet flood, waiting for it to have really started
ssh "$TESTER_HOST" "cd $REMOTE_FOLDER_NAME; ./bench-tester.sh flood $LAYER" >/dev/null 2>&1 &
sleep 30

# assumes pwd is right
# $1: result folder name, e.g. TinyNF or DPDK-1
run_nf()
{
  i=0
  while [ $i -lt 10 ]; do
    # Remove output before the values themselves
    LD_LIBRARY_PATH="$PAPI_DIR/src" TN_ARGS="$DUT_DEVS" taskset -c "$DUT_CPUS" make -f "$BENCH_MAKEFILE_NAME" run 2>&1 | sed '0,/Counters:/d' >"$RESULTS_DIR/$1/log$i" &
    nf_name="$(make -f "$BENCH_MAKEFILE_NAME" print-nf-name)"
    # Wait 5 minutes max before retrying, but don't always wait 5min since that would take too long
    for t in $(seq 1 60); do
      sleep 5
      if ! pgrep -x "$nf_name" >/dev/null ; then
        break
      fi
    done
    if pgrep -x "$nf_name" >/dev/null ; then
      sudo pkill -x -9 "$nf_name"
    else
      i=$(echo "$i + 1" | bc)
    fi
  done
}

# Collect data on TinyNF
cd "$TINYNF_DIR"
  mkdir -p "$RESULTS_DIR/TinyNF"
  TN_DEBUG=0 TN_CFLAGS="$EXTRACFLAGS -DTN_DEBUG_PERF=10000000 -flto -s -I'$PAPI_DIR/src' -L'$PAPI_DIR/src' -lpapi" make -f "$BENCH_MAKEFILE_NAME" build
  run_nf 'TinyNF'
cd - >/dev/null

# Collect data on DPDK, without and with batching
cd "$DPDK_DIR"
  for batch in 1 32; do
    mkdir -p "$RESULTS_DIR/DPDK-$batch"
    TN_BATCH_SIZE=$batch EXTRA_CFLAGS="$EXTRACFLAGS -DTN_DEBUG_PERF=10000000 -I'$PAPI_DIR/src'" EXTRA_LDFLAGS="-L'$PAPI_DIR/src' -lpapi" make -f "$BENCH_MAKEFILE_NAME" build >/dev/null 2>&1
    ../../../../benchmarking/bind-devices-to-uio.sh $DUT_DEVS
    run_nf "DPDK-$batch"
  done
cd - >/dev/null

# Stop the flood
ssh "$TESTER_HOST" "sudo pkill -9 MoonGen"

# Since a few of the samples might have negative numbers of cycles or other such oddities...
echo "Done! If you want to look at the raw data, please read the disclaimer in the util/perf.h file of TinyNF's codebase."
