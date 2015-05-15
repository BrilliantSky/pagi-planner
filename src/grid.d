
// Generic 2-coordinate structure
struct Pos2(D)
{
	this(D x_, D y_) { x=x_; y=y_; }
	D x,y;
}

/// Contains position and boolean valid flag.
///
/// Can be cast to bool as in:
///---
/// if( result ) ...
///---
/// Or used as a Pos2:
///---
/// setTargetPos( result );
///---
struct CentroidResult
{
	bool valid=false;
	Pos2!float pos;
	this(Pos2!float p) { valid=true; pos=p; }
	this(bool v) { valid=v; }
	bool opCast(T=bool)() const { return valid; }
	alias pos this;
}

/// Find the centroid of something in a 2D array.
///
/// Object is present if m(cell) returns true.
/// Return value is castable to bool and Pos2!float.
CentroidResult findCentroid(G,M)(in G grid, M m)
{
	alias T = typeof(grid[0][0]);
	alias D = uint;

	Pos2!D start;

	// Step 1. Find some piece of the object.

	for(D y=0; y<grid.length; y++)
	{
		for(D x=0; x<grid[y].length; x++)
		{
			if( m(grid[y][x]) )
			{
				start = Pos2!D(x,y);
				// Step 2. Find the center
				return findCentroidAt(grid, m, start);
			}
		}
	}
	// Didn't find any matches
	return CentroidResult(false);
}

/// Find the centroid of something in a 2D array, given a start position.
///
/// Object is present at a location if m(cell) returns true.
CentroidResult findCentroidAt(G,M,D)(in G grid, M m, Pos2!D start)
{
	uint[Pos2!D] visited;

	// Step 1. Run Depth-first search on neighboring cells.
	void recurse(D x, D y)
	{
		// Note: uint is never less than zero, but it wraps so the length test fails anyway
		if( x<0 || y<0 || y>=grid.length || x>=grid[y].length )
			return;
		if( Pos2!D(x,y) in visited )
			return;

		if( m(grid[y][x]) )
		{
			visited[Pos2!D(x,y)] = 1;
			recurse(x-1, y);
			recurse(x+1, y);
			recurse(x, y-1);
			recurse(x, y+1);
		}
	}

	recurse( start.x, start.y );

	// Step 2. Average all of the object's cell positions.
	Pos2!float center;
	center.x = 0;
	center.y = 0;
	foreach( p,i; visited )
	{
		center.x += p.x;
		center.y += p.y;
	}
	center.x /= visited.length;
	center.y /= visited.length;

	return CentroidResult(center);
}



