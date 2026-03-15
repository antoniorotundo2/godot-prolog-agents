% logica b (cauto), utilizzato nell'esempio Simple Agent Test
% differenza con la logica a e la regola idle (che resta in attesa)

% member/2 vera se X è appartenente alla lista
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% all/2 vero se tutti gli elementi della prima lista sono in Percepts
all([], _).
all([H|T], Percepts) :- member(H, Percepts), all(T, Percepts).

% 1) se agente raggiunge un goal.
decide_action(Percepts, celebrate) :-
  member("goal_reached", Percepts), !.

% 2) se energia bassa riposa
decide_action(Percepts, rest) :-
  member("low_energy", Percepts), !.

% 3) se può attaccare e il nemico è a distanza di attacco, allora attacca
decide_action(Percepts, attack) :-
  all(["enemy_close", "can_attack"], Percepts), !.

% 4) se viene attaccato, fugge
decide_action(Percepts, flee) :-
  member("under_attack", Percepts), !.

% 5) prova ad evitare un ostacolo
decide_action(Percepts, turn_left) :-
  member("obstacle", Percepts), !.

% 6) avanza verso un target vicino
decide_action(Percepts, move_forward) :-
  member("enemy_close", Percepts), !.

% 7) altrimenti va verso un nemico che può vedere
decide_action(Percepts, move_forward) :-
  member("enemy", Percepts), !.

% 8) altrimenti resta in attesa
decide_action(_, idle).
