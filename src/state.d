
import std.algorithm;
import std.conv;
import std.stdio;

/// StateNode represents the state of the world and outgoing transitions to new states
/// Template parameters:
///   S - Type of perceived state
///   A - Type of actions used as transitions
final class StateNode(S,A)
{
	// World state, use as lookup value
	const(S) mPerceivedState;
	// Transitions from this state to another state via actions
	alias Transition!(typeof(this)) T;
	T[const(A)] mTransitions;

	// Unique ID (for debug printing)
	uint mId;
	static uint sID=0;

public:
	this(const S perceivedState, const(A[]) actions)
	{
		mPerceivedState = perceivedState;
		foreach(a; actions)
		{
			mTransitions[a] = new T();
			writefln("NewState: Action %s", a);
		}
		mId = sID++;
	}
	@property bool solution() const { return false; } //mExtraState==uint.max; }

	const(A) pickAction(Pred)() const
	{
		// Try picking the action with the least attempts (Curiosity)
		uint best = uint.max;
		auto p = Rebindable!(const(A))(null);
		foreach(a,t; mTransitions)
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
	void feedback(const(A) action, StateNode sn)
	{
		writefln("Feedback for state %s, action %s", this, action);
		auto p = action in mTransitions;
		if( !p )
			mTransitions[action] = new T(sn);
		else
		{
			p.recordResult(sn);
		}
	}
	override ulong toHash() const @trusted nothrow
	{
		return typeid(S).getHash(&mPerceivedState);
	}
	@property auto transitions() const pure nothrow { return mTransitions; }
	@property auto perceivedState() const pure nothrow { return mPerceivedState; }

	bool opEquals(const(StateNode) sn) const pure
	{
		//if( mTransitions.length != sn.mTransitions.length )
		//	return false;
		//foreach(a,t; mTransitions)
		//	if( a !in sn.mTransitions )
		//		return false;
		return mPerceivedState == sn.mPerceivedState;
	}
	override string toString() const pure { return "State"~to!string(mId); }
	uint id() const pure @property { return mId; }
}


/// Transition between StateNodes
/// Template Parameters:
///   State - Stored state type
class Transition(State)
{
	struct Result
	{
		uint count;

		/+@property float probability() const
		{
			// Hmmm, if this edge fails the first time, it will be completely unreliable.
			assert( this.outer.mNumTries > 0 );
			return cast(float)count / this.outer.mNumTries;
		}+/
	}

	Result[const(State)] mPossibleOutcomes;
	uint mNumTries;

public:
	float probability(in Result r) pure const @safe nothrow {
		assert(mNumTries > 0);
		return cast(float)r.count / mNumTries;
	}

	this()
	{
		mNumTries = 0;
	}
	this(const State result)
	{
		mPossibleOutcomes[result] = Result(1);
		mNumTries = 1;
	}

	float stability() const
	{
		//return reduce!"(p,r) => max(p, r.probability)"( 0.0, mPossibleOutcomes.byValue() );
		float maxprob(float p, in ref Result r) { return max(p, probability(r)); }
		return reduce!maxprob( 0.0f, mPossibleOutcomes.byValue() );
	}

	float probability(in State outcome) const pure
	{
		auto p = outcome in mPossibleOutcomes;
		return !p ? 0.0 : cast(float)p.count / mNumTries;
	}

	void recordResult(const State result)
	{
		writeln("RecordResult");
		writefln("Record result %s for transition %s", result.toString(), this.toString());
		auto p = result in mPossibleOutcomes;
		if( p )
			p.count++;
		else
			mPossibleOutcomes[result] = Result(1);
		mNumTries++;
	}

	@property uint attempts() const pure nothrow { return mNumTries; }

	override string toString() const pure { return to!string(mPossibleOutcomes); }

	@property auto outcomes() const pure { return mPossibleOutcomes; }
}

