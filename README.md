sjupyter-idletest is a launcher script. You run it on the login node to start a Jupyter session inside a Slurm job. It automatically chooses between JupyterLab and classic notebook, picks an unused port, and submits the job to Slurm. Once the job starts, it launches both Jupyter and a watchdog process (jupyter-idle-killer) on the compute node, then waits for Jupyter to become ready and prints the connection URL and an SSH tunnel command for you to access it from your laptop.

jupyter-idle-killer is the watchdog. It runs alongside Jupyter inside the Slurm job and continuously checks whether the session is still being used. If it detects no user activity for a configurable timeout (default 1 hour), it cancels the Slurm job – terminating the Jupyter server and freeing up the compute node for others.

The killer looks for several signs of life:

Kernels that are currently executing code (busy state).

Kernels that have sent activity (like cell execution) within the last poll interval.

Any open terminals (which imply user interaction).

Browser “keep‑alive” activity, which it infers from changes to Jupyter’s runtime files (a fallback when the API doesn’t reflect user interaction).

If none of these are seen, and the total idle time exceeds the limit, the job is killed via scancel.

Technical Description
1. sjupyter-idletest – The Slurm Launcher
Environment detection
It finds the Jupyter executable (jupyter-lab, jupyter-notebook, or plain jupyter) and requires that an Anaconda/Miniforge module is already loaded. It captures the module name (e.g., Miniforge-24.7.1-2) so the compute node can reload the same environment.

Slurm job submission
It uses sbatch with a heredoc that forms the job script. It passes along all environment variables, including:

IDLE_TIMEOUT (default 3600s)

IDLE_POLL_INTERVAL (default 60s)

IDLE_HEARTBEAT_WINDOW (default 120s)

Proxy settings for internet access.

The job script:

Reloads the module system and the user’s chosen Conda environment.

Sets JUPYTER_RUNTIME_DIR to ~/.local/share/jupyter/runtime.

Chooses a random port (8000‑9999) that is not already in use.

Starts the idle-killer in the background, redirecting its log to ~/.sjupyter/jobs/<jobid>.idle.log.

Starts Jupyter (Lab preferred) with --no-browser, binding to the compute node’s IP, and pipes its output to a job‑specific log file.

Uses trap to kill the idle‑killer when the Jupyter process ends.

Client‑side monitoring
After submitting, the script waits for the job to enter RUNNING state. It then tails the job’s output file (%j.out) for up to SJUPYTER_TIMEOUT (default 120s) looking for the token and URL. Once found, it prints:

Direct access URLs (only valid inside the cluster).

An SSH tunnel command to forward the port from the compute node to your laptop.

Instructions to cancel the job or close the tunnel.

2. jupyter-idle-killer – The Idle Watchdog (Python)
Configuration via environment variables

IDLE_TIMEOUT – maximum allowed idle seconds.

IDLE_POLL_INTERVAL – how often to poll the Jupyter API (default 60s).

IDLE_HEARTBEAT_WINDOW – window (in seconds) for checking file modification times as a fallback activity indicator (default 120s).

SLURM_JOB_ID and JUPYTER_PORT – used to identify the correct Jupyter server and to cancel the job.

Activity detection – in order of precedence:

Jupyter Server API polling
The script attempts to find the running Jupyter server by trying several command combinations (jupyter-lab server list --json, etc.) and filters by the port.
For each server found, it queries:
/api/kernels – for each kernel, it checks:
execution_state == "busy" → activity.
last_activity timestamp – if within the last POLL_INTERVAL seconds → activity.
/api/terminals – if any terminal sessions exist → activity.
Fallback: file‑system activity
If the API shows no activity, it scans the Jupyter runtime directory (~/.local/share/jupyter/runtime) for files named jpserver-* or kernel-*. It checks each file’s modification time; if any file was modified within the HEARTBEAT_WINDOW, it treats that as recent browser or heartbeat activity. This captures keep‑alive signals that may not update the kernel’s last_activity field.
Idle timer logic

A variable last_active stores the timestamp of the most recent activity.

On each poll, if any activity is detected:

If the elapsed time since last_active exceeds POLL_INTERVAL, it logs the reason and resets last_active to now.

It then computes idle_for = now - last_active and logs the remaining time.

If idle_for > IDLE_TIMEOUT, it calls kill_job(), which executes scancel $SLURM_JOB_ID, and exits.

Logging
All actions are logged to ~/.sjupyter/jobs/<jobid>.out (the main job log) and also to a dedicated idle‑killer log (<jobid>.idle.log) for troubleshooting.

What the Scripts Are Looking For (in Summary)
Indicator	How It Is Detected
Running code	Kernel execution_state == "busy" via /api/kernels
Recent kernel interaction	last_activity timestamp of any kernel within the last POLL_INTERVAL seconds
Open terminals	Non‑empty list from /api/terminals
Browser keep‑alive / UI activity	Modification time of jpserver-* or kernel-* files in Jupyter’s runtime directory within HEARTBEAT_WINDOW
If none of these are true for IDLE_TIMEOUT seconds, the job is considered idle and terminated.

Why This Approach?
The REST API is the primary source because it directly reflects kernel and terminal state.

The file‑system fallback catches subtle client‑side activity (e.g., the browser pinging the server) that may not change kernel state but still indicates the user is present.

The launcher script ensures the watchdog runs only inside the Slurm job, so it cannot accidentally kill other sessions.

By using Slurm’s scancel, the cleanup is immediate and does not leave orphaned processes.

Together, these scripts enforce a fair‑use policy on shared HPC resources, automatically releasing compute nodes from abandoned Jupyter sessions.
