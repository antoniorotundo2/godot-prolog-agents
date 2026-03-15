package app

import cats.effect.{IO, IOApp, Ref, Resource}
import cats.effect.std.Queue
import fs2.{Pipe, Stream}
import io.circe.{Decoder, Encoder}
import io.circe.generic.semiauto.*
import io.circe.parser.*
import io.circe.syntax.*
import org.http4s.HttpRoutes
import org.http4s.dsl.io.*
import org.http4s.ember.server.EmberServerBuilder
import org.http4s.server.websocket.WebSocketBuilder2
import org.http4s.websocket.WebSocketFrame
import com.comcast.ip4s.*
import alice.tuprolog.{Prolog, Theory}

import scala.io.Source
import scala.util.control.NonFatal

final case class WsRequest(agent: String, percepts: List[String], theory: Option[String])
final case class WsResponse(agent: String, action: String, energy: Int)
final case class WsError(error: String)

final case class AgentState(
  energy: Int,
  lastAction: String,
  lastPercepts: List[String],
  lastDecisionAtMs: Long
)

final case class ServerState(
  agents: Map[String, AgentState],
  theories: Map[String, String]
)

object ServerState:
  def empty: ServerState =
    ServerState(Map.empty, Map.empty)

object AgentState:
  private val MinEnergy = 0
  private val MaxEnergy = 100

  def initial: AgentState =
    AgentState(
      energy = 100,
      lastAction = "none",
      lastPercepts = Nil,
      lastDecisionAtMs = 0L
    )

  private def deltaFor(action: String): Int =
    action match
      case "move_forward" => -5
      case "turn_left"    => -2
      case "turn_right"   => -2
      case "go_straight"  => -2
      case "u_turn"       => -3
      case "turn_random"  => -2
      case "drive"        => -2
      case "accelerate"   => -3
      case "cruise"       => -1
      case "slow"         => -1
      case "slow_down"    => -1
      case "stop"         => 0
      case "brake"        => 0
      case "wait"         => 1
      case "idle"         => -1
      case "attack"       => -8
      case "flee"         => -6
      case "rest"         => 10
      case "celebrate"    => 5
      case "wander"       => -3
      case _              => -1

  def next(
    state: AgentState,
    action: String,
    percepts: List[String],
    decidedAtMs: Long
  ): AgentState =
    val updated = state.energy + deltaFor(action)
    val clamped = math.max(MinEnergy, math.min(MaxEnergy, updated))
    state.copy(
      energy = clamped,
      lastAction = action,
      lastPercepts = percepts,
      lastDecisionAtMs = decidedAtMs
    )

  def touch(
    state: AgentState,
    percepts: List[String],
    touchedAtMs: Long
  ): AgentState =
    state.copy(
      lastPercepts = percepts,
      lastDecisionAtMs = touchedAtMs
    )

  def canReuseDecision(
    state: AgentState,
    percepts: List[String],
    nowMs: Long,
    windowMs: Long
  ): Boolean =
    state.lastAction != "none" &&
    state.lastPercepts == percepts &&
    (nowMs - state.lastDecisionAtMs) <= windowMs

object Protocol:
  given Decoder[WsRequest] = deriveDecoder[WsRequest]
  given Encoder[WsResponse] = deriveEncoder[WsResponse]
  given Encoder[WsError] = deriveEncoder[WsError]

object PrologService:
  private lazy val defaultTheoryText: Option[String] =
    try
      val src = Source.fromResource("logic.pl")
      try Some(src.mkString)
      finally src.close()
    catch
      case NonFatal(_) => None

  private def normalizeAtom(value: String): String =
    if value.startsWith("'") && value.endsWith("'") && value.length >= 2 then
      value.substring(1, value.length - 1)
    else value

  private def toPrologList(items: List[String]): String =
    val escaped = items.map { p =>
      val safe = p.replace("\\", "\\\\").replace("\"", "\\\"")
      "\"" + safe + "\""
    }
    escaped.mkString("[", ",", "]")

  def decideAction(percepts: List[String], theoryOverride: Option[String]): Either[String, String] =
    val theoryTextOpt =
      theoryOverride.filter(_.trim.nonEmpty).orElse(defaultTheoryText)
    theoryTextOpt match
      case None =>
        Left("missing_theory")
      case Some(theoryText) =>
        val engine = new Prolog()
        engine.setTheory(new Theory(theoryText))
        val goal = s"decide_action(${toPrologList(percepts)}, Action)."
        val solution = engine.solve(goal)
        if solution.isSuccess then
          Right(normalizeAtom(solution.getTerm("Action").toString))
        else Left("no_solution")

object Main extends IOApp.Simple:
  import Protocol.given
  private val DecisionReuseWindowMs = 30L

  private def buildCombinedPercepts(
    state: AgentState,
    inputPercepts: List[String]
  ): List[String] =
    val basePercepts = inputPercepts.filterNot(_ == "low_energy")
    val statePercepts = List(
      if state.energy < 30 then Some("low_energy") else None,
      Some(s"last_action_${state.lastAction}")
    ).flatten
    basePercepts ++ statePercepts

  private def handleMessage(
    text: String,
    stateRef: Ref[IO, ServerState]
  ): IO[WebSocketFrame] =
    parse(text).flatMap(_.as[WsRequest]) match
      case Left(err) =>
        IO.pure(WebSocketFrame.Text(WsError(err.getMessage).asJson.noSpaces))
      case Right(req) =>
        for
          nowMs <- IO.monotonic.map(_.toMillis)
          snapshot <- stateRef.get
          previous = snapshot.agents.getOrElse(req.agent, AgentState.initial)
          combined = buildCombinedPercepts(previous, req.percepts)
          updatedTheories =
            req.theory.filter(_.trim.nonEmpty) match
              case Some(theoryText) => snapshot.theories.updated(req.agent, theoryText)
              case None             => snapshot.theories
          theoryForAgent = updatedTheories.get(req.agent)
          preReuse = AgentState.canReuseDecision(previous, combined, nowMs, DecisionReuseWindowMs)
          actionResult <-
            if preReuse then IO.pure(Right(previous.lastAction))
            else IO.blocking(PrologService.decideAction(combined, theoryForAgent))
          frame <- actionResult match
            case Left(msg) =>
              stateRef
                .update(s => s.copy(theories = updatedTheories))
                .as(WebSocketFrame.Text(WsError(msg).asJson.noSpaces))
            case Right(action) =>
              stateRef.modify { serverState =>
                val current = serverState.agents.getOrElse(req.agent, AgentState.initial)
                val reuseNow = AgentState.canReuseDecision(
                  current,
                  combined,
                  nowMs,
                  DecisionReuseWindowMs
                ) && action == current.lastAction

                val nextState =
                  if reuseNow then AgentState.touch(current, combined, nowMs)
                  else AgentState.next(current, action, combined, nowMs)

                val mergedTheories =
                  req.theory.filter(_.trim.nonEmpty) match
                    case Some(theoryText) => serverState.theories.updated(req.agent, theoryText)
                    case None             => serverState.theories

                val response = WsResponse(req.agent, nextState.lastAction, nextState.energy)
                (
                  serverState.copy(
                    agents = serverState.agents.updated(req.agent, nextState),
                    theories = mergedTheories
                  ),
                  WebSocketFrame.Text(response.asJson.noSpaces)
                )
              }
        yield frame

  private def wsRoutes(
    wsb: WebSocketBuilder2[IO],
    stateRef: Ref[IO, ServerState]
  ): HttpRoutes[IO] =
    HttpRoutes.of[IO] {
      case GET -> Root / "health" =>
        Ok("ok")
      case GET -> Root / "ws" =>
        for
          queue <- Queue.unbounded[IO, Option[WebSocketFrame]]
          send = Stream.fromQueueNoneTerminated(queue)
          receive: Pipe[IO, WebSocketFrame, Unit] =
            _.evalMap {
              case WebSocketFrame.Text(text, _) =>
                handleMessage(text, stateRef).flatMap(frame => queue.offer(Some(frame)))
              case WebSocketFrame.Close(_) =>
                queue.offer(None)
              case _ => IO.unit
            }.handleErrorWith(_ =>
              Stream.eval(queue.offer(None)).drain
            )
          resp <- wsb.build(send, receive)
        yield resp
    }

  private def server(
    stateRef: Ref[IO, ServerState]
  ): Resource[IO, org.http4s.server.Server] =
    EmberServerBuilder.default[IO]
      .withHost(host"0.0.0.0")
      .withPort(port"8080")
      .withHttpWebSocketApp(wsb => wsRoutes(wsb, stateRef).orNotFound)
      .build

  override def run: IO[Unit] =
    Ref.of[IO, ServerState](ServerState.empty).flatMap { ref =>
      server(ref).useForever
    }
