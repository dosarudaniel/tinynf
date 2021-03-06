#!/usr/bin/python3
# Prints #funs \t #LoCs, without a newline character
# $1: path to driver codebase
# $2: file with function names in a ```-delimited block

import glob
import subprocess
import sys

with open(sys.argv[2], 'r') as file:
  lines = [line.strip() for line in file.readlines()]
  lines = [line.replace('- ', '') for line in lines]

# find start (inclusive) and end (exclusive) of lines with function names
start = 0
end = -1
for line in lines:
  if end == -1:
    start = start + 1
    if line == '```':
      end = start
  else:
    if line == '```':
      break
    else:
      end = end + 1

# ignore other lines
lines = lines[start:end]

# ignore repeated functions
lines = [line for line in lines if '*' not in line]

# get all C files in the codebase
files = glob.glob(sys.argv[1] + '/**/*.c') + glob.glob(sys.argv[1] + '/*.c')

# for each function, count its LoC (it's in the file for which count-function-loc returns something)
counts = []
for function in lines:
  for file in files:
    out = subprocess.check_output(['sh', 'count-function-loc.sh', file, function]).decode('utf-8').strip()
    if out != '':
      counts.append(int(out))
      break

print(str(len(lines)) + "\t" + str(sum(counts)), end='')
