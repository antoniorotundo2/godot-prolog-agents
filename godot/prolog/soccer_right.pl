% Soccer logic (balanced, same as left agent)

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

all([], _).
all([H|T], P) :- member(H, P), all(T, P).

decide_action(P, celebrate) :-
  member("ball_in_opp_goal", P), !.

decide_action(P, kick_to_opp) :-
  member("ball_near", P), !.

decide_action(P, sidestep) :-
  member("ball_stuck", P),
  member("ball_near", P), !.

decide_action(P, sidestep) :-
  member("enemy_near", P),
  member("ball_near", P), !.

decide_action(P, move_to_ball) :-
  member("ball_visible", P), !.

decide_action(_, defend_goal).
