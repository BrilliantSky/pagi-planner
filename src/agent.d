
import pagi;
import grid;
import std.stdio;
import std.math;
import std.datetime;
import std.random;
import std.typecons;
import std.string;

import actions;
import state;
import choice;

static ulong sdbm(string str) pure @safe nothrow
{
   ulong hash = 0;

   foreach(c; str)
       hash = c + (hash << 6) + (hash << 16) - hash;

   return hash;
}


mixin template ObjectAction()
{
	string mObject;
	float mX, mY;
public:
	this(string object, float x, float y) const
	{
		mObject=object;
		mX=x; mY=y;
	}
	mixin ActionHelper;
	/+override hash_t toHash() const nothrow
	{
		return sdbm(mObject);
	}+/
	bool opEquals(in typeof(this) other) const pure nothrow
	{
		return mObject == other.mObject;
	}
}

/// Grab an object
const class GrabAction : Action
{
	mixin ObjectAction;
	bool execute(TaskBot agent) const
	{
		writefln("Grab object %s", mObject);
		return agent.grabObjectAt(mObject, mX,mY);
	}
	override string toString() const pure { return "Grab "~mObject; }
}
/// Touch an object
const class TouchAction : actions.actions.Action
{
	mixin ObjectAction;
	bool execute(TaskBot agent) const
	{
		writefln("Touch object %s", mObject);
		return agent.moveTo(mX, mY);
	}
	override string toString() const pure { return "Touch "~mObject; }
}
/// Drop whatever is being held
const class DropAction : Action
{
	bool execute(TaskBot agent) const
	{
		writefln("Release object");
		return agent.releaseObject();
	}
	mixin ActionHelper;
	//override hash_t toHash() const nothrow { return 0; }
	bool opEquals(in DropAction action) const pure nothrow
	{
		return true;
	}
	override string toString() const pure { return "Drop"; }
}
/// Jump a few units
const class JumpAction : Action
{
	bool execute(TaskBot agent) const
	{
		writeln("Jump!");
		return agent.jump();
	}
	mixin ActionHelper;
	bool opEquals(in JumpAction action) const pure nothrow
	{
		return true;
	}
	override string toString() const pure { return "Jump"; }
}

/// The perceived state of the world.
///
/// This class represents the world as PAGI Guy can see it.
/// Each unique, visible object is stored along with which side it is on.
/// If PAGI Guy is holding something, a flag is set to true.
/// If it is a goal state, everything else is irrelevant.
/// Goal states are only equal to other goal states.
struct PerceivedState
{
	bool holding;
	bool goal;
	bool[string] objects;
	string toString() const pure { return format("{ h:%s %s }", holding, objects); }
	size_t toHash() @trusted const nothrow
	{
		if( goal )
			return size_t.max;

		size_t hash = 0b10101000_10000101_11001011_01000101__11010101_10101010_11111100_01010011;
		if( holding ) hash = ~hash;
		hash = reduce!((h,n) => h ^ sdbm(n))(hash, objects.keys); // TODO: Use byKey when it gets fixed
		return hash;
	}
	bool opEquals(in ref PerceivedState ps) const pure nothrow
	{
		return ps.holding==holding && ps.objects==objects;
	}
}
/// Combined world state and actions, used by TaskBot.PerceiveWorld().
struct StateActions
{
	PerceivedState state;
	const(Action)[] actions;
}

import std.algorithm;

/// Integrates planning algorithms with PAGI World.
///
/// This class represents PAGI Guy. It is responsible
/// for his actions and provides the interface to the
/// planning system.
class TaskBot : pagi.Agent
{
	bool ateApple; /// Determines if food was just eaten

	DetailedVisionArray mDetailedVision;     /// Vision array
	PeripheralVisionArray mPeripheralVision; /// Ditto
	uint mVisionUpdated; /// What (if any) vision has been updated

	/// Hack to hold objects in air when being held.
	///
	/// Inserts applyHandForce() calls before polling.
	override bool poll()
	{
		if( mHoldingObject.length > 0 )
		{
			applyHandForce(2000, true, true);
			applyHandForce(2000, false, true);
		}
		return super.poll();
	}

	/// Called when endorphins are received.
	override void endorphinEvent(float amount, uint location)
	{
		ateApple |= (amount > 0);
	}
	/// Called when detailed vision updated. Copies data to array for later processing.
	override void visionUpdateDetailed(in DetailedVisionArray sensors)
	{
		mDetailedVision = sensors;
		mVisionUpdated = 1;
	}
	/// Called when detailed vision updated. Copies data to array for later processing.
	override void visionUpdatePeripheral(in PeripheralVisionArray sensors)
	{
		mPeripheralVision = sensors;
		mVisionUpdated = 2;
	}
	/// Request vision update and wait for it to finish
	void updateVision()
	{
		writeln("UpdateVision");
		requestPeripheralVisionUpdate();
		mVisionUpdated = 0;
		do
		{
			poll();
		} while(!mVisionUpdated);
	}
	/// Find the center of mass of a visible object
	auto findObjectCenterCoordsDetailed(in char[] target)
	{
		bool sameObj(in char[] obj) { return obj==target; }
		auto result = grid.findCentroid(mDetailedVision, &sameObj);
		// Adjust for detailed vision space
		result.x = .15f*(result.x - 15);
		result.y = .15f*(result.y + 10);
		return result;
	}


	/// The object being held ("" for none)
	string mHoldingObject;

	/// Grab $(PARAM obj) at location ($(PARAM x), $(PARAM y)).
	///
	/// Turns horizontally towards the object and moves to within 4 units of it.
	/// Uses detailed vision to move hand onto it and grab it.
	/// Returns true if successful. Rotation is reset when finished.
	/// May time out if the object cannot be reached or grabbed.
	bool grabObjectAt(in char[] obj, float x, float y)
	{
		writefln("Grab Object @ %s %s", x, y);

		// Start a timer to avoid getting stuck
		SysTime startTime = Clock.currTime();

		// Rotate towards object
		bool left = mBody.posX > x;
		setRotation(left ? 90 : -90);

		// Always return to UP when done (except if an error occurs)
		scope(success)
		{
			setRotation(0);
		}

		// Move toward the object until 4 units away
		while(abs(mBody.posX - x) > 4)
		{
			// Check timer
			if( Clock.currTime() - startTime > dur!"seconds"(10) )
				return false;
			poll();
			applyBodyForce(16000, true);
			//writefln("Grab Object - move (%s --> %s)", mBody.posX, x);
		}
		// Opposite hand!
		Hand *hand = !left ? &mLeftHand : &mRightHand;
		do
		{
			// Check timer
			if( Clock.currTime() - startTime > dur!"seconds"(15) )
				return false;

			// Update detailed vision, hand pos, and hand sensors
			mVisionUpdated = 0;
			requestDetailedVisionUpdate();
			requestHandPosUpdate(!left);
			requestHandSensorUpdate(!left, 0);
			poll();
			while(!mVisionUpdated) {}

			// Update object location (center of object as seen by detailed vision)
			auto result = findObjectCenterCoordsDetailed(obj);
			if( !result )
				return false;
			x = result.x;
			y = result.y;

			// Move hand towards apparent center of object
			applyHandForce( (x-hand.posX)*40, (y-hand.posY)*40, !left );

			//writefln("Grab Object - grab(%s,%s) [%s %s]", x,y, hand.posX, hand.posY);

		// Run until hand is touching the object, or within 0.5 units
		} while( !hand.sensors[0].p || abs(hand.posX-x) > 0.5 || abs(hand.posY-y) > 0.5 );

		// Grab the object, set the holding variable, and return true
		setGrip(!left);
		mHoldingObject = obj.idup;
		writeln("Gripping");
		return true;
	}
	/// Move to location x,y.
	///
	/// May time out.
	/// TODO: make timeout relative to distance
	bool moveTo(float x, float y)
	{
		SysTime startTime = Clock.currTime();

		int dir = mBody.posX < x ? 28000 : -28000;
		while( abs(mBody.posX-x) > 1 )
		{
			if( Clock.currTime() - startTime > dur!"seconds"(4) )
				return false;
			poll();
			applyBodyForce(dir);
		}
		return true;
	}
	/// Drop any object(s) being held.
	bool releaseObject()
	{
		writeln("Release");
		releaseGrip(false);
		releaseGrip(true);
		mHoldingObject = "";
		for(uint i=0; i<10; i++) poll(); // delay
		return true;
	}
	/// Jump straight up into the air (small).
	bool jump()
	{
		writeln("Jump");
		applyBodyForce(45000, true);
		for(uint i=0; i<10; i++) poll(); // delay
		return true;
	}

protected:

	/// Perceive the world and generate actions.
	///
	/// Update peripheral vision and find all unique objects.
	/// Creates a PerceivedState representation and generates
	/// a list of actions that may be performed.
	/// Actions must be generated here because the location is needed.
	/// TODO: Decouple actions from perceiveWorld().
	StateActions perceiveWorld() const
	{
		updateVision();

		writeln("PerceiveWorld()");
		if( ateApple )
			return StateActions(PerceivedState(false,true), []);

		auto state = PerceivedState(); // PerceivedState object
		const(Action)[] actions; // List of actions

		// Helper function to create actions
		void addAction(A, Args...)(Args args)
		{
			actions ~= new const A(args);
		}


		// If holding, add holding object and set state flag
		state.holding = (mHoldingObject.length > 0);
		if( mHoldingObject.length > 0 )
			addAction!DropAction();

		// Can always jump
		addAction!JumpAction();

		foreach(j, ref row; mPeripheralVision)	// Each row, bottom to top
		{
			foreach(i, cell; row) // Each cell of the row, left to right
			{
				// Empty cell or not unique?
				if( cell.length == 0 || cell in state.objects )
					continue;

				// Determine which side (T/F) and add to state
				state.objects[cell] = i > row.length/2;

				// Helper function if objects are the same
				bool sameObj(in const(char)[] obj) { return obj == cell; }
				//assert(sameObj(mPeripheralVision[j][i]));
				// Find the centroid if it overlaps multiple cells
				auto center = findCentroidAt(mPeripheralVision, &sameObj, Pos2!uint(cast(uint)i,cast(uint)j));

				// Compute coordinate positions from vision space (Bugged?)
				float x = 2.0*(center.x - 7) - 0.5 + mBody.posX;
				float y = 0.667*center.y + mBody.posY;

				// Add actions based on object type
				switch(cell)
				{
				case "redWall": goto case;
				case "greenWall": goto case;
				case "blueWall":
					addAction!TouchAction(cell.idup, x,y);
					//writefln("Add touch action for %s @ %s %s (%s)", cell, x,y, mBody.posX);
					break;
				case "redDynamite": goto case;
				case "greenDynamite": goto case;
				case "blueDynamite":
					//writefln("Holding: '%s'", mHoldingObject);
					if( mHoldingObject.length == 0 )
					{
						addAction!GrabAction(cell.idup, x,y);
					//	writefln("Add grab action for %s @ %s %s (%s)", cell, x,y, mBody.posX);
					}
					break;
				case "apple": goto case;
				case "bacon": goto case;
				case "steak": goto case;
				case "redPill": goto case;
				case "bluePill": goto case;
				case "poison":
					addAction!TouchAction(cell.idup, x,y);
					//if( mHoldingObject.length == 0 )
					//	addAction!GrabAction(cell.idup, x,y); // Don't bother grabbing these
					break;
				default:
					break;
				}
			}
		}
		// Explosions should be reinforced (BROKEN)
		if( "explosion" in state.objects )
			writeln("EXPLOSION!!!!!!!!");

		return StateActions(state, actions);
	}


public:
	this(in char[] host, ushort port)
	{
		super(new pagi.Connection(host,port));
	}
/+
	const(Action)[] planActions(const(PerceivedState) state) const
	{
		struct StateActionPair
		{
			const(PerceivedState) *state;
			const(Action) *action;
		}

		bool apple = false;

		bool visit(graph.State!StateActionPair s, out StateActionPair[] next)
		{
			if( s.node.state.solution )
				return true;

			auto p = *s.node.state in mTransitions;
			if( !p )
				return false;

			//foreach(transition ; *p)
			//{
			//	next ~= StateActionPair(s.node.state, &transition);
			//}
			return false;
		}

		StateActionPair start = StateActionPair(&state, null);

		auto stack = graph.bfs(start, &visit).sequence;
		//auto s = map!(pair => *pair.action)(stack.sequence);
		const(Action)[] sequence;
		sequence.reserve(stack.length);
		foreach(sap; stack)
			sequence ~= *sap.action;
		return sequence;
	}
+//+
	class PerceivedWorldState
	{
		struct Link
		{
			
		}
		PerceivedWorldState[Action] mPredicted;
		@property float distance(const DeltaState other) const
		{
			float dist = reduce!((v,a) => (a !in mTransitions) ? 1 : 0)(0, other.mTransitions.byKey());
			dist = reduce!((v,a) => (a !in other.mTransitions) ? 1 : 0)(dist, mTransitions.byKey());
			return dist;
		}
	}+/

	/// Helper type to avoid verbosity (StateNodes are templated on states and actions).
	alias PagiStateNode = StateNode!(PerceivedState,Action);

	/// This is the State Graph.
	///
	/// StateNodes can be accessed by PerceivedState objects.
	PagiStateNode[const(PerceivedState)] mStateNodes;

	/// Learn and plan with the specified task.
	///
	/// Information is saved between calls and across tasks.
	bool run(string taskname)
	{
		// Delay a bit before loading to let PAGI Guy slow down
		poll();
		poll();
		poll();
		// Load the task!
		loadTask(taskname);
		// Require user input so PAGI Guy can be fixed if he spawns upside down or if he's moving too fast
		writeln("Press enter to start");
		stdin.readln();

		// Some delay... probably not necessary with user input.
		poll();
		poll();
		poll();
		poll();
		poll();
		writefln("Loaded task %s", taskname);

		// Perceive the world and generate available action list
		StateActions stateActions = perceiveWorld();
		writefln("Found %s actions", stateActions.state.objects.length);
		if( stateActions.state.objects.length == 0 ) // No actions
			return false;

		// Find the node for this state, if it exists, otherwise create it
		auto p = stateActions.state in mStateNodes;
		Rebindable!PagiStateNode node = ( p ? *p : (mStateNodes[stateActions.state] = new PagiStateNode(stateActions.state, stateActions.actions)) );

		// Create the planner, which operates on the graph
		auto planner = new ActionPlanner!(PerceivedState,Action)();

		// While food hasn't been eaten (the goal)
		while(!ateApple)
		{
			// No actions?
			if( stateActions.state.objects.length == 0 )
				return false;

			// Update
			poll();

			// Choose an action (planned or otherwise)
			Rebindable!(const(Action)) action = planner.nextPlannedAction(node); //pickBestAction(node);//pickGreedyAction(node,&numExplosions);
			if( !action ) // Hmmm... shouldn't need this but too late
			{
				writeln("");
				writeln("COULD NOT PICK GREEDY ACTION");
				writeln("Picking least-investigated action");
				writeln("");
				action = pickUnknownAction(node);
			}
			if( !action ) // Hmmm... REALLY shouldn't need this but too late
			{
				writeln("================");
				writeln("NO ACTIONS WERE PICKED (ERROR)");
				writeln("================");
				assert(action, "Actions were available but one could not be chosen (shouldn't happen)");
			}

			// Perform the action
			action.execute(this);
			poll();
			poll();

			// Perceive the world and generate action list
			updateVision();
			stateActions = perceiveWorld();
			writefln("Found %s actions", stateActions.state.objects.length);

			// Find the node for this state, if it exists, otherwise create it
			auto p2 = stateActions.state in mStateNodes;
			PagiStateNode nextState = ( p2 ? *p2 : (mStateNodes[stateActions.state] = new PagiStateNode(stateActions.state, stateActions.actions)) );


			writeln("================");
			writefln("Entering state %s", nextState);
			writefln("%s", stateActions.state);
			writeln("================");
			//foreach(k,v; mStateNodes)
			//{
			//	auto k2 = k;
				//writefln("%s ? ==> %s   |   %s   |   %s", k2, k in mStateNodes, k2 in mStateNodes, stateActions.state in mStateNodes);
			//}

			// Provide feedback to the graph about what happened
			node.feedback(action, nextState);

			// New current state
			node = nextState;


			// Wait for user
			//writeln("Press enter to continue");
			//stdin.readln();
		}
		ateApple=false; // reset goal condition
		return true;
	}
}

import std.getopt;

int main(string[] args)
{
	string hostname="localhost";
	ushort port=42209;
	string[] tasks;
	uint tries=1;
	bool help=false;

	arraySep = ",";
	getopt(args,
		"host|c", &hostname,
		"port|p", &port,
		"tasks|t", &tasks,
		"help|h", &help,
		"tries|r", &tries
	);
	if( help )
	{
		writeln("PAGI World Action Learning and Planning System");
		writeln("");
		writeln("Usage: planner [Options]");
		writeln("Options:");
		writeln("");
		writeln("\t--host,-c             Hostname to use to connect to PAGI World (default localhost)");
		writeln("\t--port,-p             Port to connect to PAGI world (default 42209)");
		writeln("\t--tasks,-t            Tasks to solve in PAGI world");
		writeln("\t--iterations,-i       How many times to run each task (default 1)");
		writeln("\t--help,-h             Display this help message");
		writeln("");
		return 0;
	}
	if( tasks.length == 0 )
	{
		writeln("No tasks specified, abort");
		return 1;
	}

	auto bot = new TaskBot(hostname, port);
	foreach(task; tasks)
	{
		for(uint i=0; i<tries; i++)
		{
			if( bot.run(task) )
			{
				writeln("================================");
				writefln("Solved task '%s', iteration %s", task, i);
				writeln("================================");
			}
			else
			{
				writeln("================================");
				writefln("Failed task '%s', iteration %s", task, i);
				writeln("================================");
			}
		}
	}
	return 0;
}


