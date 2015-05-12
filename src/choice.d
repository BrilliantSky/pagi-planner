
import state;

import std.random;
import std.typecons;
import std.traits;

import std.stdio;

/// Pick the action that results in a higher score by Pred
const(A) pickGreedyAction(S,A,Pred)(in StateNode!(S,A) sn, in Pred pred) //if( isSomeFunction!(Pred) && isNumeric!(ReturnType!Pred) )
{
	alias ReturnType!Pred Measure;
	Measure best = Measure.min;

	auto p = Rebindable!(const(A))(null);

	foreach(a,t; sn.transitions)
	{
		auto tmp = pred(sn.perceivedState);
		if( tmp > best )
		{
			best = tmp;
			p = a;
		}
	}

	return p;
}


// Variables: Reliability, Probability, Result
// Reliability: uint[0..oo]
// Probability: float[0,1]
// Result:      int[-1,1]

//
// Attempts     Result     Rank(1=best)
//   Low         None       5
//   High        None       6
//   Low         New        4
//   High        New        3
//   Low         Good       2
//   High        Good       1
//

// Pick an action that has a decent chance of resulting in a "Good" state, a new state, or has few attempts
const(A) pickBestAction(S,A)(in StateNode!(S,A) sn)
{
	float best = -0.001;
	auto p = Rebindable!(const(A))(null);
	foreach(a,t; sn.transitions)
	{
		float prob = t.probability(sn);
		float rank = t.attempts/10.0 * (1.0-prob) + 0.5 / (t.attempts+1);
		if( rank > best )
		{
			best = rank;
			p = a;
		}
	}
	if(p)
		writefln("Choosing Action %s with score %s", p, best);
	return p;
}

// Pick the action that has the least data
const(A) pickUnknownAction(S,A)(in StateNode!(S,A) sn)
{
	// Try picking the action with the least attempts (Curiosity)
	uint best = uint.max;
	auto p = Rebindable!(const(A))(null);
	foreach(a,t; sn.transitions)
	{
		//auto stability = t.stability();//+uniform(-10,10)/100.0f;
		//writefln("Stability for action %s: %s --> %s", a, t.stability, stability);
		if( t.attempts < best )
		{
			//writefln("%s (%s) is better than %s (%s)", a, t.attempts, p ? to!string(p) : "null", best);
			best = t.attempts;
			p = a;
		}
		//else
		//	writefln("%s (%s) is NOT better than %s (%s)", a, t.attempts, p ? to!string(p) : "null", best);
	}
	if( p )
		writefln("Choose action %s", p);
	return p;

}

import std.container.dlist;

// Plans actions ahead of time
final class ActionPlanner(S,A)
{
	alias const StateNode!(S,A) SN;

	struct PlannedAction
	{
		this(const(A) a, SN sn) { action=a; outcome=sn; }
		Rebindable!(const(A)) action;
		Rebindable!SN outcome;
	}
	PlannedAction[SN] mActions;
	Rebindable!SN mPrevState;

	const(A) nextPlannedAction(SN rootState)
	{
		scope(exit)
		{
			mPrevState = rootState;
		}
		auto p = rootState in mActions;
		if( p )
		{
			if( !mPrevState || rootState != mPrevState )
			{
				return p.action;
			}
			else
			{
				writeln("Repeat state!!!");
				return pickUnknownAction!(S,A)(rootState);
			}
		}
		else
			writeln("Unprocessed state!!!");

		class PathNode
		{
			SN state; // State Node
			const(A) action; // Action taken to get here
			float probability; // Absolute probability of getting here
			PathNode parent; // Node before this one
			float pathProbability; // How likely it is to reach the goal

			this(SN s, const(A) a, float p, PathNode pn)
			{
				state=s;
				action=a;
				probability = p;
				parent = pn;
				pathProbability = 0.0;
			}

			bool visited(SN state)
			{
				auto p = parent;
				while(p)
				{
					if( state == p.state )
						return true;
					p=p.parent;
				}
				return false;
			}
		}
		void backPropagate(PathNode pn)
		{
			float prob = pn.probability;
			while(pn.parent)
			{
				auto parent = pn.parent;
				if( parent.pathProbability > prob )
					break;

				parent.pathProbability = prob;
				mActions[parent.state] = PlannedAction(pn.action, pn.state);

				pn = parent;
			}
		}
		writeln("================");
		writefln("Rebuild plan for state %s", rootState);
		writeln("================");

		// What states have been visited?
		PathNode[SN] visited;
		// What states are to be visited next (BFS)
		DList!PathNode queue;

		// Winning path
		PathNode winning = null;

		// Set up at root (current world) state
		auto rootNode = new PathNode(rootState,null,1.0,null);
		//visited[rootState] = rootNode;
		queue.insertFront( rootNode );

		// While there is an unexplored state
		while( !queue.empty )
		{
			PathNode currNode = queue.back;
			queue.removeBack();

			// A state might get put on the queue twice
			if( currNode.state in visited )
				continue;
			visited[currNode.state] = currNode;

			writefln("Processing %s %s", currNode.state, currNode.state.transitions);

			// For each action from this state
			foreach(a,t; currNode.state.transitions)
			{
				writefln("  Processing %s", a);
				// For each possible outcome of this action
				foreach( nextState, info; t.outcomes )
				{
					writefln("    Processing %s --> %s", a, nextState);
					// Absolute probability of this outcome
					float prob = currNode.probability * t.probability(info);

					if( nextState.perceivedState.goal )
					{
						if( !winning || prob > winning.probability )
						{
							winning = new PathNode(nextState, a, prob, currNode);
							backPropagate(winning);
						}
						continue;
					}

					// Crossover to another path? Ignore for now...
					auto p = nextState in visited;
					if( p )
					{
						/+if( p.probability < prob )
						{
							p.probability = prob;
							p.action = a;
							p.parent = currNode;
						}+/
						continue;
					}
					// Loopback in graph? Ignore for now...
					if( currNode.visited(nextState) )
						continue;

					auto node = new PathNode(nextState, a, prob, currNode);
					visited[currNode.state] = currNode;
					queue.insertFront(node);
				}
			}
		}
		p = rootState in mActions;
		if( p )
		{
			writeln("SUCCESS\n================");
			return p.action;
		}
		else
		{
			writeln("FAILED\n================");
			return pickUnknownAction!(S,A)(rootState);
		}
	}

}




