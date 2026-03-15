package app

import cats.data.{EitherT, Kleisli}
import cats.effect.{IO, Ref}

final case class AppContext(
  stateRef: Ref[IO, ServerState],
  prologService: PrologService
)

type AppReader[A] = Kleisli[IO, AppContext, A]
type AppResult[A] = EitherT[AppReader, AppError, A]

object MonadSupport:
  def askContext: AppReader[AppContext] =
    Kleisli.ask[IO, AppContext]

  def liftIO[A](io: IO[A]): AppReader[A] =
    Kleisli.liftF(io)

  def askResult: AppResult[AppContext] =
    EitherT.liftF(askContext)

  def pure[A](value: A): AppResult[A] =
    EitherT.rightT(value)

  def fail[A](error: AppError): AppResult[A] =
    EitherT.leftT(error)

  def fromEither[A](either: Either[AppError, A]): AppResult[A] =
    EitherT.fromEither[AppReader](either)

  def liftResult[A](io: IO[A]): AppResult[A] =
    EitherT.liftF(liftIO(io))

