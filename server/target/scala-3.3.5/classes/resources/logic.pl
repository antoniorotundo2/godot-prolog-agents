% Extended Prolog rules for agent behavior

member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

all([], _).
all([H|T], Percepts) :- member(H, Percepts), all(T, Percepts).

% Priority-based decision rules (first match wins)
decide_action(Percepts, celebrate) :-
  member("goal_reached", Percepts), !.

decide_action(Percepts, flee) :-
  all(["enemy", "low_energy"], Percepts), !.

decide_action(Percepts, wander) :-
  all(["enemy", "last_action_rest"], Percepts), !.

decide_action(Percepts, attack) :-
  member("enemy", Percepts), !.

decide_action(Percepts, rest) :-
  member("low_energy", Percepts), !.

decide_action(Percepts, turn_left) :-
  member("obstacle", Percepts), !.

decide_action(Percepts, move_forward) :-
  member("see_food", Percepts), !.

decide_action(_, wander).
