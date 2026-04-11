# Testing

## 1) Strumenti Utilizzati

- **Scala build/test runtime**: `sbt` (compile/run);
- **Godot runtime**: esecuzione della scena in editor per la validazione del comportamento;
- **Log osservabilità**:
    - Log del server Scala (WebSocket, Action, Warning);
    - Output di debug degli agenti in Godot.

## 2) Metodologia Adottata

L'approccio principale si è basato sul **test funzionale end-to-end per scenario**, con ripetizione dei casi critici dopo ogni modifica.
Alcune delle fasi tipiche sono:
1. L'avvio del server Scala;
2. Avvio della scena su Godot;
3. Osservazione della meccanica percetti -> azioni;
4. Verifica degli effetti in scena;
5. Regressione rapida sugli scenari stabili.

## 3) Matrice di Test per Scenario
### 3.1 Simple Agent Test
- spawn dinamico di agente A/B da UI;
- connessione WebSocket e ricezione azione;
- combattimento fisico (attack, rest, dead);
- coerenza dell'energia sul server;
- rimozione dell'agente su HP/energia uguale a zero.

### 3.2 Tank Test
- acquisizione target e movimento tattico;
- fuoco solo su linea di tiro libera;
- danno, morte, respawn random;
- modalità pattuglia quando il target non è visibile.

### 3.3 Soccer Test
- inseguimento della palla;
- calcio della palla verso la porta avversaria;
- goal detection e aggiornamento del punteggio;
- reset della palla e reset dei player dopo il goal;
- recovery della palla se fuori campo.

### 3.4 Vehicle Test
- mantenimento della corsia o del path;
- attraversamento dell'incrocio con decisione di svolta;
- stop su semaforo rosso e giallo e go sul verde;
- reazione al veicolo davanti (slow/stop);
- anti-deadlock sull'incrocio.

## 4) Esempi di Test Rilevanti
### 4.1 Caso T-V-04 (Vehicle - semaforo)
- precondizione: auto in avvicinamento a semaforo rosso;
- atteso: `decide_action=stop`;
- risultato: auto rallenta o si ferma prima dell'attraversamento.

### 4.2 Caso T-S-03 (Soccer - reset)
- precondizione: la palla oltre la linea della porta;
- atteso: incremento dello score e reset delle posizioni;
- risultato: comportamento conforme.

## 5) Miglioramenti Pianificati
- suite automatica di Scala (Unit Test su parser, merge theory, update state);
- test property-based per la mappatura dei percetti -> azioni;
- pipeline CI con run automatico `sbt compile` e test.