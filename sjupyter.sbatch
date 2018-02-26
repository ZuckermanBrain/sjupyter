#!/bin/bash
#SBATCH --nodes 1
#SBATCH --exclusive
#SBATCH --time 4:00:00
#SBATCH --job-name jupyter

XDG_RUNTIME_DIR=""
jport=$(shuf -i8000-9999 -n1)
jip=$(ip route | tail -1 | awk -F 'link src ' '{print $2}')

if [ "$JUPYTER_PATH" == "" ]
then
  module load jupyter
  JUPYTER_PATH=sjupyter-notebook
fi
$JUPYTER_PATH --no-browser --notebook-dir=/shared --port=$jport --ip=$jip
