package app

import cats.effect.{IO, IOApp, Ref, Resource}
import com.comcast.ip4s.*
import org.http4s.ember.server.EmberServerBuilder

// avvio dei servizi HTTP e WebSocket con state e prolog service
object Main extends IOApp.Simple:
  private def server(
    context: AppContext
  ): Resource[IO, org.http4s.server.Server] =
    EmberServerBuilder.default[IO]
      .withHost(host"0.0.0.0")
      .withPort(port"8080")
      .withHttpWebSocketApp(wsb => WebSocketRoutes.routes(wsb, context).orNotFound)
      .build

  override def run: IO[Unit] =
    Ref.of[IO, ServerState](ServerState.empty).flatMap { stateRef =>
      val context = AppContext(stateRef, LivePrologService)
      server(context).useForever
    }

