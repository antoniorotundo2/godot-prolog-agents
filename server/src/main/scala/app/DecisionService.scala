package app

import cats.syntax.all.*
import cats.effect.IO
import io.circe.parser.*
import io.circe.syntax.*
import org.http4s.websocket.WebSocketFrame

object DecisionService:
  import Protocol.given

  private val DecisionReuseWindowMs = 30L

  def handleText(text: String): AppReader[WebSocketFrame] =
    handleRequestText(text).value.map {
      case Right(response) =>
        WebSocketFrame.Text(response.asJson.noSpaces)
      case Left(error) =>
        WebSocketFrame.Text(WsError(error.message).asJson.noSpaces)
    }

  private def handleRequestText(text: String): AppResult[WsResponse] =
    for
      request <- decodeRequest(text)
      response <- decide(request)
    yield response

  private def decodeRequest(text: String): AppResult[WsRequest] =
    val decoded =
      parse(text)
        .leftMap(err => AppError.InvalidJson(err.getMessage))
        .flatMap(_.as[WsRequest].leftMap(err => AppError.InvalidJson(err.getMessage)))

    MonadSupport.fromEither(decoded)

  private def decide(req: WsRequest): AppResult[WsResponse] =
    for
      context <- MonadSupport.askResult
      nowMs <- MonadSupport.liftResult(IO.monotonic.map(_.toMillis))
      snapshot <- MonadSupport.liftResult(context.stateRef.get)
      previous = snapshot.agents.getOrElse(req.agent, AgentState.initial)
      combinedPercepts = buildCombinedPercepts(previous, req.percepts)
      theoryForAgent = mergeTheories(snapshot.theories, req).get(req.agent)
      _ <- MonadSupport.liftResult(persistTheory(context, req))
      preReuse = AgentState.canReuseDecision(previous, combinedPercepts, nowMs, DecisionReuseWindowMs)
      action <-
        if preReuse then MonadSupport.pure(previous.lastAction)
        else MonadSupport.fromEither(context.prologService.decideAction(combinedPercepts, theoryForAgent))
      response <- MonadSupport.liftResult(
        updateStateAfterDecision(context, req, combinedPercepts, action, nowMs)
      )
    yield response

  private def persistTheory(
    context: AppContext,
    req: WsRequest
  ): IO[Unit] =
    context.stateRef.update { serverState =>
      serverState.copy(theories = mergeTheories(serverState.theories, req))
    }

  private def updateStateAfterDecision(
    context: AppContext,
    req: WsRequest,
    percepts: List[String],
    action: String,
    decidedAtMs: Long
  ): IO[WsResponse] =
    context.stateRef.modify { serverState =>
      val current = serverState.agents.getOrElse(req.agent, AgentState.initial)
      val reuseNow =
        AgentState.canReuseDecision(current, percepts, decidedAtMs, DecisionReuseWindowMs) &&
          action == current.lastAction

      val nextState =
        if reuseNow then AgentState.touch(current, percepts, decidedAtMs)
        else AgentState.next(current, action, percepts, decidedAtMs)

      val mergedTheories = mergeTheories(serverState.theories, req)
      val updatedServer = serverState.copy(
        agents = serverState.agents.updated(req.agent, nextState),
        theories = mergedTheories
      )

      val response = WsResponse(req.agent, nextState.lastAction, nextState.energy)
      (updatedServer, response)
    }

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

  private def mergeTheories(
    currentTheories: Map[String, String],
    req: WsRequest
  ): Map[String, String] =
    req.theory.filter(_.trim.nonEmpty) match
      case Some(theoryText) => currentTheories.updated(req.agent, theoryText)
      case None             => currentTheories

