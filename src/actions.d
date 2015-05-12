
import std.algorithm;
import std.conv;

import std.stdio;

import agent;

//template actions(TaskBot)
//{

const interface Action
{
	abstract bool execute(TaskBot agent) const;
	//abstract ulong toHash() const pure @safe nothrow;
	abstract bool opEquals(in Action other) const pure nothrow;
	//abstract int opCmp(in Action other) const pure nothrow;

	//static uint nextType() @property @safe { return nextActionType++; }
	abstract string toString() const pure;
}
template ActionHelper()
{
	//static immutable uint Type = Action.nextType();
	//override uint type() @property const @safe pure { return Type; };
	override bool opEquals(in Action other) const pure nothrow
	{
		auto p = cast(typeof(this))other;
		return p && this.opEquals(p);
		//if( other.type != this.type )
		//	return false;
		//return this.opEquals(cast(T)other);
	}
	/+bool opEquals(in Object other) const pure nothrow
	{
		auto p = cast(typeof(this))other;
		return p && this.opEquals(p);
		//if( other.type != this.type )
		//	return false;
		//return this.opEquals(cast(T)other);
	}+/
	/+override int opCmp(Object other)
	{
		return opEquals(other) ? 0 : (this.toHash() > other.toHash() ? 1 : -1);
	}+/
}

const class CompoundAction : Action
{
	Action[] mActions;
public:
	this(const(Action[]) actions)
	{
		mActions=actions;
	}
	override bool execute(TaskBot agent) const
	{
		writeln("Compound Action:");
		foreach(action; mActions)
		{
			if( !action.execute(agent) )
				return false;
		}
		writeln("----------------");
		return true;
	}
	/+ulong toHashImpl() pure const @trusted
	{
		ulong hash;
		foreach(a; mActions)
			hash = (hash << 5) + a.toHash();
		return hash;
	}
	override ulong toHash() const @trusted nothrow
	{
		try { // Stupid std lib defect...
			return toHashImpl();
		} catch(Exception e) { assert(false); }
	}+/
	bool opEquals(in CompoundAction other) const pure nothrow
	{
		return mActions == other.mActions;
	}
	override string toString() const pure { return "Compound "~to!string(mActions); }
	mixin ActionHelper;
}


//}

