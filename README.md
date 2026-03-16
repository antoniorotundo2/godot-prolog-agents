# Godot Prolog Agents Project

Il progetto realizza un sistema multi-agente in cui:
- avviene una simulazione fisica in un ambiente 3D mediante **Godot**;
- la decisione degli agenti è definita in **Prolog**;
- il bridge di comunicazione e di esecuzione Prolog realizzati in **Scala**;
- la comunicazione real-time avviene mediante **WebSocket**.

L'idea chiave è quella si separare la simulazione fisica, la logica dichiarativa e l'orchestrazione degli stati degli agenti.

## Tecnologie Utilizzate

### Godot

- versione: `4.6`
- linguaggio di scripting: `GDScript`

### Scala

- versione: `3.3.5`
- runtime: `cats-effect`, `fs2`, `http4s`, `circe`

### Prolog

- prolog engine: `tuProlog 3.3.0`

## Architettura Generale

### Componenti

1. **Godot client**

    Ogni agente raccoglie percetti dal mondo simulato (sensori, collisioni, distanza, ecc.) e l'invia mediante WebSocket.

2. **Scala WebSocket server**

    Riceve un JSON, mantiene lo stato per ogni agente, invoca prolog e ne restituisce un azione da eseguire.

3. **Prolog**

    Risolve `decide_action(+Percepts,-Action)` con la teoria specificata dall'agente.

### Fluso run-time per ogni agente

1. Godot costruisce `percepts` considerando il modo fisico.

2. Godot invia i percetti e la teoria al server Scala mediante WebSocket.

3. Scala aggiorna la teoria dell'agente (se fornita) e combina i percetti con lo stato interno dell'agente.

4. Scala esegue il goal di prolog mediante la teoria dell'agente più aggiornata.

5. Quando prolog emette un azione da svolgere, Scala risponde a Godot con l'azione da eseguire.

6. Infine, Godot applica la fisica ed il comportamento locale per l'azione ricevuta.

### Teoria prolog per ogni agente

Il server supporta dinamicamente una teoria per ogni agente, infatti l'agente Godot può caricare il file `.pl` dall'ispector di Godot ed inviare la teoria direttamente al server. Il server salverà la teoria in uno stato interno associando la teoria ricevuta all'id dell'agente che l'ha inviata. Da questo momento in poi tutte le decisioni successive utilizzeranno la teoria inviate dall'agente stesso. Qualora l'agente inviasse una nuova teoria questa sostituirà quella precedente. Se l'agente non dovesse mai inviare una teoria, allora verrà utilizzata la teoria fallback `logic.pl` contenuta all'interno del server stesso.

## Back-end Scala

Il back-end è stato sviluppato in moduli separati in modo tale da separare le varie responsabilità. Tra i moduli principali abbiamo:

- `Main.scala`

    Bootstrap dell'applicazione e avvio del server.

- `WebSocketRoutes.scala`

    Gestisce il routing HTTP e WebSocket.

- `DecisionService.scala`

    Pipeline decisionale di richiesta -> azione/errore.

- `PrologService.scala`

    Integrazione dell'engine di prolog (tuProlog)

- `State.scala`

    Stato agente/server e regole di energia.

- `Protocol.scala`

    Definisce il protocollo JSON utilizzato in WebSocket

- `AppError.scala`

    Gestione per gli errori di dominio

- `MonadTypes.scala`

    Definisce i tipi monadi (mediante Kleisli e EitherT) e il contesto applicativo. Le librerie sono state utilizzate per la depency injection funzionale e per la gestione degli errori.

## Protocollo JSON

### Request

```json
{ 
    "agent": "agent_1",
    "percepts": ["enemy","can_attack"],
    "theory": "testo prolog opzionale"
}
```

### Response

```json
{
    "agent": "agent_1",
    "action": "attack",
    "energy": 92
}
```

### Error

```json
{
    "error": "no_solution"
}
```

## Modello energia e ottimizzazione anti-jitter

Il back-end definisce un energia massima di 100 ad ogni agente definisce per ogni azione un costo energetico. Inoltre, all'interno del server è stata definita una finestra temporale di 30 millisecondi per il riuso decisionale. Se i percetti inviati e le azioni risultanti sono uguali all'ultima recente, allora il server riutilizzerà l'azione precedente senza invocare prolog. Questa ottimizzazione riduce il carico di CPU e le oscillazioni quando il tick di richiesta è molto frequente.

## Agente Godot

L'agente Godot è rappresentato dallo script `Agent.gd` che rappresenta una classe concreta estendibile. Lo script ha le responsabilità di:

- configurazione della WebSocket;

- invio periodico dei percetti (`send_interval`);

- invio urgente su eventi sensoristici (`request_urgent_send`);

- caricamento della teoria lato client e push sul server (`set_theory`);

- ricezione azione/energia e applicazione (`build_percepts`, `perform_action`).

## Scenari Godot implementati

### Menù principale

Rappresenta un semplice menù con dei pulsanti per il caricamento dei vari scenari

### Scenario 1: Simple Agent Test

Rappresente uno scenario base con due tipologie di agenti aventi due logiche differenti (`logic_a` e `logic_b`). In questo scenario è possibile effettuare lo spawn a run-time degli agenti di tipo a e di tipo b

### Scenario 2: Top-down Tank Test

Questo scenario rappresenta una evoluzione dello scenario 1 nel quale vi sono dei carri armati, divisi in due squadre, con la stessa logica nel quale una squadra cerca di sconfiggere la squadra avversaria.

### Scenario 3: Soccer Test

In questo scenario vi sono solo due agenti che aventi la stessa logica i quali hanno come obbiettivo di spingere la palla nella porta avversaria. Queto scenario è particolarmente interessante in quanto la palla è rappresentata da un oggetto rigido all'interno del mondo virtuale.

### Scenario 4: Vehicle Test

In questo scenario viene rappresentato un tratto stradale circolare nel quale in mezzo vi è presente un incrocio a quattro vie con quattro semafori. Ogni agente (ogni veicolo) è rappresentato dalla stessa logica che proporrà il rispetto dei semafori e delle distanze di sicurezza e delle precedenze a destra. Questi comportamenti vengono supportati da un opportuna sensoristica simulata mediante aree di collisioni e raycast.

## Come avviare il progetto

### Avvio del back-end Scala

Dall'interno della cartella `server`, eseguire:
```bash
sbt run
```

Una volta avviato apparirà su terminale una scritta di server avviato sulla porta definita nel progetto (default 8080).

### Avvio del client Godot

Importare il progetto contenuto nella cartella `godot` con Godot 4.6 e lanciare il progetto.