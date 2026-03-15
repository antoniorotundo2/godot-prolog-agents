% soccer right
% regole simmestriche a soccer left

% member/2 vera se X è appartenente alla lista
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% all/2 vero se tutti gli elementi della prima lista sono in Percepts
all([], _).
all([H|T], P) :- member(H, P), all(T, P).

% 1) se la palla entra nella area avversaria, raggiunge un goal
decide_action(P, celebrate) :-
  member("ball_in_opp_goal", P), !.

% 2) se la palla è vicina, allora la calcia verso l'area avversaria
decide_action(P, kick_to_opp) :-
  member("ball_near", P), !.

% 3) se la palla è vicina ma bloccata prova a sbloccare la palla
decide_action(P, sidestep) :-
  member("ball_stuck", P),
  member("ball_near", P), !.

% 4) se avversario è vicino alla palla, allora prova a separare la palla
decide_action(P, sidestep) :-
  member("enemy_near", P),
  member("ball_near", P), !.

% 5) se la palla è lontana, vai verso la palla
decide_action(P, move_to_ball) :-
  member("ball_visible", P), !.

% 6) altrimenti, torna verso la propria porta
decide_action(_, defend_goal).
