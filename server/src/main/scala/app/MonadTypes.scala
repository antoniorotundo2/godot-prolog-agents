package app

import cats.data.{EitherT, Kleisli}
import cats.effect.{IO, Ref}

// insieme delle dipendenze
final case class AppContext(
  stateRef: Ref[IO, ServerState],
  prologService: PrologService
)

// reader monade per le computazioni che hanno bisogno del contesto condiviso
type AppReader[A] = Kleisli[IO, AppContext, A]
// reader per la gestione del canale per gli errori
type AppResult[A] = EitherT[AppReader, AppError, A]

object MonadSupport:
  // accesso al contesto attuale dal reader
  def askContext: AppReader[AppContext] =
    Kleisli.ask[IO, AppContext]

  // redirect del I/O sul reader
  def liftIO[A](io: IO[A]): AppReader[A] =
    Kleisli.liftF(io)

  // accesso al contesto dalla pipeline
  def askResult: AppResult[AppContext] =
    EitherT.liftF(askContext)

  def pure[A](value: A): AppResult[A] =
    EitherT.rightT(value)

  def fail[A](error: AppError): AppResult[A] =
    EitherT.leftT(error)

  def fromEither[A](either: Either[AppError, A]): AppResult[A] =
    EitherT.fromEither[AppReader](either)

  // redirect del I/O direttamente nell'AppResult
  def liftResult[A](io: IO[A]): AppResult[A] =
    EitherT.liftF(liftIO(io))

