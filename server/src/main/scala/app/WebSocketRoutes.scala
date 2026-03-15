package app

import cats.effect.IO
import cats.effect.std.Queue
import fs2.{Pipe, Stream}
import org.http4s.HttpRoutes
import org.http4s.dsl.io.*
import org.http4s.server.websocket.WebSocketBuilder2
import org.http4s.websocket.WebSocketFrame

object WebSocketRoutes:
  def routes(
    wsb: WebSocketBuilder2[IO],
    context: AppContext
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
                DecisionService.handleText(text).run(context).flatMap(frame => queue.offer(Some(frame)))
              case WebSocketFrame.Close(_) =>
                queue.offer(None)
              case _ =>
                IO.unit
            }.handleErrorWith(_ =>
              Stream.eval(queue.offer(None)).drain
            )
          response <- wsb.build(send, receive)
        yield response
    }

