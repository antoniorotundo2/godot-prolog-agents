# Tecnologie Utilizzate
## Godot Engine
Nel progetto è stato utilizzato Godot 4 come motore di sviluppo lato client, in quanto rappresenta una piattaforma completa per la realizzazione di applicazioni interattive e giochi 2D/3D, mettendo a disposizione strumenti integrati per la gestione delle scene, dell'interfaccia grafica, degli input utente e della logica applicativa.
La scelta di questa tecnologia ha consentito di concentrare lo sviluppo su un ambiente unico e coerente, semplificando la costruzione della componente visuale del sistema e facilitando l'integrazione tra la rappresentazione grafica, le interazioni dell'utente e la logica ad alto livello.
Godot è risultato particolarmente adatto poiché permette di organizzare il progetto secondo una struttura modulare basata su scene e nodi, caratteristica utile per modellare in modo chiaro i diversi elementi dell'applicazione. Inoltre, l'engine offre strumenti già pronti per la gestione del rendering, della UI e degli eventi, riducendo il carico implementativo necessario per costruire manualmente tali componenti e rendendo più rapida la prototipazione e l'evoluzione del client.

La scelta di utilizzare Godot ricade anche nella sua natura di essere leggero ma soprattutto opensource, il che potrebbe permettere anche di modificare nativamente l'engine per supportare direttamente l'architettura ideata per sfruttare Prolog per la logica degli agenti direttamente all'interno dell'engine stesso.
Notare bene che è possibile sostituire Godot con qualsiasi altro engine o applicativo di scripting, implementando correttamente il protocollo ideato e basato su WebSocket.

Link Utili: [Godot Engine Website](https://godotengine.org/)

## WebSocket protocol
Per la comunicazione tra client e server è stato adottato il protocollo WebSocket, poiché consente di instaurare una connessione persistente e bidirezionale tra le due estremità, evitando il modello tradizionale di richiesta-risposta di HTTP. Questa caratteristica è particolarmente importante in applicazioni che richiedono sincronizzazione continua o aggiornamenti immediati, dal momento che permette sia al client e sia al server di inviare messaggi in qualsiasi momento, senza aprire una nuova connessione per lo scambio di dati.
L'impiego di WebSocket è stato motivato dalla necessità di supportare interazioni in tempo reale, riducendo la latenza comunicativa e migliorando la reattività complessiva del sistema. In questa architettura, infatti, il client Godot può trasmettere eventi o azioni al server, mentre il server può ripondere o propagare aggiornamenti di stato in maniera immediata, garantendo una comunicazione continua e più efficiente rispetto a soluzioni basate su polling periodico. Inoltre, il protocollo WebSocket è già implementato nativamente all'interno di Godot ma anche su altri engine e piattaforme.

Link Utili:  [WebSocket Protocol RFC](https://websocket.org/guides/websocket-protocol/) , [Godot WebSocket Documentation](https://docs.godotengine.org/en/stable/tutorials/networking/websocket.html#using-websocket-in-godot)

## Cats Effect
Per quanto riguarda il back-end,  è stata adottata la libreria cats effect, che costituisce una parte importante di Scala per la gestione degli effetti, della asincronia e della concorrenza. L'utilizzo di cats effect ha permesso di modellare facilmente le varie operazioni e la gestione del ciclo di vita dei vari agenti. La scelta di cats effect è stata particolarmente significativa nel contesto di progetto, in quanto il back-end deve poter gestire connessioni multiple attive ed elaborazioni dei vari percetti e delle azioni da dover inviare ai vari agenti. Grazie a questo modello, è stato quindi possibile costruire una logica server più robusta, mantenendo separata le operazioni degli agenti dall'esecuzione del server stesso e dalla gestione della comunicazione.

Link Utili: [Cats Effect Websiste](https://typelevel.org/cats-effect/)

## fs2
Accanto a Cats Effect è stata utilizzata la libreria fs2, pensata per rappresentare ed elaborare stream di dati in maniera funzionale, dichiarativa e componibile. Tale scelta è risultata coerente con la natura del protocollo di comunicazione utilizzato, poiché una comunicazione WebSocket può essere interpretata come un flusso continuo di messaggi in ingresso ed in uscita, che devono essere letti, trasformati, filtrati ed eventualmente inoltrati ad altri componenti del sistema.
L'adozione di fs2 ha consentito di modellare queste sequenze di eventi in modo naturale, migliorando la chiarezza del codice e rendendo più semplice la gestione di elaborazione dei messaggi in arrivo e in uscita, migliorando anche la composizione della pipeline e del controllo del ciclo di vita delle risorse associate agli stream.

Link Utili: [fs2 Website](https://fs2.io/#/)

## Kleisli
Per migliorare ulteriormente la modularità del back-end è stato impiegato Kleisli, costrutto della programmazione funzionale che consente di rappresentare e comporre funzioni che producono risultati all'interno di un contesto ben specifico. Il suo utilizzo è stato utile per organizzare la logica applicativa in modo più pulito.
Attraverso Kleisli è stato possibile evitare anche una gestione dispersiva delle dipendenze, favorendo invece una composizione più lineare delle funzioni per back-end. Questa impostazione ha contribuito a rendere il codice più leggibile, più riutilizzabile e più aderente alla programmazione funzionale, nella quale il contesto applicativo viene gestito in maniera esplicita e controllato.

Link Utili: [Javadoc Kleisli](https://www.javadoc.io/doc/org.typelevel/cats-docs_2.13/latest/cats/data/Kleisli.html) , [TypeLevel Documentation](https://typelevel.org/cats/datatypes/kleisli.html)

## EitherT
Infine, è stato utilizzato EitherT per affrontare in maniera più ordinata il problema della gestione degli errori applicativi all'interno di computazioni o parsing. Infatti, in un back-end asincrono e composabile, molte operazioni possono produrre o un effetto o un fallimento, cosa che accadeva continuamente durante la validazione e il parsing dei messaggi ricevuti in formato JSON.
EitherT ha permesso di rappresentati questi casi in modo esplicito evitando gestioni annidate e poco leggibili, favorendo una scrittura del codice più lineare. Di conseguenza, la gestione degli errori è risultata più chiara e meglio integrata con l'architettura funzionale adottata nel back-end.

Link Utili: [Javadoc EitherT](https://www.javadoc.io/doc/org.typelevel/cats-docs_2.13/latest/cats/data/EitherT.html) , [TypeLevel EitherT](https://typelevel.org/cats/datatypes/eithert.html)