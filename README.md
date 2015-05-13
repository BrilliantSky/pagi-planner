# pagi-planner
PAGI-Plannner is an action-based learning and planning system for PAGI World using a directed state graph.

## Building pagi-planner

### Prerequisisites

* dub - The D package system (http://code.dlang.org/getting_started)
* dPAGI - D Interface to PAGI World (https://github.com/BrilliantSky/dPAGI)

Since dPAGI is not registered with the D package repository, you'll need to add it locally.
After building dPAGI, run the following command:

	dub add-local <path-to-dpagi>

Now dub will find the package properly.

### Compilation

Execute the following to build pagi-planner:

	git clone https://github.com/BrilliantSky/pagi-planner.git
	cd pagi-planner
	dub build

This will produce an executable, pagi-planner, in the current directory.

## Running pagi-planner

To see the usage information, run pagi-planner and pass the -h or --help option:

	./pagi-planner -h

It will display the following output:

	PAGI World Action Learning and Planning System

	Usage: planner [Options]
	Options:

		--host,-c             Hostname to use to connect to PAGI World (default localhost)
		--port,-p             Port to connect to PAGI world (default 42209)
		--tasks,-t            Tasks to solve in PAGI world
		--iterations,-i       How many times to run each task (default 1)
		--help,-h             Display this help message

In order to use pagi-planner, PAGI World must be running and accessible over the network.
Make a note of what your ip address is and pass it to the --host option.

At least one task must be specified with --tasks. To start off, use the Red task. Copy the
tsk/red file to the same directory as PAGI World.

IMPORTANT: The task files are relative to PAGI World, not pagi-planner! You may find it useful
to link the tsk directory to wherever PAGI World is run from (see below).

Multiple tasks may be specified using commas to separate them. A task may be specified more
than once.

The resulting command should look like this:

	./pagi-planner --host 127.0.0.1 --tasks red

If you receive an error saying "Connection refused", then check the IP and port PAGI World are
running on (and also that your internet connection has not changed since starting PAGI World).


Once everything is working, it is recommended that the tsk/ subdirectory be linked into your
PAGI World directory to avoid having to copy all of the task files. For example, something
similar to the following command should work on Unix/Linux:

	cd /home/user/projects/pagi-world
	ln --symbolic /home/user/projects/pagi-planner/tsk

Then use the next command to run both the red and redgreen tasks:

	./pagi-planner --host 127.0.0.1 --tasks tsk/red,tsk/redgreen



