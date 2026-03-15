package app
// tipologie di errore nella gestione degli errori della WebSocket
sealed trait AppError:
  def message: String

object AppError:
  final case class InvalidJson(details: String) extends AppError:
    override val message: String = details

  case object MissingTheory extends AppError:
    override val message: String = "missing_theory"

  case object NoSolution extends AppError:
    override val message: String = "no_solution"

  final case class PrologFailure(details: String) extends AppError:
    override val message: String = s"prolog_failure: $details"

