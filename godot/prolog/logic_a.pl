% logica a: aggressivo, usato nell'esempio Simple Agent Test
% il cut ferma il backtracking alla prima regola valida (la priorità è top-down)

% member/2 vera se X è appartenente alla lista
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% all/2 vero se tutti gli elementi della prima lista sono in Percepts
all([], _).
all([H|T], Percepts) :- member(H, Percepts), all(T, Percepts).

% 1) se agente raggiunge un goal.
decide_action(Percepts, celebrate) :-
  member("goal_reached", Percepts), !.

% 2) se energia bassa recupera
decide_action(Percepts, rest) :-
  member("low_energy", Percepts), !.

% 3) se può attaccare e il nemico è a distanza di attacco, allora attacca
decide_action(Percepts, attack) :-
  all(["enemy_close", "can_attack"], Percepts), !.

% 4) se subisce danno, allora fugge
decide_action(Percepts, flee) :-
  member("under_attack", Percepts), !.

% 5) se vede un nemico, avanza verso di lui
decide_action(Percepts, move_forward) :-
  member("enemy", Percepts), !.

% 6) altrimenti, continua a muoversi
decide_action(_, wander).
