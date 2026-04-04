# Retrospettiva
## 1) Andamento generale dello sviluppo
Lo sviluppo è iniziato da un prototipo di base dell'architettura Godot+Scala+Prolog e si è evoluto in più iterazioni verticali:

1. sviluppo del backbone di comunicazione e dell'agente di base;
2. scenario semplice A/B;
3. scenario del soccer;
4. scenario del tank;
5. scenario vehicles (il più critico per complessità, infatti non completamente funzionante);
6. rifinitura finale, refactoring Scala e documentazione

L'andamento reale ha mostrato una dinamica tipica dei sistemi multiagente, infatti i problemi più difficili non erano nel "singolo agente", ma nella interazioni emergenti tra agenti e ambiente.

## 2) Criticità incontrate e come sono state risolte
### 2.1 Stabilità, comunicazione e parsing
Problemi:
- errori di risorse non trovate (`logic.pl`);
- errori di decoding JSON e import mancanti;
- errori di ritrovamento ed installazione di alcune librerie esterne;
- errori in log per non essere errori.

Risoluzione:
- pulizia del protocollo;
- centralizzazione del decoding e della gestione degli errori;
- teoria caricata lato agente e persistita lato server;
- abilitato opzione per sopprimere messaggi di avviso generati dal componente cats effect sul logger simple4j

### 2.2 Fluidità e comportamento agenti
Problemi:
- movimento scattoso degli agenti;
- agenti che si sovrapponevano o si bloccavano.

Risoluzione:
- tuning della frequenza di invio e ricezione;
- separazione locale;
- miglior controllo sul motore fisico e sui collider.

### 2.3 Manutenibilità back-end
Problema:
- file Scala monolitico poco scalabile.

Risoluzione:
- refactoring in moduli;
- adozione kleisli e EitherT per una pipeline più pulita.

### 2.4 Scenario Vehicles (tema più complesso)
Problemi:
- deadlock nell'incrocio;
- passaggio col rosso;
- compenetrazione auto in code.

Risoluzione:
- sensori multipli (raycast + area);
- logica di precedenza e semafori;
- anti-deadlock con unblock temporaneo randomizzato;
- lane separation sullo stesso path.

## 3) Cosa ha funzionato bene
- Approccio incrementale in scenario;
- Feedback loop rapido "modifica -> run -> verifica";
- Uso di Prolog per cambiare policy e comportamento senza toccare Scala e Godot;
- Riuso del pattern dell'agente di base.

## 4) Cosa migliorare
- introdurre test automatici formali (lato Scala);
- introdurre CI automatica;
- ampliare le metriche a runtime (latenza decisione e throughput);
- aggiungere strumenti di replay deterministico per un debug migliore.

## 5) Commenti Finali
Il risultato finale è coerente con i seguenti obbiettivi:
- integrazione completa Godot + Scala + Prolog;
- architettura estendibile;
- architettura modulare (si può cambiare Godot con altri engine come si può cambiare tuProlog con altri engine);
- architettura distribuibile (è possibile avviare più istanze Scala su diversi nodi e far collegare vari agenti nella stessa scena su nodi diversi);
- più scenari funzionanti sullo stesso backbone.

La parte più formativa è stato il passaggio da prototipo funzionante a sistema mantenibile:
- prima stabilità comportamentale sugli scenari;
- pulizia architetturale e documentazione;
- integrazione e intercomunicazione tra sistemi completamente diversi tra loro.