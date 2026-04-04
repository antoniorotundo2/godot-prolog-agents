# Processo di Sviluppo Adottato
## 1. Impostazione Generale del Processo

Il progetto è stato sviluppato in maniera incrementale, con cicli brevi di:
1. definizione di obbiettivo di iterazione;
2. implementazione;
3. verifica in scena (Godot) e lato server (Scala);
4. revisione e tuning;
5. consolidamento nella documentazione.

In questo modo, la strategia seguita ha privilegiato:

- riduzione del rischio tecnico (integrazione Godot <-> Scala <-> Prolog affrontata sin da subito);
- prototipazione rapida in scenari verticali (agenti semplici, calcio, veicoli, tank);
- rifinitura progressiva (fluidita, anti-stallo, sensoristica, robustezza del protocollo).

## 2. Modalità di divisione in itinere dei task

La suddivisione è stata orientata per componente:
- **Back-end Scala**
    - protocollo WebSocket, gestione dello stato, integrazione tuProlog, refactoring monadico.
- **Client simulativo Godot**
    - agente di base, scene, fisica, UI, sensori e oggetti.
- **Logiche Prolog**
    - regole per ogni scenario (semplice, tank, soccer, vehicle), tuning di priorità.
- **Documentazione e Validazione**
    - relazione tecnica, logiche e checklist dei test.

Ogni feature è stata trattata come "vertical slice", cioè dalla percezione in Godot alla decisione in Prolog, fino all'effetto osservabile in scena.

## 3. Modalità di revisione in itinere dei task

- verifica funzionale immediata sullo scenario interessato;
- controllo di impatti collaterali su scenari già stabili;
- revisione del codice per semplificazione e rimozione di parti obsolete.

Esempi di revisione in itinere:

- passaggio da agente specializzato a classe base riutilizzabile;
- migrazione alla nuova versione di Godot e fix di errori di parsing;
- refactoring Scala da file monolitico con pattern monadici;
- revisione logiche Prolog per il bilanciamento.

## 4. Scelta degli strumenti di test, build e continuos integration
### Build

- Scala: `sbt` (`server/build.sbt`)
- Godot: esecuzione della scena in editor o run-time

### Testing

- test funzionali manuali con check-list;
- osservazione dei log WebSocket e della coerenza delle azioni;
- validazione di stabilità fisica e comportamento agenti in scenari reali.

### Continuous Integration

- integrazione continua manuale (verifica locale per ogni modifica significativa);
- backlog e processo in file versionati.

Il motivo di tale scelta ricade sulla forte componente simulativa e visuale di Godot con test funzionali manuali, dando priorità iniziale sulla stabilità dell'integrazione multi-stack.

#### Definition of Done (DoD)

Un task è considerato "done" quando:
1. il comportamento richiesto è visibile e verificabile nello scenario target;
2. non introduce problematiche evidenti sugli scenari principali;
3. il codice rimane leggibile e coerente con la struttura del progetto;
4. eventuali parametri rilevanti sono esposti e configurabili, dove utile;
5. logiche Prolog coinvolte sono commentate e comprensibili.

#### Sprint 01

L'obbiettivo di questo Sprint è stato quello di mettere in piedi la catena completa:
Godot percezione -> WebSocket -> Scala -> Prolog -> azione -> feedback in scena

| ID | Item | Stato |
|---|---|---|
| S1-01 | Definizione protocollo WsRequest/WsResponse | Done |
| S1-02 | Endpoint /ws e /health | Done |
| S1-03 | Integrazione tuProlog base | Done |
| S1-04 | Agent base Godot con invio percetti/ricezione azione | Done |
| S1-05 | Scenario simple con 2 logiche A/B | Done |
| S1-06 | UI base spawn agenti e configurazione URL | Done |

#### Sprint 02

L'obbiettivo di questo Sprint è quello di estendere il sistema a scenari più complessi e provare a risolvere le criticità emergenti.

| ID | Item | Stato |
|---|---|---|
| S2-01 | Player soccer come agenti Prolog | Done |
| S2-02 | Goal detection + score + reset round | Done |
| S2-03 | Vehicle path follow con decisioni Prolog | Done |
| S2-04 | Semafori e precedenza a destra | Done |
| S2-05 | Sensori distanza veicolo (raycast + area) | Done |
| S2-06 | Anti-deadlock incrocio | Done |
| S2-07 | Tuning fluidità movimento/aggiornamento | Done |

### Sprint 03

L'obbiettivo di questo Sprint è il consolidamento finale, implementando un ultimo scenario, effettuando il refactoring del back-end e stilare una documentazione.

| ID | Item | Stato |
|---|---|---|
| S3-01 | Tank agent con logica Prolog tattica | Done |
| S3-02 | Shoot con line-of-sight e cooldown | Done |
| S3-03 | Respawn random tank e anti-stallo | Done |
| S3-04 | Refactoring Scala modulare | Done |
| S3-05 | Introduzione pipeline monadica (Kleisli + EitherT) | Done |
| S3-06 | Commenti migliorati su logiche Prolog | Done |
| S3-07 | Relazione tecnica completa in Markdown | Done |
| S3-08 | Definizione strategia test/CI evolutiva | Done |