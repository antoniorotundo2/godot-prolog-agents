% logica veicolo
% idea generale
% - sicurezza e precedenze
% - gestione dell'incrocio
% - avanzamento normale

% member/2 vera se X è appartenente alla lista
member(X, [X|_]).
member(X, [_|T]) :- member(X, T).

% any_turn/1, vera se agente ha almeno una manovra disponibile
any_turn(P) :-
	member("can_turn_left", P);
	member("can_turn_right", P);
	member("can_turn_straight", P);
	member("can_turn_u_turn", P).

% 1) semafori: stop forzato sul rosso/giallo o segnale esplicitivo di stop
decide_action(P, stop) :-
	member("must_stop_signal", P), !.

decide_action(P, stop) :-
	member("light_red", P), !.

decide_action(P, stop) :-
	member("light_yellow", P), !.

% 2) precedenza, se qualcosa è a destra allora agente si ferma
decide_action(P, stop) :-
	member("yield_to_right", P), !.

% 3) anti deadlock, quando godot segnala un blocco allora ne forza attraversamento
decide_action(P, drive) :-
	member("intersection_unblock", P), !.

% 4) sicurezza tra i veicoli in modo da fermare immediatamente il veicolo
decide_action(P, stop) :-
	member("vehicle_very_close", P), !.

% anche il sensore di prossimità viene trattato come condizione ad alto rischio
decide_action(P, stop) :-
	member("vehicle_in_area_sensor", P), !.

% 5) sicurezza di rallentamento in avvicinamento
decide_action(P, slow_down) :-
	member("vehicle_close", P), !.

% prova a rallentare quando vede un ostacolo davanti
decide_action(P, slow_down) :-
	member("vehicle_ahead", P), !.

% 6) incrocio, la prima volta chiede randomicamente una scelta di svolta, successivamente esegue le manovre scelte agente
decide_action(P, turn_random) :-
	member("at_intersection", P),
	any_turn(P),
	\+ member("last_action_turn_random", P), !.

decide_action(P, drive) :-
	member("at_intersection", P),
	any_turn(P), !.

% avanzamento, semaforo verde o nessun semaforo, quindi avanza
decide_action(P, drive) :-
	member("light_green", P), !.

decide_action(P, drive) :-
	member("light_none", P), !.

% altrimenti, continua a guidare
decide_action(_, drive).
