% Vehicle logic for path-following cars with semaphore awareness.
% Priority: safety first, then intersection routing, then cruise.

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

any_turn(P) :-
	member("can_turn_left", P);
	member("can_turn_right", P);
	member("can_turn_straight", P);
	member("can_turn_u_turn", P).

% Semaphores: full stop on red/yellow.
decide_action(P, stop) :-
	member("must_stop_signal", P), !.

decide_action(P, stop) :-
	member("light_red", P), !.

decide_action(P, stop) :-
	member("light_yellow", P), !.

% Right-of-way at intersections: give precedence to vehicle on the right.
decide_action(P, stop) :-
	member("yield_to_right", P), !.

% Godot deadlock breaker requested a forced pass through the intersection.
decide_action(P, drive) :-
	member("intersection_unblock", P), !.

% Keep hard safety for very close vehicles.
decide_action(P, stop) :-
	member("vehicle_very_close", P), !.

% Area sensor is considered high-risk: force stop.
decide_action(P, stop) :-
	member("vehicle_in_area_sensor", P), !.

% Slow down for close vehicles.
decide_action(P, slow_down) :-
	member("vehicle_close", P), !.

% Early slowdown when something is detected ahead.
decide_action(P, slow_down) :-
	member("vehicle_ahead", P), !.

% At intersection:
% 1) request a turn command once
% 2) then drive (so the car actually moves after choosing)
decide_action(P, turn_random) :-
	member("at_intersection", P),
	any_turn(P),
	\+ member("last_action_turn_random", P), !.

decide_action(P, drive) :-
	member("at_intersection", P),
	any_turn(P), !.

decide_action(P, drive) :-
	member("light_green", P), !.

decide_action(P, drive) :-
	member("light_none", P), !.

decide_action(_, drive).
