ThisBuild / scalaVersion := "3.3.5" // versione Scala usata
ThisBuild / organization := "example" // organizzazione del progetto
ThisBuild / version := "0.1.0-SNAPSHOT" // versione del progetto

Compile / run / outputStrategy := Some(StdoutOutput)
Compile / run / javaOptions += "-Dorg.slf4j.simpleLogger.logFile=System.out"
// esegue `run` in un processo forkato per evitare warning di cats-effect
Compile / run / fork := true
// disabilita l'avviso di cats-effect relativo all'esecuzione su thread non-main
Compile / run / javaOptions += "-Dcats.effect.warnOnNonMainThreadDetected=false"

lazy val root = (project in file("."))
  .settings(
    name := "godot-prolog-bridge",  // nome progetto
    Compile / run / fork := true,
    libraryDependencies ++= Seq(
      // effetti e concorrenza (Cats Effect)
      "org.typelevel" %% "cats-effect" % "3.5.4",
      // FS2 per stream e IO (core + IO utilities)
      "co.fs2" %% "fs2-core" % "3.10.2",
      "co.fs2" %% "fs2-io" % "3.10.2",
      // http4s per server HTTP / WebSocket (Ember server, DSL, integrazione con Circe)
      "org.http4s" %% "http4s-ember-server" % "0.23.26",
      "org.http4s" %% "http4s-dsl" % "0.23.26",
      "org.http4s" %% "http4s-circe" % "0.23.26",
      // Circe per JSON (core, parser, derivazione generica)
      "io.circe" %% "circe-core" % "0.14.7",
      "io.circe" %% "circe-parser" % "0.14.7",
      "io.circe" %% "circe-generic" % "0.14.7",
      // tuProlog (Java library) — notare l'uso di % singolo per artefatti Java
      "it.unibo.alice.tuprolog" % "tuprolog" % "3.3.0",
      // binding SLF4J per avere logging funzionante (usa % perché è una libreria Java)
      "org.slf4j" % "slf4j-simple" % "2.0.9"
    )
  )
