% Top-down tank agent logic

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

all([], _).
all([H|T], P) :- member(H, P), all(T, P).

decide_action(P, retreat) :-
  member("enemy_too_close", P), !.

decide_action(P, strafe_left) :-
  all(["enemy_blocked", "team_1"], P), !.

decide_action(P, strafe_right) :-
  all(["enemy_blocked", "team_2"], P), !.

decide_action(P, shoot) :-
  all(["enemy_in_range", "can_shoot"], P),
  \+ member("enemy_blocked", P), !.

decide_action(P, strafe_left) :-
  member("enemy_right", P),
  member("enemy_in_range", P), !.

decide_action(P, strafe_right) :-
  member("enemy_left", P),
  member("enemy_in_range", P), !.

decide_action(P, advance) :-
  member("enemy_visible", P), !.

decide_action(P, patrol) :-
  member("no_enemy", P), !.

decide_action(_, hold).
