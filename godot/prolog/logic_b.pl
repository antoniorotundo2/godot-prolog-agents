% Logic B: cautious

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

all([], _).
all([H|T], Percepts) :- member(H, Percepts), all(T, Percepts).

decide_action(Percepts, celebrate) :-
  member("goal_reached", Percepts), !.

decide_action(Percepts, rest) :-
  member("low_energy", Percepts), !.

decide_action(Percepts, attack) :-
  all(["enemy_close", "can_attack"], Percepts), !.

decide_action(Percepts, flee) :-
  member("under_attack", Percepts), !.

decide_action(Percepts, turn_left) :-
  member("obstacle", Percepts), !.

decide_action(Percepts, move_forward) :-
  member("enemy_close", Percepts), !.

decide_action(Percepts, move_forward) :-
  member("enemy", Percepts), !.

decide_action(Percepts, move_forward) :-
  member("see_food", Percepts), !.

decide_action(_, idle).
