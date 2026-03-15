% logica di combattimento del tank
% obbiettivi del tank
% - sicurezza se il nemico è troppo vicino
% - posizionamento sulla linea di tiro
% - spara solo se può colpire
% - altrimenti, pattuglia la zona se non vede un nemico

% member/2 vera se X è appartenente alla lista
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% all/2 vero se tutti gli elementi della prima lista sono in Percepts
all([], _).
all([H|T], P) :- member(H, P), all(T, P).

% 1) distanza di sicurezza, prova ad arretrare
decide_action(P, retreat) :-
  member("enemy_too_close", P), !.

% 2) se può sparare ed il nemico è in area di tiro, allora spara
decide_action(P, shoot) :-
  all(["enemy_in_range", "can_shoot"], P),
  \+ member("enemy_blocked", P), !.

% 3) correzione di posizione laterale, in base al posizionamento relativo del nemico 
decide_action(P, strafe_left) :-
  member("enemy_right", P),
  member("enemy_in_range", P), !.

decide_action(P, strafe_right) :-
  member("enemy_left", P),
  member("enemy_in_range", P), !.

% 4) se vede il nemico ma non può sparare, avanza
decide_action(P, advance) :-
  member("enemy_visible", P), !.

% 5) se non c'è il nemico, allora pattuglia la zona
decide_action(P, patrol) :-
  member("no_enemy", P), !.

% 6) altrimenti, mantiene la posizione
decide_action(_, hold).
